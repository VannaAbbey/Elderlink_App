import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum ShiftLogType {
  task,
  emergencyAlert,
  incidentReport,
}

class CaregiverShiftLogService {
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
        'log_type': 'task',
        'task_id': taskId,
        'caregiver_id': caregiverId,
        'caregiver_fname': finalCaregiverFname,
        'elderly_id': elderlyId,
        'elderly_fname': elderlyFname,
        'task_description': taskDescription,
        'task_status': status, // Changed from 'status' to 'task_status'
        'completion_time': FieldValue.serverTimestamp(),
        'inc_reason': reason ?? '', // Changed from 'reason' to 'inc_reason'
        'logged_at': FieldValue.serverTimestamp(),
        'task_date': taskDate,
        'date_string': dateString,
        // Removed 'description' field entirely
        'emergency_type': '',
        'incident_type': '',
        'additional_info': '', // Keep consistent with other log types
      };

      // Add the document and get the reference to set the log_id
      final docRef = await _firestore.collection('cg_shift_logs').add(logData);
      
      // Update the document with its own ID
      await docRef.update({'log_id': docRef.id});
      
      print('✅ Task log created successfully for task: $taskDescription, Status: $status');
    } catch (e) {
      print('❌ Error creating task log: $e');
      rethrow;
    }
  }

  /// Creates an emergency alert log entry
  static Future<void> createEmergencyAlertLog({
    required String caregiverId,
    required String emergencyType,
    required String description,
    String? caregiverFname,
  }) async {
    try {
      print('🔍 Creating emergency alert log with data:');
      print('   - Caregiver ID: $caregiverId');
      print('   - Emergency Type: "$emergencyType"');
      print('   - Additional Info: "$description"');
      
      // Get caregiver's first name
      String finalCaregiverFname;
      if (caregiverFname != null && caregiverFname.isNotEmpty) {
        finalCaregiverFname = caregiverFname;
        print('✅ Using provided caregiver name: $finalCaregiverFname');
      } else {
        finalCaregiverFname = await _getCaregiverName(caregiverId);
        
        // Final fallback
        if (finalCaregiverFname == 'Unknown Caregiver') {
          finalCaregiverFname = 'Caregiver';
          print('⚠️ Using generic caregiver name as final fallback');
        }
      }

      final now = DateTime.now();
      final dateString = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final logData = {
        'log_id': '',
        'log_type': 'emergency_alert',
        'caregiver_id': caregiverId,
        'caregiver_fname': finalCaregiverFname,
        'emergency_type': emergencyType,
        'additional_info': description, // Store additional info separately
        'completion_time': FieldValue.serverTimestamp(),
        'logged_at': FieldValue.serverTimestamp(),
        'task_date': now,
        'date_string': dateString,
        // Empty fields for other log types
        'task_id': '',
        'elderly_id': '',
        'elderly_fname': '',
        'task_description': '',
        'task_status': '', // Changed from 'status' to 'task_status'
        'inc_reason': '', // Changed from 'reason' to 'inc_reason'
        'incident_type': '',
        // Removed 'description' field entirely
      };

      // Add the document and get the reference to set the log_id
      final docRef = await _firestore.collection('cg_shift_logs').add(logData);
      
      // Update the document with its own ID
      await docRef.update({'log_id': docRef.id});
      
      print('✅ Emergency alert log created successfully for type: $emergencyType');
    } catch (e) {
      print('❌ Error creating emergency alert log: $e');
      rethrow;
    }
  }

  /// Creates an incident report log entry
  static Future<void> createIncidentReportLog({
    required String caregiverId,
    required String incidentType,
    required String description,
    String? caregiverFname,
  }) async {
    try {
      print('🔍 Creating incident report log with data:');
      print('   - Caregiver ID: $caregiverId');
      print('   - Incident Type: "$incidentType"');
      print('   - Additional Info: "$description"');
      
      // Get caregiver's first name
      String finalCaregiverFname;
      if (caregiverFname != null && caregiverFname.isNotEmpty) {
        finalCaregiverFname = caregiverFname;
        print('✅ Using provided caregiver name: $finalCaregiverFname');
      } else {
        finalCaregiverFname = await _getCaregiverName(caregiverId);
        
        // Final fallback
        if (finalCaregiverFname == 'Unknown Caregiver') {
          finalCaregiverFname = 'Caregiver';
          print('⚠️ Using generic caregiver name as final fallback');
        }
      }

      final now = DateTime.now();
      final dateString = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final logData = {
        'log_id': '',
        'log_type': 'incident_report',
        'caregiver_id': caregiverId,
        'caregiver_fname': finalCaregiverFname,
        'incident_type': incidentType,
        'additional_info': description, // Store additional info separately
        'completion_time': FieldValue.serverTimestamp(),
        'logged_at': FieldValue.serverTimestamp(),
        'task_date': now,
        'date_string': dateString,
        // Empty fields for other log types
        'task_id': '',
        'elderly_id': '',
        'elderly_fname': '',
        'task_description': '',
        'task_status': '', // Changed from 'status' to 'task_status'
        'inc_reason': '', // Changed from 'reason' to 'inc_reason'
        'emergency_type': '',
        // Removed 'description' field entirely
      };

      // Add the document and get the reference to set the log_id
      final docRef = await _firestore.collection('cg_shift_logs').add(logData);
      
      // Update the document with its own ID
      await docRef.update({'log_id': docRef.id});
      
      print('✅ Incident report log created successfully for type: $incidentType');
    } catch (e) {
      print('❌ Error creating incident report log: $e');
      rethrow;
    }
  }

  /// Gets shift logs for a specific date (all types)
  static Stream<List<Map<String, dynamic>>> getShiftLogsForDate(DateTime date) {
    final dateString = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    return _firestore
        .collection('cg_shift_logs')
        .where('date_string', isEqualTo: dateString)
        .snapshots()
        .map((snapshot) {
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

  /// Gets shift logs for a specific caregiver on a specific date
  static Stream<List<Map<String, dynamic>>> getShiftLogsForCaregiverAndDate(
      String caregiverId, DateTime date) {
    final dateString = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    return _firestore
        .collection('cg_shift_logs')
        .where('caregiver_id', isEqualTo: caregiverId)
        .where('date_string', isEqualTo: dateString)
        .snapshots()
        .map((snapshot) {
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

  /// Formats the log message based on log type and data
  static String formatLogMessage(Map<String, dynamic> logData) {
    final logType = logData['log_type'];
    final caregiverFname = logData['caregiver_fname'] ?? 'Caregiver';
    
    switch (logType) {
      case 'task':
        return _formatTaskLogMessage(
          caregiverFname: caregiverFname,
          elderlyFname: logData['elderly_fname'] ?? '',
          taskDescription: logData['task_description'] ?? '',
          status: logData['task_status'] ?? '', // Changed from 'status' to 'task_status'
        );
      case 'emergency_alert':
        return 'Caregiver $caregiverFname sent an Emergency Alert';
      case 'incident_report':
        return 'Caregiver $caregiverFname sent an Incident Report';
      default:
        return 'Unknown log type';
    }
  }

  /// Gets the description/reason for the log entry
  static String? getLogDescription(Map<String, dynamic> logData) {
    final logType = logData['log_type'];
    
    switch (logType) {
      case 'task':
        final reason = logData['inc_reason']?.toString(); // Changed from 'reason' to 'inc_reason'
        return (reason != null && reason.isNotEmpty) ? 'Reason: $reason' : null;
      case 'emergency_alert':
        final emergencyType = logData['emergency_type']?.toString() ?? '';
        final additionalInfo = logData['additional_info']?.toString() ?? '';
        
        String description = '"$emergencyType"';
        if (additionalInfo.isNotEmpty) {
          description += ' - $additionalInfo';
        }
        return description;
      case 'incident_report':
        final incidentType = logData['incident_type']?.toString() ?? '';
        final additionalInfo = logData['additional_info']?.toString() ?? '';
        
        String description = '"$incidentType"';
        if (additionalInfo.isNotEmpty) {
          description += ' - $additionalInfo';
        }
        return description;
      default:
        return null;
    }
  }

  /// Formats the task log message based on status
  static String _formatTaskLogMessage({
    required String caregiverFname,
    required String elderlyFname,
    required String taskDescription,
    required String status,
  }) {
    print('🔍 Formatting task log message - Elderly name: "$elderlyFname"');
    
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

  // =============================================================================
  // BACKWARD COMPATIBILITY METHODS FOR TASKLOGSERVICE
  // These methods maintain the same interface as the old TaskLogService
  // =============================================================================

  /// Gets task logs for a specific date (backward compatibility)
  /// Filters the unified shift logs to return only task logs
  static Stream<List<Map<String, dynamic>>> getTaskLogsForDate(DateTime date) {
    return getShiftLogsForDate(date).map((logs) {
      // Filter to only return task logs
      return logs.where((log) => log['log_type'] == 'task').toList();
    });
  }

  /// Gets task logs for a specific caregiver on a specific date (backward compatibility)
  /// Filters the unified shift logs to return only task logs
  static Stream<List<Map<String, dynamic>>> getTaskLogsForCaregiverAndDate(
      String caregiverId, DateTime date) {
    return getShiftLogsForCaregiverAndDate(caregiverId, date).map((logs) {
      // Filter to only return task logs
      return logs.where((log) => log['log_type'] == 'task').toList();
    });
  }

  /// Formats the task log message based on status (backward compatibility)
  /// This delegates to the unified service for task logs specifically
  static String formatTaskLogMessage({
    required String caregiverFname,
    required String elderlyFname,
    required String taskDescription,
    required String status,
  }) {
    final taskLogData = {
      'log_type': 'task',
      'caregiver_fname': caregiverFname,
      'elderly_fname': elderlyFname,
      'task_description': taskDescription,
      'task_status': status, // Changed from 'status' to 'task_status'
    };
    return formatLogMessage(taskLogData);
  }
}