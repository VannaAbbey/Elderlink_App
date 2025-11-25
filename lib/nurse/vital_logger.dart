// lib/nurse/vitals_logger.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Logs any action related to an elderly's vitals into `vitals_activity_logs`.
/// Action types: vitals_update, shift_completed, shift_missed, assignment_changed, vitals_followup
Future<void> logVitalAction({
  required String vitalsId,
  required String elderlyId,
  required String elderlyName,
  required String assignedDate, // YYYY-MM-DD format
  required String
  actionType, // vitals_update | shift_completed | shift_missed | assignment_changed | vitals_followup
  required String shift, // 1st, 2nd, 3rd
  String? nurseId,
  String? nurseName,
  Map<String, dynamic>? oldValue, // previous values (if any)
  Map<String, dynamic>? newValue, // new values
  String? remarks, // optional remarks
}) async {
  try {
    final docRef = FirebaseFirestore.instance
        .collection("vitals_activity_logs")
        .doc();

    final resolvedNurseName = (nurseName != null && nurseName.trim().isNotEmpty)
        ? nurseName
        : 'system';

    await docRef.set({
      "activity_id": docRef.id,
      "vitals_id": vitalsId,
      "elderly_id": elderlyId,
      "elderly_name": elderlyName,
      "assigned_date": assignedDate,
      "action_type": actionType,
      "shift": shift,
      "nurse_id": nurseId,
      "nurse_name": resolvedNurseName,
      "old_value": oldValue ?? {},
      "new_value": newValue ?? {},
      "remarks": remarks ?? "",
      "timestamp": FieldValue.serverTimestamp(),
    });
  } catch (e) {
    print("Error logging vital action: $e");
  }
}
