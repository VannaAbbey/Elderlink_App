import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'vital_update_screen.dart';
import 'follow_up_vitals_selection.dart';

class UpcomingVitalsTab extends StatefulWidget {
  final String houseId;
  final String? nurseName;

  const UpcomingVitalsTab({
    super.key,
    required this.houseId,
    required this.nurseName,
  });

  @override
  State<UpcomingVitalsTab> createState() => _UpcomingVitalsTabState();
}

// ⚠️ IMPORTANT ARCHITECTURAL DECISION:
// This class NEVER deletes vital assignment records from the database.
// Instead, it updates their status to 'reassigned' or 'inactive' to preserve history.
// Changes in house_shift_assignments and elderly_assignments are reflected in vitals
// through status updates and field modifications, not record deletion.
// This ensures complete audit trail and prevents data loss.

class _UpcomingVitalsTabState extends State<UpcomingVitalsTab>
    with AutomaticKeepAliveClientMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  List<Map<String, dynamic>>? _upcomingVitals;
  bool _isNotAssignedToShift = false;
  // Simple in-memory cache per houseId
  static final Map<String, List<Map<String, dynamic>>> _houseVitalsCache = {};
  static final Map<String, DateTime> _houseVitalsCacheTime = {};
  // Keep a longer cache to avoid repeated reloads when switching houses/tabs
  static const Duration cacheDuration = Duration(minutes: 30); // Cache for 30m
  // Track completed cleanup operations to avoid repeated work
  static final Set<String> _completedCleanups = {};

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

  Future<bool> _isNurseAssignedToCurrentShift(String nurseId) async {
    final currentShift = _getCurrentShift();
    final currentDay = _getCurrentDay();

    try {
      final shiftQuery = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .where('days_assigned', arrayContains: currentDay)
          .get();

      return shiftQuery.docs.isNotEmpty;
    } catch (e) {
      print('❌ Error checking shift assignment: $e');
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    // Prewarm nurse id lookup and start loading vitals
    _prewarm();
  }

  /// Pre-fetch lightweight data to speed up first render
  void _prewarm() async {
    // Kick off nurse id lookup so it's cached before heavy queries
    _getCachedNurseId();
    // Start loading vitals (will use cached nurse id if available)
    _loadUpcomingVitals();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _loadUpcomingVitals({bool forceRefresh = false}) async {
    final cacheKey = widget.houseId + (widget.nurseName ?? "");
    final now = DateTime.now();

    // Always set loading to true at the start, so spinner is shown until data is ready
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    if (_houseVitalsCache.containsKey(cacheKey) && !forceRefresh) {
      // Always show cached data immediately if available
      if (mounted) {
        setState(() {
          _upcomingVitals = _houseVitalsCache[cacheKey]!;
          _isLoading = false;
        });
      }

      // Check if cache is stale and refresh in background if needed
      if (_houseVitalsCacheTime.containsKey(cacheKey)) {
        final cacheTime = _houseVitalsCacheTime[cacheKey]!;
        if (now.difference(cacheTime) >= cacheDuration) {
          // Refresh in background to update cache
          Future(() async {
            try {
              final vitals = await _getUpcomingVitals();
              _houseVitalsCache[cacheKey] = vitals;
              _houseVitalsCacheTime[cacheKey] = DateTime.now();
              if (mounted) {
                setState(() {
                  _upcomingVitals = vitals;
                });
              }
            } catch (e) {
              print('❌ Background refresh failed: $e');
            }
          });
        }
      }
      return;
    }

    // No cache or force refresh - fetch fresh data
    try {
      // Use cached nurse id if available to speed up a quick existence check
      final nurseId = await _getCachedNurseId();
      if (nurseId == null) {
        // If we can't resolve nurse id yet, avoid blocking UI for long
        if (mounted) {
          setState(() {
            _upcomingVitals = [];
            _isLoading = false;
          });
        }
        return;
      }

      // First check if nurse is assigned to current shift
      final isAssignedToShift = await _isNurseAssignedToCurrentShift(nurseId);
      if (!isAssignedToShift) {
        if (mounted) {
          setState(() {
            _isNotAssignedToShift = true;
            _upcomingVitals = [];
            _isLoading = false;
          });
        }
        return;
      }

      // Fast-path: check if there is at least one pending vital in this house/shift
      final today = _getTodayDateString();
      final currentShift = _getCurrentShift();
      final quickCheck = await _firestore
          .collection('vitals')
          .where('house_id', isEqualTo: widget.houseId)
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (quickCheck.docs.isEmpty) {
        // No assignments yet - create them and get the vitals
        print('🔄 No assignments found - creating and fetching...');
        final vitals = await _ensureAssignmentsExistInBackground(
          nurseId,
          currentShift,
          _getCurrentDay(),
          today,
        );

        _houseVitalsCache[cacheKey] = vitals;
        _houseVitalsCacheTime[cacheKey] = DateTime.now();
        if (mounted) {
          setState(() {
            _upcomingVitals = vitals;
            _isLoading = false;
          });
        }
        return;
      }

      final vitals = await _getUpcomingVitals();
      _houseVitalsCache[cacheKey] = vitals;
      _houseVitalsCacheTime[cacheKey] = DateTime.now();
      if (mounted) {
        setState(() {
          _upcomingVitals = vitals;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading upcoming vitals: $e');
      if (mounted) {
        setState(() {
          _upcomingVitals = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshVitals() async {
    await _loadUpcomingVitals(forceRefresh: true);
  }

  String _getCurrentDay() {
    final now = DateTime.now();
    final currentHour = now.hour;

    // For third shift (10pm-6am), if it's after midnight (0:00-5:59),
    // we need to look at the previous day's assignments
    if (currentHour >= 0 && currentHour < 6) {
      // It's after midnight during third shift, so get previous day
      final previousDay = now.subtract(Duration(days: 1));
      return DateFormat('EEEE').format(previousDay);
    }

    // For all other times, use current day
    return DateFormat('EEEE').format(now);
  }

  String _getTodayDateString() {
    final now = DateTime.now();
    final currentHour = now.hour;

    // For third shift (10pm-6am), if it's after midnight (0:00-5:59),
    // we need to use the previous day's date for assignments
    if (currentHour >= 0 && currentHour < 6) {
      // It's after midnight during third shift, so get previous day's date
      final previousDay = now.subtract(Duration(days: 1));
      return DateFormat('yyyy-MM-dd').format(previousDay);
    }

    // For all other times, use current date
    return DateFormat('yyyy-MM-dd').format(now);
  }

  String _getPreviousShift() {
    final currentShift = _getCurrentShift();
    switch (currentShift) {
      case "1st":
        return "3rd"; // Previous shift was 3rd
      case "2nd":
        return "1st"; // Previous shift was 1st
      case "3rd":
        return "2nd"; // Previous shift was 2nd
      default:
        return "1st";
    }
  }

  // Check if we need to handle shift transition based on actual nurse change
  Future<void> _handleShiftTransition(String currentNurseId) async {
    final today = _getTodayDateString();
    final currentShift = _getCurrentShift();
    final previousShift = _getPreviousShift();
    final currentDay = _getCurrentDay();

    print('🔄 Checking shift transition: $previousShift → $currentShift');

    // 🔧 FIXED: Get elderly assigned to current nurse for PREVIOUS shift/day (not current)
    final previousNurseAssignments = await _firestore
        .collection('elderly_assignments')
        .where('user_id', isEqualTo: currentNurseId)
        .where('user_type', isEqualTo: 'nurse')
        .where('is_current', isEqualTo: true)
        .where('shift', isEqualTo: previousShift)
        .where('day', isEqualTo: currentDay)
        .get();

    final previousNurseElderlyIds = <String>{};
    for (final doc in previousNurseAssignments.docs) {
      final data = doc.data();
      final elderlyIds = List<String>.from(data['elderly_ids'] ?? []);
      previousNurseElderlyIds.addAll(elderlyIds);
    }

    print(
      '👥 Current nurse was assigned to ${previousNurseElderlyIds.length} elderly in previous shift',
    );

    // Get all pending vital assignments from previous shift for this house
    final previousShiftAssignments = await _firestore
        .collection('vitals')
        .where('house_id', isEqualTo: widget.houseId)
        .where('assigned_date', isEqualTo: today)
        .where('shift', isEqualTo: previousShift)
        .where('status', isEqualTo: 'pending')
        .get();

    print(
      '📋 Found ${previousShiftAssignments.docs.length} pending assignments from previous shift',
    );

    // 🔧 FIXED: Only inherit assignments for elderly assigned to current nurse in previous shift
    if (previousShiftAssignments.docs.isNotEmpty &&
        previousNurseElderlyIds.isNotEmpty) {
      print(
        '🔄 Shift transition detected - inheriting previous shift assignments for elderly assigned to current nurse',
      );

      for (final doc in previousShiftAssignments.docs) {
        final data = doc.data();
        final elderlyId = data['elderly_id'];

        // Only inherit if this elderly was assigned to the current nurse in the previous shift
        if (!previousNurseElderlyIds.contains(elderlyId)) {
          print(
            '⏭️ Skipping inheritance for elderly $elderlyId - not assigned to current nurse in previous shift',
          );
          continue;
        }

        final previousNurseId = data['assigned_nurse_id'];

        // Derive previous nurse name from ID
        String previousNurseName = 'Unknown Nurse';
        if (previousNurseId != null) {
          try {
            final nurseDoc = await _firestore
                .collection('users')
                .doc(previousNurseId)
                .get();
            if (nurseDoc.exists) {
              final nurseData = nurseDoc.data();
              previousNurseName = nurseData?['user_fname'] ?? 'Unknown Nurse';
            }
          } catch (e) {
            print('Error getting previous nurse name: $e');
          }
        }

        print(
          '✅ Inheriting assignment for elderly $elderlyId from $previousNurseName ($previousShift shift)',
        );

        // Transfer the assignment to the current nurse
        await doc.reference.update({
          'assigned_nurse_id': currentNurseId,
          'shift': currentShift, // Update to current shift
          'updated_at': FieldValue.serverTimestamp(),
          // Add inheritance tracking
          'inherited_from_shift': previousShift,
          'inherited_from_nurse_id': data['assigned_nurse_id'],
          'transfer_reason': 'Shift ended - inherited from previous shift',
        });

        // Log the transfer action
        final logDocRef = _firestore.collection('vitals_activity_logs').doc();
        await logDocRef.set({
          'vitals_activity_log_id': logDocRef.id,
          'elderly_id': data['elderly_id'],
          'nurse_id': currentNurseId,
          'house_id': data['house_id'],
          'vitals_id': doc.id,
          'shift': currentShift,
          'action_type': 'inherited',
          'timestamp': FieldValue.serverTimestamp(),
          'old_values': {
            'assigned_nurse_id': data['assigned_nurse_id'],
            'shift': previousShift,
          },
          'new_values': {
            'assigned_nurse_id': currentNurseId,
            'shift': currentShift,
          },
          'remarks': 'Shift ended - inherited from previous shift',
        });

        print('✅ Successfully inherited assignment for elderly: $elderlyId');
      }
    } else {
      print(
        'ℹ️ No previous shift assignments to inherit or no elderly assigned to current nurse',
      );
    }
  }

  // Clean up assignments for elderly no longer assigned to this nurse
  // ⚠️ IMPORTANT: Never delete vital records - only update status to maintain history
  Future<void> _cleanupStaleAssignments(
    String currentShift,
    String currentDay,
    String today,
  ) async {
    try {
      print(
        '🧹 Updating stale assignments for all nurses in current house (no deletions - preserving history)...',
      );

      // Get all elderly IDs assigned to ANY nurse for this shift/day (then filter by house)
      final validElderlyToNurse = <String, String>{};

      final allAssignedElderlyQuery = await _firestore
          .collection('elderly_assignments')
          .where('is_current', isEqualTo: true)
          .where(
            'house_id',
            arrayContains: widget.houseId,
          ) // 🔧 FIXED: Filter by house first
          .where('day', isEqualTo: currentDay)
          .where('shift', isEqualTo: currentShift)
          .get();

      // Build mapping of elderly to their assigned nurse (already filtered by current house)
      for (var assignDoc in allAssignedElderlyQuery.docs) {
        final nurseId = assignDoc['user_id'] as String;
        final elderlyIds = List<String>.from(assignDoc['elderly_ids'] ?? []);
        for (final elderlyId in elderlyIds) {
          // No need to check house_id since we filtered by house_id arrayContains
          validElderlyToNurse[elderlyId] = nurseId;
        }
      }

      print(
        '🧹 Valid elderly-to-nurse mappings for current house: $validElderlyToNurse',
      );

      // Get all pending vital assignments for CURRENT house, shift, and date
      final existingAssignments = await _firestore
          .collection('vitals')
          .where('house_id', isEqualTo: widget.houseId)
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .where('status', isEqualTo: 'pending')
          .get();

      int updatedCount = 0;
      for (final doc in existingAssignments.docs) {
        final data = doc.data();
        final elderlyId = data['elderly_id'];
        final currentAssignedNurse = data['assigned_nurse_id'];

        // Check if this elderly is still assigned to the same nurse
        final correctNurse = validElderlyToNurse[elderlyId];

        if (correctNurse == null) {
          // Elderly is no longer assigned to any nurse in this house
          await doc.reference.update({
            'status': 'reassigned',
            'updated_at': FieldValue.serverTimestamp(),
            'reassignment_reason':
                'Elderly no longer assigned to any nurse in this house',
            'reassigned_at': FieldValue.serverTimestamp(),
          });
          updatedCount++;
          print(
            '🧹 Marked assignment as reassigned for elderly: $elderlyId (no longer assigned to any nurse)',
          );
        } else if (currentAssignedNurse != correctNurse) {
          // Elderly is assigned to a different nurse now
          await doc.reference.update({
            'assigned_nurse_id': correctNurse,
            'updated_at': FieldValue.serverTimestamp(),
            'reassignment_reason': 'Elderly reassigned to different nurse',
            'reassigned_at': FieldValue.serverTimestamp(),
          });
          updatedCount++;
          print(
            '🧹 Reassigned elderly: $elderlyId from nurse $currentAssignedNurse to nurse $correctNurse',
          );
        }
      }

      print(
        '🧹 Status update complete: Updated $updatedCount stale assignments',
      );
    } catch (e) {
      print('❌ Error updating stale assignments: $e');
    }
  }

  /// ⚡ OPTIMIZED: Get authenticated nurse ID directly from Firebase Auth
  Future<String?> _getCachedNurseId() async {
    // Use the authenticated user's UID directly for reliable nurse identification
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('No authenticated user found');
      return null;
    }
    return user.uid;
  }

  Future<List<Map<String, dynamic>>> _getUpcomingVitals() async {
    try {
      final currentShift = _getCurrentShift();
      final currentDay = _getCurrentDay();
      final today = _getTodayDateString();

      print(
        '⚡ OPTIMIZED: Fetching for nurse: ${widget.nurseName}, shift: $currentShift, day: $currentDay',
      );
      print('🏠 House: "${widget.houseId}"');

      // ⚡ OPTIMIZATION 1: Use cached nurse ID
      final nurseId = await _getCachedNurseId();
      if (nurseId == null) return [];

      print('✅ Nurse ID: $nurseId');

      // 🔧 OPTIMIZATION: Only run cleanup operations once per day per nurse to avoid repeated work
      final cleanupKey = '$nurseId-$today-$currentShift';
      final needsCleanup = !_completedCleanups.contains(cleanupKey);

      if (needsCleanup) {
        print('🔄 Ensuring all assignments are created before fetching...');

        // First handle shift transition to create inherited assignments
        await _handleShiftTransition(nurseId);

        // Clean up any assignments for elderly no longer assigned to any nurse in this house
        await _cleanupStaleAssignments(currentShift, currentDay, today);

        // Then ensure all regular assignments are created
        await _ensureAllAssignmentsExist(currentShift, currentDay, today);

        _completedCleanups.add(cleanupKey);
        print('✅ Cleanup operations completed for today');
      } else {
        print('⏭️ Skipping cleanup operations - already done for today');
      }

      // Get elderly assigned to all nurses (general assignments, not per shift)
      final elderlyToNurse = <String, String>{};
      final nurseAssignmentsQuery = await _firestore
          .collection('elderly_assignments')
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where(
            'house_id',
            arrayContains: widget.houseId,
          ) // 🔧 FIXED: Filter by house
          .where(
            'shift',
            isEqualTo: currentShift,
          ) // 🔧 FIXED: Filter by current shift
          .where(
            'day',
            isEqualTo: currentDay,
          ) // 🔧 FIXED: Filter by current day
          .get();

      print(
        '🔍 DEBUG: Found ${nurseAssignmentsQuery.docs.length} elderly_assignments documents',
      );

      for (final doc in nurseAssignmentsQuery.docs) {
        final data = doc.data();
        print('🔍 DEBUG: Assignment doc ${doc.id}: ${data}');
        final assignedNurseId = data['user_id'] as String;
        final elderlyIds = List<String>.from(data['elderly_ids'] ?? []);
        print('🔍 DEBUG: Nurse $assignedNurseId has elderly: $elderlyIds');
        for (final elderlyId in elderlyIds) {
          elderlyToNurse[elderlyId] = assignedNurseId;
        }
      }

      print(
        '✅ Found assignments for ${elderlyToNurse.length} elderly for all nurses',
      );

      // 🔧 MODIFIED: Get elderly assigned to CURRENT nurse only
      final currentNurseElderlyIds = <String>[];
      for (final entry in elderlyToNurse.entries) {
        if (entry.value == nurseId) {
          currentNurseElderlyIds.add(entry.key);
        }
      }

      print(
        '👥 Current nurse ($nurseId) is assigned to ${currentNurseElderlyIds.length} elderly: $currentNurseElderlyIds',
      );

      // If no elderly assigned to current nurse, return empty
      if (currentNurseElderlyIds.isEmpty) {
        print('ℹ️ No elderly assigned to current nurse');
        return [];
      }

      // 🔍 DEBUG: Check which elderly are in the current house
      final elderlyInCurrentHouse = <String>[];
      for (final elderlyId in currentNurseElderlyIds) {
        final elderlyDoc = await _firestore
            .collection('elderly')
            .doc(elderlyId)
            .get();
        if (elderlyDoc.exists) {
          final elderlyData = elderlyDoc.data()!;
          final elderlyHouseId = elderlyData['house_id'];
          print(
            '🔍 DEBUG: Elderly $elderlyId is in house $elderlyHouseId (current house: ${widget.houseId})',
          );
          if (elderlyHouseId == widget.houseId) {
            elderlyInCurrentHouse.add(elderlyId);
          }
        } else {
          print('🔍 DEBUG: Elderly $elderlyId document not found');
        }
      }

      print(
        '🏠 Elderly in current house: ${elderlyInCurrentHouse.length} out of ${currentNurseElderlyIds.length}',
      );

      // Use only elderly in current house
      final filteredElderlyIds = elderlyInCurrentHouse;

      // 🔧 MODIFIED: Query for pending vitals for CURRENT nurse's elderly only (in current house)
      final vitalsQuery = await _firestore
          .collection('vitals')
          .where('house_id', isEqualTo: widget.houseId)
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .where('status', isEqualTo: 'pending')
          .where(
            'elderly_id',
            whereIn: filteredElderlyIds.take(10).toList(),
          ) // Firestore whereIn limit
          .get();

      // Handle Firestore whereIn limit (30 items max) by chunking if needed
      final allVitals = <QueryDocumentSnapshot>[];
      allVitals.addAll(vitalsQuery.docs);

      // If we have more than 10 elderly, query in chunks
      if (filteredElderlyIds.length > 10) {
        for (var i = 10; i < filteredElderlyIds.length; i += 10) {
          final chunk = filteredElderlyIds.skip(i).take(10).toList();
          if (chunk.isNotEmpty) {
            final chunkQuery = await _firestore
                .collection('vitals')
                .where('house_id', isEqualTo: widget.houseId)
                .where('assigned_date', isEqualTo: today)
                .where('shift', isEqualTo: currentShift)
                .where('status', isEqualTo: 'pending')
                .where('elderly_id', whereIn: chunk)
                .get();
            allVitals.addAll(chunkQuery.docs);
          }
        }
      }

      print(
        '⚡ Found ${allVitals.length} pending vital assignments for current nurse\'s elderly',
      );

      // Process vitals assignments for current nurse only
      final upcomingVitals = <Map<String, dynamic>>[];
      final seenElderlyIds = <String>{};

      // ⚡ OPTIMIZATION: Batch fetch elderly data to reduce database calls
      final elderlyIdsToFetch = <String>[];
      for (final vitalDoc in allVitals) {
        final vitalData = vitalDoc.data() as Map<String, dynamic>;
        final elderlyId = vitalData['elderly_id'];
        if (!seenElderlyIds.contains(elderlyId)) {
          seenElderlyIds.add(elderlyId);
          elderlyIdsToFetch.add(elderlyId);
        }
      }

      // Batch fetch all elderly documents at once
      final elderlyDocs = await Future.wait(
        elderlyIdsToFetch.map(
          (id) => _firestore.collection('elderly').doc(id).get(),
        ),
      );

      // Create a map for quick lookup
      final elderlyDataMap = <String, Map<String, dynamic>>{};
      for (final doc in elderlyDocs) {
        if (doc.exists) {
          elderlyDataMap[doc.id] = doc.data()!;
        }
      }

      // ⚡ OPTIMIZATION: Collect all unique nurse IDs that need name lookup
      final nurseIdsToFetch = <String>{};
      for (final vitalDoc in allVitals) {
        final vitalData = vitalDoc.data() as Map<String, dynamic>;
        final assignedNurseId = vitalData['assigned_nurse_id'];
        final inheritedNurseId = vitalData['inherited_from_nurse_id'];
        if (assignedNurseId != null) nurseIdsToFetch.add(assignedNurseId);
        if (inheritedNurseId != null) nurseIdsToFetch.add(inheritedNurseId);
      }

      // Batch fetch all nurse documents
      final nurseDocs = await Future.wait(
        nurseIdsToFetch.map(
          (id) => _firestore.collection('users').doc(id).get(),
        ),
      );

      // Create nurse data map for quick lookup
      final nurseDataMap = <String, Map<String, dynamic>>{};
      for (final doc in nurseDocs) {
        if (doc.exists) {
          nurseDataMap[doc.id] = doc.data()!;
        }
      }

      // Reset seenElderlyIds for final processing
      seenElderlyIds.clear();

      for (final vitalDoc in allVitals) {
        final vitalData = vitalDoc.data() as Map<String, dynamic>;
        final elderlyId = vitalData['elderly_id'];

        // 🔧 MODIFIED: No need to filter by nurse since we already filtered by elderly assigned to current nurse
        if (!seenElderlyIds.contains(elderlyId)) {
          seenElderlyIds.add(elderlyId);

          // Get elderly details from our batched data
          final elderlyData = elderlyDataMap[elderlyId];
          if (elderlyData == null) continue;

          final elderlyName =
              '${elderlyData['elderly_fname'] ?? ''} ${elderlyData['elderly_lname'] ?? ''}'
                  .trim();
          if (elderlyName.isEmpty) continue;

          // Get assigned nurse name from batched nurse data
          final assignedNurseId = vitalData['assigned_nurse_id'];
          String assignedNurseName = 'Unknown Nurse';
          if (assignedNurseId != null &&
              nurseDataMap.containsKey(assignedNurseId)) {
            final nurseData = nurseDataMap[assignedNurseId]!;
            assignedNurseName =
                '${nurseData['user_fname'] ?? ''} ${nurseData['user_lname'] ?? ''}'
                    .trim();
          }

          // Get original nurse name for inherited assignments
          String originalNurseName = assignedNurseName;
          final inheritedNurseId = vitalData['inherited_from_nurse_id'];
          if (inheritedNurseId != null &&
              nurseDataMap.containsKey(inheritedNurseId)) {
            final inheritedNurseData = nurseDataMap[inheritedNurseId]!;
            originalNurseName =
                '${inheritedNurseData['user_fname'] ?? ''} ${inheritedNurseData['user_lname'] ?? ''}'
                    .trim();
          }

          upcomingVitals.add({
            'assignment_id': vitalDoc.id,
            'elderly_id': elderlyId,
            'elderly_name': elderlyName,
            'assigned_nurse_id': assignedNurseId,
            'assigned_nurse_name': assignedNurseName,
            'house_id': vitalData['house_id'],
            'shift': vitalData['shift'],
            'assigned_date': vitalData['assigned_date'],
            'status': vitalData['status'],
            'blood_pressure': vitalData['blood_pressure'],
            'pulse_rate': vitalData['pulse_rate'],
            'oxygen_saturation': vitalData['oxygen_saturation'],
            'temperature': vitalData['temperature'],
            'respiratory_rate': vitalData['respiratory_rate'],
            'vital_remarks': vitalData['vital_remarks'],
            'completed_at': vitalData['completed_at'],
            'updated_by_nurse_id': vitalData['updated_by_nurse_id'],
            'updated_by_nurse_name': null, // Can be fetched if needed
            'original_nurse': originalNurseName,
          });
        }
      }

      // Sort by elderly name
      upcomingVitals.sort((a, b) {
        return (a['elderly_name'] as String).compareTo(
          b['elderly_name'] as String,
        );
      });

      print(
        '⚡ Returning ${upcomingVitals.length} elderly assignments for current nurse',
      );
      return upcomingVitals;
    } catch (e) {
      print('❌ Error getting upcoming vitals: $e');
      return [];
    }
  }

  /// ⚡ BACKGROUND: Ensure assignments exist and return the vitals list
  Future<List<Map<String, dynamic>>> _ensureAssignmentsExistInBackground(
    String nurseId,
    String currentShift,
    String currentDay,
    String today,
  ) async {
    try {
      print('🔄 Background: Ensuring assignments exist for all nurses...');

      // Get all elderly assignments (general, not per shift)
      final allAssignmentsQuery = await _firestore
          .collection('elderly_assignments')
          .where('is_current', isEqualTo: true)
          .where(
            'house_id',
            arrayContains: widget.houseId,
          ) // 🔧 FIXED: Filter by house
          .where(
            'shift',
            isEqualTo: currentShift,
          ) // 🔧 FIXED: Filter by current shift
          .where(
            'day',
            isEqualTo: currentDay,
          ) // 🔧 FIXED: Filter by current day
          .get();

      final elderlyToNurse = <String, String>{};
      for (final doc in allAssignmentsQuery.docs) {
        final data = doc.data();
        final nurseId = data['user_id'] as String;
        final elderlyIds = List<String>.from(data['elderly_ids'] ?? []);
        for (final elderlyId in elderlyIds) {
          elderlyToNurse[elderlyId] = nurseId;
        }
      }

      print('✅ Found assignments for ${elderlyToNurse.length} elderly');

      // Ensure assignments exist for all elderly in this house
      if (elderlyToNurse.isNotEmpty) {
        await _ensureAllAssignmentsExist(currentShift, currentDay, today);
      }

      print('✅ Background assignment creation completed');

      // Now fetch the vitals
      return await _getUpcomingVitals();
    } catch (e) {
      print('❌ Error ensuring assignments exist: $e');
      return [];
    }
  }

  Future<void> _updateVitals(Map<String, dynamic> elderlyInfo) async {
    print('🔄 Navigating to update vitals for: ${elderlyInfo['elderly_name']}');
    print('🏥 Assignment ID being passed: ${elderlyInfo['assignment_id']}');
    print('👴 Elderly ID: ${elderlyInfo['elderly_id']}');

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VitalUpdateScreen(
          assignmentId: elderlyInfo['assignment_id'],
          elderlyId: elderlyInfo['elderly_id'],
          elderlyName: elderlyInfo['elderly_name'],
          nurseName: widget.nurseName,
          houseId: widget.houseId,
        ),
      ),
    );

    // Refresh the list if vitals were updated (removes from upcoming)
    if (result == true && mounted) {
      await _refreshVitals();
      // Optionally: trigger a callback/event to update completed tab if needed
    }
  }

  // 🆕 FOLLOW-UP VITALS: Show selection screen for follow-up recordings
  Future<void> _showFollowUpVitalsSelection() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FollowUpVitalsSelectionScreen(
          nurseName: widget.nurseName,
          houseId: widget.houseId,
        ),
      ),
    );

    // Refresh the list if follow-up vitals were recorded
    if (result == true && mounted) {
      await _refreshVitals();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    print(
      '🏗️ UpcomingVitalsTab build() called with houseId: ${widget.houseId}',
    );
    final upcomingVitals = _upcomingVitals ?? [];

    // Check if nurse is not assigned to current shift
    if (_isNotAssignedToShift) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'You are not assigned to this shift',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Please check your schedule or contact your supervisor',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Always show loading spinner if _isLoading is true
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              upcomingVitals.isEmpty
                  ? 'Creating assignments...'
                  : 'Loading assignments...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Show empty state if no assignments
    if (upcomingVitals.isEmpty) {
      return Center(
        child: Text(
          'No upcoming vitals',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _refreshVitals,
          child: ListView.builder(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
            itemCount: upcomingVitals.length,
            itemBuilder: (context, index) {
              final elderlyInfo = upcomingVitals[index];
              final lastVital =
                  elderlyInfo['last_vital'] as Map<String, dynamic>?;

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Elderly Name
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: const Color(0xFF00588E),
                            child:
                                elderlyInfo['elderly_profilePic']?.isNotEmpty ==
                                    true
                                ? ClipOval(
                                    child: Image.network(
                                      elderlyInfo['elderly_profilePic'],
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Icon(Icons.person, color: Colors.white),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              elderlyInfo['elderly_name'] ?? 'Unknown',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588E),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      // Assigned Nurse
                      Text(
                        'Assigned to: ${elderlyInfo['assigned_nurse_name'] ?? 'Unknown'}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: 12),

                      // Status and Tap to Update
                      GestureDetector(
                        onTap: () => _updateVitals(elderlyInfo),
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: elderlyInfo['status'] == 'missed'
                                  ? Colors.red.withOpacity(0.3)
                                  : Colors.orange.withOpacity(0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: elderlyInfo['status'] == 'missed'
                                ? Colors.red.withOpacity(0.1)
                                : Colors.orange.withOpacity(0.1),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                elderlyInfo['status'] == 'missed'
                                    ? Icons.warning
                                    : Icons.pending_actions,
                                color: elderlyInfo['status'] == 'missed'
                                    ? Colors.red
                                    : Colors.orange,
                                size: 24,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                elderlyInfo['is_inherited'] ==
                                                    true
                                                ? Colors.blue
                                                : Colors.orange,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            elderlyInfo['is_inherited'] == true
                                                ? 'INHERITED'
                                                : 'PENDING',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            elderlyInfo['is_inherited'] == true
                                                ? 'From Previous Shift'
                                                : 'Not Updated Today',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color:
                                                  elderlyInfo['is_inherited'] ==
                                                      true
                                                  ? Colors.blue
                                                  : Colors.orange,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 4),
                                    // Split the inherited info into separate lines to prevent overflow
                                    if (elderlyInfo['is_inherited'] ==
                                        true) ...[
                                      Text(
                                        'Originally: ${elderlyInfo['original_nurse']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${elderlyInfo['inherited_from_shift']} shift - Tap to complete',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ] else
                                      Text(
                                        'Tap to update vital signs for ${_getTodayDateString()}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                color: elderlyInfo['is_inherited'] == true
                                    ? Colors.blue
                                    : Colors.orange,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Last vital info if available
                      if (lastVital != null) ...[
                        SizedBox(height: 12),
                        Text(
                          'Last recorded vitals:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                        SizedBox(height: 8),
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.withOpacity(0.1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'BP: ${lastVital['blood_pressure'] ?? 'N/A'}',
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Pulse: ${lastVital['pulse_rate'] ?? 'N/A'}',
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'O₂: ${lastVital['o2_sat'] ?? 'N/A'}%',
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Temp: ${lastVital['temperature'] ?? 'N/A'}°C',
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 4),
                              Text(
                                'RR: ${lastVital['respiratory_rate'] ?? 'N/A'}',
                              ),
                              if (lastVital['vital_record_at'] != null)
                                Text(
                                  'Recorded: ${DateFormat('MMM dd, yyyy HH:mm').format((lastVital['vital_record_at'] as Timestamp).toDate())}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton.extended(
            onPressed: _showFollowUpVitalsSelection,
            backgroundColor: Colors.green[600],
            foregroundColor: Colors.white,
            icon: Icon(Icons.add_circle_outline),
            label: Text(
              'Follow-up',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            heroTag: "followup_vitals_fab",
          ),
        ),
      ],
    );
  }

  // 🔧 FIXED: Ensure all assigned elderly have vital assignments
  Future<void> _ensureAllAssignmentsExist(
    String shift,
    String currentDay,
    String today,
  ) async {
    try {
      print('🔍 Checking all nurse assignments...');

      // Get elderly assigned to ALL nurses (general assignments)
      final nurseAssignmentsQuery = await _firestore
          .collection('elderly_assignments')
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where(
            'house_id',
            arrayContains: widget.houseId,
          ) // 🔧 FIXED: Filter by house
          .where('shift', isEqualTo: shift) // 🔧 FIXED: Filter by current shift
          .where(
            'day',
            isEqualTo: currentDay,
          ) // 🔧 FIXED: Filter by current day
          .get();

      final elderlyToProcess = <String, String>{}; // elderlyId -> nurseId

      for (final assignDoc in nurseAssignmentsQuery.docs) {
        final data = assignDoc.data();
        final assignedNurseId = data['user_id'] as String;
        final elderlyIds = List<String>.from(data['elderly_ids'] ?? []);
        for (final elderlyId in elderlyIds) {
          elderlyToProcess[elderlyId] = assignedNurseId;
        }
      }

      print(
        '📋 Found ${elderlyToProcess.length} elderly assignments for all nurses',
      );

      // Process each elderly assignment
      for (final entry in elderlyToProcess.entries) {
        final elderlyId = entry.key;
        final assignedNurseId = entry.value;

        // Fetch elderly details to get house information
        final elderlyDoc = await _firestore
            .collection('elderly')
            .doc(elderlyId)
            .get();

        if (!elderlyDoc.exists) {
          print('⚠️ Elderly document not found: $elderlyId');
          continue;
        }

        final elderlyData = elderlyDoc.data()!;

        // Only process elderly in the current house (like medication does)
        if (elderlyData['house_id'] != widget.houseId) {
          print(
            '⏭️ Skipping elderly $elderlyId - not in current house ${widget.houseId}',
          );
          continue;
        }

        // Only process alive elderly
        if (elderlyData['elderly_status'] != 'Alive') {
          print(
            '⏭️ Skipping elderly $elderlyId - status is ${elderlyData['elderly_status']}',
          );
          continue;
        }

        final elderlyName =
            '${elderlyData['elderly_fname'] ?? ''} ${elderlyData['elderly_lname'] ?? ''}'
                .trim();
        final elderlyHouseId = elderlyData['house_id'];

        print(
          '📋 Checking assignments for: $elderlyName (House: $elderlyHouseId, Nurse: $assignedNurseId)',
        );

        // Check if vital assignment already exists for this elderly/nurse/shift/day
        final existingVitalQuery = await _firestore
            .collection('vitals')
            .where('elderly_id', isEqualTo: elderlyId)
            .where('assigned_nurse_id', isEqualTo: assignedNurseId)
            .where('assigned_date', isEqualTo: today)
            .where('shift', isEqualTo: shift)
            .limit(1)
            .get();

        // If no vital assignment exists for this nurse, check if vitals were already completed today by ANY nurse
        if (existingVitalQuery.docs.isEmpty) {
          final completedTodayQuery = await _firestore
              .collection('vitals')
              .where('elderly_id', isEqualTo: elderlyId)
              .where('assigned_date', isEqualTo: today)
              .where('status', isEqualTo: 'completed')
              .limit(1)
              .get();

          if (completedTodayQuery.docs.isNotEmpty) {
            print(
              '⏭️ Skipping assignment creation for: $elderlyName - vitals already completed today by another nurse',
            );
            continue; // Skip creating new assignment
          }

          print(
            '➕ Creating vital assignment for: $elderlyName (House: $elderlyHouseId, Nurse: $assignedNurseId)',
          );

          await _firestore.collection('vitals').add({
            // 🔧 ASSIGNMENT FIELDS (required)
            'elderly_id': elderlyId,
            'assigned_nurse_id': assignedNurseId,
            'house_id': elderlyHouseId, // Use the elderly's actual house_id
            'shift': shift,
            'assigned_date': today,
            'status': 'pending',
            'created_at': FieldValue.serverTimestamp(),

            // 🔧 ULTRA CLEAN: Only essential vital fields (null until recorded)
            'blood_pressure': null,
            'pulse_rate': null,
            'oxygen_saturation': null,
            'temperature': null,
            'respiratory_rate': null,

            // ✅ Single completion timestamp (null until completed)
            'completed_at': null,

            // ✅ Minimal tracking (null until updated)
            'updated_by_nurse_id': null,
          });
          print('✅ Created vital assignment for: $elderlyName');
        } else {
          print('ℹ️ Vital assignment already exists for: $elderlyName');
        }
      }

      print('✅ All assignments verified and created if needed');
    } catch (e) {
      print('❌ Error ensuring assignments exist: $e');
    }
  }
}
