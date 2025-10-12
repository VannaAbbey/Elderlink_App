import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

      // Fast-path: check if there is at least one pending assignment for this nurse/house/shift
      final today = _getTodayDateString();
      final currentShift = _getCurrentShift();
      final quickCheck = await _firestore
          .collection('vitals')
          .where('assigned_nurse_id', isEqualTo: nurseId)
          .where(
            'house_id',
            isEqualTo: widget.houseId,
          ) // ✅ Filter by current house
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (quickCheck.docs.isEmpty) {
        // No assignments yet - spawn background creation but render UI quickly
        _ensureAssignmentsExistInBackground(
          nurseId,
          currentShift,
          _getCurrentDay(),
          today,
        );

        if (mounted) {
          setState(() {
            _upcomingVitals = [];
            _isLoading = false; // stop spinner so UI is responsive
          });
        }

        // update cache as empty for now
        _houseVitalsCache[cacheKey] = [];
        _houseVitalsCacheTime[cacheKey] = DateTime.now();
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

    print('🔄 Checking shift transition: $previousShift → $currentShift');

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

    // Mark previous shift assignments as missed when shift changes
    // This ensures pending work from previous shift is properly handled
    if (previousShiftAssignments.docs.isNotEmpty) {
      // Check if the current nurse is different from the nurse who had previous shift assignments
      final firstAssignment = previousShiftAssignments.docs.first.data();
      final previousNurseId = firstAssignment['assigned_nurse_id'];
      final previousNurseName = firstAssignment['assigned_nurse_name'];

      print(
        'Previous nurse: $previousNurseName ($previousNurseId), Current nurse: ${widget.nurseName} ($currentNurseId)',
      );

      // Always transfer previous shift assignments to current nurse when shift changes
      print(
        '🔄 Shift transition detected - transferring previous shift assignments to current nurse',
      );

      for (final doc in previousShiftAssignments.docs) {
        final data = doc.data();

        // Transfer the assignment to the current nurse
        await doc.reference.update({
          'assigned_nurse_id': currentNurseId,
          'assigned_nurse_name': widget.nurseName,
          'shift': currentShift, // Update to current shift
          'updated_at': FieldValue.serverTimestamp(),
          // Add inheritance tracking
          'inherited_from_shift': previousShift,
          'inherited_from_nurse_id': data['assigned_nurse_id'],
          'inherited_from_nurse_name': data['assigned_nurse_name'],
          'transfer_reason': 'Shift ended - inherited from previous shift',
        });

        // Log the transfer action
        await _firestore.collection('vital_activity_logs').add({
          'vital_assignment_id': doc.id,
          'elderly_id': data['elderly_id'],
          'elderly_name': data['elderly_name'],
          'nurse_id': currentNurseId,
          'nurse_name': widget.nurseName,
          'action_type': 'inherited',
          'house_id': data['house_id'],
          'timestamp': FieldValue.serverTimestamp(),
          'reason': 'Shift ended - inherited from previous shift',
          'previous_shift': previousShift,
          'current_shift': currentShift,
          'inherited_from_nurse_id': data['assigned_nurse_id'],
          'inherited_from_nurse_name': data['assigned_nurse_name'],
        });

        print(
          '✅ Transferred assignment for: ${data['elderly_name']} (inherited from ${data['assigned_nurse_name']} - $previousShift shift)',
        );
      }
    }
  }

  // Clean up assignments for elderly no longer assigned to this nurse
  // ⚠️ IMPORTANT: Never delete vital records - only update status to maintain history
  Future<void> _cleanupStaleAssignments(
    String nurseId,
    String shift,
    String currentDay,
    String today,
  ) async {
    try {
      print(
        '🧹 Updating stale assignments (no deletions - preserving history)...',
      );

      // Get elderly IDs assigned to this nurse/shift/day in CURRENT house only
      final validElderlyIds = <String>{};

      final assignedElderlyQuery = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('day', isEqualTo: currentDay)
          .where('shift', isEqualTo: shift)
          .get();

      // Filter elderly by current house
      for (var assignDoc in assignedElderlyQuery.docs) {
        final elderlyIds = List<String>.from(assignDoc['elderly_ids'] ?? []);
        for (final elderlyId in elderlyIds) {
          // Check if this elderly belongs to the current house
          final elderlyDoc = await _firestore
              .collection('elderly')
              .doc(elderlyId)
              .get();
          if (elderlyDoc.exists) {
            final elderlyData = elderlyDoc.data()!;
            if (elderlyData['house_id'] == widget.houseId) {
              validElderlyIds.add(elderlyId);
            }
          }
        }
      }

      print(
        '🧹 Valid elderly IDs for this nurse in current house: $validElderlyIds',
      );

      // ⚠️ IMPORTANT: Only query assignments for THIS nurse in CURRENT house to avoid touching other nurses' data
      final existingAssignments = await _firestore
          .collection('vitals')
          .where(
            'assigned_nurse_id',
            isEqualTo: nurseId,
          ) // ✅ Only this nurse's assignments
          .where('house_id', isEqualTo: widget.houseId) // ✅ Only current house
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: shift)
          .where('status', isEqualTo: 'pending')
          .get();

      int updatedCount = 0;
      for (final doc in existingAssignments.docs) {
        final data = doc.data();
        final elderlyId = data['elderly_id'];

        // Instead of deleting, mark as reassigned if elderly is no longer assigned to this nurse
        if (!validElderlyIds.contains(elderlyId)) {
          await doc.reference.update({
            'status': 'reassigned',
            'updated_at': FieldValue.serverTimestamp(),
            'reassignment_reason': 'Elderly no longer assigned to this nurse',
            'reassigned_at': FieldValue.serverTimestamp(),
          });
          updatedCount++;
          print(
            '� Marked assignment as reassigned for elderly: $elderlyId (no longer assigned to nurse)',
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

  // Update assignments for incorrect or changed data
  // ⚠️ IMPORTANT: Never delete vital records - only update status to maintain history
  Future<void> _cleanupIncorrectAssignments(
    String nurseId,
    List<String> validElderlyIds,
  ) async {
    final today = _getTodayDateString();
    final currentShift = _getCurrentShift();

    print(
      '🧹 Updating incorrect assignments (no deletions - preserving history)...',
    );
    print('🧹 Valid elderly IDs for this nurse: $validElderlyIds');

    // Get all vital assignments for this nurse, today, and current shift in CURRENT house
    // Only consider pending assignments for status updates to avoid modifying completed/missed records
    // ⚠️ IMPORTANT: Only query assignments for THIS nurse in CURRENT house to avoid touching other nurses' data
    final incorrectAssignments = await _firestore
        .collection('vitals')
        .where(
          'assigned_nurse_id',
          isEqualTo: nurseId,
        ) // ✅ Only this nurse's assignments
        .where('house_id', isEqualTo: widget.houseId) // ✅ Only current house
        .where('assigned_date', isEqualTo: today)
        .where('shift', isEqualTo: currentShift)
        .where('status', isEqualTo: 'pending')
        .get();

    int updatedCount = 0;
    for (final doc in incorrectAssignments.docs) {
      final data = doc.data();
      final elderlyId = data['elderly_id'];
      final assignmentHouseId = data['house_id'];
      bool shouldUpdate = false;
      String updateReason = '';

      // Check if elderly ID is in the valid list for this nurse
      if (!validElderlyIds.contains(elderlyId)) {
        shouldUpdate = true;
        updateReason = 'Elderly not assigned to this nurse';
      }
      // Double-check against actual elderly data
      else {
        final elderlyDoc = await _firestore
            .collection('elderly')
            .doc(elderlyId)
            .get();

        if (elderlyDoc.exists) {
          final elderlyData = elderlyDoc.data()!;
          final actualHouseId = elderlyData['house_id'];
          final elderlyStatus = elderlyData['elderly_status'];

          // Update assignment house_id if it doesn't match the elderly's actual house
          if (actualHouseId != assignmentHouseId) {
            await doc.reference.update({'house_id': actualHouseId});
            print(
              '🔄 Updated house_id for ${data['elderly_name']} from $assignmentHouseId to $actualHouseId',
            );
          }

          // Mark as inactive if elderly is not alive (but don't delete)
          if (elderlyStatus != 'Alive') {
            shouldUpdate = true;
            updateReason =
                'Elderly status is not Alive (status: $elderlyStatus)';
          }
        } else {
          shouldUpdate = true;
          updateReason = 'Elderly document does not exist';
        }
      }

      if (shouldUpdate) {
        await doc.reference.update({
          'status': 'inactive',
          'updated_at': FieldValue.serverTimestamp(),
          'inactivation_reason': updateReason,
          'inactive_at': FieldValue.serverTimestamp(),
        });
        updatedCount++;
        print(
          '� Marked assignment as inactive: ${data['elderly_name']} - $updateReason',
        );
      }
    }

    print(
      '🧹 Status update complete: Updated $updatedCount incorrect assignments',
    );
  }

  Future<void> _createDailyVitalAssignments(
    String nurseId,
    List<String> elderlyIds,
  ) async {
    final today = _getTodayDateString();
    final currentShift = _getCurrentShift();

    print(
      '🏗️ Creating daily vital assignments for date: $today, shift: $currentShift',
    );
    print('🏗️ Nurse ID: $nurseId');
    print('🏗️ House ID: ${widget.houseId}');
    print('🏗️ Elderly IDs count: ${elderlyIds.length}');

    // ⚠️ IMPORTANT: This method only creates assignments for the specified nurseId.
    // It never modifies or deletes other nurses' existing assignments.
    final batch = _firestore.batch();
    int batchCreates = 0;

    for (final elderlyId in elderlyIds) {
      // Check if vital assignment already exists for this specific nurse
      final existingQuery = await _firestore
          .collection('vitals')
          .where('elderly_id', isEqualTo: elderlyId)
          .where(
            'assigned_nurse_id',
            isEqualTo: nurseId,
          ) // ✅ Ensures we only check THIS nurse's assignments
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .limit(1)
          .get();

      if (existingQuery.docs.isEmpty) {
        // Double-check that this elderly is still assigned to this nurse (simplified to avoid arrayContains conflict)
        final currentAssignmentCheck = await _firestore
            .collection('elderly_assignments')
            .where('user_id', isEqualTo: nurseId)
            .where('user_type', isEqualTo: 'nurse')
            .where('is_current', isEqualTo: true)
            .where('elderly_ids', arrayContains: elderlyId)
            .where('day', isEqualTo: _getCurrentDay())
            .where('shift', isEqualTo: currentShift)
            .limit(1)
            .get();

        // Additional client-side check for house assignment
        bool isValidAssignment = false;

        // Get elderly details first
        final elderlyDoc = await _firestore
            .collection('elderly')
            .doc(elderlyId)
            .get();

        if (elderlyDoc.exists) {
          final elderlyData = elderlyDoc.data()!;
          final elderlyHouseId = elderlyData['house_id'];

          // Check if nurse is assigned to this elderly's house
          if (currentAssignmentCheck.docs.isNotEmpty) {
            final data = currentAssignmentCheck.docs.first.data();
            final houseIds = List<String>.from(data['house_id'] ?? []);
            isValidAssignment = houseIds.contains(elderlyHouseId);
          }
        }

        if (!isValidAssignment) {
          print(
            '⏭️ Skipping vital assignment creation for $elderlyId - nurse not assigned to this elderly\'s house',
          );
          continue;
        }

        if (elderlyDoc.exists) {
          final elderlyData = elderlyDoc.data()!;

          // Only create assignment if elderly is Alive (no house check needed since we already validated house assignment)
          if (elderlyData['elderly_status'] == 'Alive') {
            final elderlyName =
                '${elderlyData['elderly_fname'] ?? ''} ${elderlyData['elderly_lname'] ?? ''}'
                    .trim();

            final docRef = _firestore.collection('vitals').doc();
            batch.set(docRef, {
              'elderly_id': elderlyId,
              'elderly_name': elderlyName,
              'assigned_nurse_id': nurseId,
              'assigned_nurse_name': widget.nurseName ?? 'Unknown',
              'house_id': elderlyData['house_id'],
              'shift': currentShift,
              'assigned_date': today,
              'status': 'pending',
              'created_at': FieldValue.serverTimestamp(),
              'blood_pressure': null,
              'pulse_rate': null,
              'oxygen_saturation': null,
              'temperature': null,
              'respiratory_rate': null,
              'vital_remarks': null,
              'completed_at': null,
              'updated_by_nurse_id': null,
              'updated_by_nurse_name': null,
            });
            batchCreates++;
            print('➕ Queued create for vital assignment: $elderlyName');
          }
        }
      } else {
        print(
          '⏭️ EXISTING assignment found for elderly: $elderlyId, skipping creation',
        );
      }
    }

    if (batchCreates > 0) {
      try {
        await batch.commit();
        print('✅ Batch created $batchCreates vital assignments');
      } catch (e) {
        print('❌ Error committing batch create: $e');
      }
    } else {
      print('ℹ️ No new assignments to create');
    }
  }

  /// ⚡ OPTIMIZED: Cached nurse data to avoid repeated lookups
  String? _cachedNurseId;
  DateTime? _lastCacheTime;

  Future<String?> _getCachedNurseId() async {
    // Cache for 5 minutes to avoid repeated user lookups
    if (_cachedNurseId != null &&
        _lastCacheTime != null &&
        DateTime.now().difference(_lastCacheTime!).inMinutes < 5) {
      return _cachedNurseId;
    }

    final nameParts = widget.nurseName?.split(' ') ?? [];
    if (nameParts.length < 2) {
      print('Invalid nurse name format: ${widget.nurseName}');
      return null;
    }

    final firstName = nameParts[0];
    final lastName = nameParts[1];

    final userQuery = await _firestore
        .collection('users')
        .where('user_fname', isEqualTo: firstName)
        .where('user_lname', isEqualTo: lastName)
        .where('user_type', isEqualTo: 'nurse')
        .get();

    if (userQuery.docs.isEmpty) {
      print('No nurse found with name: $firstName $lastName');
      return null;
    }

    _cachedNurseId = userQuery.docs.first.id;
    _lastCacheTime = DateTime.now();
    return _cachedNurseId;
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

      // 🔧 FIXED: Always ensure assignments exist first before querying
      print('🔄 Ensuring all assignments are created before fetching...');

      // First handle shift transition to create inherited assignments
      await _handleShiftTransition(nurseId);

      // Clean up any assignments for elderly no longer assigned to this nurse
      await _cleanupStaleAssignments(nurseId, currentShift, currentDay, today);

      // Then ensure all regular assignments are created
      await _ensureAllAssignmentsExist(
        nurseId,
        currentShift,
        currentDay,
        today,
      );

      // Get valid elderly IDs currently assigned to this nurse for this shift/day
      final validElderlyIds = <String>{};
      final nurseElderlyQuery = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .where('day', isEqualTo: currentDay)
          .get();

      for (final doc in nurseElderlyQuery.docs) {
        final data = doc.data();
        final elderlyIds = List<String>.from(data['elderly_ids'] ?? []);
        validElderlyIds.addAll(elderlyIds);
      }

      print(
        '✅ Valid elderly IDs for this nurse/shift/day: ${validElderlyIds.length}',
      );

      // 🔧 FIXED: Query vitals collection to get assignments for this nurse in CURRENT house only
      // Only show 'pending' status assignments in UI - 'reassigned' and 'inactive' are historical records
      final vitalsQuery = await _firestore
          .collection('vitals')
          .where('assigned_nurse_id', isEqualTo: nurseId)
          .where(
            'house_id',
            isEqualTo: widget.houseId,
          ) // ✅ Filter by current house
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .where(
            'status',
            isEqualTo: 'pending',
          ) // ✅ Only active assignments for UI
          .get();

      print(
        '⚡ Found ${vitalsQuery.docs.length} pending vital assignments for current house',
      );

      // Process vitals assignments to get assigned elderly that are still valid
      final upcomingVitals = <Map<String, dynamic>>[];
      final seenElderlyIds = <String>{};

      for (final vitalDoc in vitalsQuery.docs) {
        final vitalData = vitalDoc.data();
        final elderlyId = vitalData['elderly_id'];

        // Only process elderly that are currently assigned to this nurse
        if (!validElderlyIds.contains(elderlyId)) {
          print(
            '⏭️ Skipping elderly $elderlyId - not currently assigned to this nurse',
          );
          continue;
        }

        if (!seenElderlyIds.contains(elderlyId)) {
          seenElderlyIds.add(elderlyId);

          // Get elderly details
          final elderlyDoc = await _firestore
              .collection('elderly')
              .doc(elderlyId)
              .get();
          if (!elderlyDoc.exists) continue;

          final elderlyData = elderlyDoc.data()!;
          // Process all elderly assigned to this nurse (no house filtering needed)

          upcomingVitals.add({
            'assignment_id': vitalDoc.id, // ✅ Use actual vitals document ID
            'elderly_id': elderlyId,
            'elderly_name':
                '${elderlyData['elderly_fname'] ?? 'Unknown'} ${elderlyData['elderly_lname'] ?? 'Elderly'}',
            'elderly_profilePic': elderlyData['profilePic'] ?? '',
            'house_id': elderlyData['house_id'],
            'status': 'pending',
            'assigned_date': today,
            'shift': currentShift,
            'original_nurse':
                vitalData['inherited_from_nurse_name'] ??
                widget.nurseName ??
                'Unknown Nurse',
            'is_inherited': vitalData['inherited_from_shift'] != null,
            'inherited_from_shift': vitalData['inherited_from_shift'],
            'last_vital': null, // Can be loaded on-demand later
          });

          print(
            '✅ Added elderly: ${elderlyData['elderly_fname']} ${elderlyData['elderly_lname']} with vitals doc ID: ${vitalDoc.id}',
          );
        }
      }

      // Sort by elderly name
      upcomingVitals.sort(
        (a, b) => (a['elderly_name'] as String).compareTo(
          b['elderly_name'] as String,
        ),
      );

      print('⚡ Returning ${upcomingVitals.length} elderly assignments');
      return upcomingVitals;
    } catch (e) {
      print('❌ Error getting upcoming vitals: $e');
      return [];
    }
  }

  /// ⚡ BACKGROUND: Ensure assignments exist without blocking UI
  void _ensureAssignmentsExistInBackground(
    String nurseId,
    String currentShift,
    String currentDay,
    String today,
  ) async {
    try {
      print('🔄 Background: Ensuring assignments exist...');

      // Handle shift transition in background
      await _handleShiftTransition(nurseId);

      // Check shift assignment
      final shiftQuery = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .where('days_assigned', arrayContains: currentDay)
          .get();

      if (shiftQuery.docs.isEmpty) {
        print('🔄 Background: Nurse not assigned to this shift');
        return;
      }

      // Get ALL nurse's assigned elderly for current day and shift across ALL houses
      final nurseElderlyQuery = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .where('day', isEqualTo: currentDay)
          .get();

      if (nurseElderlyQuery.docs.isEmpty) {
        print(
          '🔄 Background: No nurse elderly assignments found for this shift',
        );
        return;
      }

      // Collect elderly IDs assigned to this nurse in CURRENT house only
      final allElderlyIds = <String>[];
      for (final doc in nurseElderlyQuery.docs) {
        final data = doc.data();
        final elderlyIds = List<String>.from(data['elderly_ids'] ?? []);
        // Filter by current house
        for (final elderlyId in elderlyIds) {
          final elderlyDoc = await _firestore
              .collection('elderly')
              .doc(elderlyId)
              .get();
          if (elderlyDoc.exists) {
            final elderlyData = elderlyDoc.data()!;
            if (elderlyData['house_id'] == widget.houseId) {
              allElderlyIds.add(elderlyId);
            }
          }
        }
      }

      if (allElderlyIds.isEmpty) {
        print('🔄 Background: No elderly assigned to this nurse');
        return;
      }

      // ⚡ OPTIMIZATION: Batch fetch elderly data instead of individual queries
      final validElderlyIds = <String>[];

      if (allElderlyIds.isNotEmpty) {
        // Process in chunks of 10 to respect Firestore's 'whereIn' limit
        for (var i = 0; i < allElderlyIds.length; i += 10) {
          final end = (i + 10 < allElderlyIds.length)
              ? i + 10
              : allElderlyIds.length;
          final chunk = allElderlyIds.sublist(i, end);

          final elderlyQuery = await _firestore
              .collection('elderly')
              .where(FieldPath.documentId, whereIn: chunk)
              .where('elderly_status', isEqualTo: 'Alive')
              .get();

          for (final doc in elderlyQuery.docs) {
            validElderlyIds.add(doc.id);
          }
        }
      }

      if (validElderlyIds.isNotEmpty) {
        // Clean up incorrect assignments (only for elderly no longer assigned)
        await _cleanupIncorrectAssignments(nurseId, validElderlyIds);

        // Create missing assignments for ALL valid elderly
        await _createDailyVitalAssignments(nurseId, validElderlyIds);

        // Refresh UI with new data by updating the in-memory cache and state
        try {
          final cacheKey = widget.houseId + (widget.nurseName ?? "");
          final vitals = await _getUpcomingVitals();
          _houseVitalsCache[cacheKey] = vitals;
          _houseVitalsCacheTime[cacheKey] = DateTime.now();
          if (mounted) {
            setState(() {
              _upcomingVitals = vitals;
              _isLoading = false;
            });
          }
          print(
            '✅ Background: Assignment creation completed, cache & UI updated',
          );
        } catch (e) {
          print('❌ Background: Failed to refresh cache/UI: $e');
        }
      }
    } catch (e) {
      print('❌ Background assignment creation failed: $e');
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

    // Refresh the list if vitals were updated
    if (result == true && mounted) {
      await _refreshVitals();
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

    // Always show loading spinner if _isLoading is true or if there are no assignments
    if (_isLoading || upcomingVitals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading assignments...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
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
            label: Text('Follow-up'),
            heroTag: "followup_vitals_fab",
          ),
        ),
      ],
    );
  }

  // 🔧 FIXED: Ensure all assigned elderly have vital assignments
  Future<void> _ensureAllAssignmentsExist(
    String nurseId,
    String shift,
    String currentDay,
    String today,
  ) async {
    try {
      print('🔍 Checking all nurse assignments...');

      // ⚠️ IMPORTANT: This method only creates assignments for the specified nurseId.
      // It never modifies or deletes other nurses' existing assignments.

      // Get elderly assigned to this nurse for current day/shift in CURRENT house only
      final assignedElderlyQuery = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('day', isEqualTo: currentDay)
          .where('shift', isEqualTo: shift)
          .get();

      // Process assignments and filter by current house
      for (var assignDoc in assignedElderlyQuery.docs) {
        final elderlyIds = List<String>.from(assignDoc['elderly_ids'] ?? []);
        for (final elderlyId in elderlyIds) {
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

          // ✅ Only process elderly that belong to the current house
          if (elderlyData['house_id'] != widget.houseId) {
            continue; // Skip elderly from other houses
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
            '📋 Checking assignments for: $elderlyName (House: $elderlyHouseId)',
          );

          // Check if vital assignment already exists (for ANY house - we create once per nurse/elderly/shift/day)
          final existingVitalQuery = await _firestore
              .collection('vitals')
              .where('elderly_id', isEqualTo: elderlyId)
              .where(
                'assigned_nurse_id',
                isEqualTo: nurseId,
              ) // ✅ Ensures assignment is for THIS nurse only
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
              '➕ Creating vital assignment for: $elderlyName (House: $elderlyHouseId)',
            );

            await _firestore.collection('vitals').add({
              // 🔧 ASSIGNMENT FIELDS (required)
              'elderly_id': elderlyId,
              'elderly_name': elderlyName,
              'assigned_nurse_id': nurseId,
              'assigned_nurse_name': widget.nurseName ?? 'Unknown',
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
              'vital_remarks': null,

              // ✅ Single completion timestamp (null until completed)
              'completed_at': null,

              // ✅ Minimal tracking (null until updated)
              'updated_by_nurse_id': null,
              'updated_by_nurse_name': null,
            });
            print('✅ Created vital assignment for: $elderlyName');
          } else {
            print('ℹ️ Vital assignment already exists for: $elderlyName');
          }
        }
      }

      print('✅ All assignments verified and created if needed');
    } catch (e) {
      print('❌ Error ensuring assignments exist: $e');
    }
  }
}
