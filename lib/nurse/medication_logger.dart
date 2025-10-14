// lib/nurse/medication_logger.dart
import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> logMedicationAction({
  required String medicationId,
  required String elderlyId,
  required String elderlyName,
  required String nurseName,
  required String actionType,
  required Map<String, dynamic>? oldValue,
  required Map<String, dynamic>? newValue,
}) async {
  final docRef = FirebaseFirestore.instance
      .collection("Medication_Activity_Logs")
      .doc();
  await docRef.set({
    "med_activity_log_id": docRef.id,
    "medication_id": medicationId,
    "elderly_id": elderlyId,
    "nurse_name": nurseName,
    "action": actionType,
    "elderly_name": elderlyName,
    "timestamp": Timestamp.fromDate(DateTime.now()),
    // Keep old fields for backward compatibility if needed
    "old_value": oldValue ?? {},
    "new_value": newValue ?? {},
  });
}
