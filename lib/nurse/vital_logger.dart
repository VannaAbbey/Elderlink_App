// lib/nurse/vitals_logger.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Logs any action related to an elderly's vitals into `vitals_activity_logs`.
Future<void> logVitalAction({
  required String vitalId,
  required String elderlyId,
  required String elderlyName,
  required String nurseId,
  required String nurseName,
  required String houseId, // Add house_id parameter
  required String
  actionType, // e.g., "vital_recorded", "vital_verified", "vital_updated"
  Map<String, dynamic>? oldValue, // previous vital values (if any)
  Map<String, dynamic>? newValue, // new vital values
  String? remarks, // optional remarks
}) async {
  try {
    await FirebaseFirestore.instance.collection("vital_activity_logs").add({
      "vital_id": vitalId,
      "elderly_id": elderlyId,
      "elderly_name": elderlyName,
      "nurse_id": nurseId,
      "nurse_name": nurseName,
      "house_id": houseId, // Include house_id in the log
      "action_type": actionType,
      "old_value": oldValue ?? {},
      "new_value": newValue ?? {},
      "remarks": remarks ?? "",
      "timestamp": FieldValue.serverTimestamp(),
    });
  } catch (e) {
    print("Error logging vital action: $e");
  }
}
