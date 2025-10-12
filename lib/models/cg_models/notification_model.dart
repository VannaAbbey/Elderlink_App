import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationPriority {
  low,
  normal,
  high,
  urgent,
}

extension NotificationPriorityExtension on NotificationPriority {
  String get value {
    switch (this) {
      case NotificationPriority.low:
        return 'low';
      case NotificationPriority.normal:
        return 'normal';
      case NotificationPriority.high:
        return 'high';
      case NotificationPriority.urgent:
        return 'urgent';
    }
  }

  static NotificationPriority fromString(String value) {
    switch (value.toLowerCase()) {
      case 'low':
        return NotificationPriority.low;
      case 'high':
        return NotificationPriority.high;
      case 'urgent':
        return NotificationPriority.urgent;
      default:
        return NotificationPriority.normal;
    }
  }
}

class NotificationModel {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final String? taskId; // Kept for backward compatibility
  final String? elderlyId;
  final String userId; // Replaces caregiverId - can be caregiver, nurse, admin, etc.
  final String userType; // "caregiver", "nurse", "admin", etc.
  final NotificationType type;
  final Map<String, dynamic>? metadata;
  
  // New enhanced fields
  final String? referenceId;
  final String? referenceType;
  final NotificationPriority priority;
  final String? category;
  final DateTime? expiresAt;

  NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.taskId,
    this.elderlyId,
    required this.userId,
    required this.userType,
    required this.type,
    this.metadata,
    this.referenceId,
    this.referenceType,
    this.priority = NotificationPriority.normal,
    this.category,
    this.expiresAt,
  });

  factory NotificationModel.fromFirestore(Map<String, dynamic> data, String id) {
    return NotificationModel(
      id: id,
      title: data['notification_title'] ?? data['title'] ?? '', // Support both new and old field names
      message: data['notification_message'] ?? data['message'] ?? '',
      timestamp: (data['notification_timestamp'] ?? data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['is_read'] ?? false,
      taskId: data['task_id'],
      elderlyId: data['elderly_id'],
      userId: data['user_id'] ?? data['caregiver_id'] ?? '', // Support legacy caregiver_id
      userType: data['user_type'] ?? 'caregiver', // Default to caregiver for backward compatibility
      type: NotificationTypeExtension.fromString(data['notification_type'] ?? data['type'] ?? 'general'),
      metadata: data['metadata'],
      referenceId: data['reference_id'],
      referenceType: data['reference_type'],
      priority: NotificationPriorityExtension.fromString(data['priority'] ?? 'normal'),
      category: data['category'],
      expiresAt: (data['expires_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'notification_title': title,
      'notification_message': message,
      'notification_timestamp': Timestamp.fromDate(timestamp),
      'is_read': isRead,
      'task_id': taskId,
      'elderly_id': elderlyId,
      'user_id': userId,
      'user_type': userType,
      'notification_type': type.value,
      'metadata': metadata,
      'reference_id': referenceId,
      'reference_type': referenceType,
      'priority': priority.value,
      'category': category,
      'expires_at': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
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
    String? userId,
    String? userType,
    NotificationType? type,
    Map<String, dynamic>? metadata,
    String? referenceId,
    String? referenceType,
    NotificationPriority? priority,
    String? category,
    DateTime? expiresAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      taskId: taskId ?? this.taskId,
      elderlyId: elderlyId ?? this.elderlyId,
      userId: userId ?? this.userId,
      userType: userType ?? this.userType,
      type: type ?? this.type,
      metadata: metadata ?? this.metadata,
      referenceId: referenceId ?? this.referenceId,
      referenceType: referenceType ?? this.referenceType,
      priority: priority ?? this.priority,
      category: category ?? this.category,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}

enum NotificationType {
  // Task types
  taskAssigned,
  taskCompleted,
  taskMissed,
  taskUpdated,
  taskDeleted,
  
  // Leave request types
  leaveSubmitted,
  leaveApproved,
  leaveDenied,
  leaveModified,
  leaveCancelled,
  
  // Shift types
  shiftReminder,
  shiftChanged,
  shiftAssigned,
  
  // Other types
  incidentReported,
  systemMaintenance,
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
      case NotificationType.leaveSubmitted:
        return 'Leave Submitted';
      case NotificationType.leaveApproved:
        return 'Leave Approved';
      case NotificationType.leaveDenied:
        return 'Leave Denied';
      case NotificationType.leaveModified:
        return 'Leave Modified';
      case NotificationType.leaveCancelled:
        return 'Leave Cancelled';
      case NotificationType.shiftReminder:
        return 'Shift Reminder';
      case NotificationType.shiftChanged:
        return 'Shift Changed';
      case NotificationType.shiftAssigned:
        return 'Shift Assigned';
      case NotificationType.incidentReported:
        return 'Incident Reported';
      case NotificationType.systemMaintenance:
        return 'System Maintenance';
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
      case NotificationType.leaveSubmitted:
        return 'event_note';
      case NotificationType.leaveApproved:
        return 'check_circle';
      case NotificationType.leaveDenied:
        return 'cancel';
      case NotificationType.leaveModified:
        return 'edit_note';
      case NotificationType.leaveCancelled:
        return 'cancel';
      case NotificationType.shiftReminder:
        return 'schedule';
      case NotificationType.shiftChanged:
        return 'update';
      case NotificationType.shiftAssigned:
        return 'assignment_turned_in';
      case NotificationType.incidentReported:
        return 'warning';
      case NotificationType.systemMaintenance:
        return 'build';
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
      case 'leavesubmitted':
      case 'leave_submitted':
        return NotificationType.leaveSubmitted;
      case 'leaveapproved':
      case 'leave_approved':
        return NotificationType.leaveApproved;
      case 'leavedenied':
      case 'leave_denied':
        return NotificationType.leaveDenied;
      case 'leavemodified':
      case 'leave_modified':
        return NotificationType.leaveModified;
      case 'leavecancelled':
      case 'leave_cancelled':
        return NotificationType.leaveCancelled;
      case 'shiftreminder':
      case 'shift_reminder':
        return NotificationType.shiftReminder;
      case 'shiftchanged':
      case 'shift_changed':
        return NotificationType.shiftChanged;
      case 'shiftassigned':
      case 'shift_assigned':
        return NotificationType.shiftAssigned;
      case 'incidentreported':
      case 'incident_reported':
        return NotificationType.incidentReported;
      case 'systemmaintenance':
      case 'system_maintenance':
        return NotificationType.systemMaintenance;
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
      case NotificationType.leaveSubmitted:
        return 'leave_submitted';
      case NotificationType.leaveApproved:
        return 'leave_approved';
      case NotificationType.leaveDenied:
        return 'leave_denied';
      case NotificationType.leaveModified:
        return 'leave_modified';
      case NotificationType.leaveCancelled:
        return 'leave_cancelled';
      case NotificationType.shiftReminder:
        return 'shift_reminder';
      case NotificationType.shiftChanged:
        return 'shift_changed';
      case NotificationType.shiftAssigned:
        return 'shift_assigned';
      case NotificationType.incidentReported:
        return 'incident_reported';
      case NotificationType.systemMaintenance:
        return 'system_maintenance';
      case NotificationType.general:
        return 'general';
    }
  }
}