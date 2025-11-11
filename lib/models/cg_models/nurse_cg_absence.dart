import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for the nurse_cg_absence collection
/// This collection dictates whether a user (caregiver/nurse) gets marked as absent/on leave
class NurseCgAbsence {
  final String? id; // Document ID from Firestore
  final String absenceDate; // Format: "YYYY-MM-DD"
  final String absenceType; // "absent" or "leave"
  final int assignmentVersion; // Version number for tracking
  final DateTime createdAt;
  final String houseId; // House ID (e.g., "H001")
  final String markedBy; // User ID of supervisor who marked them absent
  final String shift; // Shift number (e.g., "1st", "2nd", "3rd")
  final String status; // Status: "active" or "inactive"
  final String userId; // User ID of the caregiver/nurse who is absent
  final String userType; // "caregiver" or "nurse"

  NurseCgAbsence({
    this.id,
    required this.absenceDate,
    required this.absenceType,
    required this.assignmentVersion,
    required this.createdAt,
    required this.houseId,
    required this.markedBy,
    required this.shift,
    required this.status,
    required this.userId,
    required this.userType,
  });

  /// Create from Firestore document snapshot
  factory NurseCgAbsence.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NurseCgAbsence(
      id: doc.id,
      absenceDate: data['absence_date'] ?? '',
      absenceType: data['absence_type'] ?? 'absent',
      assignmentVersion: data['assignment_version'] ?? 1,
      createdAt: (data['created_at'] as Timestamp).toDate(),
      houseId: data['house_id'] ?? '',
      markedBy: data['marked_by'] ?? '',
      shift: data['shift'] ?? '',
      status: data['status'] ?? 'active',
      userId: data['user_id'] ?? '',
      userType: data['user_type'] ?? 'caregiver',
    );
  }

  /// Create from JSON/Map
  factory NurseCgAbsence.fromMap(Map<String, dynamic> data) {
    return NurseCgAbsence(
      id: data['id'],
      absenceDate: data['absence_date'] ?? '',
      absenceType: data['absence_type'] ?? 'absent',
      assignmentVersion: data['assignment_version'] ?? 1,
      createdAt: data['created_at'] is Timestamp
          ? (data['created_at'] as Timestamp).toDate()
          : DateTime.parse(data['created_at']),
      houseId: data['house_id'] ?? '',
      markedBy: data['marked_by'] ?? '',
      shift: data['shift'] ?? '',
      status: data['status'] ?? 'active',
      userId: data['user_id'] ?? '',
      userType: data['user_type'] ?? 'caregiver',
    );
  }

  /// Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'absence_date': absenceDate,
      'absence_type': absenceType,
      'assignment_version': assignmentVersion,
      'created_at': Timestamp.fromDate(createdAt),
      'house_id': houseId,
      'marked_by': markedBy,
      'shift': shift,
      'status': status,
      'user_id': userId,
      'user_type': userType,
    };
  }

  /// Copy with method for creating modified copies
  NurseCgAbsence copyWith({
    String? id,
    String? absenceDate,
    String? absenceType,
    int? assignmentVersion,
    DateTime? createdAt,
    String? houseId,
    String? markedBy,
    String? shift,
    String? status,
    String? userId,
    String? userType,
  }) {
    return NurseCgAbsence(
      id: id ?? this.id,
      absenceDate: absenceDate ?? this.absenceDate,
      absenceType: absenceType ?? this.absenceType,
      assignmentVersion: assignmentVersion ?? this.assignmentVersion,
      createdAt: createdAt ?? this.createdAt,
      houseId: houseId ?? this.houseId,
      markedBy: markedBy ?? this.markedBy,
      shift: shift ?? this.shift,
      status: status ?? this.status,
      userId: userId ?? this.userId,
      userType: userType ?? this.userType,
    );
  }

  @override
  String toString() {
    return 'NurseCgAbsence(id: $id, userId: $userId, absenceDate: $absenceDate, absenceType: $absenceType, shift: $shift, status: $status)';
  }
}