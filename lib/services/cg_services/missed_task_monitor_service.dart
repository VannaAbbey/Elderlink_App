import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_service.dart';
import 'caregiver_shift_log_service.dart';
import '../../models/cg_models/notification_model.dart';

/// Global service that continuously monitors tasks and marks them as missed
/// This service runs across all screens and doesn't require WorkManager
class MissedTaskMonitorService {
  static final MissedTaskMonitorService _instance = MissedTaskMonitorService._internal();
  factory MissedTaskMonitorService() => _instance;
  MissedTaskMonitorService._internal();

  Timer? _monitorTimer;
  StreamSubscription<QuerySnapshot>? _taskSubscription;
  bool _isMonitoring = false;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  /// Getter to check if monitoring is active
  bool get isMonitoring => _isMonitoring;

  /// Start monitoring for missed tasks
  /// This runs every 30 seconds to check for overdue tasks
  Future<void> startMonitoring() async {
    if (_isMonitoring) {
      print('⚠️ Missed task monitor already running');
      return;
    }

    print('🔄 Starting missed task monitor service...');
    _isMonitoring = true;

    // Initial check
    await _checkMissedTasks();

    // Set up periodic checking every 30 seconds
    _monitorTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      await _checkMissedTasks();
    });

    // Also set up real-time Firestore listener for immediate updates
    _setupRealtimeListener();

    print('✅ Missed task monitor service started');
  }

  /// Stop monitoring
  void stopMonitoring() {
    print('🛑 Stopping missed task monitor service...');
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _taskSubscription?.cancel();
    _taskSubscription = null;
    _isMonitoring = false;
    print('✅ Missed task monitor service stopped');
  }

  /// Set up real-time Firestore listener to detect tasks as they become overdue
  void _setupRealtimeListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _taskSubscription = FirebaseFirestore.instance
        .collection('care_tasks')
        .where('task_status', arrayContains: 'Upcoming')
        .where('caregiver_id', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) {
      // When tasks change, check immediately
      _checkMissedTasks();
    });
  }

  /// Check all upcoming tasks and mark overdue ones as missed
  Future<void> _checkMissedTasks() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('⚠️ No user logged in, stopping missed task monitor');
        stopMonitoring(); // Stop monitoring if user is null
        return;
      }

      final now = DateTime.now();
      
      // Query upcoming tasks for current user
      final tasksSnapshot = await FirebaseFirestore.instance
          .collection('care_tasks')
          .where('task_status', arrayContains: 'Upcoming')
          .where('caregiver_id', isEqualTo: user.uid)
          .get();

      int missedCount = 0;

      for (var doc in tasksSnapshot.docs) {
        final data = doc.data();
        
        // Get task timing information
        final taskEnd = (data['task_end'] is Timestamp) 
            ? (data['task_end'] as Timestamp).toDate() 
            : data['task_end'] as DateTime?;
        
        final taskDate = (data['task_date'] is Timestamp) 
            ? (data['task_date'] as Timestamp).toDate() 
            : data['task_date'] as DateTime?;

        if (taskEnd == null || taskDate == null) continue;

        // Combine date and time to get actual end DateTime
        final taskEndDateTime = DateTime(
          taskDate.year,
          taskDate.month,
          taskDate.day,
          taskEnd.hour,
          taskEnd.minute,
        );

        // Check if task is overdue
        if (now.isAfter(taskEndDateTime)) {
          print('⏰ MISSED TASK DETECTED: ${data['task_description']} ended at ${_formatTime(taskEndDateTime)}');
          
          // Mark task as missed
          await _markTaskAsMissed(doc.id, data, taskEndDateTime);
          missedCount++;
        }
      }

      if (missedCount > 0) {
        print('✅ Marked $missedCount task(s) as missed');
      }
    } catch (e) {
      print('❌ Error checking missed tasks: $e');
    }
  }

  /// Mark a specific task as missed
  Future<void> _markTaskAsMissed(String docId, Map<String, dynamic> data, DateTime taskEndDateTime) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Update task status to Missed
      await FirebaseFirestore.instance
          .collection('care_tasks')
          .doc(docId)
          .update({
        'task_status': ['Missed'],
        'last_updated': FieldValue.serverTimestamp(),
        'marked_missed_at': FieldValue.serverTimestamp(),
        'marked_by': 'monitor_service',
      });

      // Create task log entry
      await _createTaskLog(docId, data);

      // Send notification to user
      await _sendMissedTaskNotification(data, taskEndDateTime);

      print('✅ Task ${data['task_description']} marked as missed successfully');
    } catch (e) {
      print('❌ Error marking task as missed: $e');
    }
  }

  /// Create a task log entry
  Future<void> _createTaskLog(String taskId, Map<String, dynamic> taskData) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final taskDate = (taskData['task_date'] is Timestamp)
          ? (taskData['task_date'] as Timestamp).toDate()
          : (taskData['task_date'] as DateTime?) ?? DateTime.now();

      // Use CaregiverShiftLogService to create task log in the correct collection
      await CaregiverShiftLogService.createTaskLog(
        taskId: taskId,
        caregiverId: user.uid,
        elderlyId: taskData['elderly_id'] ?? '',
        elderlyFname: taskData['elderly_fname'] ?? 'Unknown',
        taskDescription: taskData['task_description'] ?? 'Unknown Task',
        status: 'Missed',
        taskDate: taskDate,
        reason: 'Task ended without completion',
      );

      print('✅ Task log created for missed task');
    } catch (e) {
      print('❌ Error creating task log: $e');
    }
  }

  /// Send notification about missed task
  Future<void> _sendMissedTaskNotification(Map<String, dynamic> taskData, DateTime taskEndDateTime) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final taskDescription = taskData['task_description'] ?? 'Task';
      final elderlyName = taskData['elderly_fname'] ?? 'Elderly';
      final taskTime = _formatTime(taskEndDateTime);

      // Create Firestore notification
      final notificationId = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}_task_missed_$elderlyName';
      
      await NotificationService().createNotification(
        userId: user.uid,
        title: '⚠️ Missed Task',
        message: 'You missed "$taskDescription" for $elderlyName at $taskTime',
        type: NotificationType.taskMissed,
        taskId: taskData['task_id'],
        elderlyId: taskData['elderly_id'],
        priority: NotificationPriority.high,
      );

      // Send local push notification
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'task_reminders',
        'Task Reminders',
        channelDescription: 'Notifications for task reminders',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
      );

      await _notificationsPlugin.show(
        notificationId.hashCode,
        '⚠️ Missed Task',
        'You missed "$taskDescription" for $elderlyName at $taskTime',
        notificationDetails,
      );

      print('✅ Missed task notification sent');
    } catch (e) {
      print('❌ Error sending missed task notification: $e');
    }
  }

  /// Format time for display
  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$hour12:$minute $ampm';
  }
}