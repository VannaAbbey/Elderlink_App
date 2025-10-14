import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'notification_service.dart';

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
  static const Duration _cacheDuration = Duration(minutes: 2);
  List<Map<String, String>> _elderlyList = [];
  String? _selectedElderly;
  bool _isLoading = false;
  List<Map<String, dynamic>> _upcomingMedications = [];
  Timer? _missedMedicationTimer;
  Timer? _autoRefreshTimer;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.selectedDate ?? DateTime.now();
    // Prewarm nurse id and load data (uses cache if available) to make
    // the first frame appear faster when switching tabs/houses.
    _prewarm();
    _startMissedMedicationTimer();
    _startAutoRefreshTimer();
  }

  @override
  bool get wantKeepAlive => true;

  void _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
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
      setState(() {
        _selectedDate = picked;
      });
      // Reload medications for the new date
      _prewarm();
    }
  }

  Future<void> _prewarm() async {
    // Kick off assigned elderly and medications loading in background.
    // We intentionally don't await both sequentially to reduce perceived wait.
    _loadAssignedElderly();
    _loadUpcomingMedications();
  }

  @override
  void dispose() {
    _missedMedicationTimer?.cancel();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  String _getSelectedDay() {
    return DateFormat('EEEE').format(_selectedDate);
  }

  String _getCurrentShift() {
    final currentHour = _selectedDate.hour;
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

  Future<String?> _getNurseId() async {
    try {
      final nameParts = widget.nurseName?.split(' ') ?? [];
      if (nameParts.length < 2) return null;

      final firstName = nameParts[0];
      final lastName = nameParts[1];

      final userQuery = await _firestore
          .collection('users')
          .where('user_fname', isEqualTo: firstName)
          .where('user_lname', isEqualTo: lastName)
          .where('user_type', isEqualTo: 'nurse')
          .get();

      return userQuery.docs.isNotEmpty ? userQuery.docs.first.id : null;
    } catch (e) {
      print('Error getting nurse ID: $e');
      return null;
    }
  }

  Future<List<String>> _getNurseWorkingDays(String nurseId) async {
    try {
      final currentShift = _getCurrentShift();
      final currentDay = _getSelectedDay();

      // For shifts that span midnight (like 3rd shift), we need special handling
      if (currentShift == "3rd" && _selectedDate.hour < 6) {
        // If it's 3rd shift and before 6 AM, check if nurse was assigned to previous day
        final days = [
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday',
        ];
        final currentDayIndex = days.indexOf(currentDay);
        final previousDayIndex = currentDayIndex == 0 ? 6 : currentDayIndex - 1;
        final previousDay = days[previousDayIndex];

        // Check if nurse has 3rd shift assignment on the previous day
        final shiftQuery = await _firestore
            .collection('house_shift_assignments')
            .where('user_id', isEqualTo: nurseId)
            .where('user_type', isEqualTo: 'nurse')
            .where('is_current', isEqualTo: true)
            .where('shift', isEqualTo: currentShift)
            .where('days_assigned', arrayContains: previousDay)
            .get();

        if (shiftQuery.docs.isNotEmpty) {
          // Nurse was assigned to 3rd shift on previous day, so they're working today
          return [currentDay];
        }
      }

      // Normal case: check current shift and current day
      final shiftQuery = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .get();

      if (shiftQuery.docs.isNotEmpty) {
        final data = shiftQuery.docs.first.data();
        return List<String>.from(data['days_assigned'] ?? []);
      }
      return [];
    } catch (e) {
      print('Error getting nurse working days: $e');
      return [];
    }
  }

  Future<bool> _isNurseScheduledForToday() async {
    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) return false;

      // First check if nurse has any current shift assignment at all
      final anyShiftQuery = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .get();

      if (anyShiftQuery.docs.isNotEmpty) {
        // Nurse has some current shift assignment, consider them scheduled
        return true;
      }

      // Fallback to the original day-specific logic
      final workingDays = await _getNurseWorkingDays(nurseId);
      final today = _getSelectedDay();

      return workingDays.contains(today);
    } catch (e) {
      print('Error checking if nurse is scheduled for today: $e');
      return false;
    }
  }

  Future<void> _saveMedicationToDatabase({
    required String elderlyId,
    required String medicationName,
    required String dosage,
    required String repeatInterval,
    required int numberOfIntakes,
    required List<TimeOfDay> intakeTimes,
  }) async {
    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) {
        throw Exception('Could not find nurse ID');
      }

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

      // Create medication document in new Medications table
      final medicationData = {
        'medication_id': '', // Will be set after creation
        'elderly_id': elderlyId,
        'house_id': widget.houseId,
        'created_nurse_id': nurseId,
        'medication_name': medicationName,
        'dosage': dosage,
        'repeat_interval': repeatInterval,
        'shift': _getCurrentShift(),
        'working_days': repeatInterval == 'Daily'
            ? null // null means all days for Daily medications
            : workingDays, // specific days for Once medications
        'created_at': Timestamp.fromDate(DateTime.now()),
        'updated_at': Timestamp.fromDate(DateTime.now()),
        'status': 'active',
      };

      final medicationDocRef = await _firestore
          .collection('medications')
          .add(medicationData);

      final medicationId = medicationDocRef.id;

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
          'status': 'pending',
          'completed_at': null,
          'completed_by': null,
          'created_at': Timestamp.fromDate(DateTime.now()),
          'updated_at': Timestamp.fromDate(DateTime.now()),
        });
      }

      // Commit the batch
      await batch.commit();

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
      await _loadUpcomingMedications(forceRefresh: true);

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

        final taskStart = DateTime(now.year, now.month, now.day, hour, minute);

        // Skip past takes
        if (taskStart.isBefore(now)) continue;

        // Avoid duplicates: check existing medical_tasks
        final existing = await _firestore
            .collection('medical_tasks')
            .where('task_source', isEqualTo: 'Medication')
            .where('medication_id', isEqualTo: medicationId)
            .where('take_index', isEqualTo: takeNumber - 1) // 0-based index
            .where('task_start', isEqualTo: Timestamp.fromDate(taskStart))
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

        final taskTitle =
            '$medName ${dosage.isNotEmpty ? '- $dosage' : ''} for $elderlyName';
        final taskDesc =
            'Medication scheduled for $elderlyName at ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

        final taskDocRef = _firestore.collection('medical_tasks').doc();
        await taskDocRef.set({
          'task_id': taskDocRef.id,
          'medication_id': medicationId,
          'elderly_id': elderlyId,
          'task_title': taskTitle,
          'task_description': taskDesc,
          'task_start': taskStart,
          'task_status': 'pending',
          'take_index': takeNumber - 1, // 0-based index
          'task_source': 'Medication',
          'task_frequency': 'Daily',
          'task_category': 'Medication',
          'days': 1,
        });

        // schedule notification 5 minutes before (only if in future)
        final notifyTime = taskStart.subtract(Duration(minutes: 5));
        if (notifyTime.isAfter(DateTime.now())) {
          NotificationService.scheduleTaskNotification(
            id: ('${medicationId}_${takeNumber - 1}').hashCode,
            title: 'Medication Reminder',
            body: '$medName for $elderlyName in 5 minutes',
            dateTime: notifyTime,
          );
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
        });
        return;
      }

      print('Found nurse ID: $nurseId');

      // First check if nurse is assigned to work this shift on this day
      print('Checking shift assignment for nurseId: $nurseId');
      print('Looking for - Shift: $currentShift, Day: $currentDay');

      final shiftQuery = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .where('days_assigned', arrayContains: currentDay)
          .get();

      if (shiftQuery.docs.isEmpty) {
        print('Nurse is not assigned to this shift on this day');
        print('Query returned no results for house_shift_assignments');
        if (!mounted) return;
        setState(() {
          _elderlyList = [];
          _isLoading = false;
        });
        return;
      }

      print('Found shift assignment: ${shiftQuery.docs.first.data()}');

      print('Checking elderly assignments...');
      print(
        'Params - nurseId: $nurseId, house: ${widget.houseId}, shift: $currentShift, day: $currentDay',
      );

      // Get nurse-elderly assignments for the current nurse
      final nurseElderlyQuery = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .where('day', isEqualTo: currentDay)
          .get();

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
      });
    } catch (e) {
      print('Error loading assigned elderly: $e');
      if (mounted) {
        setState(() {
          _elderlyList = [];
          _isLoading = false;
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
      final nurseAssignFuture = _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('house_id', arrayContains: widget.houseId)
          .where('shift', isEqualTo: currentShift)
          .where('day', isEqualTo: currentDay)
          .get();

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

      // Filter medications by assigned elderly, shift and working day
      final medsToInclude = <Map<String, dynamic>>[];
      final elderlyIdsNeeded = <String>{};
      final medicationIds = <String>[];

      for (final doc in medicationsQuery.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final elderlyId = data['elderly_id'] as String?;
        if (elderlyId == null) continue;

        if (!assignedElderlyIds.contains(elderlyId)) continue;

        final medicationShift = data['shift'] as String?;
        final workingDays = data['working_days'] as List?;
        final repeatInterval = data['repeat_interval'] as String?;

        // Check if medication is scheduled for current shift and day
        bool isScheduledForToday = false;
        if (medicationShift == currentShift) {
          if (repeatInterval == 'Daily' || workingDays == null) {
            // Daily medications or null working_days means all days
            isScheduledForToday = true;
          } else if (workingDays.contains(currentDay)) {
            // Once medications with specific working days
            isScheduledForToday = true;
          }
        }

        if (isScheduledForToday) {
          medsToInclude.add({'id': doc.id, ...data});
          elderlyIdsNeeded.add(elderlyId);
          medicationIds.add(doc.id);
        }
      }

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

      // Group takes by medication_id and filter by shift time
      final takesByMedication = <String, List<Map<String, dynamic>>>{};
      for (final takeDoc in allTakesDocs) {
        final takeData = takeDoc.data() as Map<String, dynamic>;
        final medId = takeData['medication_id'] as String;

        // Check if take's scheduled time falls within current shift
        final scheduledTimeStr = takeData['scheduled_time'] as String?;
        if (scheduledTimeStr != null &&
            _isTimeInCurrentShift(scheduledTimeStr)) {
          if (!takesByMedication.containsKey(medId)) {
            takesByMedication[medId] = [];
          }
          takesByMedication[medId]!.add({'id': takeDoc.id, ...takeData});
        }
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

        // Filter out completed takes - only show active takes
        final activeTakes = allTakes
            .where((take) => take['status'] != 'complete')
            .toList();

        // Skip medications that have no active takes
        if (activeTakes.isEmpty) continue;

        // Convert to old format for compatibility with existing UI
        final intakeTimes = activeTakes
            .map((t) => t['scheduled_time'] as String)
            .toList();
        final takeStatuses = activeTakes
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
          'number_of_intakes': activeTakes.length,
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
    // Ensure elderly list is loaded before showing dialog
    if (_elderlyList.isEmpty && !_isLoading) {
      await _loadAssignedElderly();
    }

    String? selectedElderlyTemp = _selectedElderly;
    String? selectedMedicationTemp;
    String? selectedDosageTemp;
    String? selectedIntervalTemp;
    int? numberOfIntakesTemp;
    List<TimeOfDay?> intakeTimes = [];

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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(validationMessage!),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
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
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Please fill in all fields'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
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
    );
  }

  void _showNotScheduledDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 45),
              SizedBox(height: 8),
              Text(
                'Not Scheduled \n Today',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF00588E),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            'It is not your shift or schedule today. You cannot add medications when you are not scheduled.',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.justify,
          ),
          actions: [
            Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF00588E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        );
      },
    );
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
                                  ScaffoldMessenger.of(
                                    parentContext,
                                  ).showSnackBar(
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
                                  ScaffoldMessenger.of(
                                    parentContext,
                                  ).showSnackBar(
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

  void _startMissedMedicationTimer() {
    // Check for missed medications every 5 minutes
    _missedMedicationTimer = Timer.periodic(Duration(minutes: 5), (timer) {
      _checkForMissedMedications();
    });
    // Also check immediately
    _checkForMissedMedications();
  }

  void _startAutoRefreshTimer() {
    // Auto-refresh medication data every 45 seconds to ensure data is always updated
    _autoRefreshTimer = Timer.periodic(Duration(seconds: 45), (timer) {
      if (mounted) {
        _loadUpcomingMedications(forceRefresh: true);
      }
    });
  }

  Future<void> _checkForMissedMedications() async {
    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) return;

      final currentTime = DateTime.now();
      final currentDay = _getSelectedDay();
      final currentShift = _getCurrentShift();

      print(
        'Checking for missed medications at ${DateFormat('HH:mm').format(currentTime)}',
      );

      // Get nurse's assigned elderly for current day and shift
      final nurseElderlyQuery = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('house_id', arrayContains: widget.houseId)
          .where('shift', isEqualTo: currentShift)
          .where('day', isEqualTo: currentDay)
          .get();

      if (nurseElderlyQuery.docs.isEmpty) return;

      // Get assigned elderly IDs for this nurse
      final assignedElderlyIds = List<String>.from(
        nurseElderlyQuery.docs.first.data()['elderly_ids'] ?? [],
      );

      if (assignedElderlyIds.isEmpty) return;

      // Get all upcoming medications for current house and shift
      final medicationsQuery = await _firestore
          .collection('medications')
          .where('house_id', isEqualTo: widget.houseId)
          .where('status', isEqualTo: 'active')
          .get();

      for (final doc in medicationsQuery.docs) {
        final data = doc.data();
        final elderlyId = data['elderly_id'] as String;

        // Only check medications for elderly assigned to this nurse
        if (!assignedElderlyIds.contains(elderlyId)) continue;

        final medicationShift = data['shift'] as String?;
        final workingDays = data['working_days'] as List?;
        final repeatInterval = data['repeat_interval'] as String?;

        // Only check medications for current shift and current day
        bool shouldCheckMedication = false;
        if (medicationShift == currentShift) {
          if (repeatInterval == 'Daily' || workingDays == null) {
            // Daily medications or null working_days means all days
            shouldCheckMedication = true;
          } else if (workingDays.contains(currentDay)) {
            // Once medications with specific working days
            shouldCheckMedication = true;
          }
        }

        if (shouldCheckMedication) {
          final takeStatuses = data['take_statuses'] as List<dynamic>? ?? [];
          bool hasUpdates = false;

          for (int i = 0; i < takeStatuses.length; i++) {
            final take = takeStatuses[i] as Map<String, dynamic>;
            final status = take['status'] as String;
            final scheduledTimeStr = take['scheduled_time'] as String;

            // Only check takes that are scheduled within the current shift
            if (!_isTimeInCurrentShift(scheduledTimeStr)) continue;

            // Only check pending medications
            if (status == 'pending') {
              // Parse scheduled time (assuming format is HH:mm)
              final timeParts = scheduledTimeStr.split(':');
              if (timeParts.length == 2) {
                final scheduledHour = int.tryParse(timeParts[0]) ?? 0;
                final scheduledMinute = int.tryParse(timeParts[1]) ?? 0;

                // Create scheduled DateTime for today
                final scheduledDateTime = DateTime(
                  currentTime.year,
                  currentTime.month,
                  currentTime.day,
                  scheduledHour,
                  scheduledMinute,
                );

                // Check if more than 1 hour has passed since scheduled time
                final timeDifference = currentTime.difference(
                  scheduledDateTime,
                );
                if (timeDifference.inHours >= 1) {
                  print(
                    'Marking take ${take['take_number']} as missed for medication ${data['medication_name']} (overdue by ${timeDifference.inMinutes} minutes)',
                  );

                  // Update status to missed
                  takeStatuses[i]['status'] = 'missed';
                  takeStatuses[i]['missed_at'] = currentTime;
                  takeStatuses[i]['missed_reason'] =
                      'Automatically marked as missed after 1 hour';
                  hasUpdates = true;
                }
              }
            }
          }

          // Update the document if there were changes
          if (hasUpdates) {
            await _firestore.collection('medications').doc(doc.id).update({
              'take_statuses': takeStatuses,
            });
            print(
              'Updated missed statuses for medication: ${data['medication_name']}',
            );
          }
        }
      }

      // Refresh the UI if there were any updates
      await _loadUpcomingMedications(forceRefresh: true);
    } catch (e) {
      print('Error checking for missed medications: $e');
    }
  }

  // Removed _createCompletedMedicationIntake - using unified activity logs only

  // Removed methods that use separate collections - now using unified activity logs only

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
      if (takeNumber == null) {
        takeNumber = 1;
      }

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
    List<TimeOfDay?> intakeTimes = [];

    // Parse existing intake times
    final existingTimes = List<String>.from(
      medicationData['intake_times'] ?? [],
    );
    for (String timeStr in existingTimes) {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        intakeTimes.add(
          TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
        );
      }
    }

    // Fill remaining slots with null
    while (intakeTimes.length < 6) {
      intakeTimes.add(null);
    }

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
      if (selectedMedicationTemp != medicationData['medication_name'])
        return true;

      // Check dosage
      if (selectedDosageTemp != medicationData['dosage']) return true;

      // Check repeat interval
      if (selectedIntervalTemp != medicationData['repeat_interval'])
        return true;

      // Check number of intakes
      if (numberOfIntakesTemp != medicationData['number_of_intakes'])
        return true;

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
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'No changes detected. Please modify at least one field before updating.',
                                    ),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Please select all intake times',
                                      ),
                                    ),
                                  );
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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(validationMessage!),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Medication updated successfully')),
      );
    } catch (e) {
      print('Error updating medication: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating medication')));
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
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                // Medication Details Section
                Container(
                  margin: const EdgeInsets.only(top: 16),
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
                                        '${displayHour}:${minute.toString().padLeft(2, '0')}$period';
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
                                  ScaffoldMessenger.of(
                                    parentContext,
                                  ).showSnackBar(
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
                                  ScaffoldMessenger.of(
                                    parentContext,
                                  ).showSnackBar(
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

  Future<void> _deleteIndividualTake(
    String medicationId,
    Map<String, dynamic> medicationData,
    int takeNumber,
  ) async {
    try {
      // Prevent deleting any take except the last one if there are multiple takes
      if (takeNumber != (medicationData['number_of_intakes'] ?? 1)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please delete the last take first (${_getOrdinal(medicationData['number_of_intakes'])} take)',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Get current take statuses
      final takeStatuses = List<Map<String, dynamic>>.from(
        medicationData['take_statuses'] ?? [],
      );

      // Find the take to delete
      final takeToDelete = takeStatuses.firstWhere(
        (take) => take['take_number'] == takeNumber,
        orElse: () => <String, dynamic>{},
      );

      if (takeToDelete.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Take not found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Show confirmation dialog first
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Text('Delete ${_getOrdinal(takeNumber)} Take'),
            content: Text(
              'Are you sure you want to delete the ${_getOrdinal(takeNumber)} take for ${medicationData['medication_name']}?\n\n'
              'This will permanently remove this take and cancel its scheduled notification.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text('Delete', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      );

      if (confirm != true) {
        return;
      }

      // Determine the index of the take being removed (0-based)
      final int removedIndex = takeNumber - 1;

      // Cancel notification for this specific take
      try {
        final notifyId = ('${medicationId}_${removedIndex}').hashCode;
        NotificationService.cancelNotification(notifyId);
      } catch (e) {
        print('Error cancelling notification: $e');
      }

      // Delete the corresponding medical_task
      try {
        final taskQuery = await _firestore
            .collection('medical_tasks')
            .where('medication_id', isEqualTo: medicationId)
            .where('take_index', isEqualTo: removedIndex)
            .get();

        for (final doc in taskQuery.docs) {
          await doc.reference.delete();
        }
      } catch (e) {
        print('Error deleting medical task: $e');
      }

      // Delete the take from medication_takes collection
      try {
        final takeQuery = await _firestore
            .collection('medication_takes')
            .where('medication_id', isEqualTo: medicationId)
            .where('take_number', isEqualTo: takeNumber)
            .get();

        for (final doc in takeQuery.docs) {
          await doc.reference.delete();
        }
      } catch (e) {
        print('Error deleting medication take: $e');
      }

      // Update remaining takes in medication_takes collection
      try {
        final remainingTakesQuery = await _firestore
            .collection('medication_takes')
            .where('medication_id', isEqualTo: medicationId)
            .where('take_number', isGreaterThan: takeNumber)
            .get();

        final batch = _firestore.batch();
        for (final doc in remainingTakesQuery.docs) {
          final takeData = doc.data();
          final currentTakeNumber = takeData['take_number'] as int;
          batch.update(doc.reference, {
            'take_number': currentTakeNumber - 1,
            'updated_at': Timestamp.fromDate(DateTime.now()),
          });
        }
        await batch.commit();
      } catch (e) {
        print('Error updating remaining takes: $e');
      }

      // Remove the specific take from take_statuses
      takeStatuses.removeWhere((take) => take['take_number'] == takeNumber);

      // Also remove from intake_times array (same index)
      List<String> intakeTimes = List<String>.from(
        medicationData['intake_times'] ?? [],
      );
      if (removedIndex >= 0 && removedIndex < intakeTimes.length) {
        intakeTimes.removeAt(removedIndex);
      }

      // Re-index remaining takes to maintain sequential numbering
      for (int i = 0; i < takeStatuses.length; i++) {
        takeStatuses[i]['take_number'] = i + 1;
        // Update scheduled_time to match new intake_times array
        if (i < intakeTimes.length) {
          takeStatuses[i]['scheduled_time'] = intakeTimes[i];
        }
      }

      // Update number_of_intakes
      final newIntakeCount = takeStatuses.length;

      // Update the medication document
      await _firestore.collection('medications').doc(medicationId).update({
        'take_statuses': takeStatuses,
        'intake_times': intakeTimes,
        'number_of_intakes': newIntakeCount,
        'updated_at': Timestamp.fromDate(DateTime.now()),
      });

      // Log the deletion activity
      await _logMedicationActivity(
        action: 'delete_individual_take',
        medicationId: medicationId,
        medicationData: medicationData,
        takeNumber: takeNumber,
        oldData: takeToDelete,
      );

      // If no takes remain, delete the entire medication
      if (takeStatuses.isEmpty) {
        await _deleteMedication(medicationId, medicationData);
        return;
      }

      // Refresh the UI
      await _loadUpcomingMedications(forceRefresh: true);

      // Restart auto-refresh timer to prevent immediate auto-refresh after manual operation
      _autoRefreshTimer?.cancel();
      _startAutoRefreshTimer();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_getOrdinal(takeNumber)} take deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error in _deleteIndividualTake: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting take'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteMedication(
    String medicationId,
    Map<String, dynamic> medicationData,
  ) async {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Delete Entire Medication'),
          content: Text(
            'Are you sure you want to delete this entire medication: ${medicationData['medication_name']}?\n\n'
            'This action cannot be undone and will remove ALL takes and associated intake records.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                try {
                  // Log the deletion activity
                  await _logMedicationActivity(
                    action: 'delete_medication',
                    medicationId: medicationId,
                    medicationData: medicationData,
                    takeNumber: 0, // 0 for whole medication deletion
                    oldData: medicationData,
                  );

                  // Delete any medical_tasks created from this medication
                  try {
                    // Query any task that references this medication id (broader match)
                    final tasks = await _firestore
                        .collection('medical_tasks')
                        .where('medication_id', isEqualTo: medicationId)
                        .get();

                    for (final t in tasks.docs) {
                      final data = t.data();
                      // Try cancel by deterministic id if take_index exists
                      final takeIndex = data['take_index'];
                      if (takeIndex != null) {
                        final notifyId =
                            ('${medicationId}_$takeIndex').hashCode;
                        NotificationService.cancelNotification(notifyId);
                      }
                      // Also attempt to cancel any possible notification ids based on medication intakes
                      try {
                        final numIntakes =
                            (medicationData['number_of_intakes'] as int?) ?? 0;
                        for (int i = 0; i < numIntakes; i++) {
                          final notifyId = ('${medicationId}_$i').hashCode;
                          NotificationService.cancelNotification(notifyId);
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
                        .collection('completed_medication_intakes')
                        .where('medication_id', isEqualTo: medicationId)
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
                        .where('medication_id', isEqualTo: medicationId)
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
                  await _loadUpcomingMedications(forceRefresh: true);

                  // Restart auto-refresh timer to prevent immediate auto-refresh after manual operation
                  _autoRefreshTimer?.cancel();
                  _startAutoRefreshTimer();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Medication deleted successfully')),
                  );
                } catch (e) {
                  print('Error deleting medication: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting medication')),
                  );
                }
              },
              child: Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
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
    int currentIndex = 0;

    for (final medication in _upcomingMedications) {
      final takeStatuses = medication['take_statuses'] as List<dynamic>? ?? [];

      // Sort take statuses by take_number
      takeStatuses.sort((a, b) {
        final aNum = a['take_number'] as int? ?? 0;
        final bNum = b['take_number'] as int? ?? 0;
        return aNum.compareTo(bNum);
      });

      // Only show pending takes - exclude completed and missed
      final upcomingTakes = takeStatuses.where((take) {
        final status = take['status'] as String;
        return status == 'pending';
      }).toList();

      for (final take in upcomingTakes) {
        if (currentIndex == index) {
          return {'medication': medication, 'take': take};
        }
        currentIndex++;
      }
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

      return '${displayHour}:${minute.toString().padLeft(2, '0')}$period';
    } catch (e) {
      return timeString; // Return original if parsing fails
    }
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
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                border: Border.all(color: statusColor.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
                color: statusColor.withOpacity(0.1),
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
                          'Scheduled Time: ${_formatTimeTo12Hour(scheduledTime)}',
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
                      Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 4),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          size: 20,
                          color: statusColor,
                        ),
                        onSelected: (String newStatus) {
                          _updateTakeStatus(
                            medication['id'],
                            take['take_number'],
                            newStatus,
                          );
                        },
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<String>>[
                              PopupMenuItem<String>(
                                value: 'pending',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.schedule,
                                      color: Colors.orange,
                                      size: 16,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Pending'),
                                  ],
                                ),
                              ),
                              PopupMenuItem<String>(
                                value: 'complete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 16,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Complete'),
                                  ],
                                ),
                              ),
                              PopupMenuItem<String>(
                                value: 'missed',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.cancel,
                                      color: Colors.red,
                                      size: 16,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Missed'),
                                  ],
                                ),
                              ),
                            ],
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
                  'Created: ${DateFormat('MMM dd, yyyy HH:mm').format((medication['created_at'] as Timestamp).toDate())}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ),

            // Action buttons section
            SizedBox(height: 12),

            // Individual Take Delete Button (only show for the last take if there are 2 or more takes total)
            if (status == 'pending' &&
                (medication['number_of_intakes'] ?? 1) > 1 &&
                takeNumber == (medication['number_of_intakes'] ?? 1))
              Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Center(
                  child: ElevatedButton.icon(
                    onPressed: () => _deleteIndividualTake(
                      medication['id'],
                      medication,
                      takeNumber,
                    ),
                    icon: Icon(Icons.remove_circle_outline, size: 16),
                    label: Text('Delete This ${_getOrdinal(takeNumber)} Take'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ),

            // Edit and Delete Entire Medication buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () =>
                      _editMedication(medication['id'], medication),
                  icon: Icon(Icons.edit, size: 16),
                  label: Text('Edit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () =>
                      _deleteMedication(medication['id'], medication),
                  icon: Icon(Icons.delete_forever, size: 16),
                  label: Text('Delete All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
          ],
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

      // Update the take status
      final updateData = <String, dynamic>{
        'status': newStatus,
        'updated_at': Timestamp.fromDate(DateTime.now()),
      };

      if (newStatus == 'complete') {
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
      if (newStatus == 'complete' && originalStatus != 'complete') {
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
      if (allStatuses.every((status) => status == 'completed')) {
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
    } catch (e) {
      print('Error updating take status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating status'),
          backgroundColor: Colors.red,
        ),
      );
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
                DateFormat('MMM dd, yyyy').format(_selectedDate),
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
        // Main Content
        Expanded(
          child: Stack(
            children: [
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                // Medications List
                _upcomingMedications.isEmpty
                    ? Center(
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
              if (!_isLoading)
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FutureBuilder<bool>(
                      future: _isNurseScheduledForToday(),
                      builder: (context, snapshot) {
                        final isScheduled = snapshot.data ?? false;

                        return FloatingActionButton.extended(
                          onPressed: isScheduled
                              ? () => _showAddMedicationDialog()
                              : () => _showNotScheduledDialog(),
                          label: Text(
                            'Add Medication',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          icon: Icon(Icons.add, color: Colors.white),
                          backgroundColor: isScheduled
                              ? Color(0xFF00588E)
                              : Colors.grey,
                        );
                      },
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
