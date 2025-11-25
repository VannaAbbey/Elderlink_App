// Test script to create a missed vital for testing
// Run this as a standalone Dart script to add test data

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  // Initialize Firebase
  await Firebase.initializeApp();
  final firestore = FirebaseFirestore.instance;

  print('🧪 Creating test missed vital...');

  try {
    // Create a test missed vital
    final testVitalId =
        'TEST_MISSED_VITAL_${DateTime.now().millisecondsSinceEpoch}';

    await firestore.collection('vitals').doc(testVitalId).set({
      'house_id': 'H001',
      'elderly_id':
          'E001', // You might need to adjust this to match existing elderly
      'assigned_nurse_id': 'N001', // Adjust to match current nurse ID
      'vital_type': 'blood_pressure',
      'assigned_date': '2025-11-24',
      'assigned_time': '08:00',
      'status': 'missed',
      'created_at': FieldValue.serverTimestamp(),
      'missed_at': FieldValue.serverTimestamp(),
      'shift': 'morning',
    });

    // Also create activity log entry
    await firestore.collection('vital_activity_logs').add({
      'house_id': 'H001',
      'vital_id': testVitalId,
      'elderly_id': 'E001',
      'nurse_id': 'N001',
      'nurse_name': 'Test Nurse',
      'action_type': 'missed_auto',
      'timestamp': FieldValue.serverTimestamp(),
      'shift': 'morning',
      'notes': 'Created by test script for missed vital system validation',
    });

    print('✅ Test missed vital created successfully!');
    print('📱 Now check the Missed Vitals tab in the app');
  } catch (e) {
    print('❌ Error creating test data: $e');
  }
}
