import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../providers/auth_provider.dart' as my_auth;
import '../providers/cg_providers/absence_provider.dart';
import 'elderly_list.dart';
import 'medication_management.dart';
import 'vital_monitoring.dart';
import 'emergency.dart';
import 'nurse_bottom_navbar.dart';
import 'incident_report.dart';
import 'nurse_sidebar.dart';
import 'notification_service.dart';
import '../widgets/nurse_widgets/nurse_notification_icon_button.dart';
import '../main.dart' as main;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:confetti/confetti.dart';
import '../services/attendance_check_service.dart';
import '../services/vitals_daily_auto_creator.dart';

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

  final Map<String, bool> _shownTaskDialogs =
      {}; // track which tasks have been shown

  List<Map<String, dynamic>> _currentTasks =
      []; // Store current tasks for See All

  List<Map<String, dynamic>> _todaysBirthdays = []; // Store today's birthdays

  late ConfettiController _confettiController;

  // Real-time schedule listener
  StreamSubscription<QuerySnapshot>? _scheduleSubscription;
  // Real-time birthday listener
  StreamSubscription<QuerySnapshot>? _birthdaySubscription;
  // Real-time incident listener
  StreamSubscription<QuerySnapshot>? _incidentSubscription;
  // Track processed incidents to prevent duplicates
  final Set<String> _processedIncidents = {};
  Map<String, dynamic>? _cachedScheduleData;
  bool _isLoadingSchedule = true;

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
        final taskId = doc.id; // Get the document ID
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
              payload: taskId, // Pass the task ID as payload
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
            payload: taskId, // Pass the task ID as payload
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

    // Auto-check/create vitals_daily documents when nurse logs in
    VitalsDailyAutoCreator.ensureVitalsDailyExist();

    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
    _loadHouses();
    _initializeScheduleListener(); // Initialize real-time schedule listener
    _initializeEmergencyListener(); // Initialize emergency listener
    _initializeIncidentListener(); // Initialize incident listener
    // Real-time birthday listener
    _birthdaySubscription = FirebaseFirestore.instance
        .collection('elderly')
        .where('elderly_status', isEqualTo: 'Alive')
        .snapshots()
        .listen((_) {
          _checkForBirthday();
        });
    // NOTE: NotificationService is already initialized in main.dart - no need to reinitialize
    _scheduleNotificationsForExistingTasks(); // schedule notifications for existing tasks
    // After first frame we can access context safely and generate medication tasks
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateMedicationTasksForToday();
      _checkForBirthday(); // Check for birthday on app start
      // Global attendance service is now handled by AuthWrapper
      // No need for local attendance initialization

      // Check for pending notification payload
      final pending = NotificationService.getAndClearPendingPayload();
      if (pending != null) {
        _handleNotificationTap(pending);
      }
      // Clean up old medication task descriptions (one-time fix)
      _cleanupOldMedicationDescriptions();
    });
    // ✅ DISABLED: Exact medication time checker to prevent duplicate notifications
    // Medication notifications are now handled by Firebase Cloud Functions only
    // _startExactMedicationTimeChecker(); // REMOVED TO FIX DUPLICATES

    // Start timer to check for missed medical tasks
    _startMissedTaskChecker();
  }

  /// One-time cleanup to fix old medication task descriptions
  Future<void> _cleanupOldMedicationDescriptions() async {
    try {
      debugPrint('🧹 Starting cleanup of old medication tasks...');

      // Get all medical tasks (both 'medication' and 'Medication' task_source)
      final allTasksQuery = await _firestore.collection('medical_tasks').get();

      int updatedCount = 0;
      for (final doc in allTasksQuery.docs) {
        final data = doc.data();
        final taskSource = data['task_source'] as String?;
        final title = data['task_title'] as String?;
        final description = data['task_description'] as String?;

        // Check if it's a medication task (case-insensitive)
        if (taskSource != null && taskSource.toLowerCase() == 'medication') {
          Map<String, dynamic> updates = {};

          // Standardize task_source to lowercase
          if (taskSource != 'medication') {
            updates['task_source'] = 'medication';
          }

          // Fix title: should be just "Medication"
          // Old format: "Metformin - 10mg for Graciela Mendoza"
          if (title != null && title != 'Medication') {
            updates['task_title'] = 'Medication';
            // Move old title to description
            updates['task_description'] = title;
          }

          // Fix description: remove "at [time]" if present and only if we haven't already set description
          if (description != null &&
              description.contains(' at ') &&
              !updates.containsKey('task_description')) {
            final cleanDesc = description.replaceAll(
              RegExp(r' at \d{1,2}:\d{2}'),
              '',
            );
            updates['task_description'] = cleanDesc;
          }

          // Apply updates if any
          if (updates.isNotEmpty) {
            debugPrint('📝 Updating task ${doc.id}:');
            debugPrint('   Old title: $title');
            debugPrint('   Old description: $description');
            debugPrint('   Updates: $updates');

            await doc.reference.update(updates);
            updatedCount++;
          }
        }
      }
      debugPrint('✅ Cleaned up $updatedCount medication tasks');
    } catch (e) {
      debugPrint('Error cleaning up old medication tasks: $e');
    }
  }

  /// Initialize real-time schedule listener for auto-updates
  void _initializeScheduleListener() async {
    try {
      final nurseId = await _getNurseIdFromAuth();
      if (nurseId == null) {
        debugPrint('❌ No nurse ID found for schedule listener');
        return;
      }

      debugPrint('🔄 Initializing schedule listener for nurse: $nurseId');

      _scheduleSubscription = _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .snapshots()
          .listen(
            (snapshot) {
              debugPrint(
                '📅 Schedule update received: ${snapshot.docs.length} assignments',
              );

              if (mounted) {
                setState(() {
                  if (snapshot.docs.isNotEmpty) {
                    _cachedScheduleData = snapshot.docs.first.data();
                    debugPrint(
                      '✅ Schedule updated: ${_cachedScheduleData?['shift']}',
                    );
                  } else {
                    _cachedScheduleData = null;
                    debugPrint('⚠️ No schedule assignments found');
                  }
                  _isLoadingSchedule = false;
                });
              }
            },
            onError: (error) {
              debugPrint('❌ Error in schedule listener: $error');
              if (mounted) {
                setState(() {
                  _isLoadingSchedule = false;
                });
              }
            },
          );

      debugPrint('✅ Schedule listener initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing schedule listener: $e');
      if (mounted) {
        setState(() {
          _isLoadingSchedule = false;
        });
      }
    }
  }

  void _initializeEmergencyListener() {
    print('🚀 Initializing emergency listener');
    try {
      FirebaseFirestore.instance
          .collection('emergency_alert')
          .orderBy('alert_timestamp', descending: true)
          .snapshots()
          .listen((snapshot) async {
            print(
              '🔥 Emergency snapshot received: ${snapshot.docs.length} documents',
            );

            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser == null) {
              print('❌ No user logged in, skipping emergency check');
              return;
            }

            final currentNurseId = currentUser.uid;
            print('👤 Current nurse ID: $currentNurseId');

            for (var doc in snapshot.docs) {
              final data = doc.data();
              final alertId = doc.id;
              final isViewed = data['alert_viewed'] as bool? ?? false;

              if (isViewed) continue; // Skip already viewed alerts

              final assignedNurseIdsRaw = data['user_id_nu'];
              List<dynamic> assignedNurseIds = [];

              if (assignedNurseIdsRaw is List) {
                assignedNurseIds = assignedNurseIdsRaw;
              } else if (assignedNurseIdsRaw is String) {
                assignedNurseIds = [assignedNurseIdsRaw];
              }

              print('📋 Alert $alertId assigned to nurses: $assignedNurseIds');

              if (assignedNurseIds.isNotEmpty &&
                  assignedNurseIds.contains(currentNurseId)) {
                print(
                  '🚨 Emergency alert for current nurse! Showing alert with alarm',
                );

                // Show emergency dialog directly using local context
                if (mounted) {
                  await _showEmergencyDialog(alertId, data);
                }
              } else {
                print('❌ Alert not for current nurse or nurse not assigned');
              }
            }
          });
      print('✅ Emergency listener initialized successfully');
    } catch (e) {
      print('❌ Error initializing emergency listener: $e');
    }
  }

  Future<void> _showEmergencyDialog(
    String alertId,
    Map<String, dynamic> data,
  ) async {
    print('🔔 Showing emergency dialog for alert: $alertId');

    // Get description from the alert data - only additional info now
    final additionalInfo = data['additional_info'] ?? '';

    // Call EmergencyService to show alert with alarm
    await main.EmergencyService.showEmergencyAlert(
      alertId: alertId,
      description: additionalInfo.isNotEmpty
          ? additionalInfo
          : 'Emergency alert received',
      emergencyType: data['emergency_type'] ?? '',
    );
    print('✅ Emergency dialog completed');
  }

  // ✅ REMOVED: _startExactMedicationTimeChecker() and _checkExactMedicationTimes()
  // These functions were creating DUPLICATE medication notifications alongside Firebase Cloud Functions
  //
  // REASON FOR REMOVAL:
  // - Firebase Cloud Functions now handle ALL medication notifications via:
  //   * scheduleMedicationNotifications (creates scheduled_notifications)
  //   * processMedicationNotifications (sends FCM notifications)
  // - This client-side timer was sending additional local notifications
  // - Result: Users got 2 notifications per medication ("Medication Time" + "Medication")
  //
  // NOW: Only Firebase handles medication notifications = NO MORE DUPLICATES ✅

  void _startMissedTaskChecker() {
    // Check for missed medical tasks every 1 minute
    Timer.periodic(const Duration(minutes: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      await _checkMissedTasks();
    });
    // Also check immediately on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkMissedTasks();
    });
  }

  Future<void> _checkMissedTasks() async {
    try {
      final now = DateTime.now();
      print(
        '🔍 Checking for missed medical tasks at ${DateFormat('HH:mm').format(now)}',
      );

      // Get all medical tasks that are medication-related and still pending
      // Check both lowercase 'medication' and capitalized 'Medication'
      final tasksQuery = await _firestore
          .collection('medical_tasks')
          .where('task_status', isEqualTo: 'pending')
          .get();

      print('📋 Found ${tasksQuery.docs.length} pending tasks (all types)');

      for (final doc in tasksQuery.docs) {
        final data = doc.data();
        final taskSource = data['task_source'] as String?;
        final taskStart = (data['task_start'] as Timestamp?)?.toDate();

        // Only check medication tasks (case-insensitive)
        if (taskSource == null || taskSource.toLowerCase() != 'medication') {
          continue;
        }

        if (taskStart == null) continue;

        // Check if more than 1 hour has passed since scheduled time
        final timeDifference = now.difference(taskStart);

        print('⏰ Medication task ${doc.id}:');
        print('   Scheduled: $taskStart');
        print('   Current: $now');
        print('   Difference: ${timeDifference.inMinutes} minutes');

        if (timeDifference.inHours >= 1) {
          print(
            '🚨 Task ${doc.id} is overdue by ${timeDifference.inMinutes} minutes - deleting',
          );

          // Delete the medical task (it will be handled by medication_takes and activity logs)
          await doc.reference.delete();
          print('✅ Deleted overdue medical task ${doc.id}');
        }
      }
    } catch (e) {
      debugPrint('❌ Error checking missed tasks: $e');
    }
  }

  void _initializeIncidentListener() {
    try {
      // Cancel existing subscription to prevent multiple listeners
      _incidentSubscription?.cancel();

      _incidentSubscription = FirebaseFirestore.instance
          .collection('incident_report')
          .orderBy('incident_date_time', descending: true)
          .snapshots()
          .listen((snapshot) async {
            print(
              '📝 Incident snapshot received: ${snapshot.docs.length} documents',
            );

            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser == null) {
              print('❌ No user logged in, skipping incident check');
              return;
            }

            final currentNurseId = currentUser.uid;
            print('👤 Current nurse ID: $currentNurseId');

            // Process ONLY ADDED document changes to prevent duplicates
            for (var change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final doc = change.doc;
                final data = doc.data()!;
                final incidentId = doc.id;

                // Check if we already processed this incident
                if (_processedIncidents.contains(incidentId)) {
                  print('⚠️ Incident $incidentId already processed, skipping');
                  continue;
                }

                // Mark as processed
                _processedIncidents.add(incidentId);

                final incidentType =
                    data['incident_type'] ?? 'No incident type';
                final additionalInfo = data['additional_info'] ?? '';
                final timestampRaw = data['incident_date_time']?.toDate();

                print('🔍 Processing added incident: $incidentId');
                print('📋 Type: $incidentType, Additional: $additionalInfo');
                print(
                  '🚫 Incident notifications now handled by FCM only - skipping local notification',
                );

                if (timestampRaw == null) continue;

                // Skip local notifications - FCM Cloud Function handles all incident notifications
                // This prevents duplicate notifications
                continue;
              }
            }
          });
      print('✅ Incident listener initialized successfully');
    } catch (e) {
      print('❌ Error initializing incident listener: $e');
    }
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
      final auth = Provider.of<my_auth.AuthProvider>(context, listen: false);
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

  Future<void> _checkForBirthday() async {
    try {
      final nurseId = await _getNurseIdFromAuth();
      if (nurseId == null) {
        debugPrint('Birthday check: No nurse ID found');
        return;
      }
      debugPrint('Birthday check: Nurse ID = $nurseId');

      // 🎂 MODIFIED: Fetch ALL elderly birthdays (not just assigned ones)
      debugPrint('Birthday check: Fetching ALL elderly birthdays...');

      // Get ALL elderly who are alive
      final elderlyQuery = await _firestore
          .collection('elderly')
          .where('elderly_status', isEqualTo: 'Alive')
          .get();

      debugPrint(
        'Birthday check: Found ${elderlyQuery.docs.length} elderly in system',
      );

      if (elderlyQuery.docs.isEmpty) {
        debugPrint('Birthday check: No elderly found in system');
        setState(() => _todaysBirthdays = []);
        return;
      }

      // Check each elderly for birthday today
      final List<Map<String, dynamic>> birthdays = [];
      for (final doc in elderlyQuery.docs) {
        final data = doc.data();
        final birthday = data['elderly_bday'] ?? data['birthdate'];

        if (_isBirthdayToday(birthday)) {
          final gender = data['elderly_sex'] ?? 'male';
          debugPrint('Birthday check: Elderly ${doc.id} gender: $gender');
          final prefix = gender.toLowerCase().startsWith('f') ? 'Lola' : 'Lolo';
          final fullName =
              '$prefix ${data['elderly_fname']} ${data['elderly_lname']}';
          birthdays.add({'id': doc.id, 'name': fullName, 'birthday': birthday});
          debugPrint('Birthday check: Today is $fullName\'s birthday!');
        }
      }

      debugPrint('Birthday check: Found ${birthdays.length} birthdays today');

      setState(() => _todaysBirthdays = birthdays);
      if (birthdays.isNotEmpty) {
        final names = birthdays.map((b) => b['name'] as String).toList();
        final today = DateTime.now().toIso8601String().split('T')[0];
        final acknowledgedKey = 'birthday_acknowledged_all_$today';
        await _showBirthdayDialog(names, acknowledgedKey, isManualTap: false);
      }
    } catch (e) {
      debugPrint('Error checking for birthday: $e');
      setState(() => _todaysBirthdays = []);
    }
  }

  bool _isBirthdayToday(dynamic birthday) {
    if (birthday == null) {
      debugPrint('Birthday check: Birthday is null');
      return false;
    }

    DateTime birthDate;
    if (birthday is Timestamp) {
      birthDate = birthday.toDate();
    } else if (birthday is DateTime) {
      birthDate = birthday;
    } else {
      debugPrint(
        'Birthday check: Birthday is not Timestamp or DateTime: $birthday (type: ${birthday.runtimeType})',
      );
      return false;
    }

    final now = DateTime.now();
    final isToday = birthDate.month == now.month && birthDate.day == now.day;
    debugPrint(
      'Birthday check: Birth date: ${birthDate.month}/${birthDate.day}, Today: ${now.month}/${now.day}, Is today: $isToday',
    );
    return isToday;
  }

  Future<void> _showBirthdayDialog(
    List<String> names,
    String acknowledgedKey, {
    bool isManualTap = false,
  }) async {
    // Check if already acknowledged (only for auto-show, not manual tap)
    if (!isManualTap) {
      final prefs = await SharedPreferences.getInstance();
      final alreadyAcknowledged = prefs.getBool(acknowledgedKey) ?? false;
      if (alreadyAcknowledged) {
        debugPrint('Birthday already acknowledged for today');
        return;
      }
    }

    _confettiController.play();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Stack(
          children: [
            AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              contentPadding: EdgeInsets.zero,
              content: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  image: DecorationImage(
                    image: AssetImage('assets/images/birthdaybg.png'),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 60), // Add spacing at top
                      // Title
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              '🎉 Happy Birthday! 🎂',
                              style: const TextStyle(
                                color: Color(0xFF00588E),
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Poppins',
                                fontSize: 22,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Content
                      Text(
                        names.length == 1
                            ? "Today is ${names[0]}'s birthday! 🎈🥳"
                            : names.length == 2
                            ? "Today is ${names[0]} and ${names[1]}'s birthday! 🎈🥳"
                            : "Today is ${names.sublist(0, names.length - 1).join(', ')} and ${names.last}'s birthday! 🎈🥳",
                        style: const TextStyle(
                          fontSize: 16,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.justify,
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        'Greet them with a warm hug and love.',
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: 'Poppins',
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.justify,
                      ),
                      const SizedBox(height: 20),
                      const Text('🎂🍰🎈🎉🎊', style: TextStyle(fontSize: 24)),
                      const SizedBox(height: 20),
                      // Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool(acknowledgedKey, true);
                            _confettiController.stop();
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00588E),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Acknowledge 🎉',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                colors: const [
                  Colors.red,
                  Colors.blue,
                  Colors.green,
                  Colors.yellow,
                  Colors.pink,
                  Colors.purple,
                ],
              ),
            ),
          ],
        );
      },
    );
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
            .where('status', isEqualTo: 'active')
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
              final taskTitle = 'Medication';
              final taskDesc =
                  '$medName ${dosage.isNotEmpty ? '- $dosage' : ''} for $elderlyName';

              final taskDocRef = await _firestore
                  .collection('medical_tasks')
                  .add({
                    'task_title': taskTitle,
                    'task_description': taskDesc,
                    'task_category': 'Medication',
                    'task_start': taskStart,
                    'task_frequency': repeatInterval == 'Daily'
                        ? 'Every Assigned Days'
                        : 'Once',
                    'task_status':
                        'pending', // Ensure lowercase for consistency
                    'days': taskDays,
                    // metadata to avoid duplicates and allow tracing
                    'task_source': 'medication',
                    'medication_id': medicationId,
                    'take_index': t,
                    'elderly_id': elderlyId,
                    'created_at': FieldValue.serverTimestamp(),
                  });

              final taskId = taskDocRef.id; // Get the task ID

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
                  payload: taskId, // Pass the task ID as payload
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
                  payload: taskId, // Pass the task ID as payload
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

      final shiftQuery = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
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
  void dispose() {
    _confettiController.dispose();
    // Cancel schedule listener
    _scheduleSubscription?.cancel();
    // Cancel birthday listener
    _birthdaySubscription?.cancel();
    // Cancel incident listener
    _incidentSubscription?.cancel();
    // Stop the periodic attendance check timer
    AttendanceCheckService.stopPeriodicAttendanceCheck();
    super.dispose();
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
                      child: RefreshIndicator(
                        onRefresh: () async {
                          // Refresh houses data
                          await _loadHouses();
                          // Refresh birthdays
                          await _checkForBirthday();
                          // The medical tasks will refresh automatically via StreamBuilder
                        },
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
                            _birthdaySection(),
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

                                  // Use cached schedule data instead of FutureBuilder
                                  _isLoadingSchedule
                                      ? const Center(
                                          child: CircularProgressIndicator(),
                                        )
                                      : Builder(
                                          builder: (context) {
                                            final statusData =
                                                _cachedScheduleData;
                                            final daysAssigned =
                                                statusData?['days_assigned']
                                                    as List<dynamic>? ??
                                                [];

                                            // Handle shift field - could be String or Map
                                            final shiftData =
                                                statusData?['shift'];
                                            final shift = shiftData is String
                                                ? shiftData
                                                : shiftData
                                                      is Map<String, dynamic>
                                                ? (shiftData['name'] ??
                                                      shiftData['shift_name'] ??
                                                      'Not assigned')
                                                : 'Not assigned';

                                            // Handle start_time and end_time fields (NEW structure)
                                            final startTime =
                                                statusData?['start_time']
                                                    as String? ??
                                                '';
                                            final endTime =
                                                statusData?['end_time']
                                                    as String? ??
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
                                                  padding: const EdgeInsets.all(
                                                    16,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Color(0xFFB7DDF5),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Text(
                                                        'Current Work Schedule',
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Color(
                                                            0xFF00588E,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 15,
                                                      ),
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceEvenly,
                                                        children: [
                                                          for (
                                                            int i = 0;
                                                            i < 7;
                                                            i++
                                                          )
                                                            Column(
                                                              children: [
                                                                Container(
                                                                  width: 32,
                                                                  height: 32,
                                                                  decoration: BoxDecoration(
                                                                    shape: BoxShape
                                                                        .circle,
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
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500,
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
                                                  padding: const EdgeInsets.all(
                                                    16,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Color(0xFFB7DDF5),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.access_time,
                                                        color: Color(
                                                          0xFF00588E,
                                                        ),
                                                        size: 70,
                                                      ),
                                                      const SizedBox(width: 20),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .center,
                                                          children: [
                                                            const Text(
                                                              'Current Shift Schedule',
                                                              style: TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Color(
                                                                  0xFF00588E,
                                                                ),
                                                              ),
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                            ),
                                                            const SizedBox(
                                                              height: 8,
                                                            ),
                                                            Text(
                                                              '${shift.toUpperCase()} SHIFT',
                                                              style: TextStyle(
                                                                fontSize: 24,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Color(
                                                                  0xFF00588E,
                                                                ),
                                                              ),
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                            ),
                                                            const SizedBox(
                                                              height: 6,
                                                            ),
                                                            Text(
                                                              timeRange,
                                                              style: TextStyle(
                                                                fontSize: 18,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: Color(
                                                                  0xFF00588E,
                                                                ),
                                                              ),
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                const SizedBox(height: 15),

                                                // Absence Status & Temporary Assignments
                                                Consumer<AbsenceProvider>(
                                                  builder: (context, absenceProvider, child) {
                                                    // Show absence status if absent
                                                    if (absenceProvider
                                                        .isAbsentToday) {
                                                      return Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              16,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors
                                                              .orange[100],
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                          border: Border.all(
                                                            color:
                                                                Colors.orange,
                                                            width: 2,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              absenceProvider
                                                                          .absenceType ==
                                                                      'leave'
                                                                  ? Icons
                                                                        .event_busy
                                                                  : Icons
                                                                        .cancel_outlined,
                                                              color:
                                                                  Colors.orange,
                                                              size: 40,
                                                            ),
                                                            const SizedBox(
                                                              width: 12,
                                                            ),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: const [
                                                                  Text(
                                                                    'Not Present at Work',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          16,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      color: Colors
                                                                          .black87,
                                                                    ),
                                                                  ),
                                                                  SizedBox(
                                                                    height: 4,
                                                                  ),
                                                                  Text(
                                                                    'You are marked absent/on leave for today',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          14,
                                                                      color: Colors
                                                                          .black54,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }

                                                    // Show temporary assignments if any
                                                    final tempCount =
                                                        absenceProvider
                                                            .temporaryElderlyIds
                                                            .length;
                                                    print(
                                                      '🏠 Nurse Home.dart: Temporary elderly count = $tempCount',
                                                    );
                                                    print(
                                                      '🏠 Nurse Home.dart: hasTemporaryAssignments = ${absenceProvider.hasTemporaryAssignments}',
                                                    );

                                                    if (absenceProvider
                                                            .hasTemporaryAssignments &&
                                                        tempCount > 0) {
                                                      return Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              16,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              Colors.blue[50],
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                          border: Border.all(
                                                            color: Colors.blue,
                                                            width: 2,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            const Icon(
                                                              Icons.people,
                                                              color:
                                                                  Colors.blue,
                                                              size: 40,
                                                            ),
                                                            const SizedBox(
                                                              width: 12,
                                                            ),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  const Text(
                                                                    'Temporary Assignments',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          16,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      color: Colors
                                                                          .black87,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    height: 4,
                                                                  ),
                                                                  Text(
                                                                    'You have $tempCount temporary ${tempCount == 1 ? 'assignment' : 'assignments'} today',
                                                                    style: const TextStyle(
                                                                      fontSize:
                                                                          14,
                                                                      color: Colors
                                                                          .black54,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }

                                                    // Check if nurse is scheduled for today
                                                    final now = DateTime.now();
                                                    final daysOfWeek = [
                                                      'Sunday',
                                                      'Monday',
                                                      'Tuesday',
                                                      'Wednesday',
                                                      'Thursday',
                                                      'Friday',
                                                      'Saturday',
                                                    ];
                                                    final todayName =
                                                        daysOfWeek[now.weekday %
                                                            7]; // Convert weekday to day name
                                                    final isScheduledToday =
                                                        daysAssigned.contains(
                                                          todayName,
                                                        );

                                                    // Show not on duty status if not scheduled for today
                                                    if (!isScheduledToday) {
                                                      return Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              16,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.red[50],
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                          border: Border.all(
                                                            color: Colors.red,
                                                            width: 2,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          children: const [
                                                            Icon(
                                                              Icons.event_busy,
                                                              color: Colors.red,
                                                              size: 40,
                                                            ),
                                                            SizedBox(width: 12),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Text(
                                                                    'Not On Duty',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          16,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      color: Colors
                                                                          .black87,
                                                                    ),
                                                                  ),
                                                                  SizedBox(
                                                                    height: 4,
                                                                  ),
                                                                  Text(
                                                                    'You are not on duty for today',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          14,
                                                                      color: Colors
                                                                          .black54,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }

                                                    // Check if shift has started or ended
                                                    bool shiftNotStarted =
                                                        false;
                                                    bool shiftEnded = false;

                                                    if (startTime.isNotEmpty &&
                                                        endTime.isNotEmpty) {
                                                      try {
                                                        final now =
                                                            DateTime.now();

                                                        // Parse shift times
                                                        final startParts =
                                                            startTime.split(
                                                              ':',
                                                            );
                                                        final shiftStartHour =
                                                            int.parse(
                                                              startParts[0],
                                                            );
                                                        final shiftStartMinute =
                                                            int.parse(
                                                              startParts[1],
                                                            );

                                                        final endParts = endTime
                                                            .split(':');
                                                        final shiftEndHour =
                                                            int.parse(
                                                              endParts[0],
                                                            );
                                                        final shiftEndMinute =
                                                            int.parse(
                                                              endParts[1],
                                                            );

                                                        DateTime
                                                        shiftStartDateTime =
                                                            DateTime(
                                                              now.year,
                                                              now.month,
                                                              now.day,
                                                              shiftStartHour,
                                                              shiftStartMinute,
                                                            );

                                                        DateTime
                                                        shiftEndDateTime =
                                                            DateTime(
                                                              now.year,
                                                              now.month,
                                                              now.day,
                                                              shiftEndHour,
                                                              shiftEndMinute,
                                                            );

                                                        // Determine if it's an overnight shift
                                                        final isOvernightShift =
                                                            shiftEndHour <
                                                                shiftStartHour ||
                                                            (shiftEndHour ==
                                                                    shiftStartHour &&
                                                                shiftEndMinute <=
                                                                    shiftStartMinute);

                                                        if (isOvernightShift) {
                                                          // Overnight shift logic (e.g., 3rd shift: 10 PM - 6 AM)
                                                          if (now.hour <
                                                                  shiftEndHour ||
                                                              (now.hour ==
                                                                      shiftEndHour &&
                                                                  now.minute <
                                                                      shiftEndMinute)) {
                                                            // Current time is in the "end period" (before shift end) - shift is active
                                                            shiftNotStarted =
                                                                false;
                                                            shiftEnded = false;
                                                          } else if (now.hour >=
                                                                  shiftStartHour ||
                                                              (now.hour ==
                                                                      shiftStartHour &&
                                                                  now.minute >=
                                                                      shiftStartMinute)) {
                                                            // Current time is in the "start period" (after shift start) - shift is active
                                                            shiftNotStarted =
                                                                false;
                                                            shiftEnded = false;
                                                          } else {
                                                            // Time is between end and start
                                                            // Check if we're before start or after end
                                                            if (now.hour <
                                                                shiftStartHour) {
                                                              shiftNotStarted =
                                                                  true;
                                                              shiftEnded =
                                                                  false;
                                                            } else {
                                                              shiftNotStarted =
                                                                  false;
                                                              shiftEnded = true;
                                                            }
                                                          }
                                                        } else {
                                                          // Regular shift (not overnight)
                                                          if (now.isBefore(
                                                            shiftStartDateTime,
                                                          )) {
                                                            shiftNotStarted =
                                                                true;
                                                            shiftEnded = false;
                                                          } else if (now.isAfter(
                                                            shiftEndDateTime,
                                                          )) {
                                                            shiftNotStarted =
                                                                false;
                                                            shiftEnded = true;
                                                          } else {
                                                            // Currently within shift hours
                                                            shiftNotStarted =
                                                                false;
                                                            shiftEnded = false;
                                                          }
                                                        }
                                                      } catch (e) {
                                                        print(
                                                          'Error checking shift times: $e',
                                                        );
                                                        shiftNotStarted = false;
                                                        shiftEnded = false;
                                                      }
                                                    }

                                                    // Show shift not started status
                                                    if (shiftNotStarted) {
                                                      return Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              16,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              Colors.amber[50],
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                          border: Border.all(
                                                            color: Colors.amber,
                                                            width: 2,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          children: const [
                                                            Icon(
                                                              Icons.schedule,
                                                              color:
                                                                  Colors.amber,
                                                              size: 40,
                                                            ),
                                                            SizedBox(width: 12),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Text(
                                                                    'Shift Not Started',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          16,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      color: Colors
                                                                          .black87,
                                                                    ),
                                                                  ),
                                                                  SizedBox(
                                                                    height: 4,
                                                                  ),
                                                                  Text(
                                                                    'Your shift hasn\'t started yet for today',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          14,
                                                                      color: Colors
                                                                          .black54,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }

                                                    // Show shift ended status
                                                    if (shiftEnded) {
                                                      return Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              16,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              Colors.grey[200],
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                          border: Border.all(
                                                            color: Colors.grey,
                                                            width: 2,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          children: const [
                                                            Icon(
                                                              Icons.work_off,
                                                              color:
                                                                  Colors.grey,
                                                              size: 40,
                                                            ),
                                                            SizedBox(width: 12),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Text(
                                                                    'Shift Ended',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          16,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      color: Colors
                                                                          .black87,
                                                                    ),
                                                                  ),
                                                                  SizedBox(
                                                                    height: 4,
                                                                  ),
                                                                  Text(
                                                                    'Your shift has ended for today',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          14,
                                                                      color: Colors
                                                                          .black54,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }

                                                    // Show normal status (on duty)
                                                    return Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            16,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.green[50],
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                        border: Border.all(
                                                          color: Colors.green,
                                                          width: 2,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: const [
                                                          Icon(
                                                            Icons.check_circle,
                                                            color: Colors.green,
                                                            size: 40,
                                                          ),
                                                          SizedBox(width: 12),
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  'On Duty',
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        16,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    color: Colors
                                                                        .black87,
                                                                  ),
                                                                ),
                                                                SizedBox(
                                                                  height: 4,
                                                                ),
                                                                Text(
                                                                  'You are on duty today',
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        14,
                                                                    color: Colors
                                                                        .black54,
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
                  ),
                  if (isSidebarOpen)
                    NurseSidebar(
                      isSidebarOpen: isSidebarOpen,
                      toggleSidebar: toggleSidebar,
                      parentContext: context,
                    ),
                ],
              )
            : _screens[selectedIndex],
        bottomNavigationBar: NurseBottomNavBar(
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
              onTap: toggleSidebar,
              child: Consumer<my_auth.AuthProvider>(
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
                Consumer<my_auth.AuthProvider>(
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
        const NurseNotificationIconButton(),
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
          // Tasks list - filtered by nurse's assigned elderly
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 2,
              vertical: 8,
            ), // Reduced horizontal padding for wider cards
            child: FutureBuilder<Set<String>>(
              future: _getNurseAssignedElderlyIds(),
              builder: (context, elderlySnapshot) {
                if (elderlySnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final assignedElderlyIds = elderlySnapshot.data ?? {};

                if (assignedElderlyIds.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Text(
                        "No elderly assigned to you.",
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }

                return StreamBuilder<QuerySnapshot>(
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

                    // Get current shift time range
                    final currentShift = _getCurrentShift();
                    int shiftStartHour, shiftEndHour;
                    if (currentShift == '1st') {
                      shiftStartHour = 6;
                      shiftEndHour = 14;
                    } else if (currentShift == '2nd') {
                      shiftStartHour = 14;
                      shiftEndHour = 22;
                    } else {
                      // 3rd shift
                      shiftStartHour = 22;
                      shiftEndHour =
                          30; // 6 AM next day (22 + 8 = 30 for comparison)
                    }

                    // Filter tasks by assigned elderly AND shift time
                    final nurseRelatedTasks = tasks.where((task) {
                      final taskElderlyId = task['elderly_id'] as String?;

                      // Check if elderly is assigned to this nurse
                      if (taskElderlyId == null ||
                          !assignedElderlyIds.contains(taskElderlyId)) {
                        return false;
                      }

                      // Check if task time falls within current shift
                      final taskStart = task['task_start'] != null
                          ? (task['task_start'] as Timestamp).toDate()
                          : DateTime.now();

                      final taskHour = taskStart.hour;

                      // For 3rd shift (22:00-06:00), handle time wrapping
                      if (currentShift == '3rd') {
                        return taskHour >= 22 || taskHour < 6;
                      } else {
                        return taskHour >= shiftStartHour &&
                            taskHour < shiftEndHour;
                      }
                    }).toList();

                    debugPrint(
                      '🔍 Total tasks: ${tasks.length}, Nurse\'s elderly tasks (shift filtered): ${nurseRelatedTasks.length}',
                    );

                    // Store current tasks for See All functionality
                    _currentTasks = nurseRelatedTasks;

                    // Filter tasks for today and tomorrow (only future tasks)
                    final filteredTasks = nurseRelatedTasks.where((task) {
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
                      final tomorrowStart = todayStart.add(
                        const Duration(days: 1),
                      );
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

                    // Sort filtered tasks by time proximity to current time (nearest first)
                    final now = DateTime.now();
                    filteredTasks.sort((a, b) {
                      final aStart = a['task_start'] != null
                          ? (a['task_start'] as Timestamp).toDate()
                          : DateTime.now();
                      final bStart = b['task_start'] != null
                          ? (b['task_start'] as Timestamp).toDate()
                          : DateTime.now();

                      // Calculate time difference from now
                      final aDiff = (aStart.difference(now)).abs();
                      final bDiff = (bStart.difference(now)).abs();

                      return aDiff.compareTo(bDiff);
                    });

                    // Limit to 3 most relevant tasks
                    final displayedTasks = filteredTasks.take(3).toList();

                    debugPrint(
                      'Total tasks: ${tasks.length}, Filtered tasks: ${filteredTasks.length}, Displayed tasks: ${displayedTasks.length}',
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
                        else if (displayedTasks.isEmpty)
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
                            itemCount: displayedTasks.length,
                            itemBuilder: (context, index) {
                              final task = displayedTasks[index];
                              final title = task['task_title'] ?? '';
                              final description =
                                  task['task_description'] ?? '';
                              final start = task['task_start'] != null
                                  ? (task['task_start'] as Timestamp).toDate()
                                  : DateTime.now();
                              final formattedTime = TimeOfDay.fromDateTime(
                                start,
                              ).format(context);

                              // Schedule notification and dialog if not already shown
                              final taskId = task['task_id'];
                              final frequency =
                                  task['task_frequency'] ?? 'Once';
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
                              } else if (!_shownTaskDialogs.containsKey(
                                    taskId,
                                  ) &&
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
                                onPressed: _showAddTaskDialog,
                                icon: const Icon(Icons.add),
                                label: const Text(
                                  "Add Task",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF22688E),
                                  foregroundColor: Colors.white,
                                  elevation: null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Get all elderly IDs assigned to this nurse for their current shift
  Future<Set<String>> _getNurseAssignedElderlyIds() async {
    try {
      final nurseId = await _getNurseIdFromAuth();
      if (nurseId == null) return {};

      final currentShift = _getCurrentShift();
      final currentDay = _getCurrentDay();

      debugPrint(
        '🔍 Getting assigned elderly for nurse: $nurseId, shift: $currentShift, day: $currentDay',
      );

      // Get elderly_assignments for this nurse for current shift AND current day
      final assignQuery = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .where('day', isEqualTo: currentDay)
          .get();

      if (assignQuery.docs.isEmpty) {
        debugPrint(
          '❌ No elderly assignments found for nurse on $currentDay ($currentShift shift)',
        );
        return {};
      }

      // Collect all elderly IDs across assignments
      final Set<String> elderlyIds = {};
      for (final doc in assignQuery.docs) {
        final data = doc.data();
        final ids = List<String>.from(data['elderly_ids'] ?? []);
        elderlyIds.addAll(ids);
      }

      debugPrint(
        '✅ Found ${elderlyIds.length} assigned elderly for $currentDay ($currentShift): $elderlyIds',
      );
      return elderlyIds;
    } catch (e) {
      debugPrint('❌ Error getting assigned elderly: $e');
      return {};
    }
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
                                    'task_status': 'pending',
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
              titlePadding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
              contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(
                      color: Color.fromARGB(255, 204, 203, 203),
                      thickness: 2,
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
                          'Date: ${DateFormat('MMM. d, yyyy').format(selectedDate)}',
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
                              builder: (context, child) {
                                return Theme(
                                  data: ThemeData.light().copyWith(
                                    colorScheme: const ColorScheme.light(
                                      primary: Color(0xFF00588E),
                                    ),
                                  ),
                                  child: child!,
                                );
                              },
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
                    const SizedBox(height: 5),
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

                                // All tasks use the same blue color like in Medical Tasks
                                Color bgColor = const Color.fromARGB(
                                  255,
                                  177,
                                  217,
                                  250,
                                );

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: bgColor,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.grey.withOpacity(0.3),
                                        spreadRadius: 1,
                                        blurRadius: 2,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: ListTile(
                                    title: Row(
                                      children: [
                                        Icon(
                                          title.toLowerCase() == 'medication'
                                              ? Icons.medication
                                              : Icons.assignment,
                                          color:
                                              title.toLowerCase() ==
                                                  'medication'
                                              ? Colors.green
                                              : Color(0xFF00588E),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
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
    print('Showing task dialog for task: $taskId');
    try {
      if (!mounted) return;

      // Fetch task data to get frequency
      final taskDoc = await _firestore
          .collection('medical_tasks')
          .doc(taskId)
          .get();
      if (!taskDoc.exists) return;
      final taskData = taskDoc.data() as Map<String, dynamic>;
      final frequency = taskData['task_frequency'] ?? 'Once';
      final taskDaysRaw = taskData['days'];
      final taskDays = taskDaysRaw is List
          ? List<String>.from(taskDaysRaw)
          : <String>[];

      await showDialog(
        context: main.navigatorKey.currentContext!,
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
                  Navigator.of(main.navigatorKey.currentContext!).pop();
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
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text(
                    "Task Reminder",
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
                              fontSize: 16,
                              color: Color(0xFF00588E),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16,
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
                              fontSize: 16,
                              color: Color(0xFF00588E),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            time,
                            style: const TextStyle(
                              fontSize: 16,
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

                      Navigator.of(main.navigatorKey.currentContext!).pop();
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
                      Navigator.of(main.navigatorKey.currentContext!).pop();
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
    print('Handling notification tap with payload: $payload');
    if (payload != null && payload.isNotEmpty) {
      try {
        // Wait a bit to ensure the app is ready
        await Future.delayed(const Duration(seconds: 3));
        print('Delayed, now fetching task data');

        // Fetch task data
        final taskDoc = await _firestore
            .collection('medical_tasks')
            .doc(payload)
            .get();

        if (taskDoc.exists && main.navigatorKey.currentContext != null) {
          print('Task exists and context available, showing dialog');
          final taskData = taskDoc.data() as Map<String, dynamic>;
          final title = taskData['task_title'] ?? 'Task';
          final description = taskData['task_description'] ?? '';
          final start =
              (taskData['task_start'] as Timestamp?)?.toDate() ??
              DateTime.now();
          final formattedTime = TimeOfDay.fromDateTime(
            start,
          ).format(main.navigatorKey.currentContext!);

          // Show task dialog with alarm
          await _showTaskDialog(payload, title, description, formattedTime);
        } else {
          print('Task does not exist or context not available');
        }
      } catch (e) {
        debugPrint('Error handling notification tap: $e');
      }
    } else {
      print('Payload is null or empty');
    }
  }

  Widget _medicalTaskCard(
    String title,
    String description,
    String time, {
    String? taskId,
    String? tomorrowMark,
  }) {
    return Dismissible(
      key: Key(taskId ?? UniqueKey().toString()),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        // Show delete confirmation dialog
        return await showDialog<bool>(
              context: context,
              barrierDismissible: false,
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
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        iconSize: 28,
                        icon: const Icon(Icons.close, color: Color(0xFF00588E)),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text(
                            "Delete Task",
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
                      const SizedBox(height: 12),
                      // Confirmation question
                      const Text(
                        'Are you sure you want to delete this task?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 16),
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
                                      fontSize: 16,
                                      color: Color(0xFF00588E),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 16,
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
                                      fontSize: 16,
                                      color: Color(0xFF00588E),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    time,
                                    style: const TextStyle(
                                      fontSize: 16,
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
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Delete (Left)
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text(
                              'Delete',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Cancel (Right)
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00588E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ) ??
            false;
      },
      onDismissed: (direction) async {
        // Delete the task from Firestore
        if (taskId != null) {
          try {
            await _firestore.collection('medical_tasks').doc(taskId).delete();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Task deleted successfully'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error deleting task: $e'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        }
      },
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.delete, color: Colors.white, size: 32),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white, size: 32),
      ),
      child: Card(
        color: Color(0xFFB7DDF5), // Same color as Current Work Schedule
        margin: const EdgeInsets.symmetric(
          horizontal: 2, // Minimal horizontal margin for maximum width
          vertical: 8,
        ), // Reduced horizontal margin for wider cards
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tomorrow mark badge (if applicable)
              if (tomorrowMark != null) ...[
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          Colors.white, // White background for tomorrow badge
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Color(0xFF00588E), width: 2),
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
                const SizedBox(height: 12),
              ],

              // Title row with icon
              Row(
                children: [
                  const Icon(
                    Icons.medical_services,
                    color: Color(0xFF00588E),
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00588E),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Description with medication icon
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.medication, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      description,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Time container (matching medication_upcoming style)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule,
                          color: Colors.orange,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Scheduled Time',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              time,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588E),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ); // End of Dismissible and _medicalTaskCard
  }

  // ---------------------- BIRTHDAY SECTION ----------------------
  Widget _birthdaySection() {
    if (_todaysBirthdays.isEmpty) {
      return const SizedBox.shrink(); // Don't show section if no birthdays
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(
          255,
          223,
          186,
          0.25,
        ), // Light orange background
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.cake,
                color: Color(0xFFFF6B35), // Orange color for birthday
                size: 45,
              ),
              SizedBox(width: 8),
              Text(
                "Today's Birthdays",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFF6B35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              final names = _todaysBirthdays
                  .map((b) => b['name'] as String)
                  .toList();
              final today = DateTime.now().toIso8601String().split('T')[0];
              final acknowledgedKey = 'birthday_acknowledged_all_$today';
              _showBirthdayDialog(names, acknowledgedKey, isManualTap: true);
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFF6B35).withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '🎉 Happy Birthday! 🎂',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFF6B35),
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Color(0xFFFF6B35),
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._todaysBirthdays.map((birthday) {
                    final name = birthday['name'] as String;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
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
