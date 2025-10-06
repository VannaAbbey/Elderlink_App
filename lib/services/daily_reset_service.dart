import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class DailyResetService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Reset daily vital assignments at the end of each day
  // This should run automatically between shifts (around 5:00 AM before first shift)
  static Future<void> resetDailyVitalAssignments() async {
    try {
      final now = DateTime.now();
      final currentHour = now.hour;

      // Only run reset between 4:00 AM and 6:00 AM (before first shift starts)
      if (currentHour < 4 || currentHour >= 6) {
        print('Daily reset can only run between 4:00 AM and 6:00 AM');
        return;
      }

      final yesterday = now.subtract(Duration(days: 1));
      final yesterdayString = DateFormat('yyyy-MM-dd').format(yesterday);

      print('Starting daily reset for assignments from: $yesterdayString');

      // Get all completed assignments from yesterday
      final completedAssignments = await _firestore
          .collection('daily_vital_assignments')
          .where('assigned_date', isEqualTo: yesterdayString)
          .where('status', isEqualTo: 'completed')
          .get();

      print(
        'Found ${completedAssignments.docs.length} completed assignments to reset',
      );

      // Mark missed assignments from yesterday
      final pendingAssignments = await _firestore
          .collection('daily_vital_assignments')
          .where('assigned_date', isEqualTo: yesterdayString)
          .where('status', isEqualTo: 'pending')
          .get();

      // Update pending to missed
      final batch = _firestore.batch();
      for (final doc in pendingAssignments.docs) {
        batch.update(doc.reference, {
          'status': 'missed',
          'updated_at': FieldValue.serverTimestamp(),
          'missed_reason': 'Auto-marked as missed after day ended',
        });
      }

      await batch.commit();
      print(
        'Marked ${pendingAssignments.docs.length} pending assignments as missed',
      );

      // Note: We don't delete completed assignments as they serve as history
      // New assignments will be created automatically when nurses check upcoming vitals

      print('Daily reset completed successfully');
    } catch (e) {
      print('Error during daily reset: $e');
    }
  }

  // Check if daily reset is needed (can be called on app startup)
  static Future<void> checkAndRunDailyReset() async {
    try {
      final now = DateTime.now();
      final currentHour = now.hour;

      // Run reset if it's between 4:00 AM and 6:00 AM
      if (currentHour >= 4 && currentHour < 6) {
        await resetDailyVitalAssignments();
      }
    } catch (e) {
      print('Error checking daily reset: $e');
    }
  }

  // Get vital statistics for a specific elderly (for future health graph)
  static Future<List<Map<String, dynamic>>> getElderlyVitalHistory({
    required String elderlyId,
    int days = 30,
  }) async {
    try {
      final endDate = DateTime.now();
      final startDate = endDate.subtract(Duration(days: days));

      final vitalHistory = await _firestore
          .collection('vitals')
          .where('elderly_id', isEqualTo: elderlyId)
          .where(
            'vital_record_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .where(
            'vital_record_at',
            isLessThanOrEqualTo: Timestamp.fromDate(endDate),
          )
          .orderBy('vital_record_at', descending: true)
          .get();

      return vitalHistory.docs.map((doc) {
        final data = doc.data();
        return {
          'date': (data['vital_record_at'] as Timestamp).toDate(),
          'blood_pressure': data['blood_pressure'],
          'pulse_rate': data['pulse_rate'],
          'o2_sat': data['o2_sat'],
          'temperature': data['temperature'],
          'respiratory_rate': data['respiratory_rate'],
          'recorded_by': data['updated_by_nurse_name'],
        };
      }).toList();
    } catch (e) {
      print('Error getting vital history: $e');
      return [];
    }
  }

  // Get daily completion statistics for a house/nurse
  static Future<Map<String, int>> getDailyCompletionStats({
    required String houseId,
    String? nurseId,
    String? date,
  }) async {
    try {
      final queryDate = date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

      var query = _firestore
          .collection('daily_vital_assignments')
          .where('house_id', isEqualTo: houseId)
          .where('assigned_date', isEqualTo: queryDate);

      if (nurseId != null) {
        query = query.where('assigned_nurse_id', isEqualTo: nurseId);
      }

      final assignments = await query.get();

      int pending = 0;
      int completed = 0;
      int missed = 0;

      for (final doc in assignments.docs) {
        final status = doc.data()['status'] as String;
        switch (status) {
          case 'pending':
            pending++;
            break;
          case 'completed':
            completed++;
            break;
          case 'missed':
            missed++;
            break;
        }
      }

      return {
        'pending': pending,
        'completed': completed,
        'missed': missed,
        'total': assignments.docs.length,
      };
    } catch (e) {
      print('Error getting completion stats: $e');
      return {'pending': 0, 'completed': 0, 'missed': 0, 'total': 0};
    }
  }
}
