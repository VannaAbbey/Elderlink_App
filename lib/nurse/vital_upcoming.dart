import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'vital_update_screen.dart';
import 'follow_up_vitals_selection.dart';
import 'notification_service.dart';
import '../services/vitals_daily_auto_creator.dart';

class UpcomingVitalsTab extends StatefulWidget {
  final String houseId;
  final String? nurseName;
  final DateTime? selectedDate;

  const UpcomingVitalsTab({
    super.key,
    required this.houseId,
    required this.nurseName,
    this.selectedDate,
  });

  @override
  State<UpcomingVitalsTab> createState() => _UpcomingVitalsTabState();
}

class _UpcomingVitalsTabState extends State<UpcomingVitalsTab>
    with AutomaticKeepAliveClientMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>>? _upcomingVitals = [];
  bool _isNotAssignedToShift = false;

  StreamSubscription<QuerySnapshot>? _vitalsListener;
  StreamSubscription<QuerySnapshot>? _assignmentsListener;
  StreamSubscription<QuerySnapshot>? _shiftAssignmentsListener;
  String? _nurseId;

  // Track initial load to avoid deleteAndRecreate on app open
  bool _assignmentsInitialLoad = true;
  bool _shiftAssignmentsInitialLoad = true;

  @override
  bool get wantKeepAlive => true;

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return '1st';
    if (currentHour >= 14 && currentHour < 22) return '2nd';
    return '3rd';
  }

  String _getTodayDateString() {
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  @override
  void initState() {
    super.initState();
    _initializeSystem();
  }

  Future<void> _initializeSystem() async {
    // Get nurse ID
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _nurseId = user.uid;
    }

    _initializeVitalsListener();
    _initializeAssignmentsListener();
    _initializeShiftAssignmentsListener();

    // On app open, always check schedule and ensure vitals_daily is up to date
    await _refreshVitalsDailyIfNeeded();
  }

  /// Called when assignments or shift assignments change
  Future<void> _refreshVitalsDailyIfNeeded() async {
    // Check if nurse has any assignments for today/shift
    final todayDay = DateFormat('EEEE').format(DateTime.now());
    final currentShift = _getCurrentShift();
    final assignments = await _firestore
        .collection('elderly_assignments')
        .where('user_id', isEqualTo: _nurseId)
        .where('user_type', isEqualTo: 'nurse')
        .where('is_current', isEqualTo: true)
        .where('day', isEqualTo: todayDay)
        .where('shift', isEqualTo: currentShift)
        .get();
    if (assignments.docs.isEmpty) {
      // If the current nurse has no assignments, DON'T immediately delete all
      // vitals_daily. Only delete everything if there are no assignments at
      // all for the given day+shift across the system. This prevents
      // accidental global deletion when a single nurse has no assignments
      // (e.g. switching tabs or not scheduled).
      print(
        '🔍 [AutoRefresh] Current nurse has no assignments. Checking global assignments...',
      );
      final globalAssignments = await _firestore
          .collection('elderly_assignments')
          .where('is_current', isEqualTo: true)
          .where('day', isEqualTo: todayDay)
          .where('shift', isEqualTo: currentShift)
          .limit(1)
          .get();

      if (globalAssignments.docs.isEmpty) {
        print(
          '🧹 [AutoRefresh] No assignments system-wide for $todayDay $currentShift — deleting vitals_daily...',
        );
        await VitalsDailyAutoCreator.deleteAndRecreate();
      } else {
        print(
          'ℹ️ [AutoRefresh] Other assignments exist system-wide — will not delete vitals_daily. Ensuring vitals exist...',
        );
        await VitalsDailyAutoCreator.ensureVitalsDailyExist();
      }
    } else {
      print(
        '🔄 [AutoRefresh] Assignments found for current nurse, ensuring vitals_daily is up to date...',
      );
      await VitalsDailyAutoCreator.ensureVitalsDailyExist();
    }
  }

  void _initializeVitalsListener() {
    _vitalsListener?.cancel(); // Cancel existing listener

    final today = _getTodayDateString();
    final currentShift = _getCurrentShift();

    print(
      '🔄 [VitalsListener] Setting up for house: ${widget.houseId}, date: $today, shift: $currentShift',
    );

    _vitalsListener = _firestore
        .collection('vitals_daily')
        .where('house_id', isEqualTo: widget.houseId)
        .where('assigned_date', isEqualTo: today)
        .snapshots()
        .listen((snapshot) async {
          if (!mounted) return;
          print(
            '📊 [VitalsListener] Received ${snapshot.docs.length} vitals_daily documents',
          );
          await _processPendingVitals(snapshot.docs, currentShift);
        });
  }

  /// 🆕 Listen to elderly_assignments changes for real-time schedule updates
  void _initializeAssignmentsListener() {
    if (_nurseId == null) return;

    final today = DateFormat('EEEE').format(DateTime.now());
    final currentShift = _getCurrentShift();

    print('🔄 [Assignments] Setting up listener for nurse: nurseId');

    _assignmentsListener = _firestore
        .collection('elderly_assignments')
        .where('user_id', isEqualTo: _nurseId)
        .where('user_type', isEqualTo: 'nurse')
        .where('is_current', isEqualTo: true)
        .where('day', isEqualTo: today)
        .where('shift', isEqualTo: currentShift)
        .snapshots()
        .listen(
          (snapshot) async {
            if (!mounted) return;

            print(
              '📅 [Assignments] Snapshot received: snapshot.docs.length docs, changes: snapshot.docChanges.length',
            );

            // Skip ONLY the very first load when app opens
            if (_assignmentsInitialLoad) {
              print(
                'ℹ️ [Assignments] Initial load - skipping vitals_daily refresh',
              );
              _assignmentsInitialLoad = false;
              return;
            }

            await _refreshVitalsDailyIfNeeded();
            print('🔄 [Assignments] Reinitializing vitals listener...');
            _initializeVitalsListener();
          },
          onError: (error) {
            print('❌ [Assignments] Error in listener: $error');
          },
        );
  }

  /// 🆕 Listen to house_shift_assignments changes for real-time schedule updates
  void _initializeShiftAssignmentsListener() {
    if (_nurseId == null) return;

    final today = DateFormat('EEEE').format(DateTime.now());
    final currentShift = _getCurrentShift();

    print('🔄 [ShiftAssignments] Setting up listener for nurse: nurseId');

    _shiftAssignmentsListener = _firestore
        .collection('house_shift_assignments')
        .where('user_id', isEqualTo: _nurseId)
        .where('user_type', isEqualTo: 'nurse')
        .where('is_current', isEqualTo: true)
        .where('shift', isEqualTo: currentShift)
        .where('days_assigned', arrayContains: today)
        .snapshots()
        .listen(
          (snapshot) async {
            if (!mounted) return;

            print(
              '📅 [ShiftAssignments] Snapshot received: snapshot.docs.length docs, changes: snapshot.docChanges.length',
            );

            // Skip ONLY the very first load when app opens
            if (_shiftAssignmentsInitialLoad) {
              print(
                'ℹ️ [ShiftAssignments] Initial load - skipping vitals_daily refresh',
              );
              _shiftAssignmentsInitialLoad = false;
              return;
            }

            await _refreshVitalsDailyIfNeeded();
            print('🔄 [ShiftAssignments] Reinitializing vitals listener...');
            _initializeVitalsListener();
          },
          onError: (error) {
            print('❌ [ShiftAssignments] Error in listener: $error');
          },
        );
  }

  Future<void> _processPendingVitals(
    List<QueryDocumentSnapshot> docs,
    String currentShift,
  ) async {
    print(
      '🔍 [ProcessVitals] Starting with ${docs.length} documents, shift: $currentShift',
    );

    // STEP 1: Check if nurse has shift assignment for today
    final hasShiftAssignment = await _checkNurseShiftAssignment();
    if (!hasShiftAssignment) {
      print(
        '❌ [ProcessVitals] Nurse has NO shift assignment for today - showing empty list',
      );
      if (mounted) {
        setState(() {
          _upcomingVitals = [];
          _isLoading = false;
          _isNotAssignedToShift = true;
        });
      }
      return;
    }

    // STEP 2: Get current nurse assignments to verify which elderly are actually assigned
    final assignedElderlyIds = await _getAssignedElderlyIds();

    print(
      '🔍 [ProcessVitals] Nurse has ${assignedElderlyIds.length} assigned elderly IDs: $assignedElderlyIds',
    );

    // STEP 3: If no elderly assignments, show empty list
    if (assignedElderlyIds.isEmpty) {
      print(
        '❌ [ProcessVitals] No elderly assigned to this nurse - showing empty list',
      );
      if (mounted) {
        setState(() {
          _upcomingVitals = [];
          _isLoading = false;
          _isNotAssignedToShift = true;
        });
      }
      return;
    }

    // STEP 4: Filter vitals by assigned elderly
    final List<Map<String, dynamic>> pendingVitals = [];
    // Dedup set to avoid showing the same elderly container multiple times
    final Set<String> addedKeys = <String>{};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final elderlyId = data['elderly_id'] as String?;
      final elderlyName = data['elderly_name'] as String?;
      final shiftStatus = data['shift_status'] as Map<String, dynamic>?;

      print(
        '🟠 [Debug] Vitals: elderly=$elderlyName, elderlyId=$elderlyId, shiftStatus=$shiftStatus',
      );

      // ✅ CRITICAL: Only show vitals for elderly assigned to this nurse
      if (elderlyId == null || !assignedElderlyIds.contains(elderlyId)) {
        print(
          '⚠️ [ProcessVitals] SKIPPING $elderlyName - not in assignments (has ${assignedElderlyIds.length} assignments)',
        );
        continue;
      }

      if (shiftStatus != null && shiftStatus[currentShift] != null) {
        final currentShiftData =
            shiftStatus[currentShift] as Map<String, dynamic>;
        final assignedNurseId =
            currentShiftData['assigned_nurse_id'] as String?;
        print(
          '🟢 [Debug] currentShift=$currentShift, assignedNurseId=$assignedNurseId, myNurseId=$_nurseId',
        );

        // NOTE: Use `elderly_assignments` as the source of truth for which elderly
        // belong to this nurse. We already filtered by `assignedElderlyIds` above,
        // so if the elderlyId is in that set, prefer that assignment even if
        // `vitals_daily.shift_status.assigned_nurse_id` is different (stale/wrong).
        if (assignedNurseId != null && assignedNurseId != _nurseId) {
          if (!assignedElderlyIds.contains(elderlyId)) {
            print(
              '⚠️ [ProcessVitals] SKIPPING $elderlyName - vitals indicates different nurse ($assignedNurseId vs $_nurseId) and not in assignments',
            );
            continue;
          } else {
            print(
              'ℹ️ [ProcessVitals] MISMATCH: vitals assigned to $assignedNurseId but elderly_assignments include this nurse; accepting via assignments',
            );
            // proceed - accept because assignments say this elderly belongs to current nurse
          }
        }

        final status = currentShiftData['status'] as String?;
        print('🔍 [ProcessVitals] $elderlyName status: $status');

        if (status == 'pending') {
          final key =
              '${data['elderly_id']}_${currentShift}_${data['assigned_date']}';
          if (addedKeys.contains(key)) {
            print(
              '⚠️ [ProcessVitals] SKIPPING duplicate pending for $elderlyName (key: $key)',
            );
          } else {
            print('✅ [ProcessVitals] ADDING $elderlyName to pending list');
            pendingVitals.add({
              'vitals_id': doc.id,
              'elderly_id': data['elderly_id'],
              'elderly_name': data['elderly_name'],
              'house_id': data['house_id'],
              'assigned_date': data['assigned_date'],
              'shift': currentShift,
            });
            addedKeys.add(key);
          }
        } else {
          print(
            '⚠️ [ProcessVitals] SKIPPING $elderlyName - status is $status (not pending)',
          );
        }
      } else {
        print(
          '⚠️ [ProcessVitals] SKIPPING $elderlyName - no shift_status for $currentShift',
        );
      }
    }

    // STEP 5: Optionally include completed/missed tasks from recently ended shifts
    // Nurses should be able to review their completed/missed tasks after their shift
    // until their next scheduled shift starts. We'll compute the next scheduled
    // shift start for this nurse and show history while now < nextShiftStart.
    Future<DateTime?> _getNextScheduledShiftStart() async {
      if (_nurseId == null) return null;

      try {
        final now = DateTime.now();
        final todayWeekday = now.weekday; // Monday=1

        final assignmentsSnapshot = await _firestore
            .collection('house_shift_assignments')
            .where('user_id', isEqualTo: _nurseId)
            .where('user_type', isEqualTo: 'nurse')
            .where('is_current', isEqualTo: true)
            .get();

        DateTime? earliest;

        for (final doc in assignmentsSnapshot.docs) {
          final data = doc.data();
          final days = List<String>.from(data['days_assigned'] ?? []);
          final startTime = data['start_time'] as String? ?? '00:00';

          // Parse startTime assuming 'HH:mm' 24-hour format
          final parts = startTime.split(':');
          int startHour = 0;
          int startMinute = 0;
          if (parts.length >= 2) {
            startHour = int.tryParse(parts[0]) ?? 0;
            startMinute = int.tryParse(parts[1]) ?? 0;
          }

          for (final dayName in days) {
            final targetWeekday = _dayNameToWeekday(dayName);
            if (targetWeekday == null) continue;

            int daysUntil = (targetWeekday - todayWeekday) % 7;
            // If the day is today but start time already passed, schedule for next week
            final tentative = DateTime(
              now.year,
              now.month,
              now.day,
              startHour,
              startMinute,
            ).add(Duration(days: daysUntil));
            DateTime nextOccurrence = tentative;
            if (!nextOccurrence.isAfter(now)) {
              nextOccurrence = nextOccurrence.add(const Duration(days: 7));
            }

            if (earliest == null || nextOccurrence.isBefore(earliest)) {
              earliest = nextOccurrence;
            }
          }
        }

        return earliest;
      } catch (e) {
        print('❌ [_getNextScheduledShiftStart] Error: $e');
        return null;
      }
    }

    DateTime now = DateTime.now();
    // Determine which shifts have ended (reuse logic similar to daily_reset_service)
    final List<String> endedShifts = [];
    final int currentHour = now.hour;
    if (currentHour >= 14 && currentHour < 22) {
      endedShifts.add('1st');
    } else if (currentHour >= 22 || currentHour < 6) {
      endedShifts.add('1st');
      endedShifts.add('2nd');
    } else if (currentHour >= 6 && currentHour < 14) {
      endedShifts.add('3rd');
    }

    final nextShiftStart = await _getNextScheduledShiftStart();
    bool showHistory = true;
    if (nextShiftStart != null) {
      // Show history until the nurse's next scheduled shift starts
      showHistory = now.isBefore(nextShiftStart);
    } else {
      // If we cannot determine next scheduled shift, show history for 24 hours
      final fallback = now.add(const Duration(hours: 24));
      showHistory = now.isBefore(fallback);
    }

    if (showHistory && endedShifts.isNotEmpty) {
      print(
        'ℹ️ [ProcessVitals] Including completed/missed from ended shifts: $endedShifts until next shift at $nextShiftStart',
      );

      for (final doc in docs) {
        final data = doc.data() as Map<String, dynamic>;
        final elderlyId = data['elderly_id'] as String?;
        final elderlyName = data['elderly_name'] as String?;
        final shiftStatus = data['shift_status'] as Map<String, dynamic>?;

        if (elderlyId == null || !assignedElderlyIds.contains(elderlyId))
          continue;

        if (shiftStatus == null) continue;

        for (final ended in endedShifts) {
          if (shiftStatus[ended] == null) continue;
          final s = shiftStatus[ended] as Map<String, dynamic>;
          final status = s['status'] as String?;
          // Only include missed historical items. Completed tasks are finished
          // and should not appear in the Upcoming list.
          if (status == 'missed') {
            // Avoid duplicates: only add if not already added
            final key = '${elderlyId}_${ended}_${data['assigned_date']}';
            if (!addedKeys.contains(key)) {
              pendingVitals.add({
                'vitals_id': doc.id,
                'elderly_id': elderlyId,
                'elderly_name': elderlyName,
                'house_id': data['house_id'],
                'assigned_date': data['assigned_date'],
                'shift': ended,
                'status': status,
              });
              addedKeys.add(key);
              print(
                'ℹ️ [ProcessVitals] Adding historical missed for $elderlyName (shift: $ended)',
              );
            } else {
              print(
                '⚠️ [ProcessVitals] SKIPPING duplicate historical missed for $elderlyName (key: $key)',
              );
            }
          }
        }
      }
    } else {
      print(
        'ℹ️ [ProcessVitals] Not showing history (next shift start: $nextShiftStart)',
      );
    }

    print(
      '✅ [ProcessVitals] Final pending vitals count: ${pendingVitals.length}',
    );
    print('✅ [ProcessVitals] Calling setState to update UI...');

    if (mounted) {
      // Sort alphabetically by elderly name for stable, expected ordering
      pendingVitals.sort((a, b) {
        final aName = (a['elderly_name'] ?? '').toString();
        final bName = (b['elderly_name'] ?? '').toString();
        return aName.compareTo(bName);
      });

      setState(() {
        _upcomingVitals = pendingVitals;
        _isLoading = false;
        _isNotAssignedToShift = pendingVitals.isEmpty;
      });
      print(
        '✅ [ProcessVitals] setState completed. _upcomingVitals.length = ${_upcomingVitals?.length}',
      );
    } else {
      print('⚠️ [ProcessVitals] Widget not mounted, skipping setState');
    }
  }

  /// Check if nurse has shift assignment in house_shift_assignments
  Future<bool> _checkNurseShiftAssignment() async {
    if (_nurseId == null) {
      print('⚠️ [CheckShift] _nurseId is null');
      return false;
    }

    final today = DateFormat('EEEE').format(DateTime.now());
    final currentShift = _getCurrentShift();

    print(
      '🔍 [CheckShift] Checking house_shift_assignments for nurse: $_nurseId, day: $today, shift: $currentShift',
    );

    try {
      final shiftSnapshot = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: _nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .where('days_assigned', arrayContains: today)
          .get();

      if (shiftSnapshot.docs.isNotEmpty) {
        final doc = shiftSnapshot.docs.first;
        final data = doc.data();
        final startTime = data['start_time'] ?? '';
        final endTime = data['end_time'] ?? '';
        final daysAssigned = List<String>.from(data['days_assigned'] ?? []);

        print(
          '✅ [CheckShift] Nurse HAS shift assignment: $currentShift shift, $startTime-$endTime, days: $daysAssigned',
        );
        return true;
      } else {
        print(
          '❌ [CheckShift] Nurse has NO shift assignment for $today ($currentShift shift)',
        );
        return false;
      }
    } catch (e) {
      print('❌ [CheckShift] Error checking shift assignment: $e');
      return false;
    }
  }

  /// Get list of elderly IDs currently assigned to this nurse
  Future<Set<String>> _getAssignedElderlyIds() async {
    if (_nurseId == null) {
      print('⚠️ [GetAssignments] _nurseId is null, returning empty set');
      return {};
    }

    final today = DateFormat('EEEE').format(DateTime.now());
    final currentShift = _getCurrentShift();

    print(
      '🔍 [GetAssignments] Querying for nurse: $_nurseId, day: $today, shift: $currentShift',
    );

    try {
      final assignmentsSnapshot = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: _nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('day', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .get();

      print(
        '🔍 [GetAssignments] Found ${assignmentsSnapshot.docs.length} assignment documents',
      );

      final Set<String> elderlyIds = {};
      for (final doc in assignmentsSnapshot.docs) {
        final data = doc.data();
        final ids = List<String>.from(data['elderly_ids'] ?? []);
        print(
          '🔍 [GetAssignments] Document ${doc.id} has ${ids.length} elderly: $ids',
        );
        elderlyIds.addAll(ids);
      }

      print(
        '✅ [GetAssignments] Total unique elderly IDs: ${elderlyIds.length} - $elderlyIds',
      );
      return elderlyIds;
    } catch (e) {
      print('❌ [GetAssignments] Error getting assigned elderly IDs: $e');
      return {};
    }
  }

  @override
  void dispose() {
    _vitalsListener?.cancel();
    _assignmentsListener?.cancel();
    _shiftAssignmentsListener?.cancel();
    super.dispose();
  }

  /// Convert a day name string (e.g., 'Monday') to DateTime weekday (1..7)
  int? _dayNameToWeekday(String? dayName) {
    if (dayName == null) return null;
    switch (dayName.toLowerCase().trim()) {
      case 'monday':
        return DateTime.monday; // 1
      case 'tuesday':
        return DateTime.tuesday; // 2
      case 'wednesday':
        return DateTime.wednesday; // 3
      case 'thursday':
        return DateTime.thursday; // 4
      case 'friday':
        return DateTime.friday; // 5
      case 'saturday':
        return DateTime.saturday; // 6
      case 'sunday':
        return DateTime.sunday; // 7
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_upcomingVitals == null || _upcomingVitals!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No pending vitals for ${_getCurrentShift()} shift',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _upcomingVitals!.length,
        itemBuilder: (context, index) {
          final vital = _upcomingVitals![index];
          return _buildVitalCard(vital);
        },
      ),
    );
  }

  Widget _buildVitalCard(Map<String, dynamic> vital) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange,
          child: const Icon(Icons.pending, color: Colors.white),
        ),
        title: Text(
          vital['elderly_name'] ?? 'Unknown',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          'Shift: ${vital['shift']} | Date: ${vital['assigned_date']}',
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VitalUpdateScreen(
                vitalsId: vital['vitals_id'],
                elderlyId: vital['elderly_id'],
                elderlyName: vital['elderly_name'],
                assignedDate: vital['assigned_date'],
                houseId: widget.houseId,
              ),
            ),
          );
        },
      ),
    );
  }
}
