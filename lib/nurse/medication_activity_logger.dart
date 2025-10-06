// lib/nurse/medication_activity_logger.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

/// Unified medication activity logger
/// Logs all medication activities to the 'medication_activity_logs' collection
class MedicationActivityLogger {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get current shift based on time
  static String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

  /// Get current day
  static String _getCurrentDay() {
    return DateFormat('EEEE').format(DateTime.now());
  }

  /// Get ordinal number (1st, 2nd, 3rd, etc.)
  static String _getOrdinal(int number) {
    if (number <= 0) return '';

    if (number % 100 >= 11 && number % 100 <= 13) {
      return '${number}th';
    }

    switch (number % 10) {
      case 1:
        return '${number}st';
      case 2:
        return '${number}nd';
      case 3:
        return '${number}rd';
      default:
        return '${number}th';
    }
  }

  /// Get nurse ID from current user
  static Future<String?> _getNurseId() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      // Try to get from users collection
      final userQuery = await _firestore
          .collection('users')
          .where('user_type', isEqualTo: 'nurse')
          .get();

      for (final doc in userQuery.docs) {
        final data = doc.data();
        if (data['user_email'] == currentUser.email) {
          return doc.id;
        }
      }

      // Fallback to current user ID
      return currentUser.uid;
    } catch (e) {
      print('Error getting nurse ID: $e');
      return FirebaseAuth.instance.currentUser?.uid;
    }
  }

  /// Main logging function for medication activities
  static Future<void> logActivity({
    required String
    action, // 'add_medication', 'edit_medication', 'delete_medication', 'delete_individual_take', 'status_change'
    required String medicationId,
    required String elderlyId,
    required String houseId,
    String? nurseName,
    String? medicationName,
    int? takeNumber,
    String? oldStatus,
    String? newStatus,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) {
        print('Warning: Could not get nurse ID for logging');
        return;
      }

      // Get elderly info
      String elderlyName = 'Unknown';
      try {
        final elderlyDoc = await _firestore
            .collection('elderly')
            .doc(elderlyId)
            .get();
        if (elderlyDoc.exists) {
          final elderlyData = elderlyDoc.data() as Map<String, dynamic>;
          elderlyName =
              '${elderlyData['elderly_fname'] ?? ''} ${elderlyData['elderly_lname'] ?? ''}'
                  .trim();
          if (elderlyName.isEmpty) elderlyName = 'Unknown';
        }
      } catch (e) {
        print('Error getting elderly info: $e');
      }

      // Get nurse name if not provided
      if (nurseName == null || nurseName.isEmpty) {
        try {
          final nurseDoc = await _firestore
              .collection('users')
              .doc(nurseId)
              .get();
          if (nurseDoc.exists) {
            final nurseData = nurseDoc.data() as Map<String, dynamic>;
            nurseName =
                '${nurseData['user_fname'] ?? ''} ${nurseData['user_lname'] ?? ''}'
                    .trim();
            if (nurseName.isEmpty) {
              nurseName =
                  FirebaseAuth.instance.currentUser?.displayName ??
                  'Unknown Nurse';
            }
          }
        } catch (e) {
          nurseName =
              FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown Nurse';
        }
      }

      // Prepare activity data
      final activityData = <String, dynamic>{
        'action': action,
        'nurse_id': nurseId,
        'nurse_name': nurseName,
        'medication_id': medicationId,
        'elderly_id': elderlyId,
        'elderly_name': elderlyName,
        'house_id': houseId,
        'timestamp': FieldValue.serverTimestamp(),
        'shift': _getCurrentShift(),
        'day': _getCurrentDay(),
      };

      // Add medication name if provided
      if (medicationName != null && medicationName.isNotEmpty) {
        activityData['medication_name'] = medicationName;
      }

      // Add take-specific data if applicable
      if (takeNumber != null && takeNumber > 0) {
        activityData['take_number'] = takeNumber;
        activityData['take_ordinal'] = _getOrdinal(takeNumber);
      }

      // Add status change data if applicable
      if (oldStatus != null) activityData['old_status'] = oldStatus;
      if (newStatus != null) activityData['new_status'] = newStatus;

      // Add old/new data if provided
      if (oldData != null) activityData['old_data'] = oldData;
      if (newData != null) activityData['new_data'] = newData;

      // Add any additional data
      if (additionalData != null) {
        activityData.addAll(additionalData);
      }

      // Log to database
      await _firestore.collection('medication_activity_logs').add(activityData);
      print('✅ Medication activity logged: $action for $elderlyName');
    } catch (e) {
      print('❌ Error logging medication activity: $e');
    }
  }

  /// Convenience method for logging medication addition
  static Future<void> logAddMedication({
    required String medicationId,
    required String elderlyId,
    required String houseId,
    required String medicationName,
    String? nurseName,
    Map<String, dynamic>? medicationData,
  }) async {
    await logActivity(
      action: 'add_medication',
      medicationId: medicationId,
      elderlyId: elderlyId,
      houseId: houseId,
      nurseName: nurseName,
      medicationName: medicationName,
      newData: medicationData,
    );
  }

  /// Convenience method for logging medication editing
  static Future<void> logEditMedication({
    required String medicationId,
    required String elderlyId,
    required String houseId,
    required String medicationName,
    String? nurseName,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
  }) async {
    await logActivity(
      action: 'edit_medication',
      medicationId: medicationId,
      elderlyId: elderlyId,
      houseId: houseId,
      nurseName: nurseName,
      medicationName: medicationName,
      oldData: oldData,
      newData: newData,
    );
  }

  /// Convenience method for logging medication deletion
  static Future<void> logDeleteMedication({
    required String medicationId,
    required String elderlyId,
    required String houseId,
    required String medicationName,
    String? nurseName,
    Map<String, dynamic>? medicationData,
  }) async {
    await logActivity(
      action: 'delete_medication',
      medicationId: medicationId,
      elderlyId: elderlyId,
      houseId: houseId,
      nurseName: nurseName,
      medicationName: medicationName,
      oldData: medicationData,
    );
  }

  /// Convenience method for logging individual take deletion
  static Future<void> logDeleteIndividualTake({
    required String medicationId,
    required String elderlyId,
    required String houseId,
    required String medicationName,
    required int takeNumber,
    String? nurseName,
  }) async {
    await logActivity(
      action: 'delete_individual_take',
      medicationId: medicationId,
      elderlyId: elderlyId,
      houseId: houseId,
      nurseName: nurseName,
      medicationName: medicationName,
      takeNumber: takeNumber,
    );
  }

  /// Convenience method for logging status changes
  static Future<void> logStatusChange({
    required String medicationId,
    required String elderlyId,
    required String houseId,
    required String medicationName,
    required String oldStatus,
    required String newStatus,
    int? takeNumber,
    String? nurseName,
  }) async {
    await logActivity(
      action: 'status_change',
      medicationId: medicationId,
      elderlyId: elderlyId,
      houseId: houseId,
      nurseName: nurseName,
      medicationName: medicationName,
      takeNumber: takeNumber,
      oldStatus: oldStatus,
      newStatus: newStatus,
    );
  }
}
