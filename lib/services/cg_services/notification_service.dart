import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/cg_models/notification_model.dart';
import 'notification_deduplication_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collection reference for app notifications (new collection)
  CollectionReference get _appNotificationsCollection => 
      _firestore.collection('app_notifications');

  /// Create a new notification in Firestore with duplicate prevention
  Future<String?> createNotification({
    required String title,
    required String message,
    required String userId,
    String userType = 'caregiver', // Default to caregiver for backward compatibility
    required NotificationType type,
    String? taskId,
    String? elderlyId,
    Map<String, dynamic>? metadata,
    String? referenceId,
    String? referenceType,
    NotificationPriority priority = NotificationPriority.normal,
    String? category,
    DateTime? expiresAt,
  }) async {
    try {
      // Check for recent duplicate notifications (within last 10 seconds)
      if (taskId != null || referenceId != null) {
        final recentCutoff = DateTime.now().subtract(const Duration(seconds: 10));
        Query query = _appNotificationsCollection
            .where('user_id', isEqualTo: userId)
            .where('notification_type', isEqualTo: type.value);
            
        if (taskId != null) {
          query = query.where('task_id', isEqualTo: taskId);
        }
        if (referenceId != null) {
          query = query.where('reference_id', isEqualTo: referenceId);
        }
        
        final existingNotifications = await query.get();
        
        // Check if any recent notification exists
        for (final doc in existingNotifications.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final timestamp = (data['notification_timestamp'] as Timestamp?)?.toDate();
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
        userId: userId,
        userType: userType,
        type: type,
        taskId: taskId,
        elderlyId: elderlyId,
        metadata: metadata,
        referenceId: referenceId,
        referenceType: referenceType,
        priority: priority,
        category: category,
        expiresAt: expiresAt,
      );

      final docRef = await _appNotificationsCollection.add(notification.toFirestore());
      return docRef.id;
    } catch (e) {
      return null;
    }
  }

  /// Get notifications stream for a specific user
  Stream<List<NotificationModel>> getNotificationsStream(String userId) {
    return _appNotificationsCollection
        .where('user_id', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final notifications = snapshot.docs.map((doc) {
        return NotificationModel.fromFirestore(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }).toList();
      
      // Filter out expired notifications
      final now = DateTime.now();
      final validNotifications = notifications.where((notification) {
        return notification.expiresAt == null || notification.expiresAt!.isAfter(now);
      }).toList();
      
      // Sort by timestamp in memory to avoid index requirement
      validNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return validNotifications;
    });
  }

  /// Get unread notifications count
  Stream<int> getUnreadNotificationsCount(String userId) {
    return _appNotificationsCollection
        .where('user_id', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      // Filter unread and non-expired notifications in memory to avoid index requirement
      return snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final isRead = data['is_read'] == true;
        final expiresAt = (data['expires_at'] as Timestamp?)?.toDate();
        final isExpired = expiresAt != null && expiresAt.isBefore(now);
        
        return !isRead && !isExpired;
      }).length;
    });
  }

  /// Mark a notification as read
  Future<bool> markNotificationAsRead(String notificationId) async {
    try {
      await _appNotificationsCollection.doc(notificationId).update({
        'is_read': true,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Mark all notifications as read for a user
  Future<bool> markAllNotificationsAsRead(String userId) async {
    try {
      final unreadNotifications = await _appNotificationsCollection
          .where('user_id', isEqualTo: userId)
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
      await _appNotificationsCollection.doc(notificationId).delete();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Delete old notifications (older than specified days)
  Future<bool> deleteOldNotifications(String userId, {int daysOld = 30}) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
      final oldNotifications = await _appNotificationsCollection
          .where('user_id', isEqualTo: userId)
          .where('notification_timestamp', isLessThan: Timestamp.fromDate(cutoffDate))
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
    required String userId, // Changed from caregiverId
    String userType = 'caregiver', // Default to caregiver
    required String elderlyName,
    required String taskDescription,
    required NotificationType type,
    String? additionalInfo,
  }) async {
    // Check if we should create this notification (deduplication)
    final shouldCreate = NotificationDeduplicationService().shouldCreateNotification(
      taskId: taskId,
      caregiverId: userId, // Still uses caregiverId internally for backward compatibility
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
      userId: userId,
      userType: userType,
      type: type,
      taskId: taskId,
      referenceId: taskId,
      referenceType: 'task',
      category: 'tasks',
      metadata: {
        'elderly_name': elderlyName,
        'task_description': taskDescription,
        'additional_info': additionalInfo,
        'notification_key': notificationKey,
      },
    );
  }

  /// Get current user's ID
  String? getCurrentUserId() {
    return _auth.currentUser?.uid;
  }

  /// Helper method to create shift reminder notifications
  Future<void> createShiftReminder({
    required String userId,
    String userType = 'caregiver',
    required String shiftTime,
    required String houseName,
  }) async {
    await createNotification(
      title: 'Shift Reminder',
      message: 'Your shift at $houseName starts at $shiftTime',
      userId: userId,
      userType: userType,
      type: NotificationType.shiftReminder,
      referenceType: 'shift',
      category: 'shifts',
      metadata: {
        'shift_time': shiftTime,
        'house_name': houseName,
      },
    );
  }

  /// Get notifications by type
  Stream<List<NotificationModel>> getNotificationsByType(
    String userId,
    NotificationType type,
  ) {
    return _appNotificationsCollection
        .where('user_id', isEqualTo: userId)
        .where('notification_type', isEqualTo: type.value)
        .snapshots()
        .map((snapshot) {
      final notifications = snapshot.docs.map((doc) {
        return NotificationModel.fromFirestore(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }).toList();
      
      // Filter out expired notifications
      final now = DateTime.now();
      final validNotifications = notifications.where((notification) {
        return notification.expiresAt == null || notification.expiresAt!.isAfter(now);
      }).toList();
      
      // Sort by timestamp in memory to avoid index requirement
      validNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return validNotifications;
    });
  }

  /// Get notifications for a specific date range
  Stream<List<NotificationModel>> getNotificationsByDateRange(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) {
    return _appNotificationsCollection
        .where('user_id', isEqualTo: userId)
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

  Future<void> createLeaveNotification({
    required String userId,
    String userType = 'caregiver',
    required String leaveRequestId,
    required NotificationType type,
    required String leaveDates,
    required String leaveType,
    String? approverName,
    String? reviewerComments,
    String? previousStatus,
    String? newStatus,
    NotificationPriority priority = NotificationPriority.normal,
  }) async {
    String title;
    String message;
    
    switch (type) {
      case NotificationType.leaveSubmitted:
        title = 'Leave Request Submitted';
        message = 'Your $leaveType leave request for $leaveDates has been submitted for approval';
        break;
      case NotificationType.leaveApproved:
        title = 'Leave Request Approved';
        message = 'Your $leaveType leave for $leaveDates has been approved';
        if (approverName != null) {
          message += ' by $approverName';
        }
        if (reviewerComments != null && reviewerComments.isNotEmpty) {
          message += '.\n\n💬 Comment: $reviewerComments';
        }
        break;
      case NotificationType.leaveDenied:
        title = 'Leave Request Denied';
        message = 'Your $leaveType leave request for $leaveDates has been denied';
        if (approverName != null) {
          message += ' by $approverName';
        }
        if (reviewerComments != null && reviewerComments.isNotEmpty) {
          message += '.\n\n💬 Reason: $reviewerComments';
        } else {
          message += '.\n\nPlease contact your supervisor for more details.';
        }
        break;
      case NotificationType.leaveModified:
        title = 'Leave Request Modified';
        message = 'Your $leaveType leave request for $leaveDates has been modified';
        break;
      case NotificationType.leaveCancelled:
        title = 'Leave Request Cancelled';
        message = 'Your $leaveType leave request for $leaveDates has been cancelled';
        break;
      default:
        title = 'Leave Request Update';
        message = 'Your leave request for $leaveDates has been updated';
    }

    await createNotification(
      title: title,
      message: message,
      userId: userId,
      userType: userType,
      type: type,
      referenceId: leaveRequestId,
      referenceType: 'leave_request',
      category: 'leave',
      priority: priority,
      metadata: {
        'leave_request_id': leaveRequestId,
        'leave_dates': leaveDates,
        'leave_type': leaveType,
        'approver_name': approverName,
        'reviewer_comments': reviewerComments,
        'previous_status': previousStatus,
        'new_status': newStatus,
      },
    );
  }
}