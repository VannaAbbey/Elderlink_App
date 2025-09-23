import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class ShiftHandoverService {
  static const String shiftsCollection = 'shifts';
  static const String taskLogsCollection = 'task_logs';
  static const String additionalLogsCollection = 'additional_logs';

  /// Creates or updates shift information
  static Future<String> createOrUpdateShift({
    required DateTime shiftDate,
    required String shiftType, // 'morning', 'afternoon', 'night'
    required List<String> elderlyIds,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('ShiftHandoverService: No authenticated user found');
        throw Exception('No authenticated user');
      }

      final dateString = DateFormat('yyyy-MM-dd').format(shiftDate);
      final shiftId = '${shiftType}_${dateString}_${user.uid}';

      print('ShiftHandoverService: Creating shift: $shiftId');

      await FirebaseFirestore.instance
          .collection(shiftsCollection)
          .doc(shiftId)
          .set({
        'shift_id': shiftId,
        'caregiver_id': user.uid,
        'caregiver_email': user.email ?? '',
        'caregiver_name': user.displayName ?? 'Unknown Caregiver',
        'shift_type': shiftType,
        'shift_date': dateString,
        'elderly_ids': elderlyIds,
        'status': 'active',
        'start_time': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('ShiftHandoverService: Shift created successfully');
      return shiftId;
    } catch (e) {
      print('ShiftHandoverService: Error creating shift: $e');
      rethrow;
    }
  }

  /// Marks a shift as completed
  static Future<void> completeShift(String shiftId) async {
    try {
      print('ShiftHandoverService: Completing shift: $shiftId');

      await FirebaseFirestore.instance
          .collection(shiftsCollection)
          .doc(shiftId)
          .update({
        'status': 'completed',
        'end_time': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      print('ShiftHandoverService: Shift completed successfully');
    } catch (e) {
      print('ShiftHandoverService: Error completing shift: $e');
      rethrow;
    }
  }

  /// Gets the previous shift data for handover (collective from all previous shift caregivers)
  static Future<Map<String, dynamic>?> getPreviousShiftData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('ShiftHandoverService: No authenticated user found');
        return null;
      }

      print('🚀 === DEBUGGING getPreviousShiftData() ===');
      print('🚀 Current user ID: ${user.uid}');
      print('🚀 Current time: ${DateTime.now()}');
      
      // First, let's see ALL cg_house_assign documents to understand the data structure
      await _debugDatabaseState();

      // Get current caregiver's house and shift information from cg_house_assign
      final currentCaregiverAssignQuery = await FirebaseFirestore.instance
          .collection('cg_house_assign')
          .where('caregiver_id', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (currentCaregiverAssignQuery.docs.isEmpty) {
        print('ShiftHandoverService: No assignment found for current caregiver');
        return null;
      }

      final currentAssignment = currentCaregiverAssignQuery.docs.first.data();
      final currentHouseId = currentAssignment['house_id'] as String;
      final currentTimeRange = currentAssignment['time_range'] as Map<String, dynamic>?;
      final currentShift = currentAssignment['shift'];

      print('🏠 === CURRENT USER INFO ===');
      print('🏠 User ID: ${user.uid}');
      print('🏠 House ID: $currentHouseId');
      print('🏠 Current shift: $currentShift');
      print('🏠 Time range: $currentTimeRange');
      print('🏠 Days assigned: ${currentAssignment['days_assigned']}');
      print('🏠 Full assignment: $currentAssignment');

      // Determine previous shift timing based on current shift
      String previousShiftType = '';
      if (currentShift is String) {
        final shiftLower = currentShift.toLowerCase();
        print('ShiftHandoverService: Current shift (lowercase): "$shiftLower"');
        
        if (shiftLower.contains('1st') || shiftLower.contains('morning') || 
            (currentTimeRange != null && currentTimeRange['start'] == '06:00')) {
          previousShiftType = '3rd Shift'; // Night shift hands over to morning
        } else if (shiftLower.contains('2nd') || shiftLower.contains('afternoon') || 
                   (currentTimeRange != null && currentTimeRange['start'] == '14:00')) {
          previousShiftType = '1st Shift'; // Morning shift hands over to afternoon
        } else if (shiftLower.contains('3rd') || shiftLower.contains('night') || 
                   (currentTimeRange != null && currentTimeRange['start'] == '22:00')) {
          previousShiftType = '2nd Shift'; // Afternoon shift hands over to night
        }
      }

      print('ShiftHandoverService: Looking for previous shift type: "$previousShiftType"');

      // Find all caregivers who worked the previous shift in the same house
      List<String> previousShiftCaregiverIds = [];
      if (previousShiftType.isNotEmpty) {
        // Try exact match first
        final previousCaregiverQuery = await FirebaseFirestore.instance
            .collection('cg_house_assign')
            .where('house_id', isEqualTo: currentHouseId)
            .where('shift', isEqualTo: previousShiftType)
            .get();

        // Filter by caregivers who are actually scheduled to work today
        final today = DateTime.now();
        final todayName = _getDayName(today);
        print('🔍 ShiftHandoverService: Filtering caregivers for today: $todayName');
        
        for (var doc in previousCaregiverQuery.docs) {
          final data = doc.data();
          final caregiverId = data['caregiver_id'] as String;
          final daysAssigned = data['days_assigned'] as List<dynamic>? ?? [];
          
          print('🔍 ShiftHandoverService: Checking caregiver $caregiverId - days assigned: $daysAssigned');
          
          // Only include caregivers who are scheduled to work today and not the current user
          if (caregiverId != user.uid && daysAssigned.contains(todayName)) {
            previousShiftCaregiverIds.add(caregiverId);
            print('✅ ShiftHandoverService: ADDED caregiver $caregiverId (works on $todayName)');
          } else {
            print('❌ ShiftHandoverService: SKIPPED caregiver $caregiverId (days: $daysAssigned, today: $todayName)');
          }
        }
        
        print('ShiftHandoverService: Found ${previousShiftCaregiverIds.length} caregivers with exact shift match and day filtering');
        
        // If no exact match, try partial matching with day filtering
        if (previousShiftCaregiverIds.isEmpty) {
          print('🔍 ShiftHandoverService: No exact matches found, trying partial matching with day filtering...');
          final allHouseCaregivers = await FirebaseFirestore.instance
              .collection('cg_house_assign')
              .where('house_id', isEqualTo: currentHouseId)
              .get();
          
          for (var doc in allHouseCaregivers.docs) {
            final data = doc.data();
            final caregiverId = data['caregiver_id'] as String;
            final shift = data['shift'] as String?;
            final daysAssigned = data['days_assigned'] as List<dynamic>? ?? [];
            
            if (caregiverId != user.uid && shift != null && daysAssigned.contains(todayName)) {
              final shiftLower = shift.toLowerCase();
              final previousShiftLower = previousShiftType.toLowerCase();
              
              if (shiftLower.contains(previousShiftLower.split(' ')[0])) {
                previousShiftCaregiverIds.add(caregiverId);
                print('✅ ShiftHandoverService: ADDED caregiver $caregiverId via partial match (works on $todayName)');
              }
            }
          }
          print('ShiftHandoverService: Found ${previousShiftCaregiverIds.length} caregivers with partial shift match and day filtering');
        }
      }

      // If no specific shift match, find caregivers with different time ranges in same house
      if (previousShiftCaregiverIds.isEmpty) {
        print('ShiftHandoverService: No shift name match found, trying time-based matching...');
        
        final allHouseCaregiverQuery = await FirebaseFirestore.instance
            .collection('cg_house_assign')
            .where('house_id', isEqualTo: currentHouseId)
            .get();

        print('ShiftHandoverService: Found ${allHouseCaregiverQuery.docs.length} total caregivers in house');

        for (var doc in allHouseCaregiverQuery.docs) {
          final data = doc.data();
          final caregiverId = data['caregiver_id'] as String;
          final timeRange = data['time_range'] as Map<String, dynamic>?;
          final shift = data['shift'] as String?;
          
          print('ShiftHandoverService: Checking caregiver $caregiverId, shift: $shift, timeRange: $timeRange');
          
          // Skip current caregiver
          if (caregiverId == user.uid) continue;
          
          // Check if this caregiver has a different shift time (previous shift)
          if (currentTimeRange != null && timeRange != null && _isPreviousShift(currentTimeRange, timeRange)) {
            previousShiftCaregiverIds.add(caregiverId);
            print('ShiftHandoverService: Added caregiver $caregiverId based on time range match');
          }
        }
        
        print('ShiftHandoverService: Time-based matching found ${previousShiftCaregiverIds.length} caregivers');
      }

      print('ShiftHandoverService: Found ${previousShiftCaregiverIds.length} previous shift caregivers: $previousShiftCaregiverIds');

      // If still no caregivers found, get ALL other caregivers in the house as fallback
      if (previousShiftCaregiverIds.isEmpty) {
        print('ShiftHandoverService: No previous shift caregivers found, using fallback to get all house caregivers');
        
        final allHouseCaregiverQuery = await FirebaseFirestore.instance
            .collection('cg_house_assign')
            .where('house_id', isEqualTo: currentHouseId)
            .get();

        previousShiftCaregiverIds = allHouseCaregiverQuery.docs
            .map((doc) => doc.data()['caregiver_id'] as String)
            .where((id) => id != user.uid) // Exclude current caregiver
            .toList();
            
        print('ShiftHandoverService: Fallback found ${previousShiftCaregiverIds.length} other caregivers in house');
      }

      if (previousShiftCaregiverIds.isEmpty) {
        print('ShiftHandoverService: No other caregivers found in house, checking for any task logs today as final fallback');
        
        // Final fallback - show any task logs from today
        final today = DateTime.now();
        final todayString = DateFormat('yyyy-MM-dd').format(today);
        
        final anyTaskLogsQuery = await FirebaseFirestore.instance
            .collection(taskLogsCollection)
            .where('date_string', isEqualTo: todayString)
            .get();
        
        if (anyTaskLogsQuery.docs.isNotEmpty) {
          print('ShiftHandoverService: Found ${anyTaskLogsQuery.docs.length} task logs for today as fallback');
          
          final fallbackTaskLogs = anyTaskLogsQuery.docs.map((doc) {
            final data = doc.data();
            data['source_caregiver_name'] = data['caregiver_fname'] ?? 'Unknown Caregiver';
            return data;
          }).toList();
          
          // Sort fallback logs by completion time
          fallbackTaskLogs.sort((a, b) {
            final timeA = a['completion_time'] as Timestamp?;
            final timeB = b['completion_time'] as Timestamp?;
            if (timeA == null && timeB == null) return 0;
            if (timeA == null) return 1;
            if (timeB == null) return -1;
            return timeA.compareTo(timeB);
          });
          
          return {
            'shift_info': {
              'shift_type': 'Previous Tasks',
              'house_id': currentHouseId,
              'total_caregivers': 1,
              'caregiver_info': [{'caregiver_id': 'fallback', 'caregiver_name': 'Previous Caregivers'}],
              'shift_date': todayString,
            },
            'task_logs': fallbackTaskLogs,
            'additional_log_content': 'Showing all available task logs for today.',
          };
        }
        
        print('ShiftHandoverService: No task logs found for today either');
        return null;
      }

      // Get today's date
      final today = DateTime.now();
      final todayString = DateFormat('yyyy-MM-dd').format(today);
      final yesterdayString = DateFormat('yyyy-MM-dd').format(today.subtract(Duration(days: 1)));

      // Collect task logs from all previous shift caregivers (today and yesterday)
      List<Map<String, dynamic>> allTaskLogs = [];
      List<Map<String, dynamic>> allCaregiverInfo = [];
      List<String> allAdditionalLogContents = [];

      for (String caregiverId in previousShiftCaregiverIds) {
        // Get actual caregiver name from users collection
        String caregiverName = 'Unknown';
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(caregiverId)
              .get();
          
          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            caregiverName = userData['user_fname'] ?? userData['fname'] ?? userData['first_name'] ?? userData['firstName'] ?? 'Unknown';
          }
        } catch (e) {
          print('ShiftHandoverService: Error getting caregiver name for ID $caregiverId: $e');
        }
        
        print('ShiftHandoverService: Processing caregiver ID: $caregiverId, Name: $caregiverName');

        // Get task logs for today first, then yesterday if needed
        for (String dateString in [todayString, yesterdayString]) {
          // Simplified query without orderBy to avoid index requirement
          final taskLogsQuery = await FirebaseFirestore.instance
              .collection(taskLogsCollection)
              .where('caregiver_id', isEqualTo: caregiverId)
              .where('date_string', isEqualTo: dateString)
              .get();

          final caregiverTaskLogs = taskLogsQuery.docs.map((doc) {
            final data = doc.data();
            
            // Use the caregiver name we already determined for this caregiver
            data['source_caregiver_name'] = caregiverName;
            return data;
          }).toList();

          allTaskLogs.addAll(caregiverTaskLogs);

          // Get additional logs
          final additionalLogDoc = await FirebaseFirestore.instance
              .collection(additionalLogsCollection)
              .doc('${caregiverId}_$dateString')
              .get();

          if (additionalLogDoc.exists) {
            final content = additionalLogDoc.data()?['content'] ?? '';
            if (content.isNotEmpty) {
              allAdditionalLogContents.add('$caregiverName: $content');
            }
          }
        }
      }

      // Populate caregiver info based on ALL previous shift caregivers (not just those with task logs)
      for (String caregiverId in previousShiftCaregiverIds) {
        // Get actual caregiver name from users collection
        String caregiverName = 'Unknown';
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(caregiverId)
              .get();
          
          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            caregiverName = userData['user_fname'] ?? userData['fname'] ?? userData['first_name'] ?? userData['firstName'] ?? 'Unknown';
          }
        } catch (e) {
          print('ShiftHandoverService: Error getting caregiver name for ID $caregiverId: $e');
        }
        
        allCaregiverInfo.add({
          'caregiver_id': caregiverId,
          'caregiver_name': caregiverName,
        });
        print('ShiftHandoverService: Added caregiver info: $caregiverName (ID: $caregiverId)');
      }

      // Sort all task logs by completion time (ascending - oldest first)
      allTaskLogs.sort((a, b) {
        final timeA = a['completion_time'] as Timestamp?;
        final timeB = b['completion_time'] as Timestamp?;
        if (timeA == null && timeB == null) return 0;
        if (timeA == null) return 1; // null timestamps go to end
        if (timeB == null) return -1;
        return timeA.compareTo(timeB);
      });

      // Combine all additional log contents
      final combinedAdditionalLogs = allAdditionalLogContents.join('\n\n');

      print('ShiftHandoverService: Retrieved ${allTaskLogs.length} total task logs from ${previousShiftCaregiverIds.length} caregivers');
      print('ShiftHandoverService: Combined additional logs length: ${combinedAdditionalLogs.length}');

      return {
        'shift_info': {
          'shift_type': previousShiftType,
          'house_id': currentHouseId,
          'total_caregivers': previousShiftCaregiverIds.length,
          'caregiver_info': allCaregiverInfo,
          'shift_date': todayString,
        },
        'task_logs': allTaskLogs,
        'additional_log_content': combinedAdditionalLogs,
      };
    } catch (e) {
      print('ShiftHandoverService: Error getting previous shift data: $e');
      return null;
    }
  }

  /// Gets previous shift data for a specific date
  static Future<Map<String, dynamic>?> getPreviousShiftDataForDate(DateTime targetDate) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('ShiftHandoverService: No authenticated user found');
        return null;
      }

      final targetDateString = DateFormat('yyyy-MM-dd').format(targetDate);
      print('🚀 ShiftHandoverService: === STARTING getPreviousShiftDataForDate ===');
      print('🚀 ShiftHandoverService: Target date: $targetDate');
      print('🚀 ShiftHandoverService: Target date string: $targetDateString');
      print('🚀 ShiftHandoverService: Current user ID: ${user.uid}');
      
      // If the target date is today, use the original logic
      final today = DateTime.now();
      final isToday = targetDate.year == today.year && 
                     targetDate.month == today.month && 
                     targetDate.day == today.day;
      
      if (isToday) {
        print('ShiftHandoverService: Target date is today, using current shift handover logic');
        return await getPreviousShiftData();
      }
      
      print('ShiftHandoverService: Target date is historical, showing shift data FROM that date');

      // Get current caregiver's house and shift information from cg_house_assign
      final currentCaregiverAssignQuery = await FirebaseFirestore.instance
          .collection('cg_house_assign')
          .where('caregiver_id', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (currentCaregiverAssignQuery.docs.isEmpty) {
        print('ShiftHandoverService: No house assignment found for current caregiver');
        return null;
      }

      final currentAssignment = currentCaregiverAssignQuery.docs.first.data();
      final currentHouseId = currentAssignment['house_id'];
      final currentShift = currentAssignment['shift'];
      final currentTimeRange = currentAssignment['time_range'];

      print('🏠 ShiftHandoverService: Current caregiver house: $currentHouseId');
      print('🏠 ShiftHandoverService: Current shift: $currentShift');
      print('🏠 ShiftHandoverService: Full assignment data: $currentAssignment');

      // Determine previous shift timing based on current shift
      String previousShiftType = '';
      if (currentShift is String) {
        final shiftLower = currentShift.toLowerCase();
        
        if (shiftLower.contains('1st') || shiftLower.contains('morning') || 
            (currentTimeRange != null && currentTimeRange['start'] == '06:00')) {
          previousShiftType = '3rd Shift'; // Night shift hands over to morning
        } else if (shiftLower.contains('2nd') || shiftLower.contains('afternoon') || 
                   (currentTimeRange != null && currentTimeRange['start'] == '14:00')) {
          previousShiftType = '1st Shift'; // Morning shift hands over to afternoon
        } else if (shiftLower.contains('3rd') || shiftLower.contains('night') || 
                   (currentTimeRange != null && currentTimeRange['start'] == '22:00')) {
          previousShiftType = '2nd Shift'; // Afternoon shift hands over to night
        }
      }

      print('ShiftHandoverService: Looking for previous shift type: "$previousShiftType"');

      // Find all caregivers who worked the previous shift in the same house AND were scheduled for that specific day
      List<String> previousShiftCaregiverIds = [];
      if (previousShiftType.isNotEmpty) {
        // Get the day name from the target date
        final dayName = _getDayName(targetDate);
        print('🔍 ShiftHandoverService: Target date: $targetDate');
        print('🔍 ShiftHandoverService: Day name: $dayName');
        print('🔍 ShiftHandoverService: Looking for previous shift type: $previousShiftType');
        print('🔍 ShiftHandoverService: In house: $currentHouseId');
        
        final previousCaregiverQuery = await FirebaseFirestore.instance
            .collection('cg_house_assign')
            .where('house_id', isEqualTo: currentHouseId)
            .where('shift', isEqualTo: previousShiftType)
            .get();

        print('🏠 ShiftHandoverService: Database query completed');
        print('🏠 ShiftHandoverService: Query filters - house_id: $currentHouseId, shift: $previousShiftType');  
        print('🏠 ShiftHandoverService: Found ${previousCaregiverQuery.docs.length} total caregivers assigned to $previousShiftType shift in house $currentHouseId');
        
        // Debug: show all found caregivers and their house assignments with names
        for (var doc in previousCaregiverQuery.docs) {
          final data = doc.data();
          final caregiverId = data['caregiver_id'];
          
          // Get the actual caregiver name
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(caregiverId)
                .get();
            
            String caregiverName = 'Unknown';
            if (userDoc.exists) {
              final userData = userDoc.data() as Map<String, dynamic>;
              caregiverName = userData['user_fname'] ?? userData['fname'] ?? userData['first_name'] ?? userData['firstName'] ?? 'Unknown';
            }
            
            print('🏠 DEBUG: Found caregiver $caregiverName (ID: $caregiverId) in house ${data['house_id']} with shift ${data['shift']}, days: ${data['days_assigned']}');
          } catch (e) {
            print('🏠 DEBUG: Found caregiver ID $caregiverId in house ${data['house_id']} with shift ${data['shift']}, days: ${data['days_assigned']} (name lookup failed: $e)');
          }
        }

        if (previousCaregiverQuery.docs.isEmpty) {
          print('❌ ShiftHandoverService: No caregivers found for shift type: $previousShiftType');
          print('❌ ShiftHandoverService: This might indicate the shift type format in database is different');
        }

        // Filter by caregivers who were actually scheduled to work on this day
        for (var doc in previousCaregiverQuery.docs) {
          final data = doc.data();
          final caregiverId = data['caregiver_id'] as String;
          final daysAssigned = data['days_assigned'] as List<dynamic>? ?? [];
          
          print('🔍 ShiftHandoverService: Checking caregiver $caregiverId:');
          print('   - Days assigned: $daysAssigned');
          print('   - Target day: $dayName');
          print('   - Contains target day: ${daysAssigned.contains(dayName)}');
          
          // Only include caregivers who were scheduled to work on the target day
          if (caregiverId != user.uid && daysAssigned.contains(dayName)) {
            previousShiftCaregiverIds.add(caregiverId);
            print('✅ ShiftHandoverService: ADDED caregiver $caregiverId (works on $dayName)');
          } else {
            print('❌ ShiftHandoverService: SKIPPED caregiver $caregiverId (days: $daysAssigned, target: $dayName, current user: ${user.uid})');
          }
        }
        
        print('🔍 ShiftHandoverService: Final filtered caregivers: ${previousShiftCaregiverIds.length}');
        print('🔍 ShiftHandoverService: Caregiver IDs: $previousShiftCaregiverIds');
      }

      if (previousShiftCaregiverIds.isEmpty) {
        final dayName = _getDayName(targetDate);
        print('⚠️ ShiftHandoverService: No previous shift caregivers found for date: $targetDateString');
        print('⚠️ ShiftHandoverService: This suggests either:');
        print('   1. No caregivers were assigned to $previousShiftType shift for $dayName');
        print('   2. The database days_assigned field format is different than expected');
        print('   3. The shift type matching is not working correctly');
        
        // Don't use fallback logic that ignores shift assignments - this causes incorrect handover displays
        print('❌ ShiftHandoverService: Returning null instead of using fallback to maintain shift integrity');
        return null;
      } else {
        print('ShiftHandoverService: Found ${previousShiftCaregiverIds.length} previous shift caregivers');
      }

      // Collect all task logs and additional logs from all previous shift caregivers
      List<Map<String, dynamic>> allTaskLogs = [];
      List<String> allAdditionalLogContents = [];
      List<Map<String, dynamic>> allCaregiverInfo = [];

      for (String caregiverId in previousShiftCaregiverIds) {
        // Get actual caregiver name from users collection
        String caregiverName = 'Unknown';
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(caregiverId)
              .get();
          
          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            caregiverName = userData['user_fname'] ?? userData['fname'] ?? userData['first_name'] ?? userData['firstName'] ?? 'Unknown';
            print('ShiftHandoverService: Found caregiver name: $caregiverName for ID: $caregiverId');
          } else {
            print('ShiftHandoverService: No user document found for caregiver ID: $caregiverId');
          }
        } catch (e) {
          print('ShiftHandoverService: Error getting caregiver name for ID $caregiverId: $e');
        }
        
        print('ShiftHandoverService: Processing caregiver ID: $caregiverId, Name: $caregiverName for date: $targetDateString');

        // Get task logs for the target date
        final taskLogsQuery = await FirebaseFirestore.instance
            .collection(taskLogsCollection)
            .where('caregiver_id', isEqualTo: caregiverId)
            .where('date_string', isEqualTo: targetDateString)
            .get();

        final caregiverTaskLogs = taskLogsQuery.docs.map((doc) {
          final data = doc.data();
          data['source_caregiver_name'] = caregiverName;
          return data;
        }).toList();

        allTaskLogs.addAll(caregiverTaskLogs);

        // Get additional logs for the target date
        final additionalLogDoc = await FirebaseFirestore.instance
            .collection(additionalLogsCollection)
            .doc('${caregiverId}_$targetDateString')
            .get();

        if (additionalLogDoc.exists) {
          final content = additionalLogDoc.data()?['content'] ?? '';
          if (content.isNotEmpty) {
            allAdditionalLogContents.add('$caregiverName: $content');
          }
        }
      }

      // Populate caregiver info based on ALL previous shift caregivers (not just those with task logs)
      for (String caregiverId in previousShiftCaregiverIds) {
        // Get actual caregiver name from users collection
        String caregiverName = 'Unknown';
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(caregiverId)
              .get();
          
          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            caregiverName = userData['user_fname'] ?? userData['fname'] ?? userData['first_name'] ?? userData['firstName'] ?? 'Unknown';
          }
        } catch (e) {
          print('ShiftHandoverService: Error getting caregiver name for ID $caregiverId: $e');
        }
        
        allCaregiverInfo.add({
          'caregiver_id': caregiverId,
          'caregiver_name': caregiverName,
        });
        print('ShiftHandoverService: Added caregiver info: $caregiverName (ID: $caregiverId)');
      }

      // Sort all task logs by completion time (ascending - oldest first)
      allTaskLogs.sort((a, b) {
        final timeA = a['completion_time'] as Timestamp?;
        final timeB = b['completion_time'] as Timestamp?;
        if (timeA == null && timeB == null) return 0;
        if (timeA == null) return 1; // null timestamps go to end
        if (timeB == null) return -1;
        return timeA.compareTo(timeB);
      });

      // Combine all additional log contents
      final combinedAdditionalLogs = allAdditionalLogContents.join('\n\n');

      print('ShiftHandoverService: Retrieved ${allTaskLogs.length} total task logs for date: $targetDateString');
      print('ShiftHandoverService: Combined additional logs length: ${combinedAdditionalLogs.length}');

      return {
        'shift_info': {
          'shift_type': previousShiftType,
          'house_id': currentHouseId,
          'total_caregivers': previousShiftCaregiverIds.length,
          'caregiver_info': allCaregiverInfo,
          'shift_date': targetDateString,
        },
        'task_logs': allTaskLogs,
        'additional_log_content': combinedAdditionalLogs,
      };
    } catch (e) {
      print('ShiftHandoverService: Error getting shift data for date: $e');
      return null;
    }
  }

  /// Helper method to determine if a time range represents a previous shift
  static bool _isPreviousShift(Map<String, dynamic> currentTimeRange, Map<String, dynamic> otherTimeRange) {
    try {
      final currentStart = currentTimeRange['start'] as String? ?? '00:00';
      final currentEnd = currentTimeRange['end'] as String? ?? '23:59';
      final otherStart = otherTimeRange['start'] as String? ?? '00:00';
      final otherEnd = otherTimeRange['end'] as String? ?? '23:59';
      
      print('ShiftHandoverService: Comparing shifts - Current: $currentStart-$currentEnd, Other: $otherStart-$otherEnd');
      
      // Parse times
      final currentStartParts = currentStart.split(':');
      final otherEndParts = otherEnd.split(':');
      
      final currentStartMinutes = int.parse(currentStartParts[0]) * 60 + int.parse(currentStartParts[1]);
      final otherEndMinutes = int.parse(otherEndParts[0]) * 60 + int.parse(otherEndParts[1]);
      
      // Check if the other shift ends exactly when current shift starts OR within reasonable handover window
      final timeDifference = currentStartMinutes - otherEndMinutes;
      
      // Perfect handover (other shift ends when current starts) OR within 2 hours
      final isPreviousShift = timeDifference == 0 || (timeDifference > 0 && timeDifference <= 120);
      
      print('ShiftHandoverService: Time difference: $timeDifference minutes, isPreviousShift: $isPreviousShift');
      
      return isPreviousShift;
    } catch (e) {
      print('ShiftHandoverService: Error comparing shift times: $e');
      return false;
    }
  }

  /// Gets shift information for a specific caregiver and date
  static Future<Map<String, dynamic>?> getShiftInfo(String caregiverId, DateTime date) async {
    try {
      final dateString = DateFormat('yyyy-MM-dd').format(date);
      
      final shiftQuery = await FirebaseFirestore.instance
          .collection(shiftsCollection)
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('shift_date', isEqualTo: dateString)
          .limit(1)
          .get();

      if (shiftQuery.docs.isEmpty) {
        return null;
      }

      return shiftQuery.docs.first.data();
    } catch (e) {
      print('ShiftHandoverService: Error getting shift info: $e');
      return null;
    }
  }

  /// Helper method to determine shift type based on current time
  static String getCurrentShiftType() {
    final now = DateTime.now();
    final hour = now.hour;

    if (hour >= 6 && hour < 14) {
      return 'morning';
    } else if (hour >= 14 && hour < 22) {
      return 'afternoon';
    } else {
      return 'night';
    }
  }

  /// Helper method to format shift time range
  static String getShiftTimeRange(String shiftType) {
    switch (shiftType.toLowerCase()) {
      case 'morning':
      case '1st shift':
        return '06:00 - 14:00';
      case 'afternoon':
      case '2nd shift':
        return '14:00 - 22:00';
      case 'night':
      case '3rd shift':
        return '22:00 - 06:00';
      default:
        return 'Unknown';
    }
  }

  /// Format shift information for display (supports both individual and collective shifts)
  static String formatShiftHeader(Map<String, dynamic> shiftInfo) {
    final shiftType = shiftInfo['shift_type'] ?? 'unknown';
    final shiftDate = shiftInfo['shift_date'] ?? '';
    final totalCaregivers = shiftInfo['total_caregivers'] as int? ?? 1;
    final caregiverInfo = shiftInfo['caregiver_info'] as List<dynamic>? ?? [];
    
    // Format date for display
    String formattedDate = shiftDate;
    try {
      final date = DateTime.parse(shiftDate);
      formattedDate = DateFormat('MMMM dd, yyyy').format(date);
    } catch (e) {
      // Keep original format if parsing fails
    }

    final timeRange = getShiftTimeRange(shiftType);

    // Handle collective vs individual shift display
    if (totalCaregivers > 1 && caregiverInfo.isNotEmpty) {
      final caregiverNames = caregiverInfo
          .map((info) => info['caregiver_name'] ?? 'Unknown')
          .join(', ');
      return 'Previous Shift Handover\n$shiftType ($timeRange)\n$formattedDate\nFrom: $caregiverNames';
    } else {
      // Fallback for individual caregiver (backward compatibility)
      final caregiverName = shiftInfo['caregiver_name'] ?? 'Unknown Caregiver';
      return 'Previous Shift - $caregiverName\n$formattedDate ($timeRange)';
    }
  }

  /// Creates sample shift data for testing purposes
  static Future<void> createSampleShiftData() async {
    try {
      print('ShiftHandoverService: Creating sample shift data for testing...');
      
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      
      // Create a sample completed shift
      await FirebaseFirestore.instance
          .collection(shiftsCollection)
          .doc('sample_morning_shift')
          .set({
        'shift_id': 'sample_morning_shift',
        'caregiver_id': 'sample_caregiver_id',
        'caregiver_email': 'matthew@elderlink.com',
        'caregiver_name': 'Matthew Johnson',
        'shift_type': 'morning',
        'shift_date': DateFormat('yyyy-MM-dd').format(yesterday),
        'elderly_ids': ['aaron_id', 'maria_id'],
        'status': 'completed',
        'start_time': Timestamp.fromDate(yesterday.copyWith(hour: 6, minute: 0)),
        'end_time': Timestamp.fromDate(yesterday.copyWith(hour: 14, minute: 0)),
        'created_at': Timestamp.fromDate(yesterday),
        'updated_at': Timestamp.fromDate(yesterday),
      });

      print('ShiftHandoverService: Sample shift data created successfully');
    } catch (e) {
      print('ShiftHandoverService: Error creating sample data: $e');
    }
  }

  /// Debug method to check what data exists in the database
  static Future<void> debugDatabaseState(String currentUserId) async {
    try {
      print('=== DEBUG DATABASE STATE ===');
      
      // Check cg_house_assign for current user
      final userAssignQuery = await FirebaseFirestore.instance
          .collection('cg_house_assign')
          .where('caregiver_id', isEqualTo: currentUserId)
          .get();
      
      print('DEBUG: Current user assignments: ${userAssignQuery.docs.length}');
      for (var doc in userAssignQuery.docs) {
        final data = doc.data();
        print('DEBUG: Assignment - house: ${data['house_id']}, shift: ${data['shift']}, time_range: ${data['time_range']}');
      }
      
      if (userAssignQuery.docs.isNotEmpty) {
        final houseId = userAssignQuery.docs.first.data()['house_id'] as String;
        
        // Check all caregivers in the same house
        final houseCaregiversQuery = await FirebaseFirestore.instance
            .collection('cg_house_assign')
            .where('house_id', isEqualTo: houseId)
            .get();
        
        print('DEBUG: Total caregivers in house $houseId: ${houseCaregiversQuery.docs.length}');
        for (var doc in houseCaregiversQuery.docs) {
          final data = doc.data();
          print('DEBUG: House caregiver - id: ${data['caregiver_id']}, shift: ${data['shift']}, time_range: ${data['time_range']}');
        }
        
        // Check task logs for today
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        print('DEBUG: Checking task logs for date: $today');
        
        final taskLogsQuery = await FirebaseFirestore.instance
            .collection(taskLogsCollection)
            .where('date_string', isEqualTo: today)
            .get();
        
        print('DEBUG: Total task logs for today: ${taskLogsQuery.docs.length}');
        for (var doc in taskLogsQuery.docs) {
          final data = doc.data();
          print('DEBUG: Task log - caregiver: ${data['caregiver_id']}, elderly: ${data['elderly_fname']}, task: ${data['task_description']}, time: ${data['completion_time']}');
        }
      }
      
      print('=== END DEBUG ===');
    } catch (e) {
      print('DEBUG: Error checking database state: $e');
    }
  }

  /// Helper method to get day name from DateTime
  static String _getDayName(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return '';
    }
  }

  /// Debug method to understand database structure
  static Future<void> _debugDatabaseState() async {
    try {
      print('🔍 === DATABASE DEBUG START ===');
      
      // Get ALL cg_house_assign documents
      final allAssignments = await FirebaseFirestore.instance
          .collection('cg_house_assign')
          .get();
      
      print('🔍 Total cg_house_assign documents: ${allAssignments.docs.length}');
      
      // Group by house for better analysis
      Map<String, List<Map<String, dynamic>>> houseGroups = {};
      
      for (var doc in allAssignments.docs) {
        final data = doc.data();
        final houseId = data['house_id']?.toString() ?? 'unknown';
        
        if (!houseGroups.containsKey(houseId)) {
          houseGroups[houseId] = [];
        }
        houseGroups[houseId]!.add(data);
      }
      
      // Print organized data by house
      for (var entry in houseGroups.entries) {
        final houseId = entry.key;
        final assignments = entry.value;
        
        print('🏠 === HOUSE: $houseId (${assignments.length} caregivers) ===');
        
        for (var assignment in assignments) {
          print('  👤 Caregiver: ${assignment['caregiver_id']}');
          print('     - Shift: ${assignment['shift']}');
          print('     - Days Assigned: ${assignment['days_assigned']}');
          print('     - Time Range: ${assignment['time_range']}');
          print('     ---');
        }
      }
      
      print('🔍 === DATABASE DEBUG END ===');
    } catch (e) {
      print('❌ Error in database debug: $e');
    }
  }
}