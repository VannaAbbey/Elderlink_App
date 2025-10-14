import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import '../providers/auth_provider.dart';
import 'elderly_list.dart';
import 'medication_management.dart';
import 'vital_monitoring.dart';
import 'emergency.dart';
import 'nurse_bottom_navbar.dart';
import 'incident_report.dart';
import 'nurse_sidebar.dart';
import 'notification_service.dart';
import 'activity_logs.dart';
import '../main.dart';

class NurseHomeScreen extends StatefulWidget {
  const NurseHomeScreen({super.key});

  @override
  State<NurseHomeScreen> createState() => _NurseHomeScreenState();
}

class _NurseHomeScreenState extends State<NurseHomeScreen> {
  bool isSidebarOpen = false;
  int selectedIndex = 0;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _houses = [];
  bool _isLoadingHouses = true;

  final AudioPlayer _taskAudioPlayer = AudioPlayer();
  final Map<String, bool> _shownTaskDialogs =
      {}; // track which tasks have been shown

  List<Map<String, dynamic>> _currentTasks =
      []; // Store current tasks for See All

  bool _isNurseScheduled = false; // Track if nurse is currently scheduled
  String _nurseShiftInfo = ''; // Store shift information for dialog

  // Common task descriptions per category
  final Map<String, List<String>> _commonTaskDescriptions = {
    'Vitals': [
      'Check BP',
      'Check Temp',
      'Check Pulse',
      'Check Resp',
      'Check O2',
      'Other',
    ],
    'Medication': [
      'Administer Med',
      'Prep Doses',
      'Check Stock',
      'Update Records',
      'Other',
    ],
    'Assessment': [
      'Health Assess',
      'Mental Check',
      'Eval Mobility',
      'Check Distress',
      'Other',
    ],
    'Other': ['Other'],
    'Custom': ['Other'],
  };

  // Schedule notifications for existing medical tasks
  Future<void> _scheduleNotificationsForExistingTasks() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      debugPrint('Scheduling notifications for existing tasks');
      debugPrint('Today: $today, Tomorrow: $tomorrow, Now: $now');

      // Get all medical tasks for the next 7 days to cover all scheduled days
      final nextWeek = today.add(const Duration(days: 7));
      final query = await _firestore
          .collection('medical_tasks')
          .where(
            'task_start',
            isGreaterThanOrEqualTo: Timestamp.fromDate(today),
          )
          .where('task_start', isLessThan: Timestamp.fromDate(nextWeek))
          .get();

      debugPrint('Found ${query.docs.length} tasks for the next 7 days');

      for (final doc in query.docs) {
        final task = doc.data();
        final taskStart = (task['task_start'] as Timestamp).toDate();
        final elderlyId = task['elderly_id'] as String?;
        final medicationId = task['medication_id'] as String?;
        final takeIndex = task['take_index'] ?? 0;

        debugPrint('Processing task: ${task['task_title']}, start: $taskStart');

        // Only schedule notifications for future tasks
        if (!taskStart.isAfter(now)) {
          debugPrint('Skipping task ${task['task_title']} - in past');
          continue;
        }

        if (elderlyId != null && medicationId != null) {
          // Get elderly name
          final elderlyDoc = await _firestore
              .collection('elderly')
              .doc(elderlyId)
              .get();
          final elderlyName = elderlyDoc.exists
              ? '${elderlyDoc.data()?['elderly_fname'] ?? ''} ${elderlyDoc.data()?['elderly_lname'] ?? ''}'
                    .trim()
              : 'Unknown';

          // Get medication name
          final medDoc = await _firestore
              .collection('medications')
              .doc(medicationId)
              .get();
          final medName = medDoc.exists
              ? (medDoc.data()?['medication_name'] ?? 'Medication')
              : 'Medication';

          // Schedule 5-minute reminder notification
          final notifyTime = taskStart.subtract(Duration(minutes: 5));
          if (notifyTime.isAfter(now)) {
            debugPrint('Scheduling 5-min reminder for $medName at $notifyTime');
            final notificationId = ('${medicationId}_$takeIndex').hashCode;
            NotificationService.cancelNotification(notificationId);
            NotificationService.scheduleTaskNotification(
              id: notificationId,
              title: 'Medication Reminder',
              body: '$medName for $elderlyName in 5 minutes',
              dateTime: notifyTime,
            );
          }

          // Schedule exact time notification
          debugPrint(
            'Scheduling exact time notification for $medName at $taskStart',
          );
          final exactNotificationId =
              ('${medicationId}_$takeIndex'
                      '_exact')
                  .hashCode;
          NotificationService.cancelNotification(exactNotificationId);
          NotificationService.scheduleTaskNotification(
            id: exactNotificationId,
            title: 'Medication Time - $medName',
            body: 'Time to administer $medName to $elderlyName',
            dateTime: taskStart,
          );
        }
      }
    } catch (e) {
      debugPrint('Error scheduling notifications for existing tasks: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadHouses();
    NotificationService.init(
      onNotificationTap: _handleNotificationTap,
    ); // initialize notification service with tap handler
    _scheduleNotificationsForExistingTasks(); // schedule notifications for existing tasks
    // After first frame we can access context safely and generate medication tasks
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateMedicationTasksForToday();
      _checkNurseScheduleAndShift(); // Check if nurse is scheduled
    });
  }

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

  String _getCurrentDay() {
    final now = DateTime.now();
    final currentHour = now.hour;
    if (currentHour >= 0 && currentHour < 6) {
      final previousDay = now.subtract(Duration(days: 1));
      return DateFormat('EEEE').format(previousDay);
    }
    return DateFormat('EEEE').format(now);
  }

  Future<List<String>> _getNurseScheduledDays() async {
    try {
      final nurseId = await _getNurseIdFromAuth();
      if (nurseId == null) return [_getCurrentDay()];
      final query = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .get();
      debugPrint('Query docs for nurse $nurseId: ${query.docs.length}');
      final days = <String>{};
      for (final doc in query.docs) {
        final daysAssigned = doc.data()['days_assigned'];
        debugPrint(
          'Doc ${doc.id}: daysAssigned = $daysAssigned, type = ${daysAssigned.runtimeType}',
        );
        if (daysAssigned is List) {
          days.addAll(List<String>.from(daysAssigned));
        }
      }
      debugPrint('Scheduled days for nurse $nurseId: $days');
      return days.isEmpty ? [_getCurrentDay()] : days.toList();
    } catch (e) {
      debugPrint('Error getting scheduled days: $e');
      return [_getCurrentDay()];
    }
  }

  DateTime _getNextScheduledDate(List<String> days) {
    final now = DateTime.now();
    for (int i = 1; i <= 7; i++) {
      final date = now.add(Duration(days: i));
      final dayName = DateFormat('EEEE').format(date);
      if (days.contains(dayName)) {
        return DateTime(date.year, date.month, date.day, now.hour, now.minute);
      }
    }
    // If no next within a week, default to tomorrow
    final tomorrow = now.add(const Duration(days: 1));
    return DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      now.hour,
      now.minute,
    );
  }

  Future<String?> _getNurseIdFromAuth() async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final first = auth.userFirstName;
      final last = auth.userLastName;
      if (first.isEmpty || last.isEmpty) return null;

      final q = await _firestore
          .collection('users')
          .where('user_fname', isEqualTo: first)
          .where('user_lname', isEqualTo: last)
          .where('user_type', isEqualTo: 'nurse')
          .get();
      if (q.docs.isEmpty) return null;
      final nurseId = q.docs.first.id;
      debugPrint('Nurse id: $nurseId');
      return nurseId;
    } catch (e) {
      debugPrint('Error getting nurse id: $e');
      return null;
    }
  }

  Future<List<String>> _getNurseWorkingDays(String nurseId) async {
    try {
      final currentShift = _getCurrentShift();

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

  Future<void> _checkNurseScheduleAndShift() async {
    try {
      final nurseId = await _getNurseIdFromAuth();
      if (nurseId == null) {
        setState(() {
          _isNurseScheduled = false;
          _nurseShiftInfo = '';
        });
        return;
      }

      final currentShift = _getCurrentShift();
      final currentDay = _getCurrentDay();

      // Get nurse's shift assignment
      final shiftQuery = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .get();

      String assignedShift = '';
      List<String> assignedDays = [];
      if (shiftQuery.docs.isNotEmpty) {
        final data = shiftQuery.docs.first.data();
        assignedShift = data['shift'] ?? '';
        assignedDays = List<String>.from(data['days_assigned'] ?? []);
      }

      final isScheduled =
          assignedShift == currentShift && assignedDays.contains(currentDay);

      // Get shift time information based on assigned shift
      String shiftInfo = '';
      if (assignedShift == "1st") {
        shiftInfo = "1st shift (6:00 AM to 2:00 PM)";
      } else if (assignedShift == "2nd") {
        shiftInfo = "2nd shift (2:00 PM to 10:00 PM)";
      } else if (assignedShift == "3rd") {
        shiftInfo = "3rd shift (10:00 PM to 6:00 AM)";
      } else {
        // Fallback to current shift if no assignment
        if (currentShift == "1st") {
          shiftInfo = "1st shift (6:00 AM to 2:00 PM)";
        } else if (currentShift == "2nd") {
          shiftInfo = "2nd shift (2:00 PM to 10:00 PM)";
        } else {
          shiftInfo = "3rd shift (10:00 PM to 6:00 AM)";
        }
      }

      if (mounted) {
        setState(() {
          _isNurseScheduled = isScheduled;
          _nurseShiftInfo = shiftInfo;
        });
      }
    } catch (e) {
      debugPrint('Error checking nurse schedule: $e');
      if (mounted) {
        setState(() {
          _isNurseScheduled = false;
          _nurseShiftInfo = '';
        });
      }
    }
  }

  // Generate medical_tasks entries for medication schedule for this nurse
  Future<void> _generateMedicationTasksForToday() async {
    try {
      final nurseId = await _getNurseIdFromAuth();
      if (nurseId == null) return;

      final currentShift = _getCurrentShift();
      final currentDay = _getCurrentDay();

      // Get nurse's working days for this shift
      final nurseWorkingDays = await _getNurseWorkingDays(nurseId);

      // Get elderly_assignments for this nurse for current shift/day
      final assignQuery = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .where('day', isEqualTo: currentDay)
          .get();
      if (assignQuery.docs.isEmpty) return;

      // Collect all elderly IDs across assignments
      final Set<String> elderlyIds = {};
      for (final doc in assignQuery.docs) {
        final data = doc.data();
        final ids = List<String>.from(data['elderly_ids'] ?? []);
        elderlyIds.addAll(ids);
      }
      if (elderlyIds.isEmpty) return;

      // Fetch elderly names in chunks
      final Map<String, String> elderlyNames = {};
      final elderlyList = elderlyIds.toList();
      for (var i = 0; i < elderlyList.length; i += 30) {
        final end = (i + 30 < elderlyList.length) ? i + 30 : elderlyList.length;
        final chunk = elderlyList.sublist(i, end);
        final q = await _firestore
            .collection('elderly')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final ed in q.docs) {
          final edata = ed.data();
          final name =
              '${edata['elderly_fname'] ?? ''} ${edata['elderly_lname'] ?? ''}'
                  .trim();
          elderlyNames[ed.id] = name.isNotEmpty ? name : 'Unknown';
        }
      }

      // Query medications for these elderly in chunks and create tasks for pending takes
      final now = DateTime.now();
      for (var i = 0; i < elderlyList.length; i += 30) {
        final end = (i + 30 < elderlyList.length) ? i + 30 : elderlyList.length;
        final chunk = elderlyList.sublist(i, end);

        final medsQuery = await _firestore
            .collection('medications')
            .where('elderly_id', whereIn: chunk)
            .where('status', isEqualTo: 'upcoming')
            .where('shift', isEqualTo: currentShift)
            .get();

        for (final mdoc in medsQuery.docs) {
          final mdata = mdoc.data();
          final medicationId = mdoc.id;
          final medName = mdata['medication_name'] ?? 'Medication';
          final dosage = mdata['dosage'] ?? '';
          final elderlyId = mdata['elderly_id'] as String?;
          final repeatInterval = mdata['repeat_interval'] ?? 'Once';
          if (elderlyId == null) continue;
          final elderlyName = elderlyNames[elderlyId] ?? 'Unknown';

          final intakeTimes = List<String>.from(mdata['intake_times'] ?? []);
          final takeStatuses = List<Map<String, dynamic>>.from(
            mdata['take_statuses'] ?? [],
          );

          // Determine which days to create tasks for
          List<String> taskDays;
          if (repeatInterval == 'Daily') {
            // For daily medications, create tasks for all nurse's working days
            taskDays = nurseWorkingDays;
          } else {
            // For once medications, only create for current day
            taskDays = [currentDay];
          }

          for (final taskDay in taskDays) {
            // Find the next occurrence of this day
            DateTime nextTaskDate = now;
            for (int i = 0; i < 7; i++) {
              final checkDate = now.add(Duration(days: i));
              final checkDayName = DateFormat('EEEE').format(checkDate);
              if (checkDayName == taskDay) {
                nextTaskDate = checkDate;
                break;
              }
            }

            for (int t = 0; t < intakeTimes.length; t++) {
              final scheduled = intakeTimes[t];
              // scheduled expected as 'HH:mm'
              final parts = scheduled.split(':');
              if (parts.length != 2) continue;
              final hour = int.tryParse(parts[0]) ?? 0;
              final minute = int.tryParse(parts[1]) ?? 0;

              // build DateTime for the scheduled time on the task day
              final taskStart = DateTime(
                nextTaskDate.year,
                nextTaskDate.month,
                nextTaskDate.day,
                hour,
                minute,
              );

              // skip past takes
              if (taskStart.isBefore(now)) continue;

              // only create task if status is pending
              final status =
                  (t < takeStatuses.length && takeStatuses[t]['status'] != null)
                  ? takeStatuses[t]['status'] as String
                  : 'pending';
              if (status != 'pending') continue;

              // avoid duplicates: check for existing medical_tasks with same medication_id and take index and same start
              final existing = await _firestore
                  .collection('medical_tasks')
                  .where('task_source', isEqualTo: 'medication')
                  .where('medication_id', isEqualTo: medicationId)
                  .where('take_index', isEqualTo: t)
                  .where('task_start', isEqualTo: Timestamp.fromDate(taskStart))
                  .get();
              if (existing.docs.isNotEmpty) continue;

              // create task
              final taskTitle =
                  '$medName ${dosage.isNotEmpty ? '- $dosage' : ''} for $elderlyName';
              final taskDesc =
                  'Medication scheduled for $elderlyName at $scheduled';

              await _firestore.collection('medical_tasks').add({
                'task_title': taskTitle,
                'task_description': taskDesc,
                'task_category': 'Medication',
                'task_start': taskStart,
                'task_frequency': repeatInterval == 'Daily'
                    ? 'Every Assigned Days'
                    : 'Once',
                'task_status': 'Pending',
                'days': taskDays,
                // metadata to avoid duplicates and allow tracing
                'task_source': 'medication',
                'medication_id': medicationId,
                'take_index': t,
                'elderly_id': elderlyId,
                'created_at': FieldValue.serverTimestamp(),
              });

              // schedule notification 5 minutes before (only if in future)
              final notifyTime = taskStart.subtract(Duration(minutes: 5));
              if (notifyTime.isAfter(DateTime.now())) {
                final notificationId =
                    ('${medicationId}_${taskDay}_$t').hashCode;
                NotificationService.cancelNotification(notificationId);
                NotificationService.scheduleTaskNotification(
                  id: notificationId,
                  title: 'Medication Reminder',
                  body: '$medName for $elderlyName in 5 minutes',
                  dateTime: notifyTime,
                );
              }

              // schedule notification at exact medication time (only if in future)
              if (taskStart.isAfter(DateTime.now())) {
                final exactNotificationId =
                    ('${medicationId}_${taskDay}_$t'
                            '_exact')
                        .hashCode;
                NotificationService.cancelNotification(exactNotificationId);
                NotificationService.scheduleTaskNotification(
                  id: exactNotificationId,
                  title: 'Medication Time - $medName',
                  body: 'Time to administer $medName to $elderlyName',
                  dateTime: taskStart,
                );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error generating medication tasks: $e');
    }
  }

  Future<Map<String, dynamic>?> getCaregiverStatus() async {
    try {
      final nurseId = await _getNurseIdFromAuth();
      if (nurseId == null) return null;

      final currentShift = _getCurrentShift();

      final shiftQuery = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .get();

      if (shiftQuery.docs.isNotEmpty) {
        final data = shiftQuery.docs.first.data();
        return data;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting caregiver status: $e');
      return null;
    }
  }

  String _convertTo12HourFormat(String time24) {
    try {
      final parts = time24.split(':');
      if (parts.length != 2) return time24;

      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;

      final period = hour >= 12 ? 'PM' : 'AM';
      final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);

      return '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return time24;
    }
  }

  Future<void> _loadHouses() async {
    try {
      QuerySnapshot snapshot = await _firestore.collection('house').get();
      setState(() {
        _houses = snapshot.docs
            .map((doc) => doc.data() as Map<String, dynamic>)
            .toList();
        _houses.sort((a, b) {
          String idA = a['house_id'] ?? '';
          String idB = b['house_id'] ?? '';
          return idA.compareTo(idB);
        });
        _isLoadingHouses = false;
      });
    } catch (e) {
      debugPrint("Error fetching houses: $e");
      setState(() => _isLoadingHouses = false);
    }
  }

  void toggleSidebar() {
    if (EmergencyService.isModalOpen) return;
    setState(() {
      isSidebarOpen = !isSidebarOpen;
    });
  }

  final List<Widget> _screens = [
    const Center(child: Text("Nurse Dashboard")),
    const IncidentReportScreen(),
    EmergencyScreen(),
    MedicationManagementScreen(),
    VitalMonitoringScreen(),
  ];

  void onNavTap(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (isSidebarOpen) setState(() => isSidebarOpen = false);
      },
      child: Scaffold(
        body: selectedIndex == 0
            ? Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/background1.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ListView(
                        children: [
                          _headerSection(),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Color(0x3EB7DDF5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: const [
                                Text(
                                  'Welcome to ElderLink!',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF00588E),
                                  ),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  'Manage your tasks, view your schedule, and stay connected with your elderly residents.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _medicalTasksSection(),
                          const SizedBox(height: 30),
                          _housesSection(),
                          const SizedBox(height: 30),

                          // Your Status Section
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Color(0x3EB7DDF5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(
                                      Icons.accessibility,
                                      color: Color(0xFF00588E),
                                      size: 45,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      "Your Status",
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 15),

                                FutureBuilder<Map<String, dynamic>?>(
                                  future: getCaregiverStatus(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    }

                                    final statusData = snapshot.data;
                                    final daysAssigned =
                                        statusData?['days_assigned']
                                            as List<dynamic>? ??
                                        [];

                                    // Handle shift field - could be String or Map
                                    final shiftData = statusData?['shift'];
                                    final shift = shiftData is String
                                        ? shiftData
                                        : shiftData is Map<String, dynamic>
                                        ? (shiftData['name'] ??
                                              shiftData['shift_name'] ??
                                              'Not assigned')
                                        : 'Not assigned';

                                    // Handle start_time and end_time fields (NEW structure)
                                    final startTime =
                                        statusData?['start_time'] as String? ??
                                        '';
                                    final endTime =
                                        statusData?['end_time'] as String? ??
                                        '';

                                    final timeRange =
                                        (startTime.isNotEmpty &&
                                            endTime.isNotEmpty)
                                        ? '${_convertTo12HourFormat(startTime)} - ${_convertTo12HourFormat(endTime)}'
                                        : 'Not specified';

                                    return Column(
                                      children: [
                                        // Current Work Schedule
                                        Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Color(0xFFB7DDF5),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Current Work Schedule',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF00588E),
                                                ),
                                              ),
                                              const SizedBox(height: 15),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceEvenly,
                                                children: [
                                                  for (int i = 0; i < 7; i++)
                                                    Column(
                                                      children: [
                                                        Container(
                                                          width: 32,
                                                          height: 32,
                                                          decoration: BoxDecoration(
                                                            shape:
                                                                BoxShape.circle,
                                                            color:
                                                                daysAssigned.contains(
                                                                  [
                                                                    'Sunday',
                                                                    'Monday',
                                                                    'Tuesday',
                                                                    'Wednesday',
                                                                    'Thursday',
                                                                    'Friday',
                                                                    'Saturday',
                                                                  ][i],
                                                                )
                                                                ? Color(
                                                                    0xFF00588E,
                                                                  )
                                                                : Colors
                                                                      .grey
                                                                      .shade300,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          [
                                                            'Sun',
                                                            'Mon',
                                                            'Tue',
                                                            'Wed',
                                                            'Thu',
                                                            'Fri',
                                                            'Sat',
                                                          ][i],
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color: Color(
                                                              0xFF00588E,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        const SizedBox(height: 15),

                                        // Current Shift Schedule
                                        Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Color(0xFFB7DDF5),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.access_time,
                                                color: Color(0xFF00588E),
                                                size: 70,
                                              ),
                                              const SizedBox(width: 20),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    const Text(
                                                      'Current Shift Schedule',
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Color(
                                                          0xFF00588E,
                                                        ),
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      '${shift.toUpperCase()} SHIFT',
                                                      style: TextStyle(
                                                        fontSize: 24,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Color(
                                                          0xFF00588E,
                                                        ),
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      timeRange,
                                                      style: TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Color(
                                                          0xFF00588E,
                                                        ),
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        const SizedBox(height: 15),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isSidebarOpen && !EmergencyService.isModalOpen)
                    NurseSidebar(
                      isSidebarOpen: isSidebarOpen,
                      toggleSidebar: toggleSidebar,
                      parentContext: context,
                    ),
                ],
              )
            : _screens[selectedIndex],
        bottomNavigationBar: EmergencyService.isModalOpen
            ? null
            : NurseBottomNavBar(
                selectedIndex: selectedIndex,
                onNavTap: onNavTap,
              ),
      ),
    );
  }

  Widget _headerSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: EmergencyService.isModalOpen ? null : toggleSidebar,
              child: Consumer<AuthProvider>(
                builder: (context, authProvider, child) {
                  final profilePic = authProvider.userData?['user_profilePic'];
                  return CircleAvatar(
                    radius: 24,
                    backgroundImage:
                        (profilePic != null && profilePic.isNotEmpty)
                        ? NetworkImage(profilePic)
                        : const AssetImage('assets/images/people_icon.png')
                              as ImageProvider,
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Consumer<AuthProvider>(
                  builder: (context, authProvider, child) {
                    final firstName = authProvider.userFirstName;
                    final displayName =
                        (firstName.isEmpty || firstName == 'User')
                        ? ''
                        : firstName;
                    return Text(
                      displayName.isEmpty
                          ? 'Hello Nurse,'
                          : 'Hello Nurse $displayName,',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    );
                  },
                ),
                const Text('Hope you are doing well'),
              ],
            ),
          ],
        ),
        GestureDetector(
          onTap: EmergencyService.isModalOpen
              ? null
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ActivityLogsScreen(
                        houseId: 'H001', // Default house
                        nurseName:
                            '${Provider.of<AuthProvider>(context, listen: false).userFirstName} ${Provider.of<AuthProvider>(context, listen: false).userLastName}',
                      ),
                    ),
                  );
                },
          child: const Icon(
            Icons.notifications,
            color: Color(0XFF1D66A0),
            size: 35,
          ),
        ),
      ],
    );
  }

  // ---------------------- MEDICAL TASKS SECTION ----------------------
  Widget _medicalTasksSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(183, 221, 245, 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.medical_services,
                    color: Color(0xFF1D66A0),
                    size: 45,
                  ),
                  SizedBox(width: 6),
                  Text(
                    "Medical Tasks",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1D66A0),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () => _showAllTasksDialog(_currentTasks),
                child: const Text(
                  'See All',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const SizedBox(height: 10),
          // Tasks list
          Padding(
            padding: const EdgeInsets.all(8),
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('medical_tasks')
                  .orderBy('task_start')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final List<Map<String, dynamic>> tasks =
                    snapshot.hasData && snapshot.data!.docs.isNotEmpty
                    ? snapshot.data!.docs.map((doc) {
                        final task = doc.data() as Map<String, dynamic>;
                        task['task_id'] = doc.id; // assign doc ID
                        return task;
                      }).toList()
                    : [];

                // Store current tasks for See All functionality
                _currentTasks = tasks;

                // Filter tasks for today and tomorrow (only future tasks)
                final filteredTasks = tasks.where((task) {
                  final start = task['task_start'] != null
                      ? (task['task_start'] as Timestamp).toDate()
                      : DateTime.now();
                  final taskDaysRaw = task['days'];
                  final taskDays = taskDaysRaw is List
                      ? List<String>.from(taskDaysRaw)
                      : [];
                  final frequency = task['task_frequency'] ?? 'Once';
                  final now = DateTime.now();
                  final todayStart = DateTime(now.year, now.month, now.day);
                  final tomorrowStart = todayStart.add(const Duration(days: 1));
                  final dayAfterTomorrowStart = tomorrowStart.add(
                    const Duration(days: 1),
                  );
                  if (frequency == 'Every Assigned Days') {
                    // Find the next scheduled day
                    DateTime nextScheduledDate = now;
                    for (int i = 0; i < 7; i++) {
                      final date = now.add(Duration(days: i));
                      final dayName = DateFormat('EEEE').format(date);
                      if (taskDays.contains(dayName)) {
                        nextScheduledDate = date;
                        break;
                      }
                    }
                    // Show if the next scheduled day is today or tomorrow
                    final nextDateStart = DateTime(
                      nextScheduledDate.year,
                      nextScheduledDate.month,
                      nextScheduledDate.day,
                    );
                    return nextDateStart == todayStart ||
                        nextDateStart == tomorrowStart;
                  } else {
                    // For 'Once', only show if the task start is in the future and within tomorrow
                    return start.isAfter(now) &&
                        start.isBefore(dayAfterTomorrowStart);
                  }
                }).toList();

                debugPrint(
                  'Total tasks: ${tasks.length}, Filtered tasks: ${filteredTasks.length}',
                );

                return Column(
                  children: [
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (filteredTasks.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child: Text(
                            "No medical task available.",
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        itemCount: filteredTasks.length,
                        itemBuilder: (context, index) {
                          final task = filteredTasks[index];
                          final title = task['task_title'] ?? '';
                          final description = task['task_description'] ?? '';
                          final start = task['task_start'] != null
                              ? (task['task_start'] as Timestamp).toDate()
                              : DateTime.now();
                          final formattedTime = TimeOfDay.fromDateTime(
                            start,
                          ).format(context);

                          // Schedule notification and dialog if not already shown
                          final taskId = task['task_id'];
                          final frequency = task['task_frequency'] ?? 'Once';
                          if (frequency == 'Every Assigned Days') {
                            final now = DateTime.now();
                            final taskTime = TimeOfDay.fromDateTime(start);
                            final todayAtTime = DateTime(
                              now.year,
                              now.month,
                              now.day,
                              taskTime.hour,
                              taskTime.minute,
                            );
                            if (todayAtTime.isAfter(now) &&
                                !_shownTaskDialogs.containsKey(taskId)) {
                              _shownTaskDialogs[taskId] = true;

                              final notificationId = taskId.hashCode;
                              NotificationService.cancelNotification(
                                notificationId,
                              );
                              NotificationService.scheduleTaskNotification(
                                id: notificationId,
                                title: title,
                                body: description,
                                dateTime: todayAtTime,
                              );

                              Future.delayed(
                                todayAtTime.difference(now),
                                () async {
                                  if (mounted) {
                                    await _showTaskDialog(
                                      taskId,
                                      title,
                                      description,
                                      formattedTime,
                                    );
                                  }
                                },
                              );
                            }
                          } else if (!_shownTaskDialogs.containsKey(taskId) &&
                              start.isAfter(DateTime.now())) {
                            _shownTaskDialogs[taskId] = true;

                            final notificationId = taskId.hashCode;
                            NotificationService.cancelNotification(
                              notificationId,
                            );
                            NotificationService.scheduleTaskNotification(
                              id: notificationId,
                              title: title,
                              body: description,
                              dateTime: start,
                            );

                            Future.delayed(
                              start.difference(DateTime.now()),
                              () async {
                                if (mounted) {
                                  await _showTaskDialog(
                                    taskId,
                                    title,
                                    description,
                                    formattedTime,
                                  );
                                }
                              },
                            );
                          }

                          // All medical tasks use the same blue color
                          Color bgColor = const Color.fromARGB(
                            255,
                            153,
                            209,
                            255,
                          );

                          // Check if task is for tomorrow
                          String displayTime = formattedTime;
                          String? tomorrowMark;
                          final now = DateTime.now();
                          final tomorrow = now.add(const Duration(days: 1));
                          if (frequency != 'Every Assigned Days' &&
                              start.year == tomorrow.year &&
                              start.month == tomorrow.month &&
                              start.day == tomorrow.day) {
                            tomorrowMark = 'Tomorrow Task';
                          }

                          return _medicalTaskCard(
                            title,
                            description,
                            displayTime,
                            bgColor,
                            taskId: taskId,
                            tomorrowMark: tomorrowMark,
                          );
                        },
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isNurseScheduled
                                ? _showAddTaskDialog
                                : _showNotScheduledDialog,
                            icon: const Icon(Icons.add),
                            label: const Text(
                              "Add Task",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isNurseScheduled
                                  ? const Color(0xFF22688E)
                                  : Colors.grey.shade400,
                              foregroundColor: _isNurseScheduled
                                  ? Colors.white
                                  : const Color.fromARGB(255, 250, 249, 249),
                              elevation: _isNurseScheduled ? null : 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------- SHOW NOT SCHEDULED WARNING DIALOG ----------------------
  void _showNotScheduledDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48),
              SizedBox(height: 8),
              Text(
                'Not Scheduled Today',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00588E),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'You are not scheduled to work today. You cannot add tasks when you are not on duty.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color(0xFF00588E).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Color(0xFF00588E).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time, color: Color(0xFF00588E), size: 20),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Your shift: $_nurseShiftInfo',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF00588E),
                        ),
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF00588E),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text(
                  'OK',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------- SHOW ADD TASK DIALOG ----------------------
  void _showAddTaskDialog() {
    TimeOfDay taskTime = TimeOfDay.now();
    String taskTitle = '';
    String taskDescription = '';
    String taskCategory = 'Vitals';
    String taskFrequency = 'Once';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              titlePadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
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
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        SizedBox(width: 10),
                        Text(
                          "Add Task",
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

                    // Task Title (combo box with editable custom option)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        const SizedBox(width: 8),
                        Text(
                          'Task Title',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF216386),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.9,
                      height: 50,
                      child: DropdownButtonFormField<String>(
                        value: taskTitle.isEmpty ? null : taskTitle,
                        decoration: InputDecoration(
                          hintText: 'Select a task title',
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
                        items: _commonTaskDescriptions.keys
                            .map(
                              (title) => DropdownMenuItem(
                                value: title,
                                child: Text(title),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            taskTitle = value ?? '';
                            taskCategory = value ?? 'Vitals';
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    // If custom selected, allow typing an exact title
                    if (taskTitle == 'Custom')
                      TextField(
                        decoration: InputDecoration(
                          labelText: 'Custom Task Title',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: const Color(0xFF00588E),
                              width: 1.5,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: const Color(0xFF00588E),
                              width: 1.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: const Color(0xFF00588E),
                              width: 2,
                            ),
                          ),
                        ),
                        onChanged: (value) => taskTitle = value,
                      ),
                    const SizedBox(height: 12),

                    // Task Description (predefined choices per type, with custom fallback)
                    Builder(
                      builder: (context) {
                        final options =
                            _commonTaskDescriptions[taskTitle] ?? ['Other'];
                        final initial =
                            options.contains(taskDescription) &&
                                taskDescription.isNotEmpty
                            ? taskDescription
                            : null;

                        return Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.edit,
                                  color: Color(0xFF216386),
                                  size: 25,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Task Description',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Color(0xFF216386),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: MediaQuery.of(context).size.width * 0.9,
                              height: 50,
                              child: DropdownButtonFormField<String>(
                                value: initial,
                                decoration: InputDecoration(
                                  hintText: 'Select a description',
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
                                menuMaxHeight: 600,
                                items: options
                                    .map(
                                      (o) => DropdownMenuItem(
                                        value: o,
                                        child: Container(
                                          height: 50,
                                          alignment: Alignment.centerLeft,
                                          child: Text(o, softWrap: true),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => taskDescription = value);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (taskDescription == 'Other')
                              TextField(
                                decoration: InputDecoration(
                                  labelText: 'Custom Description',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: const Color(0xFF00588E),
                                      width: 1.5,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: const Color(0xFF00588E),
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: const Color(0xFF00588E),
                                      width: 2,
                                    ),
                                  ),
                                ),
                                onChanged: (value) => taskDescription = value,
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 5),

                    // Note: removed separate Category field; category will be derived from Task Title

                    // Repeat Interval
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Icon(Icons.repeat, color: Color(0xFF216386), size: 25),
                        const SizedBox(width: 8),
                        Text(
                          'Repeat Interval',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF216386),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.9,
                      height: 50,
                      child: DropdownButtonFormField<String>(
                        value: taskFrequency,
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
                        items: const [
                          DropdownMenuItem(value: 'Once', child: Text('Once')),
                          DropdownMenuItem(
                            value: 'Every Assigned Days',
                            child: Text('Every Assigned Days'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => taskFrequency = value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Task Time
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.access_time,
                          color: Color(0xFF216386),
                          size: 25,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Time',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF216386),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      readOnly: true,
                      controller: TextEditingController(
                        text: taskTime.format(context),
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Color.fromARGB(255, 222, 241, 246),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(
                            color: const Color(0xFF00588E),
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
                          borderSide: BorderSide(color: Colors.white, width: 2),
                        ),
                        suffixIcon: Icon(
                          Icons.access_time,
                          color: Color(0xFF00588E),
                        ),
                      ),
                      onTap: () async {
                        TimeOfDay? picked = await showTimePicker(
                          context: context,
                          initialTime: taskTime,
                        );
                        if (picked != null) setState(() => taskTime = picked);
                      },
                    ),
                    const SizedBox(height: 12),

                    const SizedBox(height: 20),

                    // Buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Submit
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00588E),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              // Construct task start DateTime from selected time
                              final now = DateTime.now();
                              DateTime taskStart = DateTime(
                                now.year,
                                now.month,
                                now.day,
                                taskTime.hour,
                                taskTime.minute,
                              );

                              // If the selected time is in the past, schedule for tomorrow
                              if (taskStart.isBefore(now)) {
                                taskStart = taskStart.add(
                                  const Duration(days: 1),
                                );
                              }

                              // Determine days based on frequency
                              List<String> days;
                              if (taskFrequency == 'Once') {
                                final taskDay = DateFormat(
                                  'EEEE',
                                ).format(taskStart);
                                days = [taskDay];
                              } else {
                                days = await _getNurseScheduledDays();
                                // For 'Every Assigned Days', set taskStart to the next scheduled day
                                DateTime nextScheduledDate = now;
                                for (int i = 0; i < 7; i++) {
                                  final date = now.add(Duration(days: i));
                                  final dayName = DateFormat(
                                    'EEEE',
                                  ).format(date);
                                  if (days.contains(dayName)) {
                                    nextScheduledDate = date;
                                    break;
                                  }
                                }
                                taskStart = DateTime(
                                  nextScheduledDate.year,
                                  nextScheduledDate.month,
                                  nextScheduledDate.day,
                                  taskTime.hour,
                                  taskTime.minute,
                                );
                              }
                              debugPrint('Final days for task: $days');

                              // Save task to Firestore
                              final docRef = await FirebaseFirestore.instance
                                  .collection('medical_tasks')
                                  .add({
                                    'task_title': taskTitle,
                                    'task_description': taskDescription,
                                    'task_category': taskCategory,
                                    'task_start': taskStart,
                                    'task_frequency': taskFrequency,
                                    'task_status': 'Pending',
                                    'days': days,
                                  });
                              debugPrint(
                                'Task added with id: ${docRef.id}, start: $taskStart, days: $days',
                              );

                              // Only schedule notification if task is for today and at least 2 minutes in the future
                              final today = DateTime(
                                now.year,
                                now.month,
                                now.day,
                              );
                              final taskDate = DateTime(
                                taskStart.year,
                                taskStart.month,
                                taskStart.day,
                              );

                              // Only schedule notifications for future tasks
                              final futureThreshold = now;

                              if (taskDate.isAtSameMomentAs(today) &&
                                  taskStart.isAfter(futureThreshold)) {
                                // Schedule notification for the task time
                                final notificationId = docRef.id.hashCode;
                                NotificationService.cancelNotification(
                                  notificationId,
                                );
                                NotificationService.scheduleTaskNotification(
                                  id: notificationId,
                                  title: taskTitle,
                                  body: taskDescription,
                                  dateTime: taskStart,
                                );

                                // Show success notification for today's future task
                                await NotificationService.showMedicalTaskNotification(
                                  taskId: docRef.id,
                                  title: 'Task Created Successfully',
                                  description:
                                      'You successfully created the task at ${taskTime.format(context)}',
                                  time: taskTime.format(context),
                                );
                              } else {
                                // Task is either for tomorrow or in the past - show appropriate success message
                                String notificationTitle =
                                    'Task Created Successfully';
                                String notificationBody;

                                if (taskDate.isAfter(today)) {
                                  // Task scheduled for tomorrow or future
                                  notificationBody =
                                      'You successfully created the task for tomorrow at ${taskTime.format(context)}';
                                } else {
                                  // Task time was in the past
                                  notificationBody =
                                      'You successfully created the task for tomorrow';
                                }

                                await NotificationService.showMedicalTaskNotification(
                                  taskId: docRef.id,
                                  title: notificationTitle,
                                  description: notificationBody,
                                  time: taskTime.format(context),
                                );
                              }

                              Navigator.of(context).pop();
                            },
                            child: Text(
                              'Submit',
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
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------- SHOW ALL TASKS DIALOG ----------------------
  void _showAllTasksDialog(List<Map<String, dynamic>> allTasks) {
    DateTime selectedDate = DateTime.now();
    bool dateSelected = true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Filter tasks by selected date if date is selected
            final filteredTasks = dateSelected
                ? allTasks.where((task) {
                    final start = task['task_start'] != null
                        ? (task['task_start'] as Timestamp).toDate()
                        : DateTime.now();
                    final taskDaysRaw = task['days'];
                    final taskDays = taskDaysRaw is List
                        ? List<String>.from(taskDaysRaw)
                        : [];
                    final frequency = task['task_frequency'] ?? 'Once';
                    if (frequency == 'Every Assigned Days') {
                      final selectedDayName = DateFormat(
                        'EEEE',
                      ).format(selectedDate);
                      return taskDays.contains(selectedDayName);
                    } else {
                      return start.year == selectedDate.year &&
                          start.month == selectedDate.month &&
                          start.day == selectedDate.day;
                    }
                  }).toList()
                : allTasks;

            return AlertDialog(
              backgroundColor: Colors.white,
              titlePadding: const EdgeInsets.fromLTRB(8, 8, 24, 20),
              contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      IconButton(
                        iconSize: 28,
                        icon: const Icon(Icons.close, color: Color(0xFF00588E)),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const Text(
                    'All Tasks',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00588E),
                      fontSize: 26,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    // Date label and picker
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Date: ${DateFormat('MMM. dd, yyyy').format(selectedDate)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color.fromARGB(255, 0, 0, 0),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.calendar_today,
                            color: Color(0xFF00588E),
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 30),
                              ),
                              lastDate: DateTime.now().add(
                                const Duration(days: 30),
                              ),
                            );
                            if (picked != null) {
                              setState(() {
                                selectedDate = picked;
                                dateSelected = true;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filteredTasks.isEmpty
                          ? const Center(
                              child: Text(
                                'No tasks for this day.',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredTasks.length,
                              itemBuilder: (context, index) {
                                final task = filteredTasks[index];
                                final title = task['task_title'] ?? '';
                                final description =
                                    task['task_description'] ?? '';
                                final start = task['task_start'] != null
                                    ? (task['task_start'] as Timestamp).toDate()
                                    : DateTime.now();
                                final formattedTime = TimeOfDay.fromDateTime(
                                  start,
                                ).format(context);

                                // Color based on category
                                final category =
                                    task['task_category'] ?? 'Other';
                                Color bgColor;
                                switch (category) {
                                  case 'Vitals':
                                    bgColor = Colors.orange[200]!;
                                    break;
                                  case 'Medication':
                                    bgColor = Colors.yellow[200]!;
                                    break;
                                  case 'Assessment':
                                    bgColor = Colors.blue[200]!;
                                    break;
                                  default:
                                    bgColor = Colors.grey[200]!;
                                }

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: bgColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ListTile(
                                    title: Text(
                                      title,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '$description\nTime: $formattedTime',
                                    ),
                                    onTap: () {
                                      // Show task dialog
                                      Navigator.of(context).pop();
                                      _showTaskDialog(
                                        task['task_id'],
                                        title,
                                        description,
                                        formattedTime,
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------- TASK DIALOG ----------------------
  Future<void> _showTaskDialog(
    String taskId,
    String title,
    String description,
    String time,
  ) async {
    try {
      await _taskAudioPlayer.setReleaseMode(ReleaseMode.loop);
      await _taskAudioPlayer.play(AssetSource('sounds/alarm.mp3'));

      if (!mounted) return;

      // Fetch task data to get frequency
      final taskDoc = await _firestore
          .collection('medical_tasks')
          .doc(taskId)
          .get();
      if (!taskDoc.exists) return;
      final taskData = taskDoc.data() as Map<String, dynamic>;
      final frequency = taskData['task_frequency'] ?? 'Once';
      final taskDays = List<String>.from(taskData['days'] ?? []);

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
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
                onPressed: () async {
                  await _taskAudioPlayer.stop();
                  Navigator.of(context).pop();
                  if (frequency == 'Once') {
                    await _firestore
                        .collection('medical_tasks')
                        .doc(taskId)
                        .delete();
                  } else if (frequency == 'Every Assigned Days') {
                    final nextDate = _getNextScheduledDate(taskDays);
                    await _firestore
                        .collection('medical_tasks')
                        .doc(taskId)
                        .update({'task_start': Timestamp.fromDate(nextDate)});
                  }
                },
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
              // Icon + Header
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: const [
                  SizedBox(width: 8),
                  Text(
                    "Task Reminder",
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
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Task Title:',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Color(0xFF00588E),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                              softWrap: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'Time:',
                            style: const TextStyle(
                              fontSize: 18,
                              color: Color(0xFF00588E),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            time,
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Text(
                    'Activity:',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF00588E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.lightBlue[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      description,
                      style: const TextStyle(fontSize: 16, color: Colors.black),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // OK
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00588E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: () async {
                      await _taskAudioPlayer.stop();
                      Navigator.of(context).pop();

                      // Handle task based on frequency
                      if (frequency == 'Once') {
                        await _firestore
                            .collection('medical_tasks')
                            .doc(taskId)
                            .delete();
                      } else if (frequency == 'Every Assigned Days') {
                        final nextDate = _getNextScheduledDate(taskDays);
                        await _firestore
                            .collection('medical_tasks')
                            .doc(taskId)
                            .update({
                              'task_start': Timestamp.fromDate(nextDate),
                            });
                      }
                    },
                    child: Text(
                      'OK',
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: () async {
                      await _taskAudioPlayer.stop();
                      Navigator.of(context).pop();
                      if (frequency == 'Once') {
                        await _firestore
                            .collection('medical_tasks')
                            .doc(taskId)
                            .delete();
                      } else if (frequency == 'Every Assigned Days') {
                        final nextDate = _getNextScheduledDate(taskDays);
                        await _firestore
                            .collection('medical_tasks')
                            .doc(taskId)
                            .update({
                              'task_start': Timestamp.fromDate(nextDate),
                            });
                      }
                    },
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
            ],
          ),
        ),
      );
    } catch (e) {
      print('❌ Task dialog error: $e');
    }
  }

  // Handle notification tap to show task dialog with alarm
  Future<void> _handleNotificationTap(String? payload) async {
    if (payload != null && payload.isNotEmpty) {
      try {
        // Fetch task data
        final taskDoc = await _firestore
            .collection('medical_tasks')
            .doc(payload)
            .get();

        if (taskDoc.exists) {
          final taskData = taskDoc.data() as Map<String, dynamic>;
          final title = taskData['task_title'] ?? 'Task';
          final description = taskData['task_description'] ?? '';
          final start =
              (taskData['task_start'] as Timestamp?)?.toDate() ??
              DateTime.now();
          final formattedTime = TimeOfDay.fromDateTime(start).format(context);

          // Show task dialog with alarm
          await _showTaskDialog(payload, title, description, formattedTime);
        }
      } catch (e) {
        debugPrint('Error handling notification tap: $e');
      }
    }
  }

  Widget _medicalTaskCard(
    String title,
    String description,
    String time,
    Color bgColor, {
    String? taskId,
    String? tomorrowMark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tomorrowMark != null)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00588E).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tomorrowMark,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00588E),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 8),
          // Header row with icon and title
          Row(
            children: [
              const Icon(
                Icons.medical_services,
                size: 24,
                color: Color(0xFF00588E),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Description section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              description,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
              ),
              softWrap: true,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),
          // Bottom row with time and action button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00588E).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Time: $time',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF00588E),
                  ),
                ),
              ),
              if (taskId != null)
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 30),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => AlertDialog(
                        backgroundColor: Colors.white,
                        titlePadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        title: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              iconSize: 28,
                              icon: const Icon(
                                Icons.close,
                                color: Color(0xFF00588E),
                              ),
                              onPressed: () => Navigator.of(context).pop(false),
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
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(width: 10),
                                Text(
                                  "Delete Task",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF00588E),
                                    fontSize: 25,
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
                            const Center(
                              child: Text(
                                'Are you sure you want to delete this task?',
                                style: TextStyle(fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF00588E),
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    child: const Text(
                                      'Delete',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: const Text(
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
                      ),
                    );
                    if (confirm == true) {
                      try {
                        // Attempt to read the task doc to see if it has medication metadata
                        final doc = await FirebaseFirestore.instance
                            .collection('medical_tasks')
                            .doc(taskId)
                            .get();
                        final data = doc.data();
                        if (data != null) {
                          // If this task was generated from a medication, cancel the deterministic notification id too
                          final medId = data['medication_id'] as String?;
                          final takeIndex = data['take_index'];
                          if (medId != null && takeIndex != null) {
                            try {
                              NotificationService.cancelNotification(
                                ('${medId}_$takeIndex').hashCode,
                              );
                            } catch (e) {
                              debugPrint(
                                'Error cancelling deterministic notification for $medId:$takeIndex -> $e',
                              );
                            }
                          }
                        }

                        await FirebaseFirestore.instance
                            .collection('medical_tasks')
                            .doc(taskId)
                            .delete();
                      } catch (e) {
                        debugPrint('Error deleting task $taskId: $e');
                      }

                      // Always attempt to cancel the doc-based notification id as well
                      try {
                        NotificationService.cancelNotification(taskId.hashCode);
                      } catch (e) {
                        debugPrint(
                          'Error cancelling notification for $taskId: $e',
                        );
                      }
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------- HOUSES SECTION ----------------------

  // ---------------------- HOUSES SECTION ----------------------
  Widget _housesSection() {
    if (_isLoadingHouses) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_houses.isEmpty) return const Text("No houses available.");

    List<String> houseImages = [
      'assets/images/Sebastian_Logo.png',
      'assets/images/Emmanuel_Logo.png',
      'assets/images/Charbell_Logo.png',
      'assets/images/Rose_Logo.png',
      'assets/images/Gabriel_Logo.png',
    ];
    List<String> houseDescriptions = [
      'Females with Psychological Needs',
      'Females that are Bedridden',
      'Males that are Bedridden',
      'Females that are Abled',
      'Males that are Abled',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.home, color: Color(0xFF00588E), size: 45),
            SizedBox(width: 8),
            Text(
              "Elderly Houses",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: _houses.length,
          itemBuilder: (context, index) {
            final house = _houses[index];
            final houseName = house['house_name'] ?? '';
            String imagePath = index < houseImages.length
                ? houseImages[index]
                : 'assets/images/people_icon.png';
            String description = index < houseDescriptions.length
                ? houseDescriptions[index]
                : 'Elderly Care Facility';

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ElderlyListScreen(
                      houseId: house['house_id'],
                      houseName: houseName,
                    ),
                  ),
                );
              },
              child: Card(
                color: const Color(0XFFE7EFFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Image.asset(imagePath, width: 80, height: 80),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              "House of $houseName",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588E),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF00588E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
