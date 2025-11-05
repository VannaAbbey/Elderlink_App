import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'notification_service.dart';
import 'package:confetti/confetti.dart';

class UpcomingMedicationsTab extends StatefulWidget {
  final String houseId;
  final String? nurseName;
  final DateTime? selectedDate;
  final Function(int)? onCountChanged;

  const UpcomingMedicationsTab({
    super.key,
    required this.houseId,
    required this.nurseName,
    this.selectedDate,
    this.onCountChanged,
  });

  @override
  State<UpcomingMedicationsTab> createState() => _UpcomingMedicationsTabState();
}

class _UpcomingMedicationsTabState extends State<UpcomingMedicationsTab>
    with AutomaticKeepAliveClientMixin<UpcomingMedicationsTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // In-memory cache to speed up UI when switching houses/tabs.
  // Keyed by: houseId|nurseName|shift|day to avoid cross-shift staleness.
  static final Map<String, List<Map<String, dynamic>>> _medsCache = {};
  static final Map<String, DateTime> _medsCacheTime = {};
  // Track medication IDs that were recently created by this instance so they
  // can be included immediately in the upcoming list without relying on
  // server timestamps or background sync.
  static final Set<String> _recentlyCreatedMedIds = {};
  static const Duration _cacheDuration = Duration(minutes: 10);
  List<Map<String, String>> _elderlyList = [];
  String? _selectedElderly;
  bool _isLoading = false;
  List<Map<String, dynamic>> _upcomingMedications = [];
  // Selection mode for bulk deletion
  bool _selectionMode = false;
  final Set<String> _selectedMedicationIds = {};
  Timer? _missedMedicationTimer;
  Timer? _autoRefreshTimer;
  Timer? _scheduleCheckTimer;
  late ConfettiController _confettiController;
  late DateTime _selectedDate;
  bool _isNurseScheduled = false;
  bool _isAddMedicationDialogOpen = false;
  List<String> _nurseWorkingDays = [];

  Future<List<String>> _fetchNurseWorkingDays() async {
    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) return [];
      final query = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .get();
      final days = <String>{};
      for (var doc in query.docs) {
        final data = doc.data();
        final assigned = List<String>.from(data['days_assigned'] ?? []);
        for (var d in assigned) {
          days.add(d);
        }
      }
      return days.toList();
    } catch (e) {
      print('Error fetching nurse working days: $e');
      return [];
    }
  }

  @override
  void initState() {
    super.initState();
    // Normalize selected date to date-only (year, month, day)
    final initDate = widget.selectedDate ?? DateTime.now();
    _selectedDate = DateTime(initDate.year, initDate.month, initDate.day);
    // Prewarm nurse id and load data (uses cache if available) to make
    // the first frame appear faster when switching tabs/houses.
    _prewarm();
    // Load nurse working days to restrict calendar selection
    _fetchNurseWorkingDays().then((days) {
      if (mounted) setState(() => _nurseWorkingDays = days);
    });
    _checkSchedule();
    _scheduleCheckTimer = Timer.periodic(
      Duration(seconds: 60),
      (timer) => _checkSchedule(),
    );
    _startMissedMedicationTimer();
    _startAutoRefreshTimer();
    _confettiController = ConfettiController(duration: Duration(seconds: 2));
  }

  @override
  bool get wantKeepAlive => true;

  void _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      selectableDayPredicate: (date) {
        if (_nurseWorkingDays.isEmpty) return true;
        final weekday = DateFormat('EEEE').format(date);
        return _nurseWorkingDays.contains(weekday);
      },
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF00588E)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      final normalized = DateTime(picked.year, picked.month, picked.day);
      if (normalized != _selectedDate) {
        setState(() {
          _selectedDate = normalized;
        });
        // Reload medications for the new date
        _loadUpcomingMedications(forceRefresh: true);
        _loadAssignedElderly();
      }
    }
  }

  Future<void> _prewarm() async {
    // Load assigned elderly first to determine nurse schedule and available elderly
    await _loadAssignedElderly();
    // Then load upcoming medications for the assigned elderly
    await _loadUpcomingMedications();
  }

  @override
  void dispose() {
    _missedMedicationTimer?.cancel();
    _autoRefreshTimer?.cancel();
    _scheduleCheckTimer?.cancel();
    _cancelAllMedicationTimers();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _checkSchedule() async {
    print('🔍 _checkSchedule: Starting schedule check...');
    final scheduled = await _isNurseScheduledForToday();
    print('🔍 _checkSchedule: _isNurseScheduledForToday returned: $scheduled');
    print(
      '🔍 _checkSchedule: _elderlyList.isNotEmpty: ${_elderlyList.isNotEmpty}',
    );
    if (mounted) {
      setState(() {
        _isNurseScheduled = scheduled || _elderlyList.isNotEmpty;
        print(
          '🔍 _checkSchedule: Setting _isNurseScheduled to: $_isNurseScheduled',
        );
      });
    }
  }

  String _getSelectedDay() {
    print('🔍 _getSelectedDay: Starting...');
    // Determine the selected day name for shift assignment checks.
    // Use the real current time to determine whether we're after midnight
    // in the 3rd shift so we attribute the shift to the previous calendar day.
    final now = DateTime.now();
    final currentHour = now.hour;
    final currentShift = _getCurrentShift();
    print('🔍 _getSelectedDay: now = $now');
    print('🔍 _getSelectedDay: currentHour = $currentHour');
    print('🔍 _getSelectedDay: currentShift = $currentShift');
    print('🔍 _getSelectedDay: _selectedDate = $_selectedDate');
    // If the selected date is today, preserve the original after-midnight
    // logic so third-shift (22:00-06:00) early hours map to the previous day.
    final today = DateTime(now.year, now.month, now.day);
    final selectedDateOnly = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    print(
      '🔍 _getSelectedDay: today = $today, selectedDateOnly = $selectedDateOnly',
    );
    if (selectedDateOnly.isAtSameMomentAs(today)) {
      if (currentHour >= 0 && currentHour < 6 && currentShift == "3rd") {
        final previousDay = now.subtract(Duration(days: 1));
        final dayName = DateFormat('EEEE').format(previousDay);
        print(
          '🔍 _getSelectedDay: ✅ Third shift early hours - returning previous day: $dayName',
        );
        return dayName;
      }
      final dayName = DateFormat('EEEE').format(now);
      print('🔍 _getSelectedDay: ✅ Today selected - returning: $dayName');
      return dayName;
    }

    // For non-today selected dates, return the weekday of the selected date.
    final dayName = DateFormat('EEEE').format(_selectedDate);
    print(
      '🔍 _getSelectedDay: ✅ Different date selected - returning: $dayName',
    );
    return dayName;
  }

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

  bool _isTimeInCurrentShift(String scheduledTime) {
    // Parse scheduled time (format: "HH:mm:ss" or "HH:mm")
    final timeParts = scheduledTime.split(':');
    if (timeParts.length < 2) return false;

    final hour = int.tryParse(timeParts[0]) ?? 0;
    final minute = int.tryParse(timeParts[1]) ?? 0;
    final scheduledHour = hour + (minute / 60.0); // Convert to decimal hours

    final currentShift = _getCurrentShift();
    switch (currentShift) {
      case "1st": // 6:00 AM - 2:00 PM
        return scheduledHour >= 6.0 && scheduledHour < 14.0;
      case "2nd": // 2:00 PM - 10:00 PM
        return scheduledHour >= 14.0 && scheduledHour < 22.0;
      case "3rd": // 10:00 PM - 6:00 AM
        return scheduledHour >= 22.0 || scheduledHour < 6.0;
      default:
        return false;
    }
  }

  Future<bool> _isNurseScheduledForToday() async {
    print('🔍 _isNurseScheduledForToday: Starting check...');
    try {
      final nurseId = await _getNurseId();
      print('🔍 _isNurseScheduledForToday: nurseId = $nurseId');
      if (nurseId == null) {
        print('🔍 _isNurseScheduledForToday: nurseId is null, returning false');
        return false;
      }

      final currentDay = _getSelectedDay();
      print('🔍 _isNurseScheduledForToday: currentDay = $currentDay');
      print('🔍 _isNurseScheduledForToday: widget.houseId = ${widget.houseId}');

      // Check if nurse is assigned to work any shift on this day for this house
      print(
        '🔍 _isNurseScheduledForToday: Querying house_shift_assignments...',
      );
      final shiftQuery = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('days_assigned', arrayContains: currentDay)
          .get();

      print(
        '🔍 _isNurseScheduledForToday: Found ${shiftQuery.docs.length} shift assignments with currentDay',
      );

      for (var doc in shiftQuery.docs) {
        final assignment = doc.data();
        print('🔍 _isNurseScheduledForToday: Checking assignment: ${doc.id}');
        print('🔍 _isNurseScheduledForToday: Assignment data: $assignment');
        final assignedHouses = List<String>.from(assignment['house_ids'] ?? []);
        print('🔍 _isNurseScheduledForToday: assignedHouses = $assignedHouses');
        if (assignedHouses.contains(widget.houseId)) {
          print(
            '🔍 _isNurseScheduledForToday: ✅ House ${widget.houseId} found in assigned houses, returning true',
          );
          return true;
        }
      }

      // If we didn't find an assignment that explicitly lists the current
      // day, try a fallback: check whether the nurse has any current
      // assignment that includes this house. This guards against cases
      // where assignment documents may be structured differently or when
      // days_assigned isn't populated but the nurse is effectively
      // assigned to the house (we prefer being permissive here to avoid
      // blocking the Add Medication action for nurses who should have access).
      print(
        '🔍 _isNurseScheduledForToday: Trying fallback query without days_assigned filter...',
      );
      final fallbackQuery = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .get();
      print(
        '🔍 _isNurseScheduledForToday: Fallback found ${fallbackQuery.docs.length} assignments',
      );
      for (var doc in fallbackQuery.docs) {
        final assignment = doc.data();
        print(
          '🔍 _isNurseScheduledForToday: Fallback checking assignment: ${doc.id}',
        );
        print(
          '🔍 _isNurseScheduledForToday: Fallback assignment data: $assignment',
        );
        final assignedHouses = List<String>.from(assignment['house_ids'] ?? []);
        print(
          '🔍 _isNurseScheduledForToday: Fallback assignedHouses = $assignedHouses',
        );
        if (assignedHouses.contains(widget.houseId)) {
          print(
            '🔍 _isNurseScheduledForToday: ✅ House ${widget.houseId} found in fallback, returning true',
          );
          return true;
        }
      }

      print(
        '🔍 _isNurseScheduledForToday: ❌ No matching assignments found, returning false',
      );
      return false;
    } catch (e) {
      print('🔍 _isNurseScheduledForToday: ❌ Error: $e');
      print('Error checking if nurse is scheduled for today: $e');
      return false;
    }
  }

  // Removed unused helper functions: _getNurseAssignedShiftsForToday and
  // _getShiftTimeString. Shift and schedule logic is handled elsewhere.

  /// Returns the current nurse user id. First try to find a user document
  /// that matches the provided widget.nurseName (if any). If that fails,
  /// fall back to the authenticated Firebase user id.
  Future<String?> _getNurseId() async {
    print('🔍 _getNurseId: Starting...');
    print('🔍 _getNurseId: widget.nurseName = ${widget.nurseName}');
    try {
      // If a nurseName was provided, try a lookup by first/last name
      if (widget.nurseName != null && widget.nurseName!.trim().isNotEmpty) {
        final parts = widget.nurseName!.trim().split(' ');
        final fname = parts.isNotEmpty ? parts.first : null;
        final lname = parts.length > 1 ? parts.sublist(1).join(' ') : null;
        print('🔍 _getNurseId: Searching by fname=$fname, lname=$lname');

        Query query = _firestore
            .collection('users')
            .where('user_type', isEqualTo: 'nurse');
        if (fname != null && fname.isNotEmpty) {
          query = query.where('user_fname', isEqualTo: fname);
        }
        if (lname != null && lname.isNotEmpty) {
          query = query.where('user_lname', isEqualTo: lname);
        }

        final snap = await query.limit(1).get();
        if (snap.docs.isNotEmpty) {
          final foundId = snap.docs.first.id;
          print('🔍 _getNurseId: ✅ Found nurse by name: $foundId');
          return foundId;
        } else {
          print('🔍 _getNurseId: ⚠️ No nurse found matching the name');
        }
      }

      // Fallback: use currently authenticated user id
      final currentUser = FirebaseAuth.instance.currentUser;
      print(
        '🔍 _getNurseId: Using fallback - currentUser.uid = ${currentUser?.uid}',
      );
      return currentUser?.uid;
    } catch (e) {
      print('🔍 _getNurseId: ❌ Error: $e');
      print('Error resolving nurse id: $e');
      final currentUser = FirebaseAuth.instance.currentUser;
      return currentUser?.uid;
    }
  }

  /// Get nurse working days for a specific nurse id (returns weekdays as list of names)
  Future<List<String>> _getNurseWorkingDays(String nurseId) async {
    try {
      final query = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .get();
      final days = <String>{};
      for (final d in query.docs) {
        final data = d.data();
        final assigned = List<String>.from(data['days_assigned'] ?? []);
        for (var ds in assigned) {
          days.add(ds);
        }
      }
      return days.toList();
    } catch (e) {
      print('Error getting nurse working days for $nurseId: $e');
      return [];
    }
  }

  /// Safely show a SnackBar using the provided context if this State is still mounted.
  void _safeShowSnackBar(BuildContext ctx, SnackBar sb) {
    if (!mounted) return;
    try {
      ScaffoldMessenger.of(ctx).showSnackBar(sb);
    } catch (e) {
      // ignore errors when context is no longer valid
      print('Failed to show SnackBar: $e');
    }
  }

  void _showNotScheduledMessage() {
    _safeShowSnackBar(
      context,
      SnackBar(
        content: Text('You are not scheduled for this shift today'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _showNotScheduledWarningDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
          titlePadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                iconSize: 28,
                icon: const Icon(Icons.close, color: Color(0xFF00588E)),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
              ),
              const Expanded(child: SizedBox()),
              const SizedBox(width: 16),
            ],
          ),
          contentPadding: const EdgeInsets.only(
            left: 16,
            top: 0,
            right: 16,
            bottom: 16,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 32,
                  ),
                  SizedBox(width: 8),
                  Text(
                    "Not Scheduled",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00588E),
                      fontSize: 26,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              const Divider(
                color: Color.fromARGB(255, 204, 203, 203),
                thickness: 2,
              ),
              const SizedBox(height: 16),
              const Text(
                'You are not scheduled for this shift today. You cannot add medications at this time.',
                style: TextStyle(fontSize: 16, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // OK Button
              Center(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00588E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'OK',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveMedicationToDatabase({
    required String elderlyId,
    required String medicationName,
    required String dosage,
    required String repeatInterval,
    required int numberOfIntakes,
    required List<TimeOfDay> intakeTimes,
  }) async {
    print('🎯🎯🎯 MEDICATION SAVE STARTED 🎯🎯🎯');
    print('🎯 Elderly: $elderlyId');
    print('🎯 Medication: $medicationName $dosage');
    print('🎯 Repeat: $repeatInterval');
    print('🎯 Number of Intakes: $numberOfIntakes');
    print('🎯 Selected Date: $_selectedDate');

    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) {
        print('❌ ERROR: Could not find nurse ID');
        throw Exception('Could not find nurse ID');
      }
      print('✅ Nurse ID found: $nurseId');

      final workingDays = await _getNurseWorkingDays(nurseId);
      if (workingDays.isEmpty) {
        throw Exception('No working days found for nurse');
      }

      // Convert TimeOfDay to Time format for database
      final intakeTimesFormatted = intakeTimes
          .map(
            (time) =>
                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00',
          )
          .toList();

      // Determine the shift based on the first intake time rather than current time
      // This ensures medications show up in the correct shift
      String medicationShift = _getCurrentShift();
      if (intakeTimes.isNotEmpty) {
        final firstIntakeHour =
            intakeTimes[0].hour + (intakeTimes[0].minute / 60.0);
        if (firstIntakeHour >= 6.0 && firstIntakeHour < 14.0) {
          medicationShift = "1st";
        } else if (firstIntakeHour >= 14.0 && firstIntakeHour < 22.0) {
          medicationShift = "2nd";
        } else {
          medicationShift = "3rd";
        }
      }

      print(
        '🔍 Saving medication: shift=$medicationShift, repeat=$repeatInterval, selectedDate=$_selectedDate',
      );
      print(
        '🔍 Intake times: ${intakeTimes.map((t) => '${t.hour}:${t.minute}').join(', ')}',
      );

      // Create medication document in new Medications table
      final medicationData = {
        'medication_id': '', // Will be set after creation
        'elderly_id': elderlyId,
        'house_id': widget.houseId,
        'created_nurse_id': nurseId,
        'created_nurse': nurseId, // Add both fields for compatibility
        'medication_name': medicationName,
        'dosage': dosage,
        'repeat_interval': repeatInterval,
        'shift': medicationShift,
        // For Daily meds, working_days=null meaning every day. For Once,
        // we'll store a one_time_date (exact calendar date) so the loader
        // can include it only on that date.
        'working_days': repeatInterval == 'Daily' ? null : null,
        'one_time_date': repeatInterval == 'Once'
            ? Timestamp.fromDate(_selectedDate)
            : null,
        'created_at': Timestamp.fromDate(DateTime.now()),
        'updated_at': Timestamp.fromDate(DateTime.now()),
        'status': 'active',
      };

      final medicationDocRef = await _firestore
          .collection('medications')
          .add(medicationData);

      final medicationId = medicationDocRef.id;

      // Track this medication id so loaders include it immediately.
      try {
        _recentlyCreatedMedIds.add(medicationId);
        print('✅✅✅ MEDICATION CREATED SUCCESSFULLY ✅✅✅');
        print('✅ Medication ID: $medicationId');
        print('✅ Medication Name: $medicationName');
        print('✅ Shift: $medicationShift');
        print('✅ Repeat Interval: $repeatInterval');
        print('✅ Selected Date: $_selectedDate');
        print(
          '🔍 DEBUG: Added medId $medicationId to _recentlyCreatedMedIds (will expire in 5 minutes)',
        );
        print(
          '🔍 DEBUG: _recentlyCreatedMedIds now contains: $_recentlyCreatedMedIds',
        );
        // Remove after 5 minutes to avoid leaking memory and to revert to
        // normal server-driven behavior.
        Timer(Duration(minutes: 5), () {
          _recentlyCreatedMedIds.remove(medicationId);
          print(
            '🔍 DEBUG: Removed medId $medicationId from _recentlyCreatedMedIds after 5 minutes',
          );
        });
      } catch (e) {
        print('❌ DEBUG: Failed to add medId to recentlyCreated set: $e');
      }

      // Update medication_id in the document
      await medicationDocRef.update({'medication_id': medicationId});

      // Create Medication_Takes records for each intake
      final batch = _firestore.batch();
      for (int i = 0; i < numberOfIntakes; i++) {
        final takeDocRef = _firestore.collection('medication_takes').doc();
        batch.set(takeDocRef, {
          'take_id': takeDocRef.id,
          'medication_id': medicationId,
          'take_number': i + 1,
          'scheduled_time': intakeTimesFormatted[i],
          // For one-time medications, record the specific scheduled date so
          // loaders can match takes to the exact calendar day.
          'scheduled_date': repeatInterval == 'Once'
              ? Timestamp.fromDate(_selectedDate)
              : null,
          'status': 'pending',
          'completed_at': null,
          'completed_by': null,
          'created_at': Timestamp.fromDate(DateTime.now()),
          'updated_at': Timestamp.fromDate(DateTime.now()),
        });
      }

      // Commit the batch
      await batch.commit();

      // Debug: verify the medication_takes were created as expected
      try {
        final createdTakesSnap = await _firestore
            .collection('medication_takes')
            .where('medication_id', isEqualTo: medicationId)
            .get();
        print(
          'DEBUG: After commit, found ${createdTakesSnap.docs.length} takes for med $medicationId',
        );
        for (var d in createdTakesSnap.docs) {
          final td = d.data();
          print(
            'DEBUG: take doc ${d.id} -> scheduled_time:${td['scheduled_time']} status:${td['status']} scheduled_date:${td['scheduled_date'] ?? 'null'}',
          );
        }
      } catch (e) {
        print('DEBUG: Error fetching created takes for med $medicationId: $e');
      }

      // Immediately include the newly created medication into local state
      // so the Upcoming UI displays it without waiting for background sync.
      try {
        final createdTakesSnap2 = await _firestore
            .collection('medication_takes')
            .where('medication_id', isEqualTo: medicationId)
            .where('status', isEqualTo: 'pending')
            .get();

        final List<QueryDocumentSnapshot> createdTakesDocs =
            createdTakesSnap2.docs;
        // Build take_statuses and intake_times similar to loader
        final takeStatusesLocal = <Map<String, dynamic>>[];
        final intakeTimesLocal = <String>[];
        for (final d in createdTakesDocs) {
          final td = d.data() as Map<String, dynamic>;
          takeStatusesLocal.add({
            'take_number': td['take_number'],
            'scheduled_time': td['scheduled_time'],
            'status': td['status'],
            'completed_at': td['completed_at'],
            'completed_by': td['completed_by'],
          });
          intakeTimesLocal.add(td['scheduled_time']);
        }

        // Fetch elderly name for display
        String elderlyName = 'Unknown';
        try {
          final elderlyDoc = await _firestore
              .collection('elderly')
              .doc(elderlyId)
              .get();
          if (elderlyDoc.exists) {
            final ed = elderlyDoc.data() as Map<String, dynamic>;
            elderlyName =
                '${ed['elderly_fname'] ?? ''} ${ed['elderly_lname'] ?? ''}'
                    .trim();
            if (elderlyName.isEmpty) elderlyName = 'Unknown';
          }
        } catch (e) {
          print('DEBUG: Error fetching elderly name for local include: $e');
        }

        final medicationEntry = {
          'id': medicationId,
          'elderly_name': elderlyName,
          'medication_name': medicationData['medication_name'],
          'dosage': medicationData['dosage'],
          'repeat_interval': medicationData['repeat_interval'],
          'shift': medicationData['shift'],
          'working_days': medicationData['working_days'],
          'status': medicationData['status'],
          'elderly_id': elderlyId,
          'house_id': medicationData['house_id'],
          'created_nurse_id': medicationData['created_nurse_id'],
          'number_of_intakes': takeStatusesLocal.length,
          'intake_times': intakeTimesLocal,
          'take_statuses': takeStatusesLocal,
          'created_at': medicationData['created_at'],
          'updated_at': medicationData['updated_at'],
        };

        // Insert into state and cache if it matches selected date takes
        // Only include if at least one take is scheduled for the selected date
        bool hasScheduledForSelected = false;
        for (final t in takeStatusesLocal) {
          final scheduled = t['scheduled_time'] as String?;
          if (scheduled == null) continue;
          final parts = scheduled.split(':');
          if (parts.length < 2) continue;
          final h = int.tryParse(parts[0]) ?? 0;
          final min = int.tryParse(parts[1]) ?? 0;
          final scheduledDateTime = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
            h,
            min,
          );
          if (scheduledDateTime.year == _selectedDate.year &&
              scheduledDateTime.month == _selectedDate.month &&
              scheduledDateTime.day == _selectedDate.day) {
            hasScheduledForSelected = true;
            break;
          }
        }

        if (hasScheduledForSelected) {
          if (mounted) {
            setState(() {
              // Prepend so new meds show at top
              _upcomingMedications.insert(0, medicationEntry);
              // Update cache for current key
              final ck =
                  '${widget.houseId}|${widget.nurseName ?? ''}|${_getCurrentShift()}|${_getSelectedDay()}';
              final existing = _medsCache[ck] ?? [];
              _medsCache[ck] = [medicationEntry, ...existing];
              _medsCacheTime[ck] = DateTime.now();
            });
            widget.onCountChanged?.call(_getTotalTakeCount());
          }
        }
      } catch (e) {
        print('DEBUG: Error including newly created medication locally: $e');
      }

      // Log the add medication activity to Medication_Activity_Logs for each take
      for (int i = 0; i < numberOfIntakes; i++) {
        await _logMedicationActivityNew(
          action: 'create',
          medicationId: medicationId,
          elderlyId: elderlyId,
          nurseId: nurseId,
          houseId: widget.houseId,
          shift: _getCurrentShift(),
          medicationName: medicationName,
          dosage: dosage,
          repeatInterval: repeatInterval,
          takeNumber: i + 1,
          scheduledTime: intakeTimesFormatted[i],
        );
      }

      print('Medication saved successfully with new structure');

      // Create corresponding medical_tasks immediately so Home shows them
      // and schedule notifications. Also force-refresh the medications list
      // cache so the Upcoming tab shows the newly created medication.
      await _createTasksForMedicationNew(
        medicationId,
        medicationData,
        intakeTimes,
      );
      // Clear relevant cache entries so the newly created medication shows immediately
      try {
        final keys = _medsCache.keys.toList();
        print(
          'DEBUG: Clearing meds cache entries for house ${widget.houseId}. Keys before clear: ${keys.length}',
        );
        for (final k in keys) {
          if (k.startsWith('${widget.houseId}|')) {
            print('DEBUG: Removing cache key: $k');
            _medsCache.remove(k);
            _medsCacheTime.remove(k);
          }
        }
        final keysAfter = _medsCache.keys.toList();
        print('DEBUG: Cache keys after clear: ${keysAfter.length}');
      } catch (e) {
        print('Error clearing meds cache after save: $e');
      }

      // Force-refresh upcoming medications so the UI includes the newly created med
      print(
        '🔍 DEBUG: About to force-refresh medications after creating med $medicationId',
      );
      print(
        '🔍 DEBUG: Before refresh - _recentlyCreatedMedIds: $_recentlyCreatedMedIds',
      );
      await _loadUpcomingMedications(forceRefresh: true);
      print(
        '🔍 DEBUG: After refresh - found ${_upcomingMedications.length} medications',
      );
      print(
        '🔍 DEBUG: Medication IDs: ${_upcomingMedications.map((m) => m['id']).toList()}',
      );

      // Restart auto-refresh timer to prevent immediate auto-refresh after manual operation
      _autoRefreshTimer?.cancel();
      _startAutoRefreshTimer();
    } catch (e) {
      print('Error saving medication: $e');
      rethrow;
    }
  }

  Future<void> _createTasksForMedicationNew(
    String medicationId,
    Map<String, dynamic> medicationData,
    List<TimeOfDay> intakeTimes,
  ) async {
    try {
      final now = DateTime.now();

      // Get all takes for this medication
      final takesSnapshot = await _firestore
          .collection('medication_takes')
          .where('medication_id', isEqualTo: medicationId)
          .where('status', isEqualTo: 'pending')
          .get();

      for (var takeDoc in takesSnapshot.docs) {
        final takeData = takeDoc.data();
        final takeNumber = takeData['take_number'] as int;
        final scheduledTimeStr = takeData['scheduled_time'] as String;

        // Parse scheduled time
        final timeParts = scheduledTimeStr.split(':');
        if (timeParts.length < 2) continue;
        final hour = int.tryParse(timeParts[0]) ?? 0;
        final minute = int.tryParse(timeParts[1]) ?? 0;

        // If this take has an explicit scheduled_date (one-time medication),
        // use that date instead of today.
        final scheduledDateTs = takeData['scheduled_date'] as Timestamp?;
        DateTime scheduledDate = now;
        if (scheduledDateTs != null) {
          scheduledDate = scheduledDateTs.toDate();
        }

        final taskStart = DateTime(
          scheduledDate.year,
          scheduledDate.month,
          scheduledDate.day,
          hour,
          minute,
        );

        DateTime finalTaskStart = taskStart;
        // For any medication (recurring or one-time), if the computed taskStart is already past
        // then schedule for the next day to avoid creating immediate past tasks.
        if (taskStart.isBefore(now)) {
          finalTaskStart = taskStart.add(Duration(days: 1));
          // Update the scheduled_date in the take document to match the new day
          await takeDoc.reference.update({
            'scheduled_date': Timestamp.fromDate(
              DateTime(
                finalTaskStart.year,
                finalTaskStart.month,
                finalTaskStart.day,
                hour,
                minute,
              ),
            ),
          });
        }

        // Skip past takes (shouldn't happen now, but keep as safety check)
        if (finalTaskStart.isBefore(now)) continue;

        // Avoid duplicates: check existing medical_tasks
        final existing = await _firestore
            .collection('medical_tasks')
            .where('task_source', isEqualTo: 'Medication')
            .where('medication_id', isEqualTo: medicationId)
            .where('take_index', isEqualTo: takeNumber - 1) // 0-based index
            .where('task_start', isEqualTo: Timestamp.fromDate(finalTaskStart))
            .get();
        if (existing.docs.isNotEmpty) continue;

        final elderlyId = medicationData['elderly_id'] as String?;
        final elderlyDoc = elderlyId != null
            ? await _firestore.collection('elderly').doc(elderlyId).get()
            : null;
        String elderlyName = 'Unknown';
        if (elderlyDoc != null && elderlyDoc.exists) {
          final ed = elderlyDoc.data() as Map<String, dynamic>;
          elderlyName =
              '${ed['elderly_fname'] ?? ''} ${ed['elderly_lname'] ?? ''}'
                  .trim();
          if (elderlyName.isEmpty) elderlyName = 'Unknown';
        }

        final medName = medicationData['medication_name'] ?? 'Medication';
        final dosage = medicationData['dosage'] ?? '';

        final taskTitle = 'Medication';
        final taskDesc =
            '$medName ${dosage.isNotEmpty ? '- $dosage' : ''} for $elderlyName';

        final taskDocRef = _firestore.collection('medical_tasks').doc();
        await taskDocRef.set({
          'task_id': taskDocRef.id,
          'medication_id': medicationId,
          'elderly_id': elderlyId,
          'task_title': taskTitle,
          'task_description': taskDesc,
          'task_start': finalTaskStart,
          'task_status': 'pending', // Ensure lowercase for consistency
          'take_index': takeNumber - 1, // 0-based index
          'task_source': 'medication',
          'task_frequency': 'Daily',
          'task_category': 'Medication',
          'days': 1,
        });

        // Schedule notifications using timer-based approach (bypasses Android restrictions)
        // Schedule notification 5 minutes before medication time
        final notifyTime = finalTaskStart.subtract(Duration(minutes: 5));
        if (notifyTime.isAfter(DateTime.now())) {
          final timeUntilNotify = notifyTime.difference(DateTime.now());
          final timer = Timer(timeUntilNotify, () async {
            try {
              await NotificationService.showMedicalTaskNotification(
                taskId: ('${medicationId}_${takeNumber - 1}').hashCode
                    .toString(),
                title: 'Medication Reminder',
                description: '$medName for $elderlyName in 5 minutes',
                elderlyName: elderlyName,
                time:
                    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
              );
              print(
                '✅ Timer-based 5-minute medication reminder sent for: $medName at ${notifyTime.toString()}',
              );
            } catch (e) {
              print('❌ Error sending 5-minute medication reminder: $e');
            }
          });
          _activeMedicationTimers.add(timer);
        }

        // Schedule notification at exact medication time
        if (finalTaskStart.isAfter(DateTime.now())) {
          final timeUntilExact = finalTaskStart.difference(DateTime.now());
          final exactTimer = Timer(timeUntilExact, () async {
            try {
              await NotificationService.showMedicalTaskNotification(
                taskId: ('${medicationId}_${takeNumber - 1}_exact').hashCode
                    .toString(),
                title: 'Medication Time!',
                description: 'Time for $medName for $elderlyName',
                elderlyName: elderlyName,
                time:
                    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
              );
              print(
                '✅ Timer-based exact medication notification sent for: $medName at ${finalTaskStart.toString()}',
              );
            } catch (e) {
              print('❌ Error sending exact medication notification: $e');
            }
          });
          _activeMedicationTimers.add(exactTimer);
        }
      }
    } catch (e) {
      print('Error creating tasks for medication: $e');
    }
  }

  Future<void> _loadAssignedElderly() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _elderlyList = [];
    });

    try {
      final currentShift = _getCurrentShift();
      final currentDay = _getSelectedDay();

      print(
        'Fetching for nurse: ${widget.nurseName}, shift: $currentShift, day: $currentDay',
      );
      print('Filtering assignments for house: ${widget.houseId}');

      // Get the nurse's ID using the existing method
      final nurseId = await _getNurseId();
      if (nurseId == null) {
        print('Could not find nurse ID for: ${widget.nurseName}');
        if (!mounted) return;
        setState(() {
          _elderlyList = [];
          _isLoading = false;
          _isNurseScheduled = false;
        });
        return;
      }

      print('Found nurse ID: $nurseId');

      // First check if nurse is assigned to work this shift on this day
      print('Checking shift assignment for nurseId: $nurseId');
      print('Looking for - Shift: $currentShift, Day: $currentDay');

      var shiftQueryBuilder = _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('days_assigned', arrayContains: currentDay);

      // For future dates, don't filter by shift to check if assigned to any shift on that day
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // Only restrict by the CURRENT shift when viewing today.
      // For past/future dates we should not force the current shift filter
      // because assignments for other shifts on other days may exist.
      if (_selectedDate.isAtSameMomentAs(today)) {
        shiftQueryBuilder = shiftQueryBuilder.where(
          'shift',
          isEqualTo: currentShift,
        );
      }

      final shiftQuery = await shiftQueryBuilder.get();

      if (shiftQuery.docs.isEmpty) {
        print('Nurse is not assigned to this shift on this day');
        print('Query returned no results for house_shift_assignments');
        if (!mounted) return;
        setState(() {
          _elderlyList = [];
          _isLoading = false;
          _isNurseScheduled = false;
        });
        return;
      }

      print('Found shift assignment: ${shiftQuery.docs.first.data()}');

      print('Checking elderly assignments...');
      print(
        'Params - nurseId: $nurseId, house: ${widget.houseId}, shift: $currentShift, day: $currentDay',
      );

      // Get nurse-elderly assignments for the current nurse
      var nurseElderlyQueryBuilder = _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('day', isEqualTo: currentDay);

      // Only restrict by shift when the selected date is today. For past
      // dates we should not force the currentShift filter -- pending takes
      // for past dates are considered missed and will be handled elsewhere.
      if (_selectedDate.isAtSameMomentAs(today)) {
        nurseElderlyQueryBuilder = nurseElderlyQueryBuilder.where(
          'shift',
          isEqualTo: currentShift,
        );
      }

      final nurseElderlyQuery = await nurseElderlyQueryBuilder.get();

      print(
        'Found ${nurseElderlyQuery.docs.length} matching nurse assignments',
      );

      if (nurseElderlyQuery.docs.isNotEmpty) {
        print('Assignment data: ${nurseElderlyQuery.docs.first.data()}');
      }

      if (nurseElderlyQuery.docs.isEmpty) {
        print('No assignments found for the current day and shift');
        if (!mounted) return;
        setState(() {
          _elderlyList = [];
          _isLoading = false;
          _isNurseScheduled = false;
        });
        return;
      }

      // Get the assignment document
      final assignmentDoc = nurseElderlyQuery.docs.first;

      final data = assignmentDoc.data();
      print('Assignment data for nurse $nurseId: $data');

      // Get only the elderly IDs for this specific assignment
      final elderlyIds = List<String>.from(data['elderly_ids'] ?? []);
      print('Extracted elderly IDs for this house: $elderlyIds');

      print('Found ${elderlyIds.length} elderly IDs: $elderlyIds');

      if (elderlyIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _elderlyList = [];
          _isLoading = false;
          _isNurseScheduled = false;
        });
        return;
      }

      // Process elderly IDs in chunks of 30 (Firestore limitation)
      final allElderly = <DocumentSnapshot>[];

      // Split the elderly IDs into chunks of 30
      for (var i = 0; i < elderlyIds.length; i += 30) {
        final end = (i + 30 < elderlyIds.length) ? i + 30 : elderlyIds.length;
        final chunk = elderlyIds.sublist(i, end);

        print('Processing chunk ${i ~/ 30 + 1} with ${chunk.length} IDs');

        final elderlyDetailsQuery = await _firestore
            .collection('elderly')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        allElderly.addAll(elderlyDetailsQuery.docs);
        print(
          'Retrieved ${elderlyDetailsQuery.docs.length} elderly for chunk ${i ~/ 30 + 1}',
        );
      }

      print('Total elderly documents retrieved: ${allElderly.length}');

      // Filter and process elderly for current house
      final filteredElderly = allElderly.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['house_id'] == widget.houseId;
      }).toList();

      print(
        'Filtered elderly for house ${widget.houseId}: ${filteredElderly.length}',
      );

      final newElderlyList = filteredElderly.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        print('Processing elderly document ${doc.id}');

        final firstName = data['elderly_fname'];
        final lastName = data['elderly_lname'];
        print('Raw data - firstName: $firstName, lastName: $lastName');

        final fullName = '${firstName ?? ''} ${lastName ?? ''}'.trim();
        print('Processed elderly: $fullName (ID: ${doc.id})');

        return {
          'id': doc.id,
          'name': fullName.isNotEmpty ? fullName : 'Unknown',
        };
      }).toList();

      // Sort alphabetically by name
      newElderlyList.sort((a, b) => a['name']!.compareTo(b['name']!));

      if (!mounted) return;
      setState(() {
        _elderlyList = newElderlyList;
        _isLoading = false;
        // If we successfully loaded assigned elderly, treat nurse as scheduled
        // for this house/date so the Add Medication FAB is available.
        _isNurseScheduled = _elderlyList.isNotEmpty;
      });
    } catch (e) {
      print('Error loading assigned elderly: $e');
      if (mounted) {
        setState(() {
          _elderlyList = [];
          _isLoading = false;
          _isNurseScheduled = false;
        });
      }
    }
  }

  Future<void> _loadUpcomingMedications({bool forceRefresh = false}) async {
    final currentDay = _getSelectedDay();
    final currentShift = _getCurrentShift();
    final cacheKey =
        '${widget.houseId}|${widget.nurseName ?? ''}|$currentShift|$currentDay';

    try {
      // If cached and not forced to refresh, return cached data immediately
      final cached = _medsCache[cacheKey];
      final cacheTime = _medsCacheTime[cacheKey];
      if (!forceRefresh &&
          cached != null &&
          cacheTime != null &&
          DateTime.now().difference(cacheTime) < _cacheDuration) {
        if (mounted) {
          setState(() {
            _upcomingMedications = List<Map<String, dynamic>>.from(cached);
            _isLoading = false;
          });
        }

        // Schedule a background refresh after cache TTL to keep things fresh
        Future.delayed(_cacheDuration, () {
          if (mounted) _loadUpcomingMedications(forceRefresh: true);
        });
        return;
      }

      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }

      final nurseId = await _getNurseId();
      if (nurseId == null) {
        if (mounted) {
          setState(() {
            _upcomingMedications = [];
            _isLoading = false;
          });
        }
        return;
      }

      // Fetch nurse assignment and medications in parallel to reduce latency.
      var nurseAssignQuery = _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('day', isEqualTo: currentDay);

      // For today and past, filter by shift; for future, load all assignments for that day
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (_selectedDate.isAtSameMomentAs(today) ||
          _selectedDate.isBefore(today)) {
        nurseAssignQuery = nurseAssignQuery.where(
          'shift',
          isEqualTo: currentShift,
        );
      }

      final nurseAssignFuture = nurseAssignQuery.get();

      // Fetch medications and takes in parallel to reduce latency.
      final medicationsFuture = _firestore
          .collection('medications')
          .where('house_id', isEqualTo: widget.houseId)
          .where('status', isEqualTo: 'active')
          .get();

      final results = await Future.wait([nurseAssignFuture, medicationsFuture]);

      final nurseElderlyQuery = results[0] as QuerySnapshot;
      final medicationsQuery = results[1] as QuerySnapshot;

      if (nurseElderlyQuery.docs.isEmpty) {
        if (mounted) {
          setState(() {
            _upcomingMedications = [];
            _isLoading = false;
          });
        }
        return;
      }

      final assignData =
          nurseElderlyQuery.docs.first.data() as Map<String, dynamic>?;
      final assignedElderlyIds = List<String>.from(
        assignData?['elderly_ids'] ?? [],
      );

      if (assignedElderlyIds.isEmpty) {
        if (mounted) {
          setState(() {
            _upcomingMedications = [];
            _isLoading = false;
          });
        }
        return;
      }

      // Filter medications by assigned elderly, shift and working day.
      // Additionally, include medications created by the current nurse within
      // the last few minutes so newly created medications appear immediately
      // in the Upcoming tab even before background syncing completes.
      final medsToInclude = <Map<String, dynamic>>[];
      final elderlyIdsNeeded = <String>{};
      final medicationIds = <String>[];

      // Determine a recent cutoff timestamp (5 minutes)
      final recentCutoff = DateTime.now().subtract(Duration(minutes: 5));
      final currentUser = FirebaseAuth.instance.currentUser;
      final currentUserId = currentUser?.uid;

      for (final doc in medicationsQuery.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final elderlyId = data['elderly_id'] as String?;
        if (elderlyId == null) continue;

        if (!assignedElderlyIds.contains(elderlyId)) continue;

        final medicationShift = data['shift'] as String?;
        final repeatInterval = data['repeat_interval'] as String?;

        // Check if medication is scheduled for current shift and day
        bool isScheduledForToday = false;
        // If medication is Daily, it's scheduled every day (shift must match)
        if (medicationShift == currentShift && repeatInterval == 'Daily') {
          isScheduledForToday = true;
        }

        // If medication is Once, include it only on its scheduled date
        if (repeatInterval == 'Once') {
          final oneTimeDateTs = data['one_time_date'] as Timestamp?;
          if (oneTimeDateTs != null) {
            final oneTimeDate = DateTime(
              oneTimeDateTs.toDate().year,
              oneTimeDateTs.toDate().month,
              oneTimeDateTs.toDate().day,
            );
            final sel = DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
            );
            if (oneTimeDate.isAtSameMomentAs(sel)) {
              // For once meds, still ensure shift matches if viewing today
              if (!_selectedDate.isAtSameMomentAs(
                    DateTime(now.year, now.month, now.day),
                  ) ||
                  medicationShift == currentShift) {
                isScheduledForToday = true;
              }
            }
          }
        }

        final createdAt = data['created_at'] as Timestamp?;
        final createdDate = createdAt?.toDate();

        final bool isRecentByThisNurse =
            createdDate != null &&
            currentUserId != null &&
            createdDate.isAfter(recentCutoff) &&
            (data['created_nurse_id'] == currentUserId ||
                data['created_nurse'] == currentUserId);

        final bool isRecentById = _recentlyCreatedMedIds.contains(doc.id);

        // Debug logs to understand inclusion/exclusion
        try {
          print(
            '🔍 DEBUG Med ${doc.id}: elderly=$elderlyId shift=${medicationShift ?? 'null'} currentShift=$currentShift repeat=${repeatInterval ?? 'null'}',
          );
          print(
            '🔍   created_at=${createdDate?.toIso8601String() ?? 'null'} created_by=${data['created_nurse_id'] ?? data['created_nurse'] ?? 'unknown'} currentUser=$currentUserId',
          );
          print(
            '🔍   isScheduled=$isScheduledForToday isRecentByThisNurse=$isRecentByThisNurse isRecentById=$isRecentById',
          );
        } catch (e) {
          print('❌ DEBUG: Failed to print med debug info for ${doc.id}: $e');
        }

        if (isRecentById) {
          print(
            '✅ DEBUG: Med ${doc.id} is in _recentlyCreatedMedIds and will be included immediately',
          );
        } else {
          print(
            '⚠️ DEBUG: Med ${doc.id} is NOT in _recentlyCreatedMedIds (set contains: $_recentlyCreatedMedIds)',
          );
        }

        if (isScheduledForToday || isRecentByThisNurse || isRecentById) {
          medsToInclude.add({'id': doc.id, ...data});
          elderlyIdsNeeded.add(elderlyId);
          medicationIds.add(doc.id);
        }
      }

      // Ensure any recently created meds by this instance are included even
      // if the initial collection query returned other medications. Firestore
      // can be eventually consistent, so fetch any recent ids not already
      // included and add them when they match the current house and
      // assignment.
      if (_recentlyCreatedMedIds.isNotEmpty) {
        print('🎯 FETCHING RECENTLY CREATED MEDS: $_recentlyCreatedMedIds');
        for (final recentId in _recentlyCreatedMedIds.toList()) {
          try {
            print('🎯 Checking recent med: $recentId');
            if (medicationIds.contains(recentId)) {
              print('🎯   Already in medicationIds, skipping');
              continue;
            }
            final recentSnap = await _firestore
                .collection('medications')
                .doc(recentId)
                .get();
            print('🎯   Firestore exists: ${recentSnap.exists}');
            if (!recentSnap.exists) continue;
            final data = recentSnap.data() as Map<String, dynamic>;
            final house = data['house_id'] as String?;
            final elderlyId = data['elderly_id'] as String?;
            print('🎯   house_id: $house (expected: ${widget.houseId})');
            print('🎯   elderly_id: $elderlyId');
            print('🎯   assignedElderlyIds: $assignedElderlyIds');
            if (house != widget.houseId || elderlyId == null) {
              print('🎯   ❌ House mismatch or no elderly_id');
              continue;
            }
            if (!assignedElderlyIds.contains(elderlyId)) {
              print('🎯   ❌ Elderly not in assigned list');
              continue;
            }

            // Determine scheduling rules similar to the main loop
            final medicationShift = data['shift'] as String?;
            final repeatInterval = data['repeat_interval'] as String?;
            print('🎯   shift: $medicationShift (current: $currentShift)');
            print('🎯   repeat: $repeatInterval');
            bool isScheduledForToday = false;
            if (medicationShift == currentShift && repeatInterval == 'Daily') {
              isScheduledForToday = true;
              print('🎯   ✅ Daily med with matching shift');
            }
            if (repeatInterval == 'Once') {
              final oneTimeDateTs = data['one_time_date'] as Timestamp?;
              print('🎯   one_time_date: ${oneTimeDateTs?.toDate()}');
              print('🎯   _selectedDate: $_selectedDate');
              if (oneTimeDateTs != null) {
                final oneTimeDate = DateTime(
                  oneTimeDateTs.toDate().year,
                  oneTimeDateTs.toDate().month,
                  oneTimeDateTs.toDate().day,
                );
                final sel = DateTime(
                  _selectedDate.year,
                  _selectedDate.month,
                  _selectedDate.day,
                );
                print('🎯   oneTimeDate: $oneTimeDate vs sel: $sel');
                if (oneTimeDate.isAtSameMomentAs(sel)) {
                  print('🎯   Date matches! Checking shift...');
                  if (!_selectedDate.isAtSameMomentAs(
                        DateTime(now.year, now.month, now.day),
                      ) ||
                      medicationShift == currentShift) {
                    isScheduledForToday = true;
                    print('🎯   ✅ Once med scheduled for today');
                  } else {
                    print(
                      '🎯   ❌ Today but shift mismatch: $medicationShift != $currentShift',
                    );
                  }
                } else {
                  print('🎯   ❌ Date mismatch');
                }
              }
            }

            print('🎯   isScheduledForToday: $isScheduledForToday');
            if (isScheduledForToday) {
              medsToInclude.add({'id': recentSnap.id, ...data});
              elderlyIdsNeeded.add(elderlyId);
              medicationIds.add(recentSnap.id);
              print(
                'DEBUG: Included recent med $recentId via unconditional fallback',
              );
            }
          } catch (e) {
            print('DEBUG: Error including recent med $recentId: $e');
          }
        }
      }

      // Fallback: if no medications were returned by the main query but we
      // recently created medications in this instance, attempt to fetch
      // those medication documents directly and include them when they match
      // the current house and assignment. This handles race conditions where
      // the newly created med may not appear in the initial collection query
      // immediately.
      if (medsToInclude.isEmpty && _recentlyCreatedMedIds.isNotEmpty) {
        try {
          for (final recentId in _recentlyCreatedMedIds.toList()) {
            final docSnap = await _firestore
                .collection('medications')
                .doc(recentId)
                .get();
            if (!docSnap.exists) continue;
            final data = docSnap.data() as Map<String, dynamic>;
            // Quick filters: house and elderly must match
            final house = data['house_id'] as String?;
            final elderlyId = data['elderly_id'] as String?;
            if (house != widget.houseId || elderlyId == null) continue;

            // Ensure elderly is assigned to this nurse for the selected date
            if (!assignedElderlyIds.contains(elderlyId)) continue;

            final medicationShift = data['shift'] as String?;
            final repeatInterval = data['repeat_interval'] as String?;

            bool isScheduledForToday = false;
            if (medicationShift == currentShift && repeatInterval == 'Daily') {
              isScheduledForToday = true;
            }
            if (repeatInterval == 'Once') {
              final oneTimeDateTs = data['one_time_date'] as Timestamp?;
              if (oneTimeDateTs != null) {
                final oneTimeDate = DateTime(
                  oneTimeDateTs.toDate().year,
                  oneTimeDateTs.toDate().month,
                  oneTimeDateTs.toDate().day,
                );
                final sel = DateTime(
                  _selectedDate.year,
                  _selectedDate.month,
                  _selectedDate.day,
                );
                if (oneTimeDate.isAtSameMomentAs(sel)) {
                  if (!_selectedDate.isAtSameMomentAs(
                        DateTime(now.year, now.month, now.day),
                      ) ||
                      medicationShift == currentShift) {
                    isScheduledForToday = true;
                  }
                }
              }
            }

            if (isScheduledForToday) {
              medsToInclude.add({'id': docSnap.id, ...data});
              elderlyIdsNeeded.add(elderlyId);
              medicationIds.add(docSnap.id);
            }
          }
        } catch (e) {
          print('DEBUG: Fallback fetch for recently created meds failed: $e');
        }
      }

      print(
        '🔍 DEBUG: medsToInclude count: ${medsToInclude.length}. medicationIds: $medicationIds',
      );
      print(
        '🔍 DEBUG: _recentlyCreatedMedIds currently contains: $_recentlyCreatedMedIds',
      );
      print(
        '🔍 DEBUG: currentShift=$currentShift, currentDay=$currentDay, selectedDate=$_selectedDate',
      );

      if (medicationIds.isEmpty) {
        if (mounted) {
          setState(() {
            _upcomingMedications = [];
            _isLoading = false;
          });
        }
        return;
      }

      // Fetch Medication_Takes for these medications in parallel batches of 10 (Firestore limit)
      final List<Future<QuerySnapshot>> takesFutures = [];
      for (var i = 0; i < medicationIds.length; i += 10) {
        final end = (i + 10 < medicationIds.length)
            ? i + 10
            : medicationIds.length;
        final batch = medicationIds.sublist(i, end);
        final future = _firestore
            .collection('medication_takes')
            .where('medication_id', whereIn: batch)
            .where('status', isEqualTo: 'pending')
            .get();
        takesFutures.add(future);
      }
      final takesSnapshots = await Future.wait(takesFutures);
      final List<QueryDocumentSnapshot> allTakesDocs = [];
      for (final snapshot in takesSnapshots) {
        allTakesDocs.addAll(snapshot.docs);
      }

      // Group takes by medication_id and include all takes for assigned medications
      final takesByMedication = <String, List<Map<String, dynamic>>>{};
      for (final takeDoc in allTakesDocs) {
        final takeData = takeDoc.data() as Map<String, dynamic>;
        final medId = takeData['medication_id'] as String;
        final status = takeData['status'] as String;

        // Include takes that are either:
        // 1. Pending and within current shift (normal upcoming medications)
        //    OR pending and belong to a recently-created medication (show immediately)
        // 2. Missed from previous shift (should be picked up by current shift nurse)
        // 3. Completed or missed for medications assigned to this nurse (show history if needed)
        bool shouldInclude = false;

        final bool isRecentById = _recentlyCreatedMedIds.contains(medId);
        final bool isFromPreviousShift =
            takeData['from_previous_shift'] == true;
        final String? missedByNurseId =
            takeData['missed_by_nurse_id'] as String?;
        final String? missedByNurseName =
            takeData['missed_by_nurse_name'] as String?;

        if (status == 'pending') {
          // For pending takes:
          // - If selected date is in the future -> include (upcoming)
          // - If selected date is today -> include those in current shift
          //   OR include all pending takes for medications just created by this nurse
          // - If selected date is before today -> DO NOT include (these are missed)
          final scheduledTimeStr = takeData['scheduled_time'] as String?;
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          if (_selectedDate.isAfter(today)) {
            shouldInclude = true; // future pending takes
          } else if (_selectedDate.isAtSameMomentAs(today)) {
            if (isRecentById) {
              // Newly created med: show all its pending takes for today
              shouldInclude = true;
            } else if (scheduledTimeStr != null) {
              // Parse scheduled time and include only if it's not already past
              final parts = scheduledTimeStr.split(':');
              int h = 0;
              int min = 0;
              if (parts.isNotEmpty) h = int.tryParse(parts[0]) ?? 0;
              if (parts.length > 1) min = int.tryParse(parts[1]) ?? 0;
              final scheduledDateTime = DateTime(
                _selectedDate.year,
                _selectedDate.month,
                _selectedDate.day,
                h,
                min,
              );
              // Show take if scheduled time is now or later
              // Modified: Always include pending medications so nurses can manually mark them as completed or missed
              shouldInclude = true;
            } else {
              shouldInclude = false;
            }
          } else {
            shouldInclude = false; // past pending takes are considered missed
          }
        } else if (status == 'missed' && isFromPreviousShift) {
          // Include missed medications from previous shift as pending tasks for current shift
          // These will be shown with a special label indicating they're from a previous shift
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);

          // Only include if selected date is today (current shift can handle today's missed meds)
          if (_selectedDate.isAtSameMomentAs(today)) {
            shouldInclude = true;
            // Mark this take data so we can display it differently in the UI
            takeData['display_as_from_previous_shift'] = true;
            takeData['previous_shift_nurse_name'] =
                missedByNurseName ?? 'Unknown';
          }
        } else if (status == 'completed' || status == 'missed') {
          // Do not include completed or regular missed takes in upcoming medications
          shouldInclude = false;
        }

        if (shouldInclude) {
          if (!takesByMedication.containsKey(medId)) {
            takesByMedication[medId] = [];
          }
          takesByMedication[medId]!.add({'id': takeDoc.id, ...takeData});
        }
      }

      // Debug: print summary of takes discovered per medication id
      try {
        print('DEBUG: Total takes fetched: ${allTakesDocs.length}');
        final medsListForDebug = medicationIds;
        for (final mid in medsListForDebug) {
          final allForMed = allTakesDocs.where((d) {
            final ddata = d.data() as Map<String, dynamic>;
            return (ddata['medication_id'] as String?) == mid;
          }).toList();
          final grouped = takesByMedication[mid] ?? [];
          print(
            'DEBUG: Med $mid => total takes in DB: ${allForMed.length}, grouped (after include filter): ${grouped.length}',
          );
          if (allForMed.isNotEmpty) {
            for (final d in allForMed) {
              final dd = d.data() as Map<String, dynamic>;
              print(
                'DEBUG:   take ${d.id} scheduled:${dd['scheduled_time']} status:${dd['status']} scheduled_date:${dd['scheduled_date'] ?? 'null'}',
              );
            }
          }
        }
      } catch (e) {
        print('DEBUG: failed to print takes summary: $e');
      }

      // Fetch elderly docs in chunks of 30 to build a lookup map
      final Map<String, String> elderlyNames = {};
      final elderlyIdList = elderlyIdsNeeded.toList();
      for (var i = 0; i < elderlyIdList.length; i += 30) {
        final end = (i + 30 < elderlyIdList.length)
            ? i + 30
            : elderlyIdList.length;
        final chunk = elderlyIdList.sublist(i, end);
        final elderlyQuery = await _firestore
            .collection('elderly')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final ed in elderlyQuery.docs) {
          final edata = ed.data();
          final name =
              '${edata['elderly_fname'] ?? ''} ${edata['elderly_lname'] ?? ''}'
                  .trim();
          elderlyNames[ed.id] = name.isNotEmpty ? name : 'Unknown';
        }
      }

      final medications = <Map<String, dynamic>>[];
      for (final m in medsToInclude) {
        final medicationId = m['id'] as String;
        final elderlyId = m['elderly_id'] as String;
        final allTakes = takesByMedication[medicationId] ?? [];

        // Filter out completed and missed takes - only show active takes
        // Accept both 'complete' and 'completed' values for backwards compatibility
        final activeTakes = allTakes.where((take) {
          final s = (take['status'] as String?) ?? '';
          return s != 'complete' && s != 'completed' && s != 'missed';
        }).toList();

        // Filter takes to only include those scheduled for the selected date.
        // If a take has an explicit 'scheduled_date' (set for Once meds), use
        // that date; otherwise assume the take is scheduled on the currently
        // selected date and combine with its scheduled_time.
        final filteredTakes = activeTakes.where((take) {
          final scheduledTimeStr = take['scheduled_time'] as String?;
          if (scheduledTimeStr == null) return false;
          final timeParts = scheduledTimeStr.split(':');
          if (timeParts.length < 2) return false;
          final hour = int.tryParse(timeParts[0]) ?? 0;
          final minute = int.tryParse(timeParts[1]) ?? 0;

          final takeScheduledDateTs = take['scheduled_date'] as Timestamp?;
          DateTime scheduledDateForTake;
          if (takeScheduledDateTs != null) {
            final d = takeScheduledDateTs.toDate();
            scheduledDateForTake = DateTime(
              d.year,
              d.month,
              d.day,
              hour,
              minute,
            );
          } else {
            scheduledDateForTake = DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              hour,
              minute,
            );
          }

          // Only compare the date portion — user expects to see takes scheduled
          // for the selected calendar day regardless of current time of day.
          return scheduledDateForTake.year == _selectedDate.year &&
              scheduledDateForTake.month == _selectedDate.month &&
              scheduledDateForTake.day == _selectedDate.day;
        }).toList();

        // Sort takes by scheduled time (earliest first). For medications
        // assigned to the 3rd shift (22:00-06:00) treat times between
        // 00:00-05:59 as next-day values by adding 24 hours so they sort
        // after late-night times (e.g., 23:30 < 00:30 -> 23.5 < 24.5).
        try {
          final medShift = (m['shift'] as String?) ?? '';
          filteredTakes.sort((a, b) {
            String at = (a['scheduled_time'] ?? '') as String;
            String bt = (b['scheduled_time'] ?? '') as String;

            double parseTimeForSort(String t) {
              final parts = t.split(':');
              int h = 0;
              int min = 0;
              if (parts.isNotEmpty) h = int.tryParse(parts[0]) ?? 0;
              if (parts.length > 1) min = int.tryParse(parts[1]) ?? 0;
              double val = h + (min / 60.0);
              // If med is 3rd shift, shift early-morning hours to after 24
              if (medShift.toLowerCase() == '3rd' && h < 6) {
                val += 24.0;
              }
              return val;
            }

            final aVal = parseTimeForSort(at);
            final bVal = parseTimeForSort(bt);
            return aVal.compareTo(bVal);
          });
        } catch (e) {
          // Non-fatal: if sorting fails, leave original order
          print('DEBUG: Failed to sort filteredTakes for med ${m['id']}: $e');
        }

        // Skip medications that have no active takes for the selected date
        if (filteredTakes.isEmpty) continue;

        // Convert to old format for compatibility with existing UI
        final intakeTimes = filteredTakes
            .map((t) => t['scheduled_time'] as String)
            .toList();
        final takeStatuses = filteredTakes
            .map(
              (t) => {
                'take_number': t['take_number'],
                'scheduled_time': t['scheduled_time'],
                'status': t['status'],
                'completed_at': t['completed_at'],
                'completed_by': t['completed_by'],
              },
            )
            .toList();

        medications.add({
          'id': medicationId,
          'elderly_name': elderlyNames[elderlyId] ?? 'Unknown',
          'medication_name': m['medication_name'],
          'dosage': m['dosage'],
          'repeat_interval': m['repeat_interval'],
          'shift': m['shift'],
          'working_days': m['working_days'],
          'status': m['status'],
          'elderly_id': elderlyId,
          'house_id': m['house_id'],
          'created_nurse_id': m['created_nurse_id'],
          'number_of_intakes': filteredTakes.length,
          'intake_times': intakeTimes,
          'take_statuses': takeStatuses,
          'created_at': m['created_at'],
          'updated_at': m['updated_at'],
        });
      }

      // Update cache and state
      _medsCache[cacheKey] = List<Map<String, dynamic>>.from(medications);
      _medsCacheTime[cacheKey] = DateTime.now();

      if (mounted) {
        setState(() {
          _upcomingMedications = medications;
          _isLoading = false;
        });
        widget.onCountChanged?.call(_getTotalTakeCount());
      }
    } catch (e) {
      print('Error loading upcoming medications: $e');
      setState(() {
        _upcomingMedications = [];
        _isLoading = false;
      });
    }
  }

  void _showAddMedicationDialog() async {
    if (_isAddMedicationDialogOpen) return;

    // Check if nurse is scheduled before showing the dialog
    if (!_isNurseScheduled) {
      _showNotScheduledWarningDialog();
      return;
    }

    _isAddMedicationDialogOpen = true;

    // Ensure elderly list is loaded before showing dialog
    if (_elderlyList.isEmpty && !_isLoading) {
      await _loadAssignedElderly();
    }

    String? selectedElderlyTemp = _selectedElderly;
    String? selectedMedicationTemp;
    String? selectedDosageTemp;
    String? selectedIntervalTemp;
    int? numberOfIntakesTemp;
    List<TimeOfDay?> intakeTimes = List<TimeOfDay?>.filled(6, null);

    // local temporaries for constructing the dialog; populated below as needed

    // Common medications for elderly
    final List<String> commonMedications = [
      'Lisinopril',
      'Metformin',
      'Atorvastatin',
      'Omeprazole',
      'Aspirin',
      'Levothyroxine',
    ];

    // Common dosages
    final List<String> commonDosages = [
      '5mg',
      '10mg',
      '25mg',
      '50mg',
      '100mg',
      '250mg',
      '500mg',
      '1g',
    ];

    // Repeat intervals
    final List<String> repeatIntervals = ['Once', 'Daily'];

    // Number of intakes options
    final List<int> intakeOptions = [1, 2, 3, 4, 5, 6];

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          titlePadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                iconSize: 28,
                icon: const Icon(Icons.close, color: Color(0xFF00588E)),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
              ),
              const Expanded(child: SizedBox()),
              const SizedBox(width: 16),
            ],
          ),
          contentPadding: const EdgeInsets.only(
            left: 16,
            top: 0,
            right: 16,
            bottom: 16,
          ),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        SizedBox(width: 10),
                        Text(
                          "Add Medication",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF216386),
                            fontSize: 26,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(
                      color: Color.fromARGB(255, 204, 203, 203),
                      thickness: 2,
                    ),
                    const SizedBox(height: 12),

                    // Subtitle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Total assigned elderly: ${_elderlyList.length}',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Elderly Selection
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.person,
                              color: Color(0xFF00588E),
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Select Elderly',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588E),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.9,
                          height: 50,
                          child: DropdownButtonFormField<String>(
                            value: selectedElderlyTemp,
                            decoration: InputDecoration(
                              hintText: 'Select elderly',
                              filled: true,
                              fillColor: Color.fromARGB(255, 222, 241, 246),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              contentPadding: EdgeInsets.only(
                                left: 12,
                                top: 12,
                                bottom: 12,
                                right: 12,
                              ),
                            ),
                            items: _elderlyList.map((elderly) {
                              return DropdownMenuItem<String>(
                                value: elderly['id']!,
                                child: Text(elderly['name'] ?? ''),
                              );
                            }).toList(),
                            onChanged: (String? value) {
                              setDialogState(() {
                                selectedElderlyTemp = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),

                    // Medication Name
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.medical_services,
                              color: Color(0xFF00588E),
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Medication Name',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588E),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.9,
                          height: 50,
                          child: DropdownButtonFormField<String>(
                            value: selectedMedicationTemp,
                            decoration: InputDecoration(
                              hintText: 'Select medication',
                              filled: true,
                              fillColor: Color.fromARGB(255, 222, 241, 246),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              contentPadding: EdgeInsets.only(
                                left: 12,
                                top: 12,
                                bottom: 12,
                                right: 12,
                              ),
                            ),
                            items: commonMedications.map((medication) {
                              return DropdownMenuItem<String>(
                                value: medication,
                                child: Text(medication),
                              );
                            }).toList(),
                            onChanged: (String? value) {
                              setDialogState(() {
                                selectedMedicationTemp = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),

                    // Dosage
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.medication,
                              color: Color(0xFF00588E),
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Dosage',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588E),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.9,
                          height: 50,
                          child: DropdownButtonFormField<String>(
                            value: selectedDosageTemp,
                            decoration: InputDecoration(
                              hintText: 'Select dosage',
                              filled: true,
                              fillColor: Color.fromARGB(255, 222, 241, 246),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              contentPadding: EdgeInsets.only(
                                left: 12,
                                top: 12,
                                bottom: 12,
                                right: 12,
                              ),
                            ),
                            items: commonDosages.map((dosage) {
                              return DropdownMenuItem<String>(
                                value: dosage,
                                child: Text(dosage),
                              );
                            }).toList(),
                            onChanged: (String? value) {
                              setDialogState(() {
                                selectedDosageTemp = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),

                    // Repeat Interval
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.repeat,
                              color: Color(0xFF00588E),
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Repeat Interval',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588E),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.9,
                          height: 50,
                          child: DropdownButtonFormField<String>(
                            value: selectedIntervalTemp,
                            decoration: InputDecoration(
                              hintText: 'Select repeat interval',
                              filled: true,
                              fillColor: Color.fromARGB(255, 222, 241, 246),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              contentPadding: EdgeInsets.only(
                                left: 12,
                                top: 12,
                                bottom: 12,
                                right: 12,
                              ),
                            ),
                            items: repeatIntervals.map((interval) {
                              return DropdownMenuItem<String>(
                                value: interval,
                                child: Text(interval),
                              );
                            }).toList(),
                            onChanged: (String? value) {
                              setDialogState(() {
                                selectedIntervalTemp = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),

                    // Number of Intakes
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.format_list_numbered,
                              color: Color(0xFF00588E),
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Number of Intakes',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588E),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        SizedBox(
                          width: 280,
                          height: 50,
                          child: DropdownButtonFormField<int>(
                            value: numberOfIntakesTemp,
                            decoration: InputDecoration(
                              hintText: 'No. of med intakes',
                              filled: true,
                              fillColor: Color.fromARGB(255, 222, 241, 246),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              contentPadding: EdgeInsets.only(
                                left: 12,
                                top: 12,
                                bottom: 12,
                                right: 12,
                              ),
                            ),
                            items: intakeOptions.map((intakeCount) {
                              return DropdownMenuItem<int>(
                                value: intakeCount,
                                child: Text('$intakeCount'),
                              );
                            }).toList(),
                            onChanged: (int? value) {
                              setDialogState(() {
                                numberOfIntakesTemp = value;
                                // Initialize intake times list
                                if (value != null) {
                                  intakeTimes = List.filled(value, null);
                                } else {
                                  intakeTimes = [];
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),

                    // Dynamic Intake Times
                    if (numberOfIntakesTemp != null && numberOfIntakesTemp! > 0)
                      ...List.generate(numberOfIntakesTemp!, (index) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${_getOrdinal(index + 1)} Take:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: GestureDetector(
                                  onTap: () async {
                                    final TimeOfDay? picked =
                                        await showTimePicker(
                                          context: context,
                                          initialTime:
                                              intakeTimes[index] ??
                                              TimeOfDay.now(),
                                        );
                                    if (picked != null) {
                                      setDialogState(() {
                                        intakeTimes[index] = picked;
                                      });
                                    }
                                  },
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Color.fromARGB(255, 162, 219, 255),
                                      border: Border.all(color: Colors.white),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          intakeTimes[index] != null
                                              ? intakeTimes[index]!.format(
                                                  context,
                                                )
                                              : 'Select time',
                                          style: TextStyle(
                                            color: intakeTimes[index] != null
                                                ? Colors.black
                                                : Colors.grey,
                                          ),
                                        ),
                                        Icon(
                                          Icons.access_time,
                                          color: Color(0xFF00588E),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    SizedBox(height: 20),

                    // Buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Add
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00588E),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              // Validate all fields are filled
                              if (selectedElderlyTemp != null &&
                                  selectedMedicationTemp != null &&
                                  selectedDosageTemp != null &&
                                  selectedIntervalTemp != null &&
                                  numberOfIntakesTemp != null &&
                                  intakeTimes.every((time) => time != null)) {
                                // Validate that intake times are in chronological order
                                bool timesAreValid = true;
                                String? validationMessage;

                                final validTimes = intakeTimes
                                    .cast<TimeOfDay>();
                                for (int i = 1; i < validTimes.length; i++) {
                                  final previousTime = validTimes[i - 1];
                                  final currentTime = validTimes[i];

                                  // Convert to minutes since midnight for comparison
                                  final previousMinutes =
                                      previousTime.hour * 60 +
                                      previousTime.minute;
                                  final currentMinutes =
                                      currentTime.hour * 60 +
                                      currentTime.minute;

                                  if (currentMinutes <= previousMinutes) {
                                    timesAreValid = false;
                                    validationMessage =
                                        '${_getOrdinal(i + 1)} take time (${currentTime.format(context)}) must be later than ${_getOrdinal(i)} take time (${previousTime.format(context)})';
                                    break;
                                  }
                                }

                                if (!timesAreValid) {
                                  if (mounted) {
                                    _safeShowSnackBar(
                                      context,
                                      SnackBar(
                                        content: Text(validationMessage!),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                  return;
                                }

                                // Show confirmation dialog instead of directly saving
                                showMedicationConfirmation(
                                  context,
                                  selectedElderlyTemp!,
                                  selectedMedicationTemp!,
                                  selectedDosageTemp!,
                                  selectedIntervalTemp!,
                                  numberOfIntakesTemp!,
                                  intakeTimes.cast<TimeOfDay>(),
                                );
                              } else {
                                if (mounted) {
                                  _safeShowSnackBar(
                                    context,
                                    SnackBar(
                                      content: Text(
                                        'Please fill in all fields',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            child: Text(
                              'Add',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Cancel
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    ).then((_) => _isAddMedicationDialogOpen = false);
  }

  void showMedicationConfirmation(
    BuildContext parentContext,
    String elderlyId,
    String medicationName,
    String dosage,
    String repeatInterval,
    int numberOfIntakes,
    List<TimeOfDay> intakeTimes,
  ) {
    bool isChecked = false;
    // Prepare a future to fetch the current nurse's user document for display
    final currentUser = FirebaseAuth.instance.currentUser;
    final Future<DocumentSnapshot?> nurseFuture = currentUser != null
        ? FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get()
        : Future.value(null);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          // add a small left-top exit icon and center the title
          titlePadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top-left X/exit icon only (larger tappable area)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                iconSize: 28,
                icon: const Icon(Icons.close, color: Color(0xFF00588E)),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close',
              ),
              // consume remaining space so header moves to next row (in content)
              const Expanded(child: SizedBox()),
              const SizedBox(width: 36),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header moved to content so it sits under the exit icon
              const Center(
                child: Text(
                  'Confirmation Form',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00588E),
                    fontSize: 26,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(color: Color(0xFF00588E), thickness: 2),
              const SizedBox(height: 12),
              const Text(
                'You are about to add a new medication to the system. '
                'Please verify all details are correct before proceeding. '
                'This action will create medication tasks and cannot be easily undone.',
                textAlign: TextAlign.justify,
              ),
              const SizedBox(height: 14),
              // Reporting nurse label (fetched asynchronously) - placed above the checkbox
              FutureBuilder<DocumentSnapshot?>(
                future: nurseFuture,
                builder: (context, snapshot) {
                  String nurseName = '-';
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (snapshot.hasData &&
                      snapshot.data != null &&
                      snapshot.data!.exists) {
                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    if (data != null) {
                      final f = data['user_fname'] ?? '';
                      final l = data['user_lname'] ?? '';
                      nurseName = ('$f $l').trim();
                    }
                  }
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.person,
                                size: 25,
                                color: Color(0xFF00588E),
                              ),
                              const SizedBox(width: 8),
                              // Make label colored and value black, and allow wrapping
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Reporting Nurse: ',
                                        style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          color: Color(0xFF00588E),
                                        ),
                                      ),
                                      TextSpan(
                                        text: nurseName,
                                        style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.start,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: isChecked,
                    onChanged: (val) =>
                        setState(() => isChecked = val ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    activeColor: const Color(0xFF00588E),
                    checkColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF00588E), width: 2),
                  ),
                  Expanded(
                    child: Text(
                      'I acknowledge that the medication information provided is accurate and complete.',
                      textAlign: TextAlign.justify,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Submit button (responsive)
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00588E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: isChecked
                            ? () async {
                                // Close confirmation dialog
                                Navigator.of(context).pop();

                                // Check if widget is still mounted
                                if (!mounted) return;

                                // Show loading indicator
                                showDialog(
                                  context: parentContext,
                                  barrierDismissible: false,
                                  builder: (context) => Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );

                                try {
                                  // Save medication to database
                                  await _saveMedicationToDatabase(
                                    elderlyId: elderlyId,
                                    medicationName: medicationName,
                                    dosage: dosage,
                                    repeatInterval: repeatInterval,
                                    numberOfIntakes: numberOfIntakes,
                                    intakeTimes: intakeTimes,
                                  );

                                  // Check if widget is still mounted
                                  if (!mounted) return;

                                  // Close loading dialog
                                  Navigator.of(parentContext).pop();

                                  // Show success message
                                  _safeShowSnackBar(
                                    parentContext,
                                    SnackBar(
                                      content: Text(
                                        'Medication added successfully',
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );

                                  // Close medication dialog
                                  Navigator.of(parentContext).pop();
                                } catch (e) {
                                  // Check if widget is still mounted
                                  if (!mounted) return;

                                  // Close loading dialog if it's open
                                  Navigator.of(parentContext).pop();

                                  // Show error message
                                  _safeShowSnackBar(
                                    parentContext,
                                    SnackBar(
                                      content: Text(
                                        'Error adding medication: ${e.toString()}',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            : null,
                        child: const Text(
                          'Submit',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 24),

                  // Cancel button (responsive)
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getOrdinal(int number) {
    if (number >= 11 && number <= 13) {
      return '${number}th';
    }
    switch (number % 10) {
      case 1:
        return '${number}st';
      case 2:
        return '${number}nd';
      case 3:
        return '${number}rd';
      default:
        return '${number}th';
    }
  }

  bool _canMarkAsMissed(String scheduledTime) {
    try {
      final scheduledTimeParts = scheduledTime.split(':');
      if (scheduledTimeParts.length >= 2) {
        final scheduledHour = int.tryParse(scheduledTimeParts[0]) ?? 0;
        final scheduledMinute = int.tryParse(scheduledTimeParts[1]) ?? 0;

        final now = DateTime.now();
        final scheduledDateTime = DateTime(
          now.year,
          now.month,
          now.day,
          scheduledHour,
          scheduledMinute,
        );

        return now.isAfter(scheduledDateTime) ||
            now.isAtSameMomentAs(scheduledDateTime);
      }
    } catch (e) {
      print('Error checking if can mark as missed: $e');
    }
    return false;
  }

  void _startMissedMedicationTimer() {
    print('⏰⏰⏰ STARTING MISSED MEDICATION TIMER ⏰⏰⏰');
    // Check for missed medications every 1 minute for faster detection
    _missedMedicationTimer = Timer.periodic(Duration(minutes: 1), (timer) {
      print('⏰ Timer tick - calling _checkForMissedMedications()');
      _checkForMissedMedications();
    });
    // Also check immediately
    print('⏰ Calling _checkForMissedMedications() immediately');
    _checkForMissedMedications();
  }

  void _startAutoRefreshTimer() {
    // Auto-refresh medication data every 10 minutes to ensure data is always updated
    _autoRefreshTimer = Timer.periodic(Duration(seconds: 600), (timer) {
      if (mounted) {
        _loadUpcomingMedications(forceRefresh: true);
      }
    });
  }

  Future<void> _checkForMissedMedications() async {
    print('🔍🔍🔍 _checkForMissedMedications() STARTED 🔍🔍🔍');
    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) {
        print('❌ _checkForMissedMedications: No nurse ID found');
        return;
      }

      final currentTime = DateTime.now();
      final currentShift = _getCurrentShift();
      final currentHour = currentTime.hour;
      final today = DateTime(
        currentTime.year,
        currentTime.month,
        currentTime.day,
      );

      print(
        '🔍 _checkForMissedMedications: Checking at ${DateFormat('HH:mm:ss').format(currentTime)}',
      );
      print('🔍 Current shift: $currentShift, House: ${widget.houseId}');

      // Determine if we're at the end of any shift
      // 1st shift ends at 14:00 (2:00 PM)
      // 2nd shift ends at 22:00 (10:00 PM)
      // 3rd shift ends at 6:00 (6:00 AM)
      bool isEndOfShift = false;
      String endingShift = '';

      if (currentHour == 14 || currentHour == 13 && currentTime.minute >= 55) {
        isEndOfShift = true;
        endingShift = '1st';
      } else if (currentHour == 22 ||
          currentHour == 21 && currentTime.minute >= 55) {
        isEndOfShift = true;
        endingShift = '2nd';
      } else if (currentHour == 6 ||
          currentHour == 5 && currentTime.minute >= 55) {
        isEndOfShift = true;
        endingShift = '3rd';
      }

      print('🔍 Is end of shift: $isEndOfShift, Ending shift: $endingShift');

      // Query medication_takes directly for pending medications
      final pendingTakesQuery = await _firestore
          .collection('medication_takes')
          .where('status', isEqualTo: 'pending')
          .get();

      print('Found ${pendingTakesQuery.docs.length} pending medication takes');

      int missedCount = 0;

      for (final takeDoc in pendingTakesQuery.docs) {
        final takeData = takeDoc.data();
        final medicationId = takeData['medication_id'] as String?;
        final scheduledTimeStr = takeData['scheduled_time'] as String?;
        final scheduledDateTs = takeData['scheduled_date'] as Timestamp?;
        final takeNumber = takeData['take_number'] as int?;

        if (scheduledTimeStr == null || scheduledDateTs == null) continue;

        // Get medication details to check if it belongs to this nurse's house
        final medDoc = await _firestore
            .collection('medications')
            .doc(medicationId)
            .get();

        if (!medDoc.exists) continue;

        final medData = medDoc.data() as Map<String, dynamic>;
        final houseId = medData['house_id'] as String?;
        final elderlyId = medData['elderly_id'] as String?;
        final medicationName =
            medData['medication_name'] as String? ?? 'Unknown';
        final dosage = medData['dosage'] as String? ?? '';
        final repeatInterval = medData['repeat_interval'] as String? ?? '';
        final shift = medData['shift'] as String?;
        final createdNurseId = medData['created_nurse_id'] as String?;

        // Skip if not in current house
        if (houseId != widget.houseId) continue;

        // Parse scheduled time (format: "HH:mm:ss" or "HH:mm")
        final timeParts = scheduledTimeStr.split(':');
        if (timeParts.length < 2) continue;

        final scheduledHour = int.tryParse(timeParts[0]) ?? 0;
        final scheduledMinute = int.tryParse(timeParts[1]) ?? 0;

        // Combine scheduled date + time
        final scheduledDate = scheduledDateTs.toDate();
        final scheduledDateTime = DateTime(
          scheduledDate.year,
          scheduledDate.month,
          scheduledDate.day,
          scheduledHour,
          scheduledMinute,
        );

        // Check if medication should be marked as missed
        bool shouldMarkAsMissed = false;
        String missedReason = '';

        // Check if more than 1 hour has passed since scheduled time
        final timeDifference = currentTime.difference(scheduledDateTime);

        // Check if this medication belongs to a shift that has ended
        bool belongsToEndedShift = false;
        if (isEndOfShift && shift == endingShift) {
          belongsToEndedShift = true;
        }

        print('⏰ Medication: $medicationName, Take $takeNumber');
        print('   Scheduled: $scheduledDateTime');
        print('   Current: $currentTime');
        print('   Shift: $shift');
        print(
          '   Difference: ${timeDifference.inMinutes} minutes (${timeDifference.inHours} hours)',
        );
        print('   Belongs to ended shift: $belongsToEndedShift');

        // Mark as missed if:
        // 1. More than 1 hour has passed, OR
        // 2. The shift has ended and this medication was scheduled for that shift
        if (timeDifference.inHours >= 1) {
          shouldMarkAsMissed = true;
          missedReason = 'Automatically marked as missed after 1 hour';
        } else if (belongsToEndedShift &&
            scheduledDateTime.isBefore(currentTime)) {
          shouldMarkAsMissed = true;
          missedReason = 'Marked as missed at end of shift';
        }

        if (shouldMarkAsMissed) {
          print(
            '🚨 Marking take $takeNumber as missed for medication $medicationName',
          );
          print('   Reason: $missedReason');

          try {
            // Get the nurse who was assigned to this medication's shift
            String? assignedNurseId = createdNurseId;
            String? assignedNurseName;

            if (assignedNurseId != null) {
              final nurseDoc = await _firestore
                  .collection('users')
                  .doc(assignedNurseId)
                  .get();

              if (nurseDoc.exists) {
                final nurseData = nurseDoc.data() as Map<String, dynamic>;
                assignedNurseName =
                    '${nurseData['user_fname'] ?? ''} ${nurseData['user_lname'] ?? ''}'
                        .trim();
              }
            }

            // Update medication_takes status to missed
            await takeDoc.reference.update({
              'status': 'missed',
              'missed_at': Timestamp.fromDate(currentTime),
              'missed_reason': missedReason,
              'missed_by_nurse_id': assignedNurseId,
              'missed_by_nurse_name': assignedNurseName ?? 'Unknown',
              'from_previous_shift': belongsToEndedShift,
              'updated_at': Timestamp.fromDate(currentTime),
            });

            // Log the missed medication activity
            try {
              await _logMedicationActivityNew(
                action: 'take_missed',
                medicationId: medicationId!,
                elderlyId: elderlyId!,
                nurseId: assignedNurseId ?? nurseId,
                houseId: houseId!,
                shift: shift ?? currentShift,
                medicationName: medicationName,
                dosage: dosage,
                repeatInterval: repeatInterval,
                takeNumber: takeNumber!,
                scheduledTime: scheduledTimeStr,
              );
            } catch (e) {
              print('Error logging missed activity: $e');
            }

            // Cancel scheduled notification for this take (if any)
            try {
              final notifyId = ('${medicationId}_${takeNumber! - 1}').hashCode;
              NotificationService.cancelNotification(notifyId);
            } catch (e) {
              print('Error cancelling notification for missed take: $e');
            }

            missedCount++;
          } catch (e) {
            print('Error updating medication_takes to missed: $e');
          }
        }
      }

      print('✅ Marked $missedCount medications as missed');

      // Refresh the UI if there were any updates
      if (missedCount > 0) {
        await _loadUpcomingMedications(forceRefresh: true);
      }
    } catch (e) {
      print('Error checking for missed medications: $e');
    }
  }

  // Timer-based notification system to bypass Android restrictions
  final List<Timer> _activeMedicationTimers = [];

  // Cancel all active medication timers
  void _cancelAllMedicationTimers() {
    for (final timer in _activeMedicationTimers) {
      timer.cancel();
    }
    _activeMedicationTimers.clear();
    print('✅ Cancelled ${_activeMedicationTimers.length} medication timers');
  }

  Future<void> _logMedicationActivity({
    required String action,
    required String medicationId,
    required Map<String, dynamic> medicationData,
    required int takeNumber,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
    Map<String, dynamic>? takeData,
  }) async {
    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) return;

      final elderlyDoc = await _firestore
          .collection('elderly')
          .doc(medicationData['elderly_id'])
          .get();

      String elderlyName = 'Unknown';
      String elderlyTitle = 'Lola';
      if (elderlyDoc.exists) {
        final elderlyData = elderlyDoc.data() as Map<String, dynamic>;
        elderlyName =
            '${elderlyData['elderly_fname']} ${elderlyData['elderly_lname']}'
                .trim();
        elderlyTitle = elderlyData['elderly_title'] ?? 'Lola';
      }

      // Get scheduled time from takeData if provided, otherwise from medicationData
      String? scheduledTime;
      if (takeData != null && takeData['scheduled_time'] != null) {
        scheduledTime = takeData['scheduled_time'] as String;
      } else if (medicationData['intake_times'] != null && takeNumber > 0) {
        final intakeTimes = List<String>.from(medicationData['intake_times']);
        if (takeNumber <= intakeTimes.length) {
          scheduledTime = intakeTimes[takeNumber - 1];
        }
      }

      final activityData = {
        'action': action,
        'nurse_id': nurseId,
        'nurse_name': widget.nurseName,
        'medication_id': medicationId,
        'medication_name': medicationData['medication_name'],
        'dosage':
            medicationData['dosage'] ?? medicationData['medication_dosage'],
        'repeat_interval': medicationData['repeat_interval'],
        'elderly_id': medicationData['elderly_id'],
        'elderly_name': elderlyName,
        'elderly_title': elderlyTitle,
        'house_id': widget.houseId,
        'take_number': takeNumber,
        'take_ordinal': _getOrdinal(takeNumber),
        'scheduled_time': scheduledTime,
        'timestamp': Timestamp.fromDate(DateTime.now()),
        'shift': _getCurrentShift(),
        'day': _getSelectedDay(),

        // 🆕 BACKWARD COMPATIBILITY FIELDS
        // Keep old field names for existing code that might read logs
        'created_by': nurseId, // Maps to nurse_id
        'created_nurse_id': nurseId, // Explicit nurse ID
        'created_nurse_name': widget.nurseName, // Explicit nurse name
        // Medication details (normalized)
        'number_of_intakes': medicationData['number_of_intakes'],
        'intake_times': medicationData['intake_times'],
        'working_days':
            medicationData['working_days'], // null for daily, array for specific

        if (oldData != null) 'old_data': oldData,
        if (newData != null) 'new_data': newData,
      };

      await _firestore.collection('medication_activity_logs').add(activityData);
      print('Medication activity logged: $action');
    } catch (e) {
      print('Error logging medication activity: $e');
    }
  }

  Future<void> _logMedicationActivityNew({
    required String action,
    required String medicationId,
    required String elderlyId,
    required String nurseId,
    required String houseId,
    required String shift,
    required String medicationName,
    required String dosage,
    required String repeatInterval,
    int? takeNumber,
    String? scheduledTime,
  }) async {
    try {
      // Set default take number if not provided (for create actions)
      takeNumber ??= 1;

      // Get elderly name
      final elderlyDoc = await _firestore
          .collection('elderly')
          .doc(elderlyId)
          .get();

      String elderlyName = 'Unknown';
      if (elderlyDoc.exists) {
        final elderlyData = elderlyDoc.data() as Map<String, dynamic>;
        elderlyName =
            '${elderlyData['elderly_fname']} ${elderlyData['elderly_lname']}'
                .trim();
      }

      // Get nurse name
      final nurseDoc = await _firestore.collection('users').doc(nurseId).get();

      String nurseName = 'Unknown';
      if (nurseDoc.exists) {
        final nurseData = nurseDoc.data() as Map<String, dynamic>;
        nurseName = '${nurseData['user_fname']} ${nurseData['user_lname']}'
            .trim();
      }

      final activityData = {
        'elderly_id': elderlyId,
        'medication_id': medicationId,
        'nurse_id': nurseId,
        'house_id': houseId,
        'action': action,
        'shift': shift,
        'timestamp': Timestamp.fromDate(DateTime.now()),
        'nurse_name': nurseName,
        'elderly_name': elderlyName,
        'medication_name': medicationName,
        'dosage': dosage,
        'repeat_interval': repeatInterval,
        'take_number': takeNumber,
        'take_ordinal': _getOrdinal(takeNumber),
        'scheduled_time': scheduledTime,
      };

      await _firestore.collection('medication_activity_logs').add(activityData);

      print('Medication activity logged to new table: $action');
    } catch (e) {
      print('Error logging medication activity to new table: $e');
    }
  }

  Future<void> _editMedication(
    String medicationId,
    Map<String, dynamic> medicationData,
  ) async {
    String? selectedMedicationTemp = medicationData['medication_name'];
    String? selectedDosageTemp = medicationData['dosage'];
    String? selectedIntervalTemp = medicationData['repeat_interval'];
    int? numberOfIntakesTemp = medicationData['number_of_intakes'];
    List<TimeOfDay?> intakeTimes = List<TimeOfDay?>.filled(6, null);

    // originalNumberOfIntakes removed (not needed)

    // Parse existing intake times when needed inside hasChanges

    final List<String> commonMedications = [
      'Lisinopril',
      'Metformin',
      'Atorvastatin',
      'Omeprazole',
      'Aspirin',
      'Levothyroxine',
    ];
    final List<String> commonDosages = [
      '5mg',
      '10mg',
      '25mg',
      '50mg',
      '100mg',
      '250mg',
      '500mg',
      '1g',
    ];
    final List<String> repeatIntervals = ['Once', 'Daily'];
    final List<int> intakeOptions = [1, 2, 3, 4, 5, 6];

    // Function to check if any changes were made
    bool hasChanges() {
      // Check medication name
      if (selectedMedicationTemp != medicationData['medication_name']) {
        return true;
      }

      // Check dosage
      if (selectedDosageTemp != medicationData['dosage']) return true;

      // Check repeat interval
      if (selectedIntervalTemp != medicationData['repeat_interval']) {
        return true;
      }

      // Check number of intakes
      if (numberOfIntakesTemp != medicationData['number_of_intakes']) {
        return true;
      }

      // Check intake times
      final existingTimes = List<String>.from(
        medicationData['intake_times'] ?? [],
      );
      final currentTimes = intakeTimes
          .where((time) => time != null)
          .cast<TimeOfDay>()
          .map(
            (time) =>
                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
          )
          .toList();

      if (existingTimes.length != currentTimes.length) return true;

      for (int i = 0; i < existingTimes.length; i++) {
        if (existingTimes[i] != currentTimes[i]) return true;
      }

      return false;
    }

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          titlePadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                iconSize: 28,
                icon: const Icon(Icons.close, color: Color(0xFF00588E)),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
              ),
              const Expanded(child: SizedBox()),
              const SizedBox(width: 16),
            ],
          ),
          contentPadding: const EdgeInsets.only(
            left: 16,
            top: 0,
            right: 16,
            bottom: 16,
          ),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        SizedBox(width: 10),
                        Text(
                          "Edit Medication",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF216386),
                            fontSize: 26,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(
                      color: Color.fromARGB(255, 204, 203, 203),
                      thickness: 2,
                    ),
                    const SizedBox(height: 12),
                    // Medication Name
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.medical_services,
                              color: Color(0xFF00588E),
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Medication Name',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588E),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.9,
                          height: 50,
                          child: DropdownButtonFormField<String>(
                            value: selectedMedicationTemp,
                            decoration: InputDecoration(
                              hintText: 'Select medication',
                              filled: true,
                              fillColor: Color.fromARGB(255, 222, 241, 246),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              contentPadding: EdgeInsets.only(
                                left: 12,
                                top: 12,
                                bottom: 12,
                                right: 12,
                              ),
                            ),
                            items: commonMedications.map((medication) {
                              return DropdownMenuItem<String>(
                                value: medication,
                                child: Text(medication),
                              );
                            }).toList(),
                            onChanged: (String? value) {
                              setDialogState(() {
                                selectedMedicationTemp = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),

                    // Dosage
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.medication,
                              color: Color(0xFF00588E),
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Dosage',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588E),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.9,
                          height: 50,
                          child: DropdownButtonFormField<String>(
                            value: selectedDosageTemp,
                            decoration: InputDecoration(
                              hintText: 'Select dosage',
                              filled: true,
                              fillColor: Color.fromARGB(255, 222, 241, 246),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              contentPadding: EdgeInsets.only(
                                left: 12,
                                top: 12,
                                bottom: 12,
                                right: 12,
                              ),
                            ),
                            items: commonDosages.map((dosage) {
                              return DropdownMenuItem<String>(
                                value: dosage,
                                child: Text(dosage),
                              );
                            }).toList(),
                            onChanged: (String? value) {
                              setDialogState(() {
                                selectedDosageTemp = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),

                    // Repeat Interval
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.repeat,
                              color: Color(0xFF00588E),
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Repeat Interval',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588E),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.9,
                          height: 50,
                          child: DropdownButtonFormField<String>(
                            value: selectedIntervalTemp,
                            decoration: InputDecoration(
                              hintText: 'Select repeat interval',
                              filled: true,
                              fillColor: Color.fromARGB(255, 222, 241, 246),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              contentPadding: EdgeInsets.only(
                                left: 12,
                                top: 12,
                                bottom: 12,
                                right: 12,
                              ),
                            ),
                            items: repeatIntervals.map((interval) {
                              return DropdownMenuItem<String>(
                                value: interval,
                                child: Text(interval),
                              );
                            }).toList(),
                            onChanged: (String? value) {
                              setDialogState(() {
                                selectedIntervalTemp = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),

                    // Number of Intakes
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.format_list_numbered,
                              color: Color(0xFF00588E),
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Number of Intakes',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588E),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.75,
                          height: 50,
                          child: DropdownButtonFormField<int>(
                            value: numberOfIntakesTemp,
                            decoration: InputDecoration(
                              hintText: 'No. of med intakes',
                              filled: true,
                              fillColor: Color.fromARGB(255, 222, 241, 246),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              contentPadding: EdgeInsets.only(
                                left: 12,
                                top: 12,
                                bottom: 12,
                                right: 24,
                              ),
                            ),
                            items: intakeOptions.map((intakeCount) {
                              return DropdownMenuItem<int>(
                                value: intakeCount,
                                child: Text('$intakeCount'),
                              );
                            }).toList(),
                            onChanged: (int? value) {
                              setDialogState(() {
                                numberOfIntakesTemp = value;
                                // Reset intake times when count changes
                                intakeTimes = List.generate(
                                  6,
                                  (index) => index < (value ?? 0)
                                      ? (intakeTimes[index] ?? TimeOfDay.now())
                                      : null,
                                );
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),

                    // Intake Times
                    if (numberOfIntakesTemp != null)
                      ...List.generate(numberOfIntakesTemp!, (index) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${_getOrdinal(index + 1)} Take:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: GestureDetector(
                                  onTap: () async {
                                    final TimeOfDay? picked =
                                        await showTimePicker(
                                          context: context,
                                          initialTime:
                                              intakeTimes[index] ??
                                              TimeOfDay.now(),
                                        );
                                    if (picked != null) {
                                      setDialogState(() {
                                        intakeTimes[index] = picked;
                                      });
                                    }
                                  },
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Color.fromARGB(255, 162, 219, 255),
                                      border: Border.all(color: Colors.white),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          intakeTimes[index] != null
                                              ? intakeTimes[index]!.format(
                                                  context,
                                                )
                                              : 'Select time',
                                          style: TextStyle(
                                            color: intakeTimes[index] != null
                                                ? Colors.black
                                                : Colors.grey,
                                          ),
                                        ),
                                        Icon(
                                          Icons.access_time,
                                          color: Color(0xFF00588E),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    SizedBox(height: 20),

                    // Buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Update
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00588E),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              // Check if any changes were made
                              if (!hasChanges()) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'No changes detected. Please modify at least one field before updating.',
                                      ),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                                return;
                              }

                              if (selectedMedicationTemp != null &&
                                  selectedDosageTemp != null &&
                                  selectedIntervalTemp != null &&
                                  numberOfIntakesTemp != null) {
                                // Validate intake times
                                bool allTimesSelected = true;
                                for (int i = 0; i < numberOfIntakesTemp!; i++) {
                                  if (intakeTimes[i] == null) {
                                    allTimesSelected = false;
                                    break;
                                  }
                                }

                                if (!allTimesSelected) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Please select all intake times',
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }

                                // Validate that intake times are in chronological order
                                bool timesAreValid = true;
                                String? validationMessage;

                                final validTimes = intakeTimes
                                    .take(numberOfIntakesTemp!)
                                    .where((t) => t != null)
                                    .cast<TimeOfDay>()
                                    .toList();
                                for (int i = 1; i < validTimes.length; i++) {
                                  final previousTime = validTimes[i - 1];
                                  final currentTime = validTimes[i];

                                  // Convert to minutes since midnight for comparison
                                  final previousMinutes =
                                      previousTime.hour * 60 +
                                      previousTime.minute;
                                  final currentMinutes =
                                      currentTime.hour * 60 +
                                      currentTime.minute;

                                  if (currentMinutes <= previousMinutes) {
                                    timesAreValid = false;
                                    validationMessage =
                                        '${_getOrdinal(i + 1)} take time (${currentTime.format(context)}) must be later than ${_getOrdinal(i)} take time (${previousTime.format(context)})';
                                    break;
                                  }
                                }

                                if (!timesAreValid) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(validationMessage!),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                  return;
                                }

                                showEditMedicationConfirmation(
                                  dialogContext,
                                  medicationId,
                                  medicationData,
                                  selectedMedicationTemp!,
                                  selectedDosageTemp!,
                                  selectedIntervalTemp!,
                                  numberOfIntakesTemp!,
                                  intakeTimes
                                      .take(numberOfIntakesTemp!)
                                      .where((t) => t != null)
                                      .cast<TimeOfDay>()
                                      .toList(),
                                );
                              }
                            },
                            child: Text(
                              'Update',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Cancel
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _updateMedicationInDatabase(
    String medicationId,
    Map<String, dynamic> medicationData,
    String selectedMedicationTemp,
    String selectedDosageTemp,
    String selectedIntervalTemp,
    int numberOfIntakesTemp,
    List<TimeOfDay> intakeTimes,
  ) async {
    try {
      final oldData = Map<String, dynamic>.from(medicationData);
      final intakeTimeStrings = intakeTimes
          .map(
            (time) =>
                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
          )
          .toList();
      List<Map<String, dynamic>> updatedTakeStatuses = [];
      final existingTakeStatuses = List<Map<String, dynamic>>.from(
        medicationData['take_statuses'] ?? [],
      );
      for (int i = 0; i < numberOfIntakesTemp; i++) {
        if (i < existingTakeStatuses.length) {
          updatedTakeStatuses.add({
            ...existingTakeStatuses[i],
            'scheduled_time': intakeTimeStrings[i],
          });
        } else {
          updatedTakeStatuses.add({
            'take_number': i + 1,
            'status': 'pending',
            'scheduled_time': intakeTimeStrings[i],
            'completed_at': null,
            'completed_by': null,
          });
        }
      }
      final newData = {
        'medication_name': selectedMedicationTemp,
        'dosage': selectedDosageTemp,
        'repeat_interval': selectedIntervalTemp,
        'number_of_intakes': numberOfIntakesTemp,
        'intake_times': intakeTimeStrings,
        'take_statuses': updatedTakeStatuses,
        'updated_at': Timestamp.fromDate(DateTime.now()),
      };
      await _firestore
          .collection('medications')
          .doc(medicationId)
          .update(newData);

      // Update the medication_takes collection with new scheduled times
      final takesQuery = await _firestore
          .collection('medication_takes')
          .where('medication_id', isEqualTo: medicationId)
          .get();

      final batch = _firestore.batch();
      for (final takeDoc in takesQuery.docs) {
        final takeData = takeDoc.data();
        final takeNumber = takeData['take_number'] as int;

        if (takeNumber <= numberOfIntakesTemp) {
          // Update existing take with new scheduled time
          batch.update(takeDoc.reference, {
            'scheduled_time': intakeTimeStrings[takeNumber - 1],
            'updated_at': Timestamp.fromDate(DateTime.now()),
          });
        } else {
          // Mark extra takes as cancelled since number of intakes was reduced
          batch.update(takeDoc.reference, {
            'status': 'cancelled',
            'updated_at': Timestamp.fromDate(DateTime.now()),
          });
        }
      }

      // If there are fewer existing takes than new number, add new takes
      if (takesQuery.docs.length < numberOfIntakesTemp) {
        for (int i = takesQuery.docs.length; i < numberOfIntakesTemp; i++) {
          final takeDocRef = _firestore.collection('medication_takes').doc();
          batch.set(takeDocRef, {
            'medication_id': medicationId,
            'take_number': i + 1,
            'scheduled_time': intakeTimeStrings[i],
            'status': 'pending',
            'created_at': Timestamp.fromDate(DateTime.now()),
            'updated_at': Timestamp.fromDate(DateTime.now()),
          });
        }
      }

      // Commit the batch update
      await batch.commit();

      await _logMedicationActivity(
        action: 'edit_medication',
        medicationId: medicationId,
        medicationData: medicationData,
        takeNumber: 0,
        oldData: oldData,
        newData: newData,
      );
      await _loadUpcomingMedications(forceRefresh: true);

      // Restart auto-refresh timer to prevent immediate auto-refresh after manual operation
      _autoRefreshTimer?.cancel();
      _startAutoRefreshTimer();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Medication updated successfully')),
        );
      }
    } catch (e) {
      print('Error updating medication: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating medication')));
      }
    }
  }

  void showEditMedicationConfirmation(
    BuildContext parentContext,
    String medicationId,
    Map<String, dynamic> medicationData,
    String medicationName,
    String dosage,
    String repeatInterval,
    int numberOfIntakes,
    List<TimeOfDay> intakeTimes,
  ) {
    bool isChecked = false;
    final currentUser = FirebaseAuth.instance.currentUser;
    final Future<DocumentSnapshot?> nurseFuture = currentUser != null
        ? FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get()
        : Future.value(null);
    showDialog(
      context: parentContext,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.white,
          // add a small left-top exit icon and center the title
          titlePadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top-left X/exit icon only (larger tappable area)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                iconSize: 28,
                icon: const Icon(Icons.close, color: Color(0xFF00588E)),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close',
              ),
              // consume remaining space so header moves to next row (in content)
              const Expanded(child: SizedBox()),
              const SizedBox(width: 36),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header moved to content so it sits under the exit icon
                const Center(
                  child: Text(
                    'Confirmation Form',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00588E),
                      fontSize: 26,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(color: Color(0xFF00588E), thickness: 2),
                const SizedBox(height: 12),
                const Text(
                  'You are about to update this medication in the system. '
                  'Please verify all details are correct before proceeding. '
                  'This action will update medication tasks and cannot be easily undone.',
                  textAlign: TextAlign.justify,
                ),
                const SizedBox(height: 14),
                // Reporting nurse label (fetched asynchronously) - placed above the checkbox
                FutureBuilder(
                  future: nurseFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final nurseDoc = snapshot.data;
                    String nurseName = 'Unknown';
                    if (nurseDoc != null && nurseDoc.exists) {
                      final nurseData = nurseDoc.data() as Map<String, dynamic>;
                      nurseName =
                          '${nurseData['user_fname']} ${nurseData['user_lname']}';
                    }
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.person,
                                  size: 25,
                                  color: Color(0xFF00588E),
                                ),
                                const SizedBox(width: 8),
                                // Make label colored and value black, and allow wrapping
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'Reporting Nurse: ',
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            color: Color(0xFF00588E),
                                          ),
                                        ),
                                        TextSpan(
                                          text: nurseName,
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.start,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                // Medication Details Section
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF00588E),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Medication Name
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.medication,
                            size: 20,
                            color: Color(0xFF00588E),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Medication: ',
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF00588E),
                                    ),
                                  ),
                                  TextSpan(
                                    text: medicationName,
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Dosage
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.scale,
                            size: 20,
                            color: Color(0xFF00588E),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Dosage: ',
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF00588E),
                                    ),
                                  ),
                                  TextSpan(
                                    text: dosage,
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Repeat Interval
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.repeat,
                            size: 20,
                            color: Color(0xFF00588E),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Repeat Interval: ',
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF00588E),
                                    ),
                                  ),
                                  TextSpan(
                                    text: repeatInterval,
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Number of Intakes
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.format_list_numbered,
                            size: 20,
                            color: Color(0xFF00588E),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Number of Intakes: ',
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF00588E),
                                    ),
                                  ),
                                  TextSpan(
                                    text: numberOfIntakes.toString(),
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Intake Times
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.access_time,
                            size: 20,
                            color: Color(0xFF00588E),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Intake Times:',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: Color(0xFF00588E),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: intakeTimes.map((time) {
                                    final hour = time.hour;
                                    final minute = time.minute;
                                    final period = hour >= 12 ? 'PM' : 'AM';
                                    final displayHour = hour == 0
                                        ? 12
                                        : (hour > 12 ? hour - 12 : hour);
                                    final formattedTime =
                                        '$displayHour:${minute.toString().padLeft(2, '0')}$period';
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: const Color(0xFF00588E),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        formattedTime,
                                        style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          color: Colors.black,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: isChecked,
                      onChanged: (val) =>
                          setState(() => isChecked = val ?? false),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      activeColor: const Color(0xFF00588E),
                      checkColor: Colors.white,
                      side: const BorderSide(
                        color: Color(0xFF00588E),
                        width: 2,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'I acknowledge that the medication information provided is accurate and complete.',
                        textAlign: TextAlign.justify,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Submit button (responsive)
                  Flexible(
                    flex: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 160,
                        minWidth: 100,
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00588E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: isChecked
                            ? () async {
                                // Close confirmation dialog
                                Navigator.of(context).pop();

                                // Check if widget is still mounted
                                if (!mounted) return;

                                // Show loading indicator
                                showDialog(
                                  context: parentContext,
                                  barrierDismissible: false,
                                  builder: (context) => Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );

                                try {
                                  // Update medication in database
                                  await _updateMedicationInDatabase(
                                    medicationId,
                                    medicationData,
                                    medicationName,
                                    dosage,
                                    repeatInterval,
                                    numberOfIntakes,
                                    intakeTimes,
                                  );

                                  // Check if widget is still mounted
                                  if (!mounted) return;

                                  // Close loading dialog
                                  Navigator.of(parentContext).pop();

                                  // Show success message
                                  _safeShowSnackBar(
                                    parentContext,
                                    SnackBar(
                                      content: Text(
                                        'Medication updated successfully',
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );

                                  // Close edit dialog
                                  Navigator.of(parentContext).pop();
                                } catch (e) {
                                  // Check if widget is still mounted
                                  if (!mounted) return;

                                  // Close loading dialog if it's open
                                  Navigator.of(parentContext).pop();

                                  // Show error message
                                  _safeShowSnackBar(
                                    parentContext,
                                    SnackBar(
                                      content: Text(
                                        'Error updating medication: ${e.toString()}',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            : null,
                        child: const Text(
                          'Update',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Cancel button (responsive)
                  Flexible(
                    flex: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 160,
                        minWidth: 100,
                      ),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteMedication(
    String medicationId,
    Map<String, dynamic> medicationData,
  ) async {
    bool isChecked = false;
    // Prepare a future to fetch the current nurse's user document for display
    final currentUser = FirebaseAuth.instance.currentUser;
    final Future<DocumentSnapshot?> nurseFuture = currentUser != null
        ? FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get()
        : Future.value(null);

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            backgroundColor: Colors.white,
            // add a small left-top exit icon and center the title
            titlePadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top-left X/exit icon only (larger tappable area)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  iconSize: 28,
                  icon: const Icon(Icons.close, color: Color(0xFF00588E)),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                ),
                // consume remaining space so header moves to next row (in content)
                const Expanded(child: SizedBox()),
                const SizedBox(width: 36),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header moved to content so it sits under the exit icon
                  const Center(
                    child: Text(
                      'Delete Confirmation',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00588E),
                        fontSize: 26,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Color(0xFF00588E), thickness: 2),
                  const SizedBox(height: 12),
                  Text(
                    'You are about to delete this entire medication: ${medicationData['medication_name']}.\n\n'
                    'This action cannot be undone and will remove ALL takes and associated intake records.',
                    textAlign: TextAlign.justify,
                  ),
                  const SizedBox(height: 14),
                  // Reporting nurse label (fetched asynchronously) - placed above the checkbox
                  FutureBuilder<DocumentSnapshot?>(
                    future: nurseFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      final nurseDoc = snapshot.data;
                      String nurseName = 'Unknown';
                      if (nurseDoc != null && nurseDoc.exists) {
                        final nurseData =
                            nurseDoc.data() as Map<String, dynamic>;
                        nurseName =
                            '${nurseData['user_fname']} ${nurseData['user_lname']}';
                      }
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.person,
                                    size: 25,
                                    color: Color(0xFF00588E),
                                  ),
                                  const SizedBox(width: 8),
                                  // Make label colored and value black, and allow wrapping
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: 'Reporting Nurse: ',
                                            style: const TextStyle(
                                              fontFamily: 'Poppins',
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                              color: Color(0xFF00588E),
                                            ),
                                          ),
                                          TextSpan(
                                            text: nurseName,
                                            style: const TextStyle(
                                              fontFamily: 'Poppins',
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                              color: Colors.black,
                                            ),
                                          ),
                                        ],
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.start,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: isChecked,
                        onChanged: (val) =>
                            setState(() => isChecked = val ?? false),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        activeColor: const Color(0xFF00588E),
                        checkColor: Colors.white,
                        side: const BorderSide(
                          color: Color(0xFF00588E),
                          width: 2,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'I acknowledge that deleting this medication is permanent and cannot be undone.',
                          textAlign: TextAlign.justify,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 160,
                      minWidth: 100,
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        minimumSize: const Size.fromHeight(44),
                      ),
                      onPressed: isChecked
                          ? () async {
                              try {
                                // Log the deletion activity
                                await _logMedicationActivity(
                                  action: 'delete_medication',
                                  medicationId: medicationId,
                                  medicationData: medicationData,
                                  takeNumber:
                                      0, // 0 for whole medication deletion
                                  oldData: medicationData,
                                );

                                // Delete any medical_tasks created from this medication
                                try {
                                  // Query any task that references this medication id (broader match)
                                  final tasks = await _firestore
                                      .collection('medical_tasks')
                                      .where(
                                        'medication_id',
                                        isEqualTo: medicationId,
                                      )
                                      .get();

                                  for (final t in tasks.docs) {
                                    final data = t.data();
                                    // Try cancel by deterministic id if take_index exists
                                    final takeIndex = data['take_index'];
                                    if (takeIndex != null) {
                                      final notifyId =
                                          ('${medicationId}_$takeIndex')
                                              .hashCode;
                                      NotificationService.cancelNotification(
                                        notifyId,
                                      );
                                    }
                                    // Also attempt to cancel any possible notification ids based on medication intakes
                                    try {
                                      final numIntakes =
                                          (medicationData['number_of_intakes']
                                              as int?) ??
                                          0;
                                      for (int i = 0; i < numIntakes; i++) {
                                        final notifyId =
                                            ('${medicationId}_$i').hashCode;
                                        NotificationService.cancelNotification(
                                          notifyId,
                                        );
                                      }
                                    } catch (_) {}

                                    await t.reference.delete();
                                  }
                                } catch (e) {
                                  print(
                                    'Error deleting medical_tasks for medication $medicationId: $e',
                                  );
                                }

                                // Delete associated completed/missed intake records (legacy collections)
                                try {
                                  final completedIntakes = await _firestore
                                      .collection(
                                        'completed_medication_intakes',
                                      )
                                      .where(
                                        'medication_id',
                                        isEqualTo: medicationId,
                                      )
                                      .get();
                                  for (final doc in completedIntakes.docs) {
                                    await doc.reference.delete();
                                  }
                                } catch (e) {
                                  print(
                                    'Error deleting completed intakes for $medicationId: $e',
                                  );
                                }

                                try {
                                  final missedIntakes = await _firestore
                                      .collection('missed_medication_intakes')
                                      .where(
                                        'medication_id',
                                        isEqualTo: medicationId,
                                      )
                                      .get();
                                  for (final doc in missedIntakes.docs) {
                                    await doc.reference.delete();
                                  }
                                } catch (e) {
                                  print(
                                    'Error deleting missed intakes for $medicationId: $e',
                                  );
                                }

                                // Delete the medication itself
                                await _firestore
                                    .collection('medications')
                                    .doc(medicationId)
                                    .delete();

                                // Remove any cached upcoming medications for this house
                                try {
                                  final keys = _medsCache.keys.toList();
                                  for (final k in keys) {
                                    if (k.startsWith('${widget.houseId}|')) {
                                      _medsCache.remove(k);
                                      _medsCacheTime.remove(k);
                                    }
                                  }
                                } catch (e) {
                                  print(
                                    'Error clearing meds cache for house ${widget.houseId}: $e',
                                  );
                                }

                                // Optimistically remove from in-memory list so UI updates instantly
                                if (mounted) {
                                  setState(() {
                                    _upcomingMedications.removeWhere(
                                      (m) => m['id'] == medicationId,
                                    );
                                  });
                                }

                                Navigator.of(dialogContext).pop();
                                // Force refresh to bypass any stale cache so UI updates immediately
                                await _loadUpcomingMedications(
                                  forceRefresh: true,
                                );

                                // Restart auto-refresh timer to prevent immediate auto-refresh after manual operation
                                _autoRefreshTimer?.cancel();
                                _startAutoRefreshTimer();

                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Medication deleted successfully',
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                print('Error deleting medication: $e');
                                Navigator.of(dialogContext).pop();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error deleting medication',
                                      ),
                                    ),
                                  );
                                }
                              }
                            }
                          : null,
                      child: const Text(
                        'Delete',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Delete multiple medications (bulk) and update UI/cache. This is a
  /// conservative deletion: for each medication id we delete the medication
  /// document, its medication_takes, associated medical_tasks, cancel
  /// notifications and remove from in-memory cache/state.
  Future<void> _deleteMedicationsBulk(List<String> medicationIds) async {
    int success = 0;
    int failed = 0;
    for (final medicationId in medicationIds) {
      try {
        // Fetch medication doc to check existence and then proceed to delete related data
        final medDoc = await _firestore
            .collection('medications')
            .doc(medicationId)
            .get();
        if (medDoc.exists) {
          // Delete associated medical_tasks
          try {
            final tasksQuery = await _firestore
                .collection('medical_tasks')
                .where('task_source', isEqualTo: 'Medication')
                .where('medication_id', isEqualTo: medicationId)
                .get();
            for (final t in tasksQuery.docs) {
              await t.reference.delete();
            }
          } catch (e) {
            print('Error deleting medical_tasks for $medicationId: $e');
          }

          // Delete medication_takes and cancel notifications
          try {
            final takesQuery = await _firestore
                .collection('medication_takes')
                .where('medication_id', isEqualTo: medicationId)
                .get();
            for (final t in takesQuery.docs) {
              final tdata = t.data();
              final takeIndex = (tdata['take_number'] as int? ?? 1) - 1;
              // Try canceling notification that may have been scheduled
              try {
                final nid = ('${medicationId}_$takeIndex').hashCode;
                NotificationService.cancelNotification(nid);
              } catch (e) {
                // ignore
              }
              await t.reference.delete();
            }
          } catch (e) {
            print('Error deleting medication_takes for $medicationId: $e');
          }

          // Finally delete medication doc
          try {
            await medDoc.reference.delete();
          } catch (e) {
            print('Error deleting medication doc $medicationId: $e');
            rethrow;
          }
        }

        // Clear related cache entries
        try {
          final keys = _medsCache.keys.toList();
          for (final k in keys) {
            if (k.startsWith('${widget.houseId}|')) {
              _medsCache.remove(k);
              _medsCacheTime.remove(k);
            }
          }
        } catch (e) {
          print('Error clearing meds cache after bulk delete: $e');
        }

        // Remove from in-memory list
        if (mounted) {
          setState(() {
            _upcomingMedications.removeWhere((m) => m['id'] == medicationId);
          });
        }

        success++;
      } catch (e) {
        print('Bulk delete failed for $medicationId: $e');
        failed++;
      }
    }

    // Refresh UI
    await _loadUpcomingMedications(forceRefresh: true);

    // Show summary
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted $success medications. Failed: $failed'),
        ),
      );
    }
  }

  int _getTotalTakeCount() {
    int totalCount = 0;
    for (final medication in _upcomingMedications) {
      final takeStatuses = medication['take_statuses'] as List<dynamic>? ?? [];
      // Only count pending takes - exclude completed and missed
      final upcomingTakes = takeStatuses.where((take) {
        final status = take['status'] as String;
        return status == 'pending';
      }).toList();
      totalCount += upcomingTakes.length;
    }
    return totalCount;
  }

  Map<String, dynamic>? _getTakeInfoByIndex(int index) {
    // Collect all pending takes from all medications
    final allTakes = <Map<String, dynamic>>[];

    for (final medication in _upcomingMedications) {
      final takeStatuses = medication['take_statuses'] as List<dynamic>? ?? [];

      // Only show pending takes - exclude completed and missed
      final upcomingTakes = takeStatuses.where((take) {
        final status = take['status'] as String;
        return status == 'pending';
      }).toList();

      for (final take in upcomingTakes) {
        allTakes.add({'medication': medication, 'take': take});
      }
    }

    // Sort all takes by scheduled time (chronological order: earliest to latest)
    allTakes.sort((a, b) {
      final aTime =
          (a['take'] as Map<String, dynamic>)['scheduled_time'] as String;
      final bTime =
          (b['take'] as Map<String, dynamic>)['scheduled_time'] as String;

      // Parse time strings (format: "HH:mm")
      final aParts = aTime.split(':');
      final bParts = bTime.split(':');

      if (aParts.length >= 2 && bParts.length >= 2) {
        final aHour = int.tryParse(aParts[0]) ?? 0;
        final aMinute = int.tryParse(aParts[1]) ?? 0;
        final bHour = int.tryParse(bParts[0]) ?? 0;
        final bMinute = int.tryParse(bParts[1]) ?? 0;

        final aTotal = aHour * 60 + aMinute;
        final bTotal = bHour * 60 + bMinute;

        return aTotal.compareTo(bTotal);
      }

      return 0;
    });

    // Return the take at the requested index
    if (index >= 0 && index < allTakes.length) {
      return allTakes[index];
    }

    return null;
  }

  String _formatTimeTo12Hour(String timeString) {
    try {
      final timeParts = timeString.split(':');
      if (timeParts.length < 2) return timeString;

      final hour = int.tryParse(timeParts[0]) ?? 0;
      final minute = int.tryParse(timeParts[1]) ?? 0;

      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);

      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return timeString; // Return original if parsing fails
    }
  }

  String _formatScheduledTimeWithDate(String timeString) {
    return 'Scheduled Time: ${_formatTimeTo12Hour(timeString)}';
  }

  Widget _buildIndividualTakeContainer(Map<String, dynamic> takeInfo) {
    final medication = takeInfo['medication'] as Map<String, dynamic>;
    final take = takeInfo['take'] as Map<String, dynamic>;

    final status = take['status'] as String;
    final takeNumber = take['take_number'] as int;
    final scheduledTime = take['scheduled_time'] as String;
    final takeOrdinal = _getOrdinal(takeNumber);

    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'complete':
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'missed':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default: // pending
        statusColor = Colors.orange;
        statusIcon = Icons.schedule;
    }

    return Dismissible(
      key: ValueKey('${medication['id']}_$takeNumber'),
      // Only allow swipe left (endToStart) so both actions are exposed from one gesture
      direction: DismissDirection.endToStart,
      // Keep a neutral left-side background (not used when swiping left)
      background: Container(color: Colors.transparent),
      // When swiping left, show a split area: blue Edit (left) and red Delete (right)
      secondaryBackground: SizedBox(
        height: double.infinity,
        child: Row(
          children: [
            // Blue edit area (left half of revealed area)
            Expanded(
              child: Container(
                // Soft/light blue background for edit reveal
                color: Color(0xFFBEEAF9),
                alignment: Alignment.centerRight,
                padding: EdgeInsets.only(right: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Use a darker blue icon/text for contrast on the light background
                    Icon(Icons.edit, color: Color(0xFF22688E)),
                    SizedBox(width: 8),
                    Text(
                      'Edit',
                      style: TextStyle(
                        color: Color(0xFF22688E),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Red delete area (right half of revealed area)
            Expanded(
              child: Container(
                // Soft/light red background for delete reveal
                color: Color(0xFFF8D7DA),
                alignment: Alignment.centerRight,
                padding: EdgeInsets.only(right: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Use a darker red icon/text for contrast on the light background
                    Text(
                      'Delete',
                      style: TextStyle(
                        color: Color(0xFFD32F2F),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.delete_forever, color: Color(0xFFD32F2F)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        // Show options sheet but don't dismiss the widget permanently
        await showModalBottomSheet(
          context: context,
          builder: (ctx) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(Icons.edit, color: Color(0xFF22688E)),
                    title: Text('Edit Medication'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _editMedication(medication['id'], medication);
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.delete_forever,
                      color: Color(0xFFD32F2F),
                    ),
                    title: Text('Delete'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _deleteMedication(medication['id'], medication);
                    },
                  ),
                ],
              ),
            );
          },
        );
        return false;
      },
      // Wrap the card in a GestureDetector so long-pressing it enters
      // selection mode and selects the medication. When in selection
      // mode, a normal tap toggles selection. Non-selection-mode taps
      // are left untouched to preserve existing interactions.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () {
          final medId = medication['id'] as String?;
          if (medId == null) return;
          setState(() {
            _selectionMode = true;
            _selectedMedicationIds.add(medId);
          });
        },
        onTap: () {
          if (!_selectionMode) return;
          final medId = medication['id'] as String?;
          if (medId == null) return;
          setState(() {
            if (_selectedMedicationIds.contains(medId)) {
              _selectedMedicationIds.remove(medId);
              if (_selectedMedicationIds.isEmpty) _selectionMode = false;
            } else {
              _selectedMedicationIds.add(medId);
            }
          });
        },
        child: Card(
          // Use soft blue background for medication containers; when selected,
          // show light red highlight for bulk-delete selection.
          color: _selectedMedicationIds.contains(medication['id'])
              ? const Color(0xFFFFEBEE)
              : const Color(0xFFE6F3FA),
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Elderly Name (and optional selection checkbox)
                Row(
                  children: [
                    if (_selectionMode)
                      Checkbox(
                        value: _selectedMedicationIds.contains(
                          medication['id'],
                        ),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedMedicationIds.add(medication['id']);
                            } else {
                              _selectedMedicationIds.remove(medication['id']);
                            }
                          });
                        },
                      ),
                    Icon(Icons.person, color: Color(0xFF00588E)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        medication['elderly_name'] ?? 'Unknown',
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

                // Medication Name and Dosage
                Row(
                  children: [
                    Icon(Icons.medication, color: Colors.green),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${medication['medication_name']} - ${medication['dosage']}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),

                // Frequency
                Row(
                  children: [
                    Icon(Icons.schedule, color: Colors.orange),
                    SizedBox(width: 8),
                    Text(
                      'Frequency: ${medication['repeat_interval']}',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
                SizedBox(height: 12),

                // Take Information Container
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.orange),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                  ),
                  child: Row(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 24),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$takeOrdinal Take',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: statusColor,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              _formatScheduledTimeWithDate(scheduledTime),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          // Square checkbox-style button on the right side.
                          GestureDetector(
                            onTap: () async {
                              // Toggle between pending and completed on tap.
                              final current =
                                  (take['status'] as String?) ?? 'pending';
                              final target =
                                  current == 'completed' ||
                                      current == 'complete'
                                  ? 'pending'
                                  : 'completed';
                              _updateTakeStatus(
                                medication['id'],
                                take['take_number'],
                                target,
                              );
                            },
                            onLongPress: () async {
                              // Long press opens a bottom sheet with full options
                              final canMarkAsMissed = _canMarkAsMissed(
                                scheduledTime,
                              );
                              showModalBottomSheet(
                                context: context,
                                builder: (ctx) {
                                  return SafeArea(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          leading: Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                          ),
                                          title: Text('Complete'),
                                          onTap: () {
                                            Navigator.of(ctx).pop();
                                            _updateTakeStatus(
                                              medication['id'],
                                              take['take_number'],
                                              'completed',
                                            );
                                          },
                                        ),
                                        if (canMarkAsMissed)
                                          ListTile(
                                            leading: Icon(
                                              Icons.cancel,
                                              color: Colors.red,
                                            ),
                                            title: Text('Missed'),
                                            onTap: () {
                                              Navigator.of(ctx).pop();
                                              _updateTakeStatus(
                                                medication['id'],
                                                take['take_number'],
                                                'missed',
                                              );
                                            },
                                          ),
                                        SizedBox(height: 8),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: statusColor,
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                color:
                                    status == 'complete' ||
                                        status == 'completed'
                                    ? statusColor
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Created timestamp (smaller and at bottom)
                if (medication['created_at'] != null)
                  Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Created: ${DateFormat('MMM dd, yyyy hh:mm a').format((medication['created_at'] as Timestamp).toDate())}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ),

                // Spacing before potential actions
                SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _updateTakeStatus(
    String medicationId,
    int takeNumber,
    String newStatus,
  ) async {
    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) {
        print('Error: Could not get nurse ID');
        return;
      }
      print('Updating take status for nurse: $nurseId');

      // Get the medication document to get elderly_id and other info
      final medicationDoc = await _firestore
          .collection('medications')
          .doc(medicationId)
          .get();
      if (!medicationDoc.exists) return;

      final medicationData = medicationDoc.data() as Map<String, dynamic>;
      final elderlyId = medicationData['elderly_id'] as String;

      // Find the specific take document
      final takeQuery = await _firestore
          .collection('medication_takes')
          .where('medication_id', isEqualTo: medicationId)
          .where('take_number', isEqualTo: takeNumber)
          .get();

      if (takeQuery.docs.isEmpty) return;

      final takeDoc = takeQuery.docs.first;
      final takeData = takeDoc.data();
      final originalStatus = takeData['status'] as String;

      // Check if trying to mark as missed - only allow after scheduled time
      if (newStatus == 'missed') {
        final scheduledTimeStr = takeData['scheduled_time'] as String;
        final scheduledTimeParts = scheduledTimeStr.split(':');
        if (scheduledTimeParts.length >= 2) {
          final scheduledHour = int.tryParse(scheduledTimeParts[0]) ?? 0;
          final scheduledMinute = int.tryParse(scheduledTimeParts[1]) ?? 0;

          final now = DateTime.now();
          final scheduledDateTime = DateTime(
            now.year,
            now.month,
            now.day,
            scheduledHour,
            scheduledMinute,
          );

          if (now.isBefore(scheduledDateTime)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Cannot mark as missed before scheduled time'),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }
        }
      }

      // Update the take status
      final updateData = <String, dynamic>{
        'status': newStatus,
        'updated_at': Timestamp.fromDate(DateTime.now()),
      };

      if (newStatus == 'completed') {
        updateData['completed_at'] = Timestamp.fromDate(DateTime.now());
        updateData['completed_by'] = nurseId;
        print(
          'Setting completed_at and completed_by for take $takeNumber: completed_at=${updateData['completed_at']}, completed_by=$nurseId',
        );
      } else {
        updateData['completed_at'] = null;
        updateData['completed_by'] = null;
        print('Clearing completed_at and completed_by for take $takeNumber');
      }

      await takeDoc.reference.update(updateData);
      print('Updated take document with status: $newStatus');

      // Log the activity to Medication_Activity_Logs
      final scheduledTime = takeData['scheduled_time'] as String;
      if (newStatus == 'completed' && originalStatus != 'completed') {
        await _logMedicationActivityNew(
          action: 'take_completed',
          medicationId: medicationId,
          elderlyId: elderlyId,
          nurseId: nurseId,
          houseId: medicationData['house_id'] ?? widget.houseId,
          shift: medicationData['shift'] ?? _getCurrentShift(),
          medicationName: medicationData['medication_name'] ?? '',
          dosage: medicationData['dosage'] ?? '',
          repeatInterval: medicationData['repeat_interval'] ?? '',
          takeNumber: takeNumber,
          scheduledTime: scheduledTime,
        );
        // Play confetti to celebrate the completed take
        try {
          _confettiController.play();
        } catch (e) {
          print('Error playing confetti: $e');
        }
      } else if (newStatus == 'missed' && originalStatus != 'missed') {
        await _logMedicationActivityNew(
          action: 'take_missed',
          medicationId: medicationId,
          elderlyId: elderlyId,
          nurseId: nurseId,
          houseId: medicationData['house_id'] ?? widget.houseId,
          shift: medicationData['shift'] ?? _getCurrentShift(),
          medicationName: medicationData['medication_name'] ?? '',
          dosage: medicationData['dosage'] ?? '',
          repeatInterval: medicationData['repeat_interval'] ?? '',
          takeNumber: takeNumber,
          scheduledTime: scheduledTime,
        );
      }

      // Check if all takes are completed to update medication status
      final allTakesQuery = await _firestore
          .collection('medication_takes')
          .where('medication_id', isEqualTo: medicationId)
          .get();

      final allStatuses = allTakesQuery.docs
          .map((doc) => doc.data()['status'] as String)
          .toList();
      String overallStatus = 'active';
      if (allStatuses.contains('missed')) {
        overallStatus = 'has_missed';
      } else if (allStatuses.every((status) => status == 'completed')) {
        overallStatus = 'completed';
      }

      // Update medication status if needed
      await medicationDoc.reference.update({
        'status': overallStatus,
        'updated_at': Timestamp.fromDate(DateTime.now()),
      });

      // If this take was marked completed or missed, remove any pending
      // medical_tasks created for this medication take so Home/upcoming no
      // longer shows it.
      if (newStatus == 'completed' || newStatus == 'missed') {
        try {
          final tasksQuery = await _firestore
              .collection('medical_tasks')
              .where('task_source', isEqualTo: 'Medication')
              .where('medication_id', isEqualTo: medicationId)
              .where('take_index', isEqualTo: takeNumber - 1)
              .get();

          for (final tdoc in tasksQuery.docs) {
            await tdoc.reference.delete();
          }
        } catch (e) {
          print(
            'Error removing medical_tasks for medication $medicationId: $e',
          );
        }
      }

      // Refresh the UI and force refresh cache to reflect the changes
      await _loadUpcomingMedications(forceRefresh: true);

      // Restart auto-refresh timer to prevent immediate auto-refresh after manual operation
      _autoRefreshTimer?.cancel();
      _startAutoRefreshTimer();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Take status updated to ${newStatus.toUpperCase()}'),
            backgroundColor: newStatus == 'completed'
                ? Colors.green
                : newStatus == 'missed'
                ? Colors.red
                : Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('Error updating take status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating status'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Activity logging is now handled directly in _updateTakeStatus method

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // Date Picker Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.white,
          child: Row(
            children: [
              const Text(
                'Date: ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF00588E),
                ),
              ),
              Text(
                DateFormat('MMM. d, yyyy').format(_selectedDate),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(
                  Icons.calendar_today,
                  color: Color(0xFF00588E),
                ),
                onPressed: () => _selectDate(context),
              ),
            ],
          ),
        ),
        // Selection toolbar for bulk actions (only visible when in selection mode)
        if (_selectionMode)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectionMode = false;
                      _selectedMedicationIds.clear();
                    });
                  },
                  icon: Icon(Icons.close, color: Colors.white),
                  label: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF00588E),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    elevation: 0,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _selectedMedicationIds.isEmpty
                      ? null
                      : () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text('Delete selected medications'),
                              content: Text(
                                'Are you sure you want to delete ${_selectedMedicationIds.length} selected medication(s)? This cannot be undone.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _deleteMedicationsBulk(
                              _selectedMedicationIds.toList(),
                            );
                            setState(() {
                              _selectionMode = false;
                              _selectedMedicationIds.clear();
                            });
                          }
                        },
                  icon: Icon(Icons.delete_forever, color: Colors.white),
                  label: Text(
                    'Delete (${_selectedMedicationIds.length})',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ),
          ),
        // Main Content
        Expanded(
          child: Stack(
            children: [
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                // Medications List with RefreshIndicator
                RefreshIndicator(
                  onRefresh: () async {
                    await _loadUpcomingMedications(forceRefresh: true);
                  },
                  child: _upcomingMedications.isEmpty
                      ? ListView(
                          // Wrap empty state in ListView to enable pull-to-refresh
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.6,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(height: 24),
                                    Icon(
                                      Icons.medication,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'No upcoming medications',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: EdgeInsets.only(bottom: 80),
                          itemCount: _getTotalTakeCount(),
                          itemBuilder: (context, index) {
                            final takeInfo = _getTakeInfoByIndex(index);
                            if (takeInfo == null) return SizedBox.shrink();

                            return _buildIndividualTakeContainer(takeInfo);
                          },
                        ),
                ),
              if (!_isLoading)
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FloatingActionButton.extended(
                      onPressed: () => _showAddMedicationDialog(),
                      label: Text(
                        'Add Medication',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      icon: Icon(Icons.add, color: Colors.white),
                      backgroundColor: Color(0xFF00588E),
                    ),
                  ),
                ),
              // Confetti overlay (sibling in the Stack)
              Positioned(
                top: 40,
                left: 0,
                right: 0,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConfettiWidget(
                    confettiController: _confettiController,
                    blastDirectionality: BlastDirectionality.explosive,
                    shouldLoop: false,
                    emissionFrequency: 0.05,
                    numberOfParticles: 20,
                    maxBlastForce: 20,
                    minBlastForce: 5,
                    gravity: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
