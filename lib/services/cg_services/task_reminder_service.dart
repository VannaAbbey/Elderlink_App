import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'notification_service.dart';
import '../../models/cg_models/notification_model.dart';
import 'caregiver_shift_log_service.dart';

/// Background callback for WorkManager - must be a top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      print('🔄 Background task started: $task');
      
      // Initialize Firebase if not already initialized
      await Firebase.initializeApp();
      
      // Check for missed tasks and update their status
      await _checkAndUpdateMissedTasks();
      
      print('✅ Background task completed successfully');
      return Future.value(true);
    } catch (e) {
      print('❌ Background task failed: $e');
      return Future.value(false);
    }
  });
}

/// Check for overdue tasks and mark them as missed
Future<void> _checkAndUpdateMissedTasks() async {
  try {
    print('🔍 Checking for missed tasks in background...');
    
    final now = DateTime.now();
    
    // Query all upcoming tasks
    final tasksSnapshot = await FirebaseFirestore.instance
        .collection('care_tasks')
        .where('task_status', arrayContains: 'Upcoming')
        .get();
    
    print('📋 Found ${tasksSnapshot.docs.length} upcoming tasks to check');
    
    int missedCount = 0;
    
    for (var doc in tasksSnapshot.docs) {
      final data = doc.data();
      
      // Calculate task end time
      final taskEnd = (data['task_end'] is Timestamp) 
          ? (data['task_end'] as Timestamp).toDate() 
          : data['task_end'] as DateTime?;
      
      final taskDate = (data['task_date'] is Timestamp) 
          ? (data['task_date'] as Timestamp).toDate() 
          : data['task_date'] as DateTime?;
      
      if (taskEnd != null && taskDate != null) {
        // Combine date and time
        final taskEndDateTime = DateTime(
          taskDate.year,
          taskDate.month,
          taskDate.day,
          taskEnd.hour,
          taskEnd.minute,
        );
        
        // Check if task is overdue
        if (now.isAfter(taskEndDateTime)) {
          print('⏰ Found missed task: ${data['task_description']} - Marking as missed');
          
          // Update task status to Missed
          await doc.reference.update({
            'task_status': ['Missed'],
            'last_updated': FieldValue.serverTimestamp(),
          });
          
          // Create task log using proper shift log service
          await CaregiverShiftLogService.createTaskLog(
            taskId: doc.id,
            caregiverId: data['caregiver_id'] ?? '',
            elderlyId: data['elderly_id'] ?? '',
            elderlyFname: data['elderly_fname'] ?? '',
            taskDescription: data['task_description'] ?? '',
            status: 'Missed',
            taskDate: taskDate,
            reason: 'Task marked as missed by background system',
          );
          
          missedCount++;
        }
      }
    }
    
    print('✅ Background check complete. Marked $missedCount tasks as missed.');
  } catch (e) {
    print('❌ Error checking missed tasks: $e');
    rethrow;
  }
}

class TaskReminderService {
  static final TaskReminderService _instance = TaskReminderService._internal();
  factory TaskReminderService() => _instance;
  TaskReminderService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  
  // Keep track of active timers to prevent garbage collection
  final List<Timer> _activeTimers = [];

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize timezone data
      tz.initializeTimeZones();
      
      // Set the local timezone - critical for scheduled notifications
      final String timeZoneName = DateTime.now().timeZoneName;
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Manila'));
        print('✅ Timezone set to Asia/Manila');
      } catch (e) {
        print('⚠️ Could not set Manila timezone, using system timezone: $timeZoneName');
        // Try to use system timezone
        try {
          tz.setLocalLocation(tz.getLocation(timeZoneName));
        } catch (e2) {
          print('⚠️ Using UTC as fallback timezone');
          tz.setLocalLocation(tz.UTC);
        }
      }
      
      // Initialize local notifications
      await _initializeLocalNotifications();
      
      // Initialize background tasks
      if (Platform.isAndroid) {
        await _initializeAndroidServices();
      }
      
      // Request permissions
      await _requestPermissions();
      
      _isInitialized = true;
      // Service initialized successfully
    } catch (e) {
      // Error initializing service - will not show notifications
    }
  }

  /// Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    try {
      print('🔧 Initializing local notifications...');
      
      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      final bool? initialized = await _notificationsPlugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      print('📱 Notification plugin initialized: $initialized');

      // Create notification channels for Android
      if (Platform.isAndroid) {
        await _createNotificationChannels();
      }
      
      print('✅ Local notifications initialization complete');
    } catch (e) {
      print('❌ Error initializing local notifications: $e');
      print('❌ Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Create Android notification channels
  Future<void> _createNotificationChannels() async {
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidImplementation == null) {
      print('⚠️ Android implementation not available');
      return;
    }

    // Test channel for debugging
    const AndroidNotificationChannel testChannel = AndroidNotificationChannel(
      'test_channel',
      'Test Notifications',
      description: 'Test notifications to verify system is working',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    const AndroidNotificationChannel taskReminderChannel = AndroidNotificationChannel(
      'task_reminders',
      'Task Reminders',
      description: 'Notifications for upcoming tasks',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    const AndroidNotificationChannel taskAlarmChannel = AndroidNotificationChannel(
      'task_alarms',
      'Task Alarms',
      description: 'Alarm notifications for task start times',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );

    try {
      await androidImplementation.createNotificationChannel(testChannel);
      await androidImplementation.createNotificationChannel(taskReminderChannel);
      await androidImplementation.createNotificationChannel(taskAlarmChannel);
      print('✅ Notification channels created successfully');
    } catch (e) {
      print('❌ Error creating notification channels: $e');
    }
  }

  /// Initialize Android-specific services
  Future<void> _initializeAndroidServices() async {
    try {
      print('🔧 Initializing Android alarm manager...');
      await AndroidAlarmManager.initialize();
      print('✅ Android alarm manager initialized');
      
      // Initialize WorkManager for background task checking
      print('🔧 Initializing WorkManager for background tasks...');
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false, // Set to true for debugging
      );
      
      // Register periodic task to check for missed tasks every 15 minutes
      await Workmanager().registerPeriodicTask(
        'check-missed-tasks',
        'checkMissedTasks',
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      
      print('✅ WorkManager initialized and periodic task registered');
      print('✅ All Android services initialized');
    } catch (e) {
      print('❌ Error initializing Android services: $e');
      print('❌ Stack trace: ${StackTrace.current}');
      // Don't rethrow, notifications can still work without background services
    }
  }

  /// Request necessary permissions
  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      final notificationStatus = await Permission.notification.request();
      final alarmStatus = await Permission.scheduleExactAlarm.request();
      final batteryStatus = await Permission.ignoreBatteryOptimizations.request();
      
      print('📱 Permission Status:');
      print('  Notification: $notificationStatus');
      print('  Exact Alarm: $alarmStatus');
      print('  Battery Optimization: $batteryStatus');
      
      if (notificationStatus != PermissionStatus.granted) {
        print('⚠️ Notification permission not granted - notifications may not work');
      }
    }
  }

  /// Schedule comprehensive reminders for a task using timer-based approach
  Future<void> scheduleTaskReminders({
    required String taskId,
    required DateTime taskStartTime,
    required DateTime taskEndTime,
    required String taskTitle,
    required String elderlyName,
    String? taskDescription,
  }) async {
    print('🚀 scheduleTaskReminders called for: $taskTitle');
    print('🔧 Service initialized: $_isInitialized');
    
    if (!_isInitialized) {
      print('❌ TaskReminderService not initialized - attempting to initialize...');
      await initialize();
      if (!_isInitialized) {
        print('❌ Failed to initialize TaskReminderService');
        return;
      }
    }

    try {
      // Cancel any existing reminders for this task
      await cancelTaskReminders(taskId);

      final now = DateTime.now();
      print('⏰ Current time: $now');
      print('⏰ Task start time: $taskStartTime');
      
      // Don't schedule reminders for past times
      if (taskStartTime.isBefore(now)) {
        print('⚠️ Task start time is in the past, skipping reminder scheduling');
        return;
      }

      print('📅 Scheduling comprehensive reminders for task: $taskTitle');
      print('   - Task ID: $taskId');
      print('   - Elderly: $elderlyName');
      print('   - Start: $taskStartTime');
      print('   - End: $taskEndTime');
      print('   - Active timers before scheduling: ${_activeTimers.length}');

      // 1. Schedule 10-minute pre-task warning (using timer approach)
      final tenMinBefore = taskStartTime.subtract(const Duration(minutes: 10));
      if (tenMinBefore.isAfter(now)) {
        final delay = tenMinBefore.difference(now);
        print('⏰ Scheduling 10-min pre-task warning in ${delay.inMinutes} minutes');
        
        final timer1 = Timer(delay, () async {
          await _showPreTaskNotification(
            taskId: taskId,
            elderlyName: elderlyName,
            taskStartTime: taskStartTime,
            taskTitle: taskTitle,
            taskDescription: taskDescription,
          );
        });
        _activeTimers.add(timer1);
      }

      // 2. Schedule task start notification (optional - can be removed if not needed)
      if (taskStartTime.isAfter(now)) {
        final delay = taskStartTime.difference(now);
        print('🚀 Scheduling task start notification in ${delay.inMinutes} minutes');
        
        final timer2 = Timer(delay, () async {
          await _showTaskStartNotification(
            taskId: taskId,
            elderlyName: elderlyName,
            taskStartTime: taskStartTime,
            taskTitle: taskTitle,
            taskDescription: taskDescription,
          );
        });
        _activeTimers.add(timer2);
      }

      // 3. Schedule task ending warning (10 minutes before end, only if task is still ongoing)
      final tenMinBeforeEnd = taskEndTime.subtract(const Duration(minutes: 10));
      print('🔍 Task ending calculation:');
      print('   - Task end time: $taskEndTime');
      print('   - 10 min before end: $tenMinBeforeEnd');
      print('   - Current time: $now');
      print('   - Is after now: ${tenMinBeforeEnd.isAfter(now)}');
      print('   - Is after start: ${tenMinBeforeEnd.isAfter(taskStartTime)}');
      
      if (tenMinBeforeEnd.isAfter(now) && tenMinBeforeEnd.isAfter(taskStartTime)) {
        final delay = tenMinBeforeEnd.difference(now);
        print('⏳ Scheduling task ending warning in ${delay.inMinutes} minutes (${delay.inSeconds} seconds)');
        
        final timer3 = Timer(delay, () async {
          print('🚨 EXECUTING task ending notification for: $taskTitle');
          // Check if task is still uncompleted before showing ending warning
          await _showTaskEndingNotification(
            taskId: taskId,
            elderlyName: elderlyName,
            taskStartTime: taskStartTime,
            taskTitle: taskTitle,
            taskDescription: taskDescription,
          );
        });
        _activeTimers.add(timer3);
      } else {
        print('⚠️ Task ending notification NOT scheduled - conditions not met');
      }

      // Schedule 5-minute warning
      final fiveMinBefore = taskStartTime.subtract(const Duration(minutes: 5));
      if (fiveMinBefore.isAfter(now)) {
        await _scheduleNotification(
          id: _generateNotificationId(taskId, 'remind_5'),
          scheduledDate: fiveMinBefore,
          title: '⏰ Task Starting Soon',
          body: '$taskTitle for $elderlyName starts in 5 minutes',
          payload: 'task_reminder:$taskId',
          channelId: 'task_reminders',
        );
      }

      // Schedule task start alarm
      await _scheduleNotification(
        id: _generateNotificationId(taskId, 'start'),
        scheduledDate: taskStartTime,
        title: '🚨 Task Starting Now!',
        body: '$taskTitle for $elderlyName',
        payload: 'task_start:$taskId',
        channelId: 'task_alarms',
        isAlarm: true,
      );

      // Schedule overdue reminder (15 minutes after start time)
      final overdueTime = taskStartTime.add(const Duration(minutes: 15));
      await _scheduleNotification(
        id: _generateNotificationId(taskId, 'overdue'),
        scheduledDate: overdueTime,
        title: '⚠️ Task Overdue',
        body: '$taskTitle for $elderlyName is overdue',
        payload: 'task_overdue:$taskId',
        channelId: 'task_alarms',
      );

      print('✅ Scheduled reminders for task: $taskTitle at ${taskStartTime.toString()}');
    } catch (e) {
      print('❌ Error scheduling task reminders: $e');
    }
  }

  /// Schedule a single notification
  Future<void> _scheduleNotification({
    required int id,
    required DateTime scheduledDate,
    required String title,
    required String body,
    required String payload,
    required String channelId,
    bool isAlarm = false,
  }) async {
    // Enhanced notification settings for better visibility
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      channelId == 'task_reminders' ? 'Task Reminders' : 'Task Alarms',
      channelDescription: 'Notifications for upcoming tasks',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      showWhen: true,
      when: scheduledDate.millisecondsSinceEpoch,
      usesChronometer: false,
      channelShowBadge: true,
      onlyAlertOnce: false,
      autoCancel: true,
    );

    final AndroidNotificationDetails alarmDetails = AndroidNotificationDetails(
      channelId,
      channelId == 'task_reminders' ? 'Task Reminders' : 'Task Alarms', 
      channelDescription: 'Alarm notifications for task start times',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      ongoing: false,
      autoCancel: true,
      showWhen: true,
      when: scheduledDate.millisecondsSinceEpoch,
      channelShowBadge: true,
      onlyAlertOnce: false,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    final NotificationDetails details = NotificationDetails(
      android: isAlarm ? alarmDetails : androidDetails,
      iOS: iosDetails,
    );

    // Use the properly initialized local timezone
    final tzScheduledDate = tz.TZDateTime.from(scheduledDate, tz.local);
    
    print('📅 Scheduling notification:');
    print('   - ID: $id');
    print('   - Title: $title');
    print('   - Scheduled for: $scheduledDate');
    print('   - TZ Scheduled for: $tzScheduledDate');
    print('   - Current time: ${DateTime.now()}');
    print('   - Time until notification: ${scheduledDate.difference(DateTime.now())}');
    
    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tzScheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
    
    print('✅ Notification scheduled successfully with ID: $id');

    // Note: Alarm sound will be played by the notification system, not immediately
  }



  /// Generate unique notification ID
  int _generateNotificationId(String taskId, String type) {
    return ('$taskId$type').hashCode.abs();
  }

  /// Cancel all reminders for a specific task
  Future<void> cancelTaskReminders(String taskId) async {
    try {
      final reminderIds = [
        _generateNotificationId(taskId, 'remind_15'),
        _generateNotificationId(taskId, 'remind_5'),
        _generateNotificationId(taskId, 'start'),
        _generateNotificationId(taskId, 'overdue'),
      ];

      for (final id in reminderIds) {
        await _notificationsPlugin.cancel(id);
      }

      print('✅ Cancelled reminders for task: $taskId');
    } catch (e) {
      print('❌ Error cancelling task reminders: $e');
    }
  }

  /// Cancel all active timers
  void cancelAllTimers() {
    for (final timer in _activeTimers) {
      timer.cancel();
    }
    _activeTimers.clear();
    print('✅ Cancelled ${_activeTimers.length} active timers');
  }

  /// Cancel all scheduled notifications
  Future<void> cancelAllReminders() async {
    try {
      await _notificationsPlugin.cancelAll();
      print('✅ Cancelled all reminders');
    } catch (e) {
      print('❌ Error cancelling all reminders: $e');
    }
  }

  // Removed alarm sound methods - notifications handle sound automatically

  /// Handle notification tap - Enhanced for new navigation requirements
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) {
      final parts = payload.split(':');
      if (parts.length == 2) {
        final screen = parts[0];
        final taskId = parts[1];
        
        print('🔔 Notification tapped: Navigate to $screen for task $taskId');
        
        // Handle different navigation requirements
        switch (screen) {
          case 'upcoming_tasks_screen':
            // Navigate to upcoming tasks screen (for pre-task, start, and ending notifications)
            _navigateToUpcomingTasks(taskId);
            break;
          case 'missed_tasks_screen':
            // Navigate to missed tasks screen (for missed task notifications)
            _navigateToMissedTasks(taskId);
            break;
          default:
            // Fallback - navigate to upcoming tasks
            _navigateToUpcomingTasks(taskId);
            break;
        }
      }
    }
  }

  /// Navigate to upcoming tasks screen
  void _navigateToUpcomingTasks(String taskId) {
    // This would typically navigate to the upcoming tasks screen
    // Implementation depends on your navigation structure
    print('📋 Navigating to upcoming tasks screen for task: $taskId');
    // TODO: Implement navigation to upcoming_tasks_screen
    // Example: Navigator.pushNamed(context, '/upcoming_tasks');
  }

  /// Navigate to missed tasks screen
  void _navigateToMissedTasks(String taskId) {
    // This would typically navigate to the missed tasks screen
    // Implementation depends on your navigation structure
    print('❌ Navigating to missed tasks screen for task: $taskId');
    // TODO: Implement navigation to missed_tasks_screen
    // Example: Navigator.pushNamed(context, '/missed_tasks');
  }

  /// Schedule reminders for recurring tasks
  Future<void> scheduleRecurringTaskReminders({
    required String taskId,
    required DateTime firstOccurrence,
    required String taskTitle,
    required String elderlyName,
    required String frequency,
    List<String>? customDays,
    String? taskDescription,
  }) async {
    try {
      // For now, schedule the first occurrence
      // Assume 30-minute task duration if not specified
      final taskEndTime = firstOccurrence.add(const Duration(minutes: 30));
      
      await scheduleTaskReminders(
        taskId: taskId,
        taskStartTime: firstOccurrence,
        taskEndTime: taskEndTime,
        taskTitle: taskTitle,
        elderlyName: elderlyName,
        taskDescription: taskDescription,
      );

      // TODO: Implement logic for scheduling future recurrences
      // This would depend on your specific recurring task logic
      print('✅ Scheduled recurring task reminders for: $taskTitle');
    } catch (e) {
      print('❌ Error scheduling recurring task reminders: $e');
    }
  }

  /// Update task reminders when task details change
  Future<void> updateTaskReminders({
    required String taskId,
    required DateTime newTaskStartTime,
    required String taskTitle,
    required String elderlyName,
    String? taskDescription,
  }) async {
    // Assume 30-minute task duration
    final taskEndTime = newTaskStartTime.add(const Duration(minutes: 30));
    
    await scheduleTaskReminders(
      taskId: taskId,
      taskStartTime: newTaskStartTime,
      taskEndTime: taskEndTime,
      taskTitle: taskTitle,
      elderlyName: elderlyName,
      taskDescription: taskDescription,
    );
  }

  /// Test notification to verify the system is working
  Future<void> showTestNotification() async {
    print('🧪 showTestNotification called');
    
    if (!_isInitialized) {
      print('🔧 Service not initialized, initializing now...');
      await initialize();
    }

    try {
      print('📱 Attempting to show test notification...');
      
      await _notificationsPlugin.show(
        999,
        '🧪 Test Notification',
        'TaskReminderService is working correctly! Time: ${DateTime.now().toString()}',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'test_channel',
            'Test Notifications',
            channelDescription: 'Test notifications to verify system is working',
            importance: Importance.high,
            priority: Priority.high,
            showWhen: true,
            enableVibration: true,
            playSound: true,
          ),
        ),
      );
      print('✅ Test notification sent successfully');
    } catch (e) {
      print('❌ Error sending test notification: $e');
      print('❌ Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Test scheduled notification using Timer approach (works around Android blocking)
  Future<void> showTestScheduledNotification() async {
    print('🧪 showTestScheduledNotification called - Using TIMER approach to bypass Android blocking');
    
    if (!_isInitialized) {
      print('🔧 Service not initialized, initializing now...');
      await initialize();
    }

    try {
      print('📱 SOLUTION: Using Dart Timer for 3-second delay instead of Android scheduling');
      
      // Show confirmation that timer is set
      await _notificationsPlugin.show(
        996,
        '⏱️ Timer Set!',
        'Timer-based notification will appear in 3 seconds...',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'task_reminders',
            'Task Reminders',
            channelDescription: 'Notifications for upcoming tasks',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
      
      print('✅ Timer confirmation sent - waiting 3 seconds...');
      
      // Use Timer instead of Android's scheduling
      Timer(const Duration(seconds: 3), () async {
        print('⏰ Timer triggered! Showing scheduled notification now');
        
        await _notificationsPlugin.show(
          995,
          '🎉 Timer Success!',
          'This notification was triggered by a Dart timer after 3 seconds! Time: ${DateTime.now().toString().substring(11,19)}',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'task_reminders',
              'Task Reminders',
              channelDescription: 'Notifications for upcoming tasks',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
            ),
          ),
        );
        
        print('✅ Timer-based notification sent successfully!');
      });
      
      print('✅ Timer set for 3 seconds - this should bypass Android scheduling issues');
      
    } catch (e) {
      print('❌ Error in timer-based scheduled notification: $e');
      print('❌ Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Check pending notifications for debugging
  /// Test immediate notification to verify service is working
  Future<void> testImmediateNotification() async {
    try {
      print('🧪 Testing immediate notification...');
      print('🔧 Service initialized: $_isInitialized');
      
      // Check if service is initialized
      if (!_isInitialized) {
        print('❌ Service not initialized, attempting to initialize...');
        await initialize();
      }
      
      // Check notification permissions
      await _checkNotificationPermissions();
      
      await _notificationsPlugin.show(
        999,
        '✅ Test Notification',
        'TaskReminderService is working! Current time: ${DateTime.now().toString().substring(11, 19)}',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'task_reminders',
            'Task Reminders',
            channelDescription: 'Test notifications',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
      
      print('✅ Test notification sent successfully');
    } catch (e) {
      print('❌ Error sending test notification: $e');
      print('❌ Stack trace: ${StackTrace.current}');
    }
  }

  /// Check notification permissions and status
  Future<void> _checkNotificationPermissions() async {
    try {
      print('🔍 Checking notification permissions...');
      
      // Check system notification permissions
      final notificationPermission = await Permission.notification.status;
      print('📱 Notification permission: $notificationPermission');
      
      if (notificationPermission != PermissionStatus.granted) {
        print('⚠️ Requesting notification permission...');
        final result = await Permission.notification.request();
        print('📱 Permission request result: $result');
      }
      
      // Check if notifications are enabled
      final bool? notificationsEnabled = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
      print('📱 Notifications enabled: $notificationsEnabled');
      
    } catch (e) {
      print('❌ Error checking permissions: $e');
    }
  }

  /// Test timer-based notification to verify timer approach works
  Future<void> testTimerNotification() async {
    try {
      print('🧪 Testing timer notification in 10 seconds...');
      
      final testTimer = Timer(const Duration(seconds: 10), () async {
        await _notificationsPlugin.show(
          998,
          '⏰ Timer Test Success!',
          'Timer-based notification is working! Time: ${DateTime.now().toString().substring(11, 19)}',
          NotificationDetails(
            android: AndroidNotificationDetails(
              'task_reminders',
              'Task Reminders',
              channelDescription: 'Timer test notifications',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
        );
        print('✅ Timer notification executed successfully');
      });
      _activeTimers.add(testTimer);
      
      print('✅ Timer notification scheduled for 10 seconds');
    } catch (e) {
      print('❌ Error scheduling timer notification: $e');
    }
  }

  /// Debug function to check service status
  Future<void> debugServiceStatus() async {
    print('🔍 === TASK REMINDER SERVICE DEBUG ===');
    print('🔧 Initialized: $_isInitialized');
    print('⏰ Active timers: ${_activeTimers.length}');
    print('📱 Current time: ${DateTime.now()}');
    
    try {
      // Check permissions
      await _checkNotificationPermissions();
      
      // Check pending notifications
      final pendingNotifications = await _notificationsPlugin.pendingNotificationRequests();
      print('📋 Pending notifications: ${pendingNotifications.length}');
      
      for (final notification in pendingNotifications) {
        print('   - ID: ${notification.id}, Title: ${notification.title}');
      }
      
    } catch (e) {
      print('❌ Error in debug check: $e');
    }
    print('🔍 === END DEBUG ===');
  }

  /// 1. Show pre-task notification (10 minutes before task starts)
  Future<void> _showPreTaskNotification({
    required String taskId,
    required String elderlyName,
    required DateTime taskStartTime,
    required String taskTitle,
    String? taskDescription,
  }) async {
    try {
      final timeString = _formatTime(taskStartTime);
      final title = '⏰ Upcoming Task Reminder';
      final body = 'You have an Upcoming Task for $elderlyName at $timeString\n${taskDescription ?? taskTitle}';
      
      // Create database notification for persistent storage with deduplication
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        try {
          await NotificationService().createTaskNotification(
            taskId: taskId,
            userId: currentUser.uid,
            userType: 'caregiver',
            elderlyName: elderlyName,
            taskDescription: taskDescription ?? taskTitle,
            type: NotificationType.shiftReminder,
            additionalInfo: 'Task reminder for $timeString',
          );
          print('✅ Database notification created for task reminder: $taskId');
        } catch (e) {
          print('❌ Error creating database notification: $e');
        }
      }
      
      await _notificationsPlugin.show(
        _generateNotificationId(taskId, 'pre_task'),
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'task_reminders',
            'Task Reminders',
            channelDescription: 'Pre-task reminder notifications',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
            category: AndroidNotificationCategory.reminder,
            autoCancel: true,
            showWhen: true,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'upcoming_tasks_screen:$taskId',
      );
      
      print('✅ Pre-task notification sent for: $taskTitle at $timeString');
    } catch (e) {
      print('❌ Error showing pre-task notification: $e');
    }
  }

  /// 2. Show task start notification (when task time begins)
  Future<void> _showTaskStartNotification({
    required String taskId,
    required String elderlyName,
    required DateTime taskStartTime,
    required String taskTitle,
    String? taskDescription,
  }) async {
    try {
      final timeString = _formatTime(taskStartTime);
      final title = '🚨 Task Starting Now!';
      final body = '${taskDescription ?? taskTitle} for $elderlyName is starting now at $timeString';
      
      // Create database notification when task starts (not when assigned)
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        try {
          await NotificationService().createTaskNotification(
            taskId: taskId,
            userId: currentUser.uid,
            userType: 'caregiver',
            elderlyName: elderlyName,
            taskDescription: taskDescription ?? taskTitle,
            type: NotificationType.taskAssigned,
            additionalInfo: 'Task starting at $timeString',
          );
          print('✅ Database notification created for task start: $taskId');
        } catch (e) {
          print('❌ Error creating database notification: $e');
        }
      }
      
      await _notificationsPlugin.show(
        _generateNotificationId(taskId, 'task_start'),
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'task_alarms',
            'Task Alarms',
            channelDescription: 'Task start notifications',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
            category: AndroidNotificationCategory.alarm,
            autoCancel: true,
            showWhen: true,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'upcoming_tasks_screen:$taskId',
      );
      
      print('✅ Task start notification sent for: $taskTitle at $timeString');
    } catch (e) {
      print('❌ Error showing task start notification: $e');
    }
  }

  /// 3. Show task ending notification (10 minutes before task ends, only if still ongoing)
  Future<void> _showTaskEndingNotification({
    required String taskId,
    required String elderlyName,
    required DateTime taskStartTime,
    required String taskTitle,
    String? taskDescription,
  }) async {
    try {
      print('🚨 TASK ENDING NOTIFICATION TRIGGERED for: $taskTitle');
      print('🔍 Checking task status before showing notification...');
      
      // First check if task is still ongoing (not completed/incomplete)
      final isTaskStillOngoing = await _checkTaskStatus(taskId);
      if (!isTaskStillOngoing) {
        print('ℹ️ Task $taskId already completed/marked, skipping ending notification');
        return;
      }
      
      print('✅ Task is still ongoing, showing ending notification');
      
      final timeString = _formatTime(taskStartTime);
      final title = '⏳ Ongoing Task Reminder';
      final body = 'You currently have an ongoing task for $elderlyName at $timeString. Don\'t miss it!\n${taskDescription ?? taskTitle}';
      
      print('📱 Sending task ending notification:');
      print('   Title: $title');
      print('   Body: $body');
      
      await _notificationsPlugin.show(
        _generateNotificationId(taskId, 'task_ending'),
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'task_reminders',
            'Task Reminders',
            channelDescription: 'Task ending reminder notifications',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
            category: AndroidNotificationCategory.reminder,
            autoCancel: true,
            showWhen: true,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'upcoming_tasks_screen:$taskId',
      );
      
      print('✅ Task ending notification sent for: $taskTitle at $timeString');
    } catch (e) {
      print('❌ Error showing task ending notification: $e');
      print('❌ Stack trace: ${StackTrace.current}');
    }
  }

  /// 4. Show missed task notification (when task moves to missed status)
  Future<void> showMissedTaskNotification({
    required String taskId,
    required String elderlyName,
    required DateTime taskStartTime,
    required String taskTitle,
    String? taskDescription,
  }) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      final timeString = _formatTime(taskStartTime);
      final title = '❌ Task Missed';
      final body = 'You have missed a task for $elderlyName at $timeString\n${taskDescription ?? taskTitle}';
      

      await _notificationsPlugin.show(
        _generateNotificationId(taskId, 'missed'),
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'task_reminders',
            'Task Reminders',
            channelDescription: 'Missed task notifications',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
            category: AndroidNotificationCategory.reminder,
            autoCancel: true,
            showWhen: true,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'missed_tasks_screen:$taskId',
      );
      
      print('✅ Sent missed task notification for: $taskTitle at $timeString');
    } catch (e) {
      print('❌ Error showing missed task notification: $e');
    }
  }

  /// Check if task is still ongoing (not completed/incomplete)
  Future<bool> _checkTaskStatus(String taskId) async {
    try {
      print('🔍 Checking status for task: $taskId');
      
      final taskDoc = await FirebaseFirestore.instance
          .collection('care_tasks')
          .doc(taskId)
          .get();
      
      if (!taskDoc.exists) {
        print('⚠️ Task $taskId no longer exists');
        return false;
      }
      
      final taskData = taskDoc.data();
      if (taskData == null) {
        print('⚠️ Task $taskId has no data');
        return false;
      }
      
      final taskStatus = List<String>.from(taskData['task_status'] ?? []);
      
      print('📋 Current task status: $taskStatus');
      
      // Return true if task is still ongoing (not completed/incomplete/missed)
      final isOngoing = !taskStatus.contains('Complete') && 
                       !taskStatus.contains('Incomplete') && 
                       !taskStatus.contains('Missed');
      
      print('📋 Task $taskId status check: ongoing=$isOngoing, status=$taskStatus');
      return isOngoing;
    } catch (e) {
      print('❌ Error checking task status for $taskId: $e');
      print('❌ Stack trace: ${StackTrace.current}');
      return false;
    }
  }

  /// Format time for display
  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  /// Schedule reminders for all upcoming tasks in the system
  Future<void> scheduleAllUpcomingTaskReminders() async {
    try {
      final now = DateTime.now();
      final oneWeekLater = now.add(const Duration(days: 7));
      
      print('🔍 Looking for upcoming tasks between $now and $oneWeekLater');
      
      // Query all upcoming tasks in the next week
      final tasksQuery = await FirebaseFirestore.instance
          .collection('care_tasks')
          .where('task_status', arrayContains: 'Upcoming')
          .where('task_start', isGreaterThan: Timestamp.fromDate(now))
          .where('task_start', isLessThan: Timestamp.fromDate(oneWeekLater))
          .get();

      print('📋 Found ${tasksQuery.docs.length} upcoming tasks to schedule reminders for');
      
      int scheduledCount = 0;
      for (final doc in tasksQuery.docs) {
        try {
          final data = doc.data();
          final taskStart = (data['task_start'] as Timestamp).toDate();
          final taskDescription = data['task_description'] ?? 'Task';
          final elderlyName = data['elderly_fname'] ?? data['elderly_name'] ?? 'Elderly';
          
          // Create full task start datetime by combining task_date with task_start time
          final taskDate = data['task_date'] != null 
              ? (data['task_date'] as Timestamp).toDate()
              : taskStart;
              
          final fullTaskStartTime = DateTime(
            taskDate.year,
            taskDate.month, 
            taskDate.day,
            taskStart.hour,
            taskStart.minute,
          );
          
          print('📅 Scheduling reminders for task: $taskDescription at $fullTaskStartTime');
          
          // Add default 30-minute task duration if end time not available
          final taskEndTime = fullTaskStartTime.add(const Duration(minutes: 30));
          
          await scheduleTaskReminders(
            taskId: doc.id,
            taskStartTime: fullTaskStartTime,
            taskEndTime: taskEndTime,
            taskTitle: taskDescription,
            elderlyName: elderlyName,
            taskDescription: taskDescription,
          );
          
          scheduledCount++;
        } catch (e) {
          print('❌ Error scheduling reminder for task ${doc.id}: $e');
        }
      }
      
      print('✅ Successfully scheduled reminders for $scheduledCount/$tasksQuery.docs.length} tasks');
    } catch (e) {
      print('❌ Error scheduling all upcoming task reminders: $e');
      print('❌ Stack trace: ${StackTrace.current}');
    }
  }

  /// Check for upcoming tasks and ensure reminders are scheduled
  Future<void> syncTaskReminders(String caregiverId) async {
    try {
      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));
      
      // Query tasks for the next 24 hours
      final tasksQuery = await FirebaseFirestore.instance
          .collection('care_tasks')
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('task_start', isGreaterThan: Timestamp.fromDate(now))
          .where('task_start', isLessThan: Timestamp.fromDate(tomorrow))
          .where('task_status', arrayContains: 'Upcoming')
          .get();

      for (final doc in tasksQuery.docs) {
        final data = doc.data();
        final taskStart = (data['task_start'] as Timestamp).toDate();
        
        // Add default 30-minute task duration if end time not available
        final taskEndTime = taskStart.add(const Duration(minutes: 30));
        
        await scheduleTaskReminders(
          taskId: doc.id,
          taskStartTime: taskStart,
          taskEndTime: taskEndTime,
          taskTitle: data['task_description'] ?? 'Task',
          elderlyName: data['elderly_fname'] ?? 'Elderly',
          taskDescription: data['task_description'],
        );
      }
      
      print('✅ Synced reminders for ${tasksQuery.docs.length} upcoming tasks');
    } catch (e) {
      print('❌ Error syncing task reminders: $e');
    }
  }
}

