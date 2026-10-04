/// 🧪 QUICK DATABASE TEST
///
/// Run this to test creating a document with redundant fields
/// and then cleaning it up with the cleanup utility.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class QuickDatabaseTest {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a test document with redundant fields
  static Future<String> createTestDocument() async {
    try {
      print('🧪 Creating test document with redundant fields...');

      final testData = {
        // ✅ Clean fields that should remain
        'elderly_id': 'TEST_CLEANUP_123',
        'elderly_name': 'Test Cleanup Elder',
        'assigned_by': 'test-nurse-id',
        'assigned_by_name': 'Test Nurse',
        'created_at': FieldValue.serverTimestamp(),
        'status': 'pending',
        'scheduled_time': Timestamp.fromDate(DateTime.now()),
        'shift': 'morning',
        'location': 'Room 999',
        'blood_pressure': '120/80',
        'pulse_rate': '72',
        'oxygen_saturation': '98',
        'temperature': '36.5',
        'respiratory_rate': '18',
        'remarks': 'Test cleanup data',
        'completed_at': FieldValue.serverTimestamp(),
        'recorded_by': 'test-nurse-id',
        'recorded_by_name': 'Test Nurse',

        // 🚫 REDUNDANT FIELDS that should be removed
        'blood_pressure_systolic': '120',
        'blood_pressure_diastolic': '80',
        'heart_rate': '72',
        'o2_sat': '98',
        'elderly_profilePic': 'test-pic-url',
        'recorded_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'assignment_id': 'old-assignment-123',
        'daily_vitals_id': 'old-daily-123',
        'task_id': 'old-task-123',
        'nurse_id': 'duplicate-nurse-id',
        'nurse_name': 'Duplicate Nurse Name',
        'vital_id': 'old-vital-id-123',
        'last_updated_at': FieldValue.serverTimestamp(),
        'last_updated_by': 'duplicate-nurse',
        'vital_record_at': FieldValue.serverTimestamp(),
        'vital_remarks': 'Duplicate remarks',
      };

      final docRef = await _firestore.collection('vitals').add(testData);
      print('✅ Created test document: ${docRef.id}');
      print(
        '📊 Document has ${testData.length} fields (${testData.length - 20} redundant)',
      );

      return docRef.id;
    } catch (e) {
      print('❌ Error creating test document: $e');
      rethrow;
    }
  }

  /// Verify that test document was cleaned up
  static Future<void> verifyCleanup(String documentId) async {
    try {
      print('🔍 Verifying cleanup for document: $documentId');

      final doc = await _firestore.collection('vitals').doc(documentId).get();
      if (!doc.exists) {
        print('❌ Document does not exist!');
        return;
      }

      final data = doc.data()!;
      final fieldCount = data.length;

      print('📊 Document now has $fieldCount fields');

      // Check for redundant fields
      final redundantFields = [
        'blood_pressure_systolic',
        'blood_pressure_diastolic',
        'heart_rate',
        'o2_sat',
        'elderly_profilePic',
        'recorded_at',
        'updated_at',
        'assignment_id',
        'daily_vitals_id',
        'task_id',
        'nurse_id',
        'nurse_name',
        'vital_id',
        'last_updated_at',
        'last_updated_by',
        'vital_record_at',
        'vital_remarks',
      ];

      final foundRedundant = <String>[];
      for (String field in redundantFields) {
        if (data.containsKey(field)) {
          foundRedundant.add(field);
        }
      }

      if (foundRedundant.isEmpty) {
        print('✅ SUCCESS: No redundant fields found! Document is clean.');
        print('✅ Remaining fields: ${data.keys.join(', ')}');
      } else {
        print('❌ STILL HAS REDUNDANT FIELDS: ${foundRedundant.join(', ')}');
      }
    } catch (e) {
      print('❌ Error verifying cleanup: $e');
    }
  }

  /// Delete test document
  static Future<void> deleteTestDocument(String documentId) async {
    try {
      await _firestore.collection('vitals').doc(documentId).delete();
      print('🗑️ Deleted test document: $documentId');
    } catch (e) {
      print('❌ Error deleting test document: $e');
    }
  }

  /// Complete test cycle
  static Future<void> runCompleteTest() async {
    print('🧪 STARTING COMPLETE DATABASE CLEANUP TEST');
    print('=' * 50);

    try {
      // 1. Create test document
      final documentId = await createTestDocument();

      print('\n⏳ Now run the Database Cleanup utility...');
      print(
        '📱 Go to Vital Monitoring → Long press "No elderly assigned" → Database Cleanup',
      );
      print('🧹 Click "Clean All" in the cleanup utility');
      print(
        '📞 Then call QuickDatabaseTest.verifyCleanup("$documentId") to check results',
      );
      print('\n🆔 Test Document ID: $documentId');
    } catch (e) {
      print('❌ Test failed: $e');
    }
  }
}
