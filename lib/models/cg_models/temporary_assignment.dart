import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for the temporary_assignments collection
/// This collection temporarily stores the reassignments of the elderly
/// to other caregivers when a caregiver is marked as absent
class TemporaryAssignment {
  final String? id; // Document ID from Firestore
  final int assignmentVersion; // Version number for tracking
  final String assignmentType; // Type: "absence_coverage"
  final DateTime createdAt;
  final String date; // Format: "YYYY-MM-DD"
  final String day; // Day of week (e.g., "Monday", "Friday")
  final List<String> elderlyIds; // List of elderly IDs temporarily assigned
  final DateTime? expiresAt; // Null if permanent, or expiration date
  final String fromUserId; // User ID of the original caregiver (who is absent)
  final String shift; // Shift number (e.g., "1st", "2nd", "3rd")
  final String status; // Status: "active" or "expired"
  final String toUserId; // User ID of the caregiver receiving the assignment

  TemporaryAssignment({
    this.id,
    required this.assignmentVersion,
    required this.assignmentType,
    required this.createdAt,
    required this.date,
    required this.day,
    required this.elderlyIds,
    this.expiresAt,
    required this.fromUserId,
    required this.shift,
    required this.status,
    required this.toUserId,
  });

  /// Create from Firestore document snapshot
  factory TemporaryAssignment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TemporaryAssignment(
      id: doc.id,
      assignmentVersion: data['assign_version'] ?? 1,
      assignmentType: data['assignment_type'] ?? 'absence_coverage',
      createdAt: (data['created_at'] as Timestamp).toDate(),
      date: data['date'] ?? '',
      day: data['day'] ?? '',
      elderlyIds: List<String>.from(data['elderly_ids'] ?? []),
      expiresAt: data['expires_at'] != null
          ? (data['expires_at'] as Timestamp).toDate()
          : null,
      fromUserId: data['from_user_id'] ?? '',
      shift: data['shift'] ?? '',
      status: data['status'] ?? 'active',
      toUserId: data['to_user_id'] ?? '',
    );
  }

  /// Create from JSON/Map
  factory TemporaryAssignment.fromMap(Map<String, dynamic> data) {
    return TemporaryAssignment(
      id: data['id'],
      assignmentVersion: data['assign_version'] ?? 1,
      assignmentType: data['assignment_type'] ?? 'absence_coverage',
      createdAt: data['created_at'] is Timestamp
          ? (data['created_at'] as Timestamp).toDate()
          : DateTime.parse(data['created_at']),
      date: data['date'] ?? '',
      day: data['day'] ?? '',
      elderlyIds: List<String>.from(data['elderly_ids'] ?? []),
      expiresAt: data['expires_at'] != null
          ? (data['expires_at'] is Timestamp
              ? (data['expires_at'] as Timestamp).toDate()
              : DateTime.parse(data['expires_at']))
          : null,
      fromUserId: data['from_user_id'] ?? '',
      shift: data['shift'] ?? '',
      status: data['status'] ?? 'active',
      toUserId: data['to_user_id'] ?? '',
    );
  }

  /// Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'assign_version': assignmentVersion,
      'assignment_type': assignmentType,
      'created_at': Timestamp.fromDate(createdAt),
      'date': date,
      'day': day,
      'elderly_ids': elderlyIds,
      'expires_at': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'from_user_id': fromUserId,
      'shift': shift,
      'status': status,
      'to_user_id': toUserId,
    };
  }

  /// Copy with method for creating modified copies
  TemporaryAssignment copyWith({
    String? id,
    int? assignmentVersion,
    String? assignmentType,
    DateTime? createdAt,
    String? date,
    String? day,
    List<String>? elderlyIds,
    DateTime? expiresAt,
    String? fromUserId,
    String? shift,
    String? status,
    String? toUserId,
  }) {
    return TemporaryAssignment(
      id: id ?? this.id,
      assignmentVersion: assignmentVersion ?? this.assignmentVersion,
      assignmentType: assignmentType ?? this.assignmentType,
      createdAt: createdAt ?? this.createdAt,
      date: date ?? this.date,
      day: day ?? this.day,
      elderlyIds: elderlyIds ?? this.elderlyIds,
      expiresAt: expiresAt ?? this.expiresAt,
      fromUserId: fromUserId ?? this.fromUserId,
      shift: shift ?? this.shift,
      status: status ?? this.status,
      toUserId: toUserId ?? this.toUserId,
    );
  }

  @override
  String toString() {
    return 'TemporaryAssignment(id: $id, date: $date, fromUserId: $fromUserId, toUserId: $toUserId, elderlyIds: $elderlyIds, status: $status)';
  }
}
