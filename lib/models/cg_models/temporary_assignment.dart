import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for the temporary_assignments collection
/// This collection temporarily stores the reassignments of the elderly
/// to other caregivers when a caregiver is marked as absent
/// 
/// Assignment Types:
/// - "absence_coverage": Temporary elderly assignment (absent caregiver's elderly)
/// - "emergency_coverage": Full house reassignment (when all caregivers in a house are absent)
/// - "emergency redistribution": Full house reassignment (web side terminology)
class TemporaryAssignment {
  final String? id; // Document ID from Firestore
  final int assignmentVersion; // Version number for tracking
  final String assignmentType; // Type: "absence_coverage", "emergency_coverage", or "emergency redistribution"
  final DateTime createdAt;
  final String date; // Format: "YYYY-MM-DD"
  final String day; // Day of week (e.g., "Monday", "Friday")
  final List<String> elderlyIds; // List of elderly IDs temporarily assigned
  final DateTime? expiresAt; // Null if permanent, or expiration date
  final String fromUserId; // User ID of the original caregiver (who is absent)
  final String shift; // Shift number (e.g., "1st", "2nd", "3rd")
  final String status; // Status: "active" or "expired"
  final String toUserId; // User ID of the caregiver receiving the assignment
  final String? emergencyCoverageHouseId; // House ID for emergency coverage (null for absence coverage)
  final String? reason; // Reason for assignment (may contain house ID info)
  final String? userType; // User type: "caregiver" or "nurse"

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
    this.emergencyCoverageHouseId,
    this.reason,
    this.userType,
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
      emergencyCoverageHouseId: data['emergency_coverage_house_id'] as String?,
      reason: data['reason'] as String?,
      userType: data['user_type'] as String?,
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
      emergencyCoverageHouseId: data['emergency_coverage_house_id'] as String?,
      reason: data['reason'] as String?,
      userType: data['user_type'] as String?,
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
      if (emergencyCoverageHouseId != null) 'emergency_coverage_house_id': emergencyCoverageHouseId,
      if (reason != null) 'reason': reason,
      if (userType != null) 'user_type': userType,
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
    String? emergencyCoverageHouseId,
    String? reason,
    String? userType,
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
      emergencyCoverageHouseId: emergencyCoverageHouseId ?? this.emergencyCoverageHouseId,
      reason: reason ?? this.reason,
      userType: userType ?? this.userType,
    );
  }

  /// Check if this is an emergency coverage assignment
  /// Supports both "emergency_coverage" and "emergency redistribution" types
  bool get isEmergencyCoverage => 
      assignmentType == 'emergency_coverage' || 
      assignmentType == 'emergency redistribution';
  
  /// Check if this is an absence coverage assignment
  bool get isAbsenceCoverage => assignmentType == 'absence_coverage';
  
  /// Get the emergency house ID from multiple sources
  /// Priority: 1) emergencyCoverageHouseId field, 2) extract from reason, 3) null
  Future<String?> getEmergencyHouseId() async {
    // First, check if we have the direct field
    if (emergencyCoverageHouseId != null && emergencyCoverageHouseId!.isNotEmpty) {
      print('🔍 Found emergency house ID from field: $emergencyCoverageHouseId');
      return emergencyCoverageHouseId;
    }
    
    // Second, try to extract from reason field (e.g., "transfer to H002")
    if (reason != null && reason!.isNotEmpty) {
      print('🔍 Attempting to extract house ID from reason: $reason');
      
      // Match patterns like "H002", "H001", etc.
      final houseIdPattern = RegExp(r'H\d{3,4}', caseSensitive: false);
      final match = houseIdPattern.firstMatch(reason!);
      
      if (match != null) {
        final extractedHouseId = match.group(0)!.toUpperCase();
        print('✅ Extracted house ID from reason: $extractedHouseId');
        return extractedHouseId;
      }
    }
    
    print('⚠️ Could not determine emergency house ID');
    return null;
  }

  @override
  String toString() {
    return 'TemporaryAssignment(id: $id, date: $date, fromUserId: $fromUserId, toUserId: $toUserId, elderlyIds: $elderlyIds, status: $status)';
  }
}