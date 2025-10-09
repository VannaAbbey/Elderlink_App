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

class _UpcomingVitalsTabState extends State<UpcomingVitalsTab>
    with AutomaticKeepAliveClientMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  List<Map<String, dynamic>>? _upcomingVitals;
  // Simple in-memory cache per houseId
  static final Map<String, List<Map<String, dynamic>>> _houseVitalsCache = {};
  static final Map<String, DateTime> _houseVitalsCacheTime = {};
  // Keep a longer cache to avoid repeated reloads when switching houses/tabs
  static const Duration cacheDuration = Duration(minutes: 5); // Cache for 5m

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
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

  Future<void> _loadUpcomingVitals() async {
    final cacheKey = widget.houseId + (widget.nurseName ?? "");
    final now = DateTime.now();
    bool cacheValid = false;

    // Always set loading to true at the start, so spinner is shown until data is ready
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    if (_houseVitalsCache.containsKey(cacheKey) &&
        _houseVitalsCacheTime.containsKey(cacheKey)) {
      final cacheTime = _houseVitalsCacheTime[cacheKey]!;
      if (now.difference(cacheTime) < cacheDuration) {
        cacheValid = true;
      }
    }

    if (cacheValid) {
      if (mounted) {
        setState(() {
          _upcomingVitals = _houseVitalsCache[cacheKey]!;
          _isLoading = false;
        });
      }
      // Only refresh in background after the TTL to avoid aggressive reads
      Future.delayed(cacheDuration, () async {
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
      return;
    }

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

      // Fast-path: check if there is at least one pending assignment for this nurse/house/shift
      final today = _getTodayDateString();
      final currentShift = _getCurrentShift();
      final quickCheck = await _firestore
          .collection('vitals')
          .where('assigned_nurse_id', isEqualTo: nurseId)
          .where('house_id', isEqualTo: widget.houseId)
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
    await _loadUpcomingVitals();
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

    // Only mark as missed if a DIFFERENT nurse is now working this shift
    // (i.e., the shift has actually changed hands)
    if (previousShiftAssignments.docs.isNotEmpty) {
      // Check if the current nurse is different from the nurse who had previous shift assignments
      final firstAssignment = previousShiftAssignments.docs.first.data();
      final previousNurseId = firstAssignment['assigned_nurse_id'];
      final previousNurseName = firstAssignment['assigned_nurse_name'];

      print(
        'Previous nurse: $previousNurseName ($previousNurseId), Current nurse: ${widget.nurseName} ($currentNurseId)',
      );

      // Only transfer assignments if it's a different nurse taking over
      if (previousNurseId != currentNurseId) {
        print(
          '🔄 Different nurse detected - transferring assignments from $previousNurseName to ${widget.nurseName}',
        ); // Transfer previous shift assignments to current nurse as new pending assignments
        for (final doc in previousShiftAssignments.docs) {
          final data = doc.data();

          // First mark the original assignment as missed for logging purposes
          await doc.reference.update({
            'status': 'missed',
            'updated_at': FieldValue.serverTimestamp(),
            'missed_reason': 'Shift ended - transferred to next nurse',
          });

          // Log the missed action for the previous nurse
          await _firestore.collection('vital_activity_logs').add({
            'vital_assignment_id': doc.id,
            'elderly_id': data['elderly_id'],
            'elderly_name': data['elderly_name'],
            'nurse_id': data['assigned_nurse_id'],
            'nurse_name': data['assigned_nurse_name'],
            'action_type': 'missed',
            'house_id':
                data['house_id'], // Add house_id for activity logs filtering
            'timestamp':
                FieldValue.serverTimestamp(), // Use timestamp instead of action_timestamp for consistency
            'reason': 'Shift ended - transferred to next nurse',
            'previous_shift': previousShift,
            'current_shift': currentShift,
            'transferred_to_nurse_id': currentNurseId,
            'transferred_to_nurse_name': widget.nurseName,
          });

          // Create a new pending vital assignment for the current nurse
          print(
            '🏗️ Creating inherited assignment with nurse name: ${data['assigned_nurse_name']}',
          );
          await _firestore.collection('vitals').add({
            // Assignment fields
            'elderly_id': data['elderly_id'],
            'elderly_name': data['elderly_name'],
            'assigned_nurse_id': currentNurseId,
            'assigned_nurse_name': widget.nurseName,
            'house_id': widget.houseId,
            'assigned_date': today,
            'shift': currentShift,
            'status': 'pending',
            'created_at': FieldValue.serverTimestamp(),

            // Inheritance tracking
            'inherited_from_shift': previousShift,
            'inherited_from_nurse_id': data['assigned_nurse_id'],
            'inherited_from_nurse_name': data['assigned_nurse_name'],

            // 🔧 ULTRA CLEAN: Only essential vital fields (no redundancy)
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

          print(
            '✅ Created new pending assignment for: ${data['elderly_name']} (inherited from ${data['assigned_nurse_name']} - $previousShift shift)',
          );
        }
      } else {
        print(
          '🔄 Same nurse ($previousNurseName) continuing - keeping assignments as pending',
        );
      }
    }
  }

  // Create daily vital assignments for all assigned elderly
  Future<void> _cleanupIncorrectAssignments(
    String nurseId,
    List<String> validElderlyIds,
  ) async {
    final today = _getTodayDateString();
    final currentShift = _getCurrentShift();

    print('🧹 Cleaning up incorrect assignments...');
    print('🧹 Valid elderly IDs for this nurse: $validElderlyIds');

    // Get all vital assignments for this nurse, today, and current shift
    // Only consider pending assignments for cleanup to avoid deleting completed/missed records
    final incorrectAssignments = await _firestore
        .collection('vitals')
        .where('assigned_nurse_id', isEqualTo: nurseId)
        .where('assigned_date', isEqualTo: today)
        .where('shift', isEqualTo: currentShift)
        .where('status', isEqualTo: 'pending')
        .get();

    int deletedCount = 0;
    for (final doc in incorrectAssignments.docs) {
      final data = doc.data();
      final elderlyId = data['elderly_id'];
      final assignmentHouseId = data['house_id'];
      bool shouldDelete = false;
      String deleteReason = '';

      // Check if elderly ID is in the valid list for this nurse
      if (!validElderlyIds.contains(elderlyId)) {
        shouldDelete = true;
        deleteReason = 'Elderly not assigned to this nurse';
      }
      // Check if house_id matches the current tab's house
      else if (assignmentHouseId != widget.houseId) {
        shouldDelete = true;
        deleteReason =
            'Wrong house_id (was: $assignmentHouseId, should be: ${widget.houseId})';
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

          // Delete if elderly's actual house doesn't match assignment house
          if (actualHouseId != assignmentHouseId) {
            shouldDelete = true;
            deleteReason =
                'Elderly actual house mismatch (assignment: $assignmentHouseId, actual: $actualHouseId)';
          }
          // Delete if elderly is not alive
          else if (elderlyStatus != 'Alive') {
            shouldDelete = true;
            deleteReason =
                'Elderly status is not Alive (status: $elderlyStatus)';
          }
        } else {
          shouldDelete = true;
          deleteReason = 'Elderly document does not exist';
        }
      }

      if (shouldDelete) {
        await doc.reference.delete();
        deletedCount++;
        print(
          '🗑️ Deleted incorrect assignment: ${data['elderly_name']} - $deleteReason',
        );
      }
    }

    print('🧹 Cleanup complete: Deleted $deletedCount incorrect assignments');
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

    // Use a WriteBatch to reduce round-trips when creating many assignments
    final batch = _firestore.batch();
    int batchCreates = 0;

    for (final elderlyId in elderlyIds) {
      // Check if vital assignment already exists for today - simplified check
      final existingQuery = await _firestore
          .collection('vitals')
          .where('elderly_id', isEqualTo: elderlyId)
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .limit(1)
          .get();

      if (existingQuery.docs.isEmpty) {
        // Get elderly details
        final elderlyDoc = await _firestore
            .collection('elderly')
            .doc(elderlyId)
            .get();
        if (elderlyDoc.exists) {
          final elderlyData = elderlyDoc.data()!;

          // Only create assignment if elderly belongs to this house and is Alive
          if (elderlyData['house_id'] == widget.houseId &&
              elderlyData['elderly_status'] == 'Alive') {
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
        print('⏭️ EXISTING assignment found for elderly: $elderlyId, skipping creation');
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

      // Then ensure all regular assignments are created
      await _ensureAllAssignmentsExist(
        nurseId,
        currentShift,
        currentDay,
        today,
      );

      // Now query for vital assignments
      final assignmentsQuery = await _firestore
          .collection('vitals')
          .where('assigned_nurse_id', isEqualTo: nurseId)
          .where('house_id', isEqualTo: widget.houseId)
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .where('status', isEqualTo: 'pending') // Only show pending
          .get();

      print('⚡ Found ${assignmentsQuery.docs.length} existing assignments');

      // ⚡ OPTIMIZATION 3: If no assignments found, properly handle setup
      if (assignmentsQuery.docs.isEmpty) {
        print(
          '🔄 No existing assignments found, checking if assignments need to be created...',
        );

        // First handle shift transition to create inherited assignments
        await _handleShiftTransition(nurseId);

        // Check again after shift transition
        final assignmentsAfterTransition = await _firestore
            .collection('vitals')
            .where('assigned_nurse_id', isEqualTo: nurseId)
            .where('house_id', isEqualTo: widget.houseId)
            .where('assigned_date', isEqualTo: today)
            .where('shift', isEqualTo: currentShift)
            .where('status', isEqualTo: 'pending')
            .get();

        if (assignmentsAfterTransition.docs.isNotEmpty) {
          print(
            '✅ Found ${assignmentsAfterTransition.docs.length} assignments after shift transition',
          );
          // Process these assignments instead
          final upcomingVitals = <Map<String, dynamic>>[];
          final seenElderlyIds = <String>{};

          for (final assignmentDoc in assignmentsAfterTransition.docs) {
            final assignmentData = _validateVitalData(assignmentDoc.data());
            final elderlyId = assignmentData['elderly_id'];

            if (!seenElderlyIds.contains(elderlyId)) {
              seenElderlyIds.add(elderlyId);

              final isInherited =
                  assignmentData['inherited_from_shift'] != null;
              String originalNurseForDisplay =
                  assignmentData['assigned_nurse_name'] ?? 'Unknown Nurse';

              if (isInherited &&
                  assignmentData['inherited_from_nurse_name'] != null) {
                originalNurseForDisplay =
                    assignmentData['inherited_from_nurse_name'];
              }

              upcomingVitals.add({
                'assignment_id': assignmentDoc.id,
                'elderly_id': assignmentData['elderly_id'],
                'elderly_name':
                    assignmentData['elderly_name'] ?? 'Unknown Elderly',
                'elderly_profilePic':
                    assignmentData['elderly_profilePic'] ?? '',
                'house_id': assignmentData['house_id'],
                'status': 'pending',
                'assigned_date': assignmentData['assigned_date'],
                'shift': assignmentData['shift'],
                'original_nurse': originalNurseForDisplay,
                'is_inherited': isInherited,
                'inherited_from_shift': assignmentData['inherited_from_shift'],
                'last_vital': null, // Can be loaded on-demand later
              });
            }
          }

          // Sort by elderly name
          upcomingVitals.sort(
            (a, b) => (a['elderly_name'] as String).compareTo(
              b['elderly_name'] as String,
            ),
          );

          print(
            '⚡ Returning ${upcomingVitals.length} elderly assignments after transition',
          );
          return upcomingVitals;
        }

        // Still no assignments, continue with background creation
        _ensureAssignmentsExistInBackground(
          nurseId,
          currentShift,
          currentDay,
          today,
        );

        // Return empty for now - will refresh automatically when background completes
        return [];
      }

      // ⚡ OPTIMIZATION 4: Batch process assignments without individual elderly lookups
      final upcomingVitals = <Map<String, dynamic>>[];
      final seenElderlyIds = <String>{};

      for (final assignmentDoc in assignmentsQuery.docs) {
        final assignmentData = _validateVitalData(assignmentDoc.data());
        final elderlyId = assignmentData['elderly_id'];

        // Only show if not completed or missed
        if (assignmentData['status'] != 'pending') continue;

        if (!seenElderlyIds.contains(elderlyId)) {
          seenElderlyIds.add(elderlyId);

          final isInherited = assignmentData['inherited_from_shift'] != null;
          String originalNurseForDisplay =
              assignmentData['assigned_nurse_name'] ?? 'Unknown Nurse';

          if (isInherited &&
              assignmentData['inherited_from_nurse_name'] != null) {
            originalNurseForDisplay =
                assignmentData['inherited_from_nurse_name'];
          }

          upcomingVitals.add({
            'assignment_id': assignmentDoc.id,
            'elderly_id': assignmentData['elderly_id'],
            'elderly_name': assignmentData['elderly_name'] ?? 'Unknown Elderly',
            'elderly_profilePic': assignmentData['elderly_profilePic'] ?? '',
            'house_id': assignmentData['house_id'],
            'status': 'pending',
            'assigned_date': assignmentData['assigned_date'],
            'shift': assignmentData['shift'],
            'original_nurse': originalNurseForDisplay,
            'is_inherited': isInherited,
            'inherited_from_shift': assignmentData['inherited_from_shift'],
            'last_vital': null, // Can be loaded on-demand later
          });
        }
      }

      // Sort by elderly name
      upcomingVitals.sort(
        (a, b) => (a['elderly_name'] as String).compareTo(
          b['elderly_name'] as String,
        ),
      );

      print('⚡ FAST: Returning ${upcomingVitals.length} elderly assignments');
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
          .collection('nurse_shift_assign')
          .where('nurse_id', isEqualTo: nurseId)
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .where('days_assigned', arrayContains: currentDay)
          .get();

      if (shiftQuery.docs.isEmpty) {
        print('🔄 Background: Nurse not assigned to this shift');
        return;
      }

      // Get nurse's assigned elderly for current day and shift
      final nurseElderlyQuery = await _firestore
          .collection('nurse_elderly_assign')
          .where('nurse_id', isEqualTo: nurseId)
          .where('is_current', isEqualTo: true)
          .where('house_ids', arrayContains: widget.houseId)
          .where('shift', isEqualTo: currentShift)
          .where('day', isEqualTo: currentDay)
          .get();

      if (nurseElderlyQuery.docs.isEmpty) {
        print('🔄 Background: No nurse elderly assignments found');
        return;
      }

      final assignmentDoc = nurseElderlyQuery.docs.first;
      final data = assignmentDoc.data();
      final allElderlyIds = List<String>.from(data['elderly_ids'] ?? []);

      // ⚡ OPTIMIZATION: Batch fetch elderly data instead of individual queries
      final elderlyIdsForThisHouse = <String>[];

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
              .where('house_id', isEqualTo: widget.houseId)
              .where('elderly_status', isEqualTo: 'Alive')
              .get();

          for (final doc in elderlyQuery.docs) {
            elderlyIdsForThisHouse.add(doc.id);
          }
        }
      }

      if (elderlyIdsForThisHouse.isNotEmpty) {
        // Clean up incorrect assignments
        await _cleanupIncorrectAssignments(nurseId, elderlyIdsForThisHouse);

        // Create missing assignments
        await _createDailyVitalAssignments(nurseId, elderlyIdsForThisHouse);

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
        ListView.builder(
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
                                  if (elderlyInfo['is_inherited'] == true) ...[
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

  // 🧹 HELPER: Clean up any inconsistent data on load
  Map<String, dynamic> _validateVitalData(Map<String, dynamic> data) {
    // 🔧 ULTRA CLEAN: Only keep essential vital fields (no redundancy)
    final requiredVitalFields = [
      'blood_pressure',
      'pulse_rate',
      'oxygen_saturation',
      'temperature',
      'respiratory_rate',
      'vital_remarks',
      'completed_at', // ✅ Keep only this timestamp (not vital_record_at)
      'updated_by_nurse_id',
      'updated_by_nurse_name',
    ];
    for (String field in requiredVitalFields) {
      if (!data.containsKey(field)) {
        data[field] = null;
      }
    }

    // 🔧 CLEAN: Normalize old field names to new standard and remove redundant fields
    if (data.containsKey('heart_rate') && !data.containsKey('pulse_rate')) {
      data['pulse_rate'] = data['heart_rate'];
    }

    if (data.containsKey('o2_sat') && !data.containsKey('oxygen_saturation')) {
      data['oxygen_saturation'] = data['o2_sat'];
    }

    // 🧹 REMOVE: Delete ALL unnecessary/redundant fields
    final fieldsToRemove = [
      // Old field names
      'heart_rate', 'o2_sat',
      // Unused form fields
      'blood_pressure_systolic', 'blood_pressure_diastolic',
      // Redundant tracking fields
      'recorded_at', 'recorded_by_nurse_id', 'updated_by_nurse', 'updated_at',
      // 🔧 NEW: Remove redundant timestamp fields
      'last_updated',
      'last_updated_at',
      'vital_record_at', // Keep only completed_at
      // 🔧 NEW: Remove unnecessary profile pic
      'elderly_profilePic',
    ];

    for (String field in fieldsToRemove) {
      data.remove(field);
    }

    return data;
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

      // Get all elderly assigned to this nurse for current day/shift
      final assignedElderlyQuery = await _firestore
          .collection('nurse_elderly_assign')
          .where('nurse_id', isEqualTo: nurseId)
          .where('house_id', isEqualTo: widget.houseId)
          .where('${currentDay.toLowerCase()}_$shift', isEqualTo: true)
          .get();

      for (var assignDoc in assignedElderlyQuery.docs) {
        final elderlyId = assignDoc['elderly_id'];
        final elderlyName = assignDoc['elderly_name'];

        print('📋 Checking assignments for: $elderlyName');

        // Check if vital assignment already exists
        final existingVitalQuery = await _firestore
            .collection('vitals')
            .where('elderly_id', isEqualTo: elderlyId)
            .where('assigned_nurse_id', isEqualTo: nurseId)
            .where('house_id', isEqualTo: widget.houseId)
            .where('assigned_date', isEqualTo: today)
            .where('shift', isEqualTo: shift)
            .limit(1)
            .get();

        // If no vital assignment exists, create one
        if (existingVitalQuery.docs.isEmpty) {
          print('➕ Creating vital assignment for: $elderlyName');

          await _firestore.collection('vitals').add({
            // 🔧 ASSIGNMENT FIELDS (required)
            'elderly_id': elderlyId,
            'elderly_name': elderlyName,
            'assigned_nurse_id': nurseId,
            'assigned_nurse_name': widget.nurseName ?? 'Unknown',
            'house_id': widget.houseId,
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

      print('✅ All assignments verified and created if needed');
    } catch (e) {
      print('❌ Error ensuring assignments exist: $e');
    }
  }
}
