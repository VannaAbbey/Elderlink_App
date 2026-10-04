/// 🔧 DATABASE CLEANUP UTILITIES FOR VITAL SIGNS
///
/// This file contains utilities to clean up redundant fields from vital documents.
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VitalsDatabaseTester {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Test if vital signs can be saved to database
  static Future<void> testVitalSave({
    required String elderlyId,
    required String assignmentId,
    String? nurseName,
  }) async {
    try {
      print('🧪 TESTING VITAL SAVE OPERATION...');

      final currentUser = FirebaseAuth.instance.currentUser;
      final nurseId = currentUser?.uid ?? 'test-nurse-id';
      final testNurseName =
          nurseName ?? currentUser?.displayName ?? 'Test Nurse';

      print('👤 Current User: $currentUser');
      print('🆔 Nurse ID: $nurseId');
      print('👩‍⚕️ Nurse Name: $testNurseName');

      final now = DateTime.now();
      final vitalId = _firestore.collection('vitals').doc().id;

      final testVitalData = {
        'vital_id': vitalId,
        'elderly_id': elderlyId,
        'assignment_id': assignmentId,
        'nurse_id': nurseId,
        'nurse_name': testNurseName,
        'status': 'completed',
        'blood_pressure': '120/80',
        'pulse_rate': '72',
        'o2_sat': '97',
        'temperature': '36.5',
        'respiratory_rate': '18',
        'vital_remarks': 'Test vital record',
        'vital_record_at': Timestamp.fromDate(now),
        'created_at': Timestamp.fromDate(now),
        'last_updated_at': Timestamp.fromDate(now),
        'last_updated_by': nurseId,
      };

      print('📊 Test Vital Data: $testVitalData');

      // Save to database
      await _firestore.collection('vitals').doc(vitalId).set(testVitalData);

      print('✅ Test vital saved successfully!');
      print('📋 Vital ID: $vitalId');

      // Verify it was saved
      final savedDoc = await _firestore.collection('vitals').doc(vitalId).get();
      if (savedDoc.exists) {
        print('✅ Verification: Document exists in database');
        print('📄 Saved Data: ${savedDoc.data()}');
      } else {
        print('❌ Verification FAILED: Document not found!');
      }
    } catch (e) {
      print('❌ Test FAILED: $e');
    }
  }

  /// Test querying completed vitals by nurse name
  static Future<void> testCompletedVitalsQuery({
    required String nurseName,
    String? houseId,
  }) async {
    try {
      print('🔍 TESTING COMPLETED VITALS QUERY...');
      print('👩‍⚕️ Nurse Name: $nurseName');
      print('🏠 House ID: ${houseId ?? "All houses"}');

      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);

      print('📅 Query Range: $startOfDay to $endOfDay');

      Query query = _firestore
          .collection('vitals')
          .where('nurse_name', isEqualTo: nurseName)
          .where('status', isEqualTo: 'completed')
          .where(
            'created_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where(
            'created_at',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
          );

      final querySnapshot = await query.get();

      print(
        '🟢 Query Results: Found ${querySnapshot.docs.length} completed vitals',
      );

      for (final doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        print(
          '   📋 ${data['elderly_id']} - BP: ${data['blood_pressure']} - Time: ${data['vital_record_at']}',
        );
      }

      if (querySnapshot.docs.isEmpty) {
        print('⚠️ No completed vitals found - this could indicate:');
        print('   1. No vitals have been saved today');
        print('   2. Nurse name mismatch in query');
        print('   3. Wrong status value');
        print('   4. Date range issue');
      }
    } catch (e) {
      print('❌ Query test FAILED: $e');
    }
  }

  /// Test querying all vital records (for debugging)
  static Future<void> testAllVitalsQuery() async {
    try {
      print('🔍 TESTING ALL VITALS QUERY...');

      final querySnapshot = await _firestore
          .collection('vitals')
          .orderBy('created_at', descending: true)
          .limit(10)
          .get();

      print('📊 Total vitals found: ${querySnapshot.docs.length}');

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        print('   📋 ID: ${doc.id}');
        print('      👴 Elderly: ${data['elderly_id']}');
        print(
          '      👩‍⚕️ Nurse: ${data['nurse_name']} (ID: ${data['nurse_id']})',
        );
        print('      📊 Status: ${data['status']}');
        print('      📅 Created: ${data['created_at']}');
        print(
          '      🩺 BP: ${data['blood_pressure']}, Pulse: ${data['pulse_rate']}',
        );
        print('');
      }
    } catch (e) {
      print('❌ All vitals query FAILED: $e');
    }
  }

  /// Test assignment status update
  static Future<void> testAssignmentUpdate({
    required String assignmentId,
    required String vitalId,
  }) async {
    try {
      print('🧪 TESTING ASSIGNMENT UPDATE...');
      print('📋 Assignment ID: $assignmentId');
      print('🩺 Vital ID: $vitalId');

      final now = DateTime.now();

      await _firestore
          .collection('daily_vital_assignments')
          .doc(assignmentId)
          .update({
            'status': 'completed',
            'completed_at': Timestamp.fromDate(now),
            'vital_id': vitalId,
            'last_updated': Timestamp.fromDate(now),
          });

      print('✅ Assignment updated successfully!');

      // Verify the update
      final updatedDoc = await _firestore
          .collection('daily_vital_assignments')
          .doc(assignmentId)
          .get();

      if (updatedDoc.exists) {
        final data = updatedDoc.data()!;
        print('✅ Verification: Assignment status is now "${data['status']}"');
        print('🕒 Completed at: ${data['completed_at']}');
        print('🔗 Linked vital ID: ${data['vital_id']}');
      } else {
        print('❌ Verification FAILED: Assignment document not found!');
      }
    } catch (e) {
      print('❌ Assignment update test FAILED: $e');
    }
  }
}

/// 🧪 DEBUG WIDGET FOR TESTING VITAL OPERATIONS
///
/// Add this widget to any screen to test database operations
class VitalsDebugPanel extends StatelessWidget {
  final String? elderlyId;
  final String? assignmentId;
  final String? nurseName;
  final String? houseId;

  const VitalsDebugPanel({
    super.key,
    this.elderlyId,
    this.assignmentId,
    this.nurseName,
    this.houseId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        border: Border.all(color: Colors.orange),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🧪 DEBUG PANEL - VITALS DATABASE TESTING',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
          ),
          const SizedBox(height: 8),

          if (elderlyId != null && assignmentId != null) ...[
            ElevatedButton(
              onPressed: () => VitalsDatabaseTester.testVitalSave(
                elderlyId: elderlyId!,
                assignmentId: assignmentId!,
                nurseName: nurseName,
              ),
              child: const Text('Test Vital Save'),
            ),
            const SizedBox(height: 8),
          ],

          if (nurseName != null) ...[
            ElevatedButton(
              onPressed: () => VitalsDatabaseTester.testCompletedVitalsQuery(
                nurseName: nurseName!,
                houseId: houseId,
              ),
              child: const Text('Test Completed Query'),
            ),
            const SizedBox(height: 8),
          ],

          ElevatedButton(
            onPressed: () => VitalsDatabaseTester.testAllVitalsQuery(),
            child: const Text('Show All Vitals'),
          ),

          const SizedBox(height: 8),
          const Text(
            'Check console for test results',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

/// 🔧 USAGE EXAMPLES:
/// 
/// 1. Add debug panel to vital update screen:
/// ```dart
/// // Add this to the body of VitalUpdateScreen
/// VitalsDebugPanel(
///   elderlyId: widget.elderlyId,
///   assignmentId: widget.assignmentId,
///   nurseName: widget.nurseName,
/// )
/// ```
/// 
/// 2. Test from anywhere in code:
/// ```dart
/// // Test saving vitals
/// VitalsDatabaseTester.testVitalSave(
///   elderlyId: "elderly123",
///   assignmentId: "assignment456",
///   nurseName: "John Doe",
/// );
/// 
/// // Test querying completed vitals
/// VitalsDatabaseTester.testCompletedVitalsQuery(
///   nurseName: "John Doe",
/// );
/// ```