import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TaskLogService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Creates a task log entry when a task status is updated
  static Future<void> createTaskLog({
    required String taskId,
    required String caregiverId,
    required String elderlyId,
    required String elderlyFname,
    required String taskDescription,
    required String status, // 'Complete', 'Incomplete', 'Missed'
    required DateTime taskDate,
    String? reason,
    String? caregiverFname, // Optional parameter to pass the name directly
  }) async {
    try {
      print('🔍 Creating task log with data:');
      print('   - Task ID: $taskId');
      print('   - Caregiver ID: $caregiverId');
      print('   - Elderly ID: $elderlyId');
      print('   - Elderly Name: "$elderlyFname"');
      print('   - Task Description: "$taskDescription"');
      print('   - Status: $status');
      print('   - Task Date: $taskDate');
      print('   - Reason: $reason');
      
      // Get caregiver's first name - Use provided name or fetch from database
      String finalCaregiverFname;
      if (caregiverFname != null && caregiverFname.isNotEmpty) {
        finalCaregiverFname = caregiverFname;
        print('✅ Using provided caregiver name: $finalCaregiverFname');
      } else {
        finalCaregiverFname = await _getCaregiverName(caregiverId);
        
        // Fallback: try to get name from Firebase Auth if available
        if (finalCaregiverFname == 'Unknown Caregiver') {
          print('🔄 Trying to get name from current user context...');
          try {
            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser != null) {
              // Try display name first
              if (currentUser.displayName != null && currentUser.displayName!.isNotEmpty) {
                finalCaregiverFname = currentUser.displayName!.split(' ').first;
                print('✅ Got name from Firebase Auth display name: $finalCaregiverFname');
              } else if (currentUser.email != null) {
                // Extract first part of email as fallback
                finalCaregiverFname = currentUser.email!.split('@').first;
                print('✅ Got name from Firebase Auth email: $finalCaregiverFname');
              }
            }
          } catch (e) {
            print('❌ Error getting name from Firebase Auth: $e');
          }
        }
        
        // Final fallback
        if (finalCaregiverFname == 'Unknown Caregiver') {
          finalCaregiverFname = 'Caregiver';
          print('⚠️ Using generic caregiver name as final fallback');
        }
      }

      // Create a date string for easier querying (YYYY-MM-DD format)
      final dateString = '${taskDate.year}-${taskDate.month.toString().padLeft(2, '0')}-${taskDate.day.toString().padLeft(2, '0')}';

      final logData = {
        'log_id': '',
        'task_id': taskId,
        'caregiver_id': caregiverId,
        'caregiver_fname': finalCaregiverFname,
        'elderly_id': elderlyId,
        'elderly_fname': elderlyFname,
        'task_description': taskDescription,
        'status': status,
        'completion_time': FieldValue.serverTimestamp(),
        'reason': reason ?? '',
        'logged_at': FieldValue.serverTimestamp(),
        'task_date': taskDate,
        'date_string': dateString, // Add this for easier querying
      };

      // Add the document and get the reference to set the log_id
      final docRef = await _firestore.collection('task_logs').add(logData);
      
      // Update the document with its own ID
      await docRef.update({'log_id': docRef.id});
      
      print('✅ Task log created successfully for task: $taskDescription, Status: $status');
    } catch (e) {
      print('❌ Error creating task log: $e');
      rethrow;
    }
  }

  /// Gets task logs for a specific date
  static Stream<List<Map<String, dynamic>>> getTaskLogsForDate(DateTime date) {
    // Create date string for querying (YYYY-MM-DD format)
    final dateString = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    return _firestore
        .collection('task_logs')
        .where('date_string', isEqualTo: dateString)
        .snapshots()
        .map((snapshot) {
      // Sort the results in memory by completion_time
      final docs = snapshot.docs.map((doc) {
        final data = doc.data();
        data['log_id'] = doc.id;
        return data;
      }).toList();
      
      // Sort by completion_time
      docs.sort((a, b) {
        final aTime = (a['completion_time'] as Timestamp?)?.toDate() ?? DateTime.now();
        final bTime = (b['completion_time'] as Timestamp?)?.toDate() ?? DateTime.now();
        return aTime.compareTo(bTime);
      });
      
      return docs;
    });
  }

  /// Gets task logs for a specific caregiver on a specific date
  static Stream<List<Map<String, dynamic>>> getTaskLogsForCaregiverAndDate(
      String caregiverId, DateTime date) {
    // Create date string for querying (YYYY-MM-DD format)
    final dateString = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    return _firestore
        .collection('task_logs')
        .where('caregiver_id', isEqualTo: caregiverId)
        .where('date_string', isEqualTo: dateString)
        .snapshots()
        .map((snapshot) {
      // Sort the results in memory by completion_time
      final docs = snapshot.docs.map((doc) {
        final data = doc.data();
        data['log_id'] = doc.id;
        return data;
      }).toList();
      
      // Sort by completion_time
      docs.sort((a, b) {
        final aTime = (a['completion_time'] as Timestamp?)?.toDate() ?? DateTime.now();
        final bTime = (b['completion_time'] as Timestamp?)?.toDate() ?? DateTime.now();
        return aTime.compareTo(bTime);
      });
      
      return docs;
    });
  }

  /// Helper method to get caregiver's first name from user document
  static Future<String> _getCaregiverName(String caregiverId) async {
    try {
      print('🔍 Getting caregiver name for ID: $caregiverId');
      
      // First, try to get from current Firebase user (most reliable)
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        if (currentUser.displayName != null && currentUser.displayName!.isNotEmpty) {
          final firstName = currentUser.displayName!.split(' ').first;
          print('✅ Got caregiver name from Firebase Auth display name: $firstName');
          return firstName;
        }
      }
      
      // Fallback: try to get from users collection
      final userDoc = await _firestore.collection('users').doc(caregiverId).get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final result = userData['user_fname'] ?? userData['fname'] ?? userData['first_name'] ?? userData['firstName'];
        if (result != null && result.toString().isNotEmpty) {
          print('✅ Got caregiver name from users collection: $result');
          return result.toString();
        }
      }
      
      // Final fallback: use email or generic name
      if (currentUser?.email != null) {
        final emailName = currentUser!.email!.split('@').first;
        print('✅ Using email-based name: $emailName');
        return emailName;
      }
      
      print('⚠️ Using generic caregiver name');
      return 'Caregiver';
    } catch (e) {
      print('❌ Error getting caregiver name: $e');
      return 'Caregiver';
    }
  }

  /// Formats the task log message based on status
  static String formatLogMessage({
    required String caregiverFname,
    required String elderlyFname,
    required String taskDescription,
    required String status,
  }) {
    print('🔍 Formatting log message - Elderly name: "$elderlyFname"');
    
    // Handle different elderly name formats
    String elderlyTitle = 'Lola'; // Default
    String cleanElderlyName = elderlyFname;
    
    if (elderlyFname.startsWith('Male ')) {
      elderlyTitle = 'Lolo';
      cleanElderlyName = elderlyFname.replaceFirst('Male ', '');
    } else if (elderlyFname.startsWith('Female ')) {
      elderlyTitle = 'Lola';
      cleanElderlyName = elderlyFname.replaceFirst('Female ', '');
    } else if (elderlyFname.startsWith('Lolo ')) {
      elderlyTitle = 'Lolo';
      cleanElderlyName = elderlyFname.replaceFirst('Lolo ', '');
    } else if (elderlyFname.startsWith('Lola ')) {
      elderlyTitle = 'Lola';
      cleanElderlyName = elderlyFname.replaceFirst('Lola ', '');
    } else {
      // If no prefix, assume it's just the name and use Lola as default
      // or try to infer from the name itself
      cleanElderlyName = elderlyFname;
    }
    
    print('✅ Parsed - Title: "$elderlyTitle", Name: "$cleanElderlyName"');
    
    switch (status) {
      case 'Complete':
        return 'Caregiver $caregiverFname completed "$taskDescription" for $elderlyTitle $cleanElderlyName.';
      case 'Incomplete':
        return 'Caregiver $caregiverFname didn\'t complete "$taskDescription" for $elderlyTitle $cleanElderlyName.';
      case 'Missed':
        return 'Caregiver $caregiverFname missed "$taskDescription" for $elderlyTitle $cleanElderlyName.';
      default:
        return 'Caregiver $caregiverFname performed "$taskDescription" for $elderlyTitle $cleanElderlyName.';
    }
  }

  /// Formats timestamp to display time (e.g., "10:00 AM")
  static String formatCompletionTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    
    final dateTime = timestamp.toDate();
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    
    return '$displayHour:$minute $period';
  }
}