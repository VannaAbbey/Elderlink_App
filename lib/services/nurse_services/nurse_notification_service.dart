import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/cg_models/notification_model.dart';

class NurseNotificationService {
  static final NurseNotificationService _instance =
      NurseNotificationService._internal();
  factory NurseNotificationService() => _instance;
  NurseNotificationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection reference for app notifications (reusing same collection as caregivers)
  CollectionReference get _appNotificationsCollection =>
      _firestore.collection('app_notifications');

  /// Create a new leave request notification for nurses
  Future<String?> createLeaveNotification({
    required String title,
    required String message,
    required String userId,
    required NotificationType type,
    String? leaveRequestId,
    Map<String, dynamic>? metadata,
    NotificationPriority priority = NotificationPriority.normal,
  }) async {
    try {
      // Check for recent duplicate notifications (within last 10 seconds)
      if (leaveRequestId != null) {
        final recentCutoff = DateTime.now().subtract(
          const Duration(seconds: 10),
        );
        Query query = _appNotificationsCollection
            .where('user_id', isEqualTo: userId)
            .where('user_type', isEqualTo: 'nurse')
            .where('notification_type', isEqualTo: type.value)
            .where('reference_id', isEqualTo: leaveRequestId);

        final existingNotifications = await query.get();

        // Check if any recent notification exists
        for (final doc in existingNotifications.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final timestamp = (data['notification_timestamp'] as Timestamp?)
              ?.toDate();
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
        userType: 'nurse',
        type: type,
        metadata: metadata,
        referenceId: leaveRequestId,
        referenceType: 'leave_request',
        priority: priority,
        category: 'leave_management',
      );

      final docRef = await _appNotificationsCollection.add(
        notification.toFirestore(),
      );
      return docRef.id;
    } catch (e) {
      return null;
    }
  }

  /// Get leave request notifications stream for a specific nurse
  Stream<List<NotificationModel>> getLeaveNotificationsStream(String nurseId) {
    return _appNotificationsCollection
        .where('user_id', isEqualTo: nurseId)
        .where('user_type', isEqualTo: 'nurse')
        .snapshots()
        .map((snapshot) {
          final notifications = snapshot.docs.map((doc) {
            return NotificationModel.fromFirestore(
              doc.data() as Map<String, dynamic>,
              doc.id,
            );
          }).toList();

          // Filter out expired notifications and only leave-related ones
          final now = DateTime.now();
          final leaveNotifications = notifications.where((notification) {
            final isNotExpired =
                notification.expiresAt == null ||
                notification.expiresAt!.isAfter(now);
            final isLeaveRelated = [
              NotificationType.leaveSubmitted,
              NotificationType.leaveApproved,
              NotificationType.leaveDenied,
              NotificationType.leaveModified,
              NotificationType.leaveCancelled,
            ].contains(notification.type);

            return isNotExpired && isLeaveRelated;
          }).toList();

          // Sort by timestamp in memory to avoid index requirement
          leaveNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          return leaveNotifications;
        });
  }

  /// Get unread leave notifications count for nurses
  Stream<int> getUnreadLeaveNotificationsCount(String nurseId) {
    return _appNotificationsCollection
        .where('user_id', isEqualTo: nurseId)
        .where('user_type', isEqualTo: 'nurse')
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          // Filter unread, non-expired leave notifications in memory
          return snapshot.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final isRead = data['is_read'] == true;
            final expiresAt = (data['expires_at'] as Timestamp?)?.toDate();
            final isExpired = expiresAt != null && expiresAt.isBefore(now);

            // Check if it's a leave-related notification
            final notificationType = data['notification_type'] ?? '';
            final isLeaveRelated = [
              'leave_submitted',
              'leave_approved',
              'leave_denied',
              'leave_modified',
              'leave_cancelled',
            ].contains(notificationType);

            return !isRead && !isExpired && isLeaveRelated;
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

  /// Mark all leave notifications as read for a nurse
  Future<bool> markAllLeaveNotificationsAsRead(String nurseId) async {
    try {
      final unreadNotifications = await _appNotificationsCollection
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_read', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (final doc in unreadNotifications.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final notificationType = data['notification_type'] ?? '';
        final isLeaveRelated = [
          'leave_submitted',
          'leave_approved',
          'leave_denied',
          'leave_modified',
          'leave_cancelled',
        ].contains(notificationType);

        if (isLeaveRelated) {
          batch.update(doc.reference, {'is_read': true});
        }
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
}
