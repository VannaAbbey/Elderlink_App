import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class AdditionalLogService {
  static const String collectionName = 'cg_additional_logs';
  
  /// Creates or updates an additional log for the current day
  static Future<void> saveAdditionalLog(String content) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('AdditionalLogService: No authenticated user found');
        return;
      }

      final now = DateTime.now();
      final dateString = DateFormat('yyyy-MM-dd').format(now);
      final documentId = '${user.uid}_$dateString';

      print('AdditionalLogService: Saving additional log for date: $dateString');
      print('AdditionalLogService: Document ID: $documentId');
      print('AdditionalLogService: Content length: ${content.length}');

      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(documentId)
          .set({
        'caregiver_id': user.uid,
        'caregiver_email': user.email ?? '',
        'date_string': dateString,
        'content': content,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('AdditionalLogService: Additional log saved successfully');
    } catch (e) {
      print('AdditionalLogService: Error saving additional log: $e');
      rethrow;
    }
  }

  /// Gets the additional log for a specific date
  static Stream<String> getAdditionalLogForDate(DateTime date) {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('AdditionalLogService: No authenticated user found for reading');
        return Stream.value('');
      }

      final dateString = DateFormat('yyyy-MM-dd').format(date);
      final documentId = '${user.uid}_$dateString';

      print('AdditionalLogService: Getting additional log for date: $dateString');
      print('AdditionalLogService: Document ID: $documentId');

      return FirebaseFirestore.instance
          .collection(collectionName)
          .doc(documentId)
          .snapshots()
          .map((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data() as Map<String, dynamic>;
          final content = data['content'] as String? ?? '';
          print('AdditionalLogService: Retrieved content length: ${content.length}');
          return content;
        } else {
          print('AdditionalLogService: No additional log found for date: $dateString');
          return '';
        }
      });
    } catch (e) {
      print('AdditionalLogService: Error getting additional log: $e');
      return Stream.value('');
    }
  }

  /// Gets the current day's additional log content (for editing)
  static Future<String> getCurrentDayAdditionalLog() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('AdditionalLogService: No authenticated user found for current log');
        return '';
      }

      final now = DateTime.now();
      final dateString = DateFormat('yyyy-MM-dd').format(now);
      final documentId = '${user.uid}_$dateString';

      print('AdditionalLogService: Getting current day log for: $dateString');

      final snapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(documentId)
          .get();

      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        final content = data['content'] as String? ?? '';
        print('AdditionalLogService: Current log content length: ${content.length}');
        return content;
      } else {
        print('AdditionalLogService: No current day log found');
        return '';
      }
    } catch (e) {
      print('AdditionalLogService: Error getting current day log: $e');
      return '';
    }
  }

  /// Deletes an additional log for a specific date (optional functionality)
  static Future<void> deleteAdditionalLog(DateTime date) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('AdditionalLogService: No authenticated user found for deletion');
        return;
      }

      final dateString = DateFormat('yyyy-MM-dd').format(date);
      final documentId = '${user.uid}_$dateString';

      print('AdditionalLogService: Deleting additional log for date: $dateString');

      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(documentId)
          .delete();

      print('AdditionalLogService: Additional log deleted successfully');
    } catch (e) {
      print('AdditionalLogService: Error deleting additional log: $e');
      rethrow;
    }
  }
}