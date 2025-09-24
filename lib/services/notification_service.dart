import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/notification_model.dart';
import 'notification_deduplication_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collection reference for notifications
  CollectionReference get _notificationsCollection => 
      _firestore.collection('notifications');

  /// Create a new notification in Firestore with duplicate prevention
  Future<String?> createNotification({
    required String title,
    required String message,
    required String caregiverId,
    required NotificationType type,
    String? taskId,
    String? elderlyId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // Check for recent duplicate notifications (within last 10 seconds)
      if (taskId != null) {
        final recentCutoff = DateTime.now().subtract(const Duration(seconds: 10));
        final existingNotifications = await _notificationsCollection
            .where('caregiver_id', isEqualTo: caregiverId)
            .where('task_id', isEqualTo: taskId)
            .where('type', isEqualTo: type.value)
            .get();
        
        // Check if any recent notification exists
        for (final doc in existingNotifications.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
          if (timestamp != null && timestamp.isAfter(recentCutoff)) {
            return doc.id; // Return existing notification ID
          }
        }
      }

      final notification = NotificationModel(
        id: '', // Will be assigned by Firestore
        title: title,
        message: message,
        timestamp: DateTime.now(),
        caregiverId: caregiverId,
        type: type,
        taskId: taskId,
        elderlyId: elderlyId,
        metadata: metadata,
      );

      final docRef = await _notificationsCollection.add(notification.toFirestore());
      return docRef.id;
    } catch (e) {
      return null;
    }
  }

  /// Get notifications stream for a specific caregiver
  Stream<List<NotificationModel>> getNotificationsStream(String caregiverId) {
    return _notificationsCollection
        .where('caregiver_id', isEqualTo: caregiverId)
        .snapshots()
        .map((snapshot) {
      final notifications = snapshot.docs.map((doc) {
        return NotificationModel.fromFirestore(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }).toList();
      
      // Sort by timestamp in memory to avoid index requirement
      notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return notifications;
    });
  }

  /// Get unread notifications count
  Stream<int> getUnreadNotificationsCount(String caregiverId) {
    return _notificationsCollection
        .where('caregiver_id', isEqualTo: caregiverId)
        .snapshots()
        .map((snapshot) {
      // Filter unread notifications in memory to avoid index requirement
      return snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['is_read'] == false || data['is_read'] == null;
      }).length;
    });
  }

  /// Mark a notification as read
  Future<bool> markNotificationAsRead(String notificationId) async {
    try {
      await _notificationsCollection.doc(notificationId).update({
        'is_read': true,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Mark all notifications as read for a caregiver
  Future<bool> markAllNotificationsAsRead(String caregiverId) async {
    try {
      final unreadNotifications = await _notificationsCollection
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('is_read', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (final doc in unreadNotifications.docs) {
        batch.update(doc.reference, {'is_read': true});
      }

      await batch.commit();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Delete a notification
  Future<bool> deleteNotification(String notificationId) async {
    try {
      await _notificationsCollection.doc(notificationId).delete();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Delete old notifications (older than specified days)
  Future<bool> deleteOldNotifications(String caregiverId, {int daysOld = 30}) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
      final oldNotifications = await _notificationsCollection
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('timestamp', isLessThan: Timestamp.fromDate(cutoffDate))
          .get();

      final batch = _firestore.batch();
      for (final doc in oldNotifications.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Create task-related notifications with enhanced duplicate prevention
  Future<void> createTaskNotification({
    required String taskId,
    required String caregiverId,
    required String elderlyName,
    required String taskDescription,
    required NotificationType type,
    String? additionalInfo,
  }) async {
    // Check if we should create this notification (deduplication)
    final shouldCreate = NotificationDeduplicationService().shouldCreateNotification(
      taskId: taskId,
      caregiverId: caregiverId,
      notificationType: type.value,
      additionalKey: elderlyName,
    );
    
    if (!shouldCreate) {
      return;
    }
    
    // Create a unique key for this notification to prevent exact duplicates
    final notificationKey = '${taskId}_${type.value}_${DateTime.now().millisecondsSinceEpoch ~/ 10000}'; // 10-second window
    
    String title;
    String message;

    switch (type) {
      case NotificationType.taskAssigned:
        title = 'New Task Assigned';
        message = 'You have a new task: "$taskDescription" for $elderlyName';
        break;
      case NotificationType.taskCompleted:
        title = 'Task Completed';
        message = 'Task "$taskDescription" for $elderlyName has been completed';
        break;
      case NotificationType.taskMissed:
        title = 'Task Missed';
        message = 'Task "$taskDescription" for $elderlyName was missed';
        break;
      case NotificationType.taskUpdated:
        title = 'Task Updated';
        message = 'Task "$taskDescription" for $elderlyName has been updated';
        if (additionalInfo != null) {
          message += '. $additionalInfo';
        }
        break;
      case NotificationType.taskDeleted:
        title = 'Task Deleted';
        message = 'Task "$taskDescription" for $elderlyName has been deleted';
        break;
      default:
        title = 'Task Notification';
        message = 'Task "$taskDescription" for $elderlyName - ${type.displayName}';
    }

    await createNotification(
      title: title,
      message: message,
      caregiverId: caregiverId,
      type: type,
      taskId: taskId,
      metadata: {
        'elderly_name': elderlyName,
        'task_description': taskDescription,
        'additional_info': additionalInfo,
        'notification_key': notificationKey,
      },
    );
  }

  /// Get current user's caregiver ID
  String? getCurrentCaregiverId() {
    return _auth.currentUser?.uid;
  }

  /// Helper method to create shift reminder notifications
  Future<void> createShiftReminder({
    required String caregiverId,
    required String shiftTime,
    required String houseName,
  }) async {
    await createNotification(
      title: 'Shift Reminder',
      message: 'Your shift at $houseName starts at $shiftTime',
      caregiverId: caregiverId,
      type: NotificationType.shiftReminder,
      metadata: {
        'shift_time': shiftTime,
        'house_name': houseName,
      },
    );
  }

  /// Get notifications by type
  Stream<List<NotificationModel>> getNotificationsByType(
    String caregiverId,
    NotificationType type,
  ) {
    return _notificationsCollection
        .where('caregiver_id', isEqualTo: caregiverId)
        .where('type', isEqualTo: type.value)
        .snapshots()
        .map((snapshot) {
      final notifications = snapshot.docs.map((doc) {
        return NotificationModel.fromFirestore(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }).toList();
      
      // Sort by timestamp in memory to avoid index requirement
      notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return notifications;
    });
  }

  /// Get notifications for a specific date range
  Stream<List<NotificationModel>> getNotificationsByDateRange(
    String caregiverId,
    DateTime startDate,
    DateTime endDate,
  ) {
    return _notificationsCollection
        .where('caregiver_id', isEqualTo: caregiverId)
        .snapshots()
        .map((snapshot) {
      final notifications = snapshot.docs.map((doc) {
        return NotificationModel.fromFirestore(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }).toList();
      
      // Filter by date range in memory to avoid index requirement
      final filtered = notifications.where((notification) {
        return notification.timestamp.isAfter(startDate.subtract(const Duration(days: 1))) &&
               notification.timestamp.isBefore(endDate.add(const Duration(days: 1)));
      }).toList();
      
      // Sort by timestamp in memory
      filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return filtered;
    });
  }
}