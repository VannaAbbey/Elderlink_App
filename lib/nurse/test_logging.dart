// Test file to debug medication activity logging
import 'package:cloud_firestore/cloud_firestore.dart';

class TestMedicationLogging {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Simple test to log an activity directly
  static Future<void> testLogActivity() async {
    try {
      print('🧪 Testing medication activity logging...');

      final testData = {
        'action': 'test_activity',
        'nurse_id': 'test_nurse_123',
        'nurse_name': 'Test Nurse',
        'medication_id': 'test_med_123',
        'medication_name': 'Test Medication',
        'elderly_id': 'test_elderly_123',
        'elderly_name': 'Test Elderly',
        'house_id': 'H001',
        'timestamp': FieldValue.serverTimestamp(),
        'shift': '2nd',
        'day': 'Monday',
      };

      print('🧪 Test data: $testData');

      final docRef = await _firestore
          .collection('medication_activity_logs')
          .add(testData);

      print('✅ Test activity logged successfully with ID: ${docRef.id}');

      // Now try to read it back
      final readBack = await _firestore
          .collection('medication_activity_logs')
          .doc(docRef.id)
          .get();

      if (readBack.exists) {
        print('✅ Test activity read back successfully: ${readBack.data()}');
      } else {
        print('❌ Test activity not found when reading back');
      }
    } catch (e) {
      print('❌ Test logging failed: $e');
    }
  }

  /// Test reading all activities
  static Future<void> testReadActivities() async {
    try {
      print('🧪 Testing reading all activities...');

      final query = await _firestore
          .collection('medication_activity_logs')
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();

      print('🧪 Found ${query.docs.length} activities');

      for (final doc in query.docs) {
        print('🧪 Activity: ${doc.id} - ${doc.data()}');
      }
    } catch (e) {
      print('❌ Test reading failed: $e');
    }
  }
}
