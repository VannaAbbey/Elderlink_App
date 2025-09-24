import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final String? taskId;
  final String? elderlyId;
  final String caregiverId;
  final NotificationType type;
  final Map<String, dynamic>? metadata;

  NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.taskId,
    this.elderlyId,
    required this.caregiverId,
    required this.type,
    this.metadata,
  });

  factory NotificationModel.fromFirestore(Map<String, dynamic> data, String id) {
    return NotificationModel(
      id: id,
      title: data['title'] ?? '',
      message: data['message'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['is_read'] ?? false,
      taskId: data['task_id'],
      elderlyId: data['elderly_id'],
      caregiverId: data['caregiver_id'] ?? '',
      type: NotificationTypeExtension.fromString(data['type'] ?? 'general'),
      metadata: data['metadata'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'message': message,
      'timestamp': Timestamp.fromDate(timestamp),
      'is_read': isRead,
      'task_id': taskId,
      'elderly_id': elderlyId,
      'caregiver_id': caregiverId,
      'type': type.value,
      'metadata': metadata,
    };
  }

  NotificationModel copyWith({
    String? id,
    String? title,
    String? message,
    DateTime? timestamp,
    bool? isRead,
    String? taskId,
    String? elderlyId,
    String? caregiverId,
    NotificationType? type,
    Map<String, dynamic>? metadata,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      taskId: taskId ?? this.taskId,
      elderlyId: elderlyId ?? this.elderlyId,
      caregiverId: caregiverId ?? this.caregiverId,
      type: type ?? this.type,
      metadata: metadata ?? this.metadata,
    );
  }
}

enum NotificationType {
  taskAssigned,
  taskCompleted,
  taskMissed,
  taskUpdated,
  taskDeleted,
  shiftReminder,
  general,
}

extension NotificationTypeExtension on NotificationType {
  String get displayName {
    switch (this) {
      case NotificationType.taskAssigned:
        return 'Task Assigned';
      case NotificationType.taskCompleted:
        return 'Task Completed';
      case NotificationType.taskMissed:
        return 'Task Missed';
      case NotificationType.taskUpdated:
        return 'Task Updated';
      case NotificationType.taskDeleted:
        return 'Task Deleted';
      case NotificationType.shiftReminder:
        return 'Shift Reminder';
      case NotificationType.general:
        return 'General';
    }
  }

  String get iconName {
    switch (this) {
      case NotificationType.taskAssigned:
        return 'assignment';
      case NotificationType.taskCompleted:
        return 'check_circle';
      case NotificationType.taskMissed:
        return 'error';
      case NotificationType.taskUpdated:
        return 'edit';
      case NotificationType.taskDeleted:
        return 'delete';
      case NotificationType.shiftReminder:
        return 'schedule';
      case NotificationType.general:
        return 'info';
    }
  }

  static NotificationType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'taskassigned':
      case 'task_assigned':
        return NotificationType.taskAssigned;
      case 'taskcompleted':
      case 'task_completed':
        return NotificationType.taskCompleted;
      case 'taskmissed':
      case 'task_missed':
        return NotificationType.taskMissed;
      case 'taskupdated':
      case 'task_updated':
        return NotificationType.taskUpdated;
      case 'taskdeleted':
      case 'task_deleted':
        return NotificationType.taskDeleted;
      case 'shiftreminder':
      case 'shift_reminder':
        return NotificationType.shiftReminder;
      default:
        return NotificationType.general;
    }
  }

  String get value {
    switch (this) {
      case NotificationType.taskAssigned:
        return 'task_assigned';
      case NotificationType.taskCompleted:
        return 'task_completed';
      case NotificationType.taskMissed:
        return 'task_missed';
      case NotificationType.taskUpdated:
        return 'task_updated';
      case NotificationType.taskDeleted:
        return 'task_deleted';
      case NotificationType.shiftReminder:
        return 'shift_reminder';
      case NotificationType.general:
        return 'general';
    }
  }
}