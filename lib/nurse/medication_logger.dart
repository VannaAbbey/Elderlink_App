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
  await FirebaseFirestore.instance.collection("medication_logs").add({
    "medication_id": medicationId,
    "elderly_id": elderlyId,
    "elderly_name": elderlyName,
    "nurse_name": nurseName,
    "action_type": actionType,
    "old_value": oldValue ?? {},
    "new_value": newValue ?? {},
    "timestamp": FieldValue.serverTimestamp(),
  });
}
