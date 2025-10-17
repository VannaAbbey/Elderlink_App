import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../services/cg_services/task_reminder_service.dart';
import '../services/cg_services/caregiver_shift_log_service.dart';
import '../services/cg_services/notification_service.dart';
import '../services/cg_services/house_service.dart';
import '../models/cg_models/notification_model.dart';

// Helper function to create a new task and set 'created_by' to the current caregiver's UID
Future<void> createTaskWithCreator(Map<String, dynamic> taskData) async {
  print('🚨 createTaskWithCreator CALLED for: ${taskData['task_description']}');
  print('🚨 Call #${DateTime.now().millisecondsSinceEpoch}');
  
  final currentUser = FirebaseAuth.instance.currentUser;
  final caregiverId = currentUser?.uid;
  final dataWithCreator = Map<String, dynamic>.from(taskData);
  if (caregiverId != null) {
    dataWithCreator['created_by'] = caregiverId;
  }
  
  // Create the task in Firestore
  final docRef = await FirebaseFirestore.instance.collection('care_tasks').add(dataWithCreator);
  print('📝 Task created in Firestore with ID: ${docRef.id}');
  
  // Note: Task notifications are handled by the reminder service when tasks are due to start
  // not immediately upon creation to avoid premature notifications
}

// Firestore helper/service class for task updates
class TaskService {
  // Reference to the 'care_tasks' collection in Firestore
  static final _tasksRef = FirebaseFirestore.instance.collection('care_tasks');
  
  /// TEST FUNCTION: Force run Progressive Task System for debugging
  static Future<void> testProgressiveTaskSystem() async {
    print('🧪 TEST: Manually triggering Progressive Task System...');
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final result = await checkAndProgressRecurringTasks(currentUser.uid);
      print('🧪 TEST RESULT: $result tasks progressed');
    } else {
      print('🧪 TEST ERROR: No current user found');
    }
  }

  /// Soft deletes a task by updating its 'task_status' to ['Deleted'].
  /// This keeps the task in the database but marks it as deleted for filtering.
  static Future<void> deleteTask(String docId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final caregiverId = currentUser?.uid;
    
    // Get original task data before deletion
    final docSnap = await _tasksRef.doc(docId).get();
    final originalData = docSnap.data();
    
    await _tasksRef.doc(docId).update({'task_status': ['Deleted']});
    
    // Create deletion notification
    if (caregiverId != null && originalData != null) {
      try {
        await NotificationService().createTaskNotification(
          taskId: docId,
          userId: caregiverId,
          userType: 'caregiver',
          elderlyName: originalData['elderly_fname'] ?? 'Unknown',
          taskDescription: originalData['task_description'] ?? 'Unknown Task',
          type: NotificationType.taskDeleted,
        );
      } catch (e) {
        print('❌ Error creating deletion notification: $e');
      }
    }
  }

  /// Updates a task document with the provided data map.
  /// Used for editing task details or other field updates.
  static Future<void> updateTask(String docId, Map<String, dynamic> updateData) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final caregiverId = currentUser?.uid;
    
    // Get original task data before update
    final docSnap = await _tasksRef.doc(docId).get();
    final originalData = docSnap.data();
    
    await _tasksRef.doc(docId).update(updateData);
    
    // Create update notification only for significant changes (not status changes)
    if (caregiverId != null && originalData != null) {
      final isSignificantUpdate = updateData.containsKey('task_description') || 
                                  updateData.containsKey('task_date') || 
                                  updateData.containsKey('task_time') ||
                                  updateData.containsKey('task_frequency');
      
      if (isSignificantUpdate) {
        try {
          String? additionalInfo;
          if (updateData.containsKey('task_description')) {
            additionalInfo = 'Description updated';
          } else if (updateData.containsKey('task_date') || updateData.containsKey('task_time')) {
            additionalInfo = 'Schedule updated';
          } else if (updateData.containsKey('task_frequency')) {
            additionalInfo = 'Frequency updated';
          }
          
          await NotificationService().createTaskNotification(
            taskId: docId,
            userId: caregiverId,
            userType: 'caregiver',
            elderlyName: originalData['elderly_fname'] ?? 'Unknown',
            taskDescription: originalData['task_description'] ?? 'Unknown Task',
            type: NotificationType.taskUpdated,
            additionalInfo: additionalInfo,
          );
        } catch (e) {
          print('❌ Error creating update notification: $e');
        }
      }
    }
  }

  /// Progressive Task System: Updates recurring tasks to next occurrence when shift ends
  static Future<int> checkAndProgressRecurringTasks(String caregiverId) async {
    try {
      print('=== Progressive Task System: Starting shift end check ===');
      
      // Get caregiver's shift time_range
      final assignSnapshot = await FirebaseFirestore.instance
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .get();
      
      if (assignSnapshot.docs.isEmpty) {
        print('No assignment found for caregiver: $caregiverId');
        return 0;
      }
      
      final assignData = assignSnapshot.docs.first.data();
      final shiftStartTime = assignData['start_time'] as String? ?? '00:00';
      final shiftEndTime = assignData['end_time'] as String? ?? '23:59';
      
      // Parse shift start and end times
      final startTimeParts = shiftStartTime.split(':');
      final startHour = int.parse(startTimeParts[0]);
      final startMinute = int.parse(startTimeParts[1]);
      
      final endTimeParts = shiftEndTime.split(':');
      final endHour = int.parse(endTimeParts[0]);
      final endMinute = int.parse(endTimeParts[1]);

      final now = DateTime.now();
      
      // Create shift start and end times for today
      final shiftStartToday = DateTime(now.year, now.month, now.day, startHour, startMinute);
      DateTime shiftEndToday = DateTime(now.year, now.month, now.day, endHour, endMinute);
      
      // Handle overnight shifts (e.g., 22:00 to 06:00)
      // If end time is earlier than start time, the shift crosses midnight
      bool isOvernightShift = endHour < startHour || (endHour == startHour && endMinute <= startMinute);
      
      if (isOvernightShift) {
        // This is an overnight shift
        // If current time is before shift start time, we're in the "next day" portion
        // So the shift end should be today, not tomorrow
        if (now.hour < startHour || (now.hour == startHour && now.minute < startMinute)) {
          // We're in the "next day" portion (after midnight, before shift start)
          // Shift end is today
          shiftEndToday = DateTime(now.year, now.month, now.day, endHour, endMinute);
          print('🌙 Detected overnight shift (in end period): $shiftStartTime to $shiftEndTime (ends today)');
        } else {
          // We're in the "same day" portion (after shift start, before midnight)
          // Shift end is tomorrow
          shiftEndToday = DateTime(now.year, now.month, now.day + 1, endHour, endMinute);
          print('🌙 Detected overnight shift (in start period): $shiftStartTime to $shiftEndTime (ends tomorrow)');
        }
      } else {
        print('☀️ Detected regular shift: $shiftStartTime to $shiftEndTime (same day)');
      }

      print('Shift starts at: $shiftStartTime ($shiftStartToday)');
      print('Shift ends at: $shiftEndTime ($shiftEndToday)');
      print('Current time: $now');
      print('now.isAfter(shiftEndToday): ${now.isAfter(shiftEndToday)}');
      
      // 🔧 FIX 1: Enhanced shift end detection for overnight shifts
      bool isActualShiftEnd = false;
      if (isOvernightShift) {
        // For overnight shifts, ensure we're truly past the shift end
        // Don't progress tasks just because it's past midnight
        if (now.hour >= endHour && now.hour < startHour) {
          // We're in the period after shift end but before next shift start
          isActualShiftEnd = true;
          print('✅ Overnight shift has actually ended (current: ${now.hour}:${now.minute.toString().padLeft(2, '0')} is after shift end: $shiftEndTime)');
        } else if (now.hour >= startHour) {
          // We're in the start period of the shift, check if end time has passed
          isActualShiftEnd = now.isAfter(shiftEndToday);
          print('🔍 Overnight shift start period - checking if end time passed: ${now.isAfter(shiftEndToday)}');
        } else {
          // We're in the end period but haven't reached actual end time yet
          isActualShiftEnd = now.isAfter(shiftEndToday);
          print('🔍 Overnight shift end period - checking if end time passed: ${now.isAfter(shiftEndToday)}');
        }
      } else {
        // For regular shifts, use existing logic
        isActualShiftEnd = now.isAfter(shiftEndToday);
      }
      
      // Check if current time has passed the actual shift end time
      if (!isActualShiftEnd) {
        print('⏰ Shift has not actually ended yet, no progression needed (current: ${now.hour}:${now.minute.toString().padLeft(2, '0')}, shift ends: $shiftEndTime)');
        return 0;
      }
      
      print('✅ Shift has ended, proceeding with task progression...');
      
      // Individual tasks have their own last_progressed_at check to prevent duplicates
      // No need for global "once per day" check that requires complex Firestore index
      print('✅ Proceeding with task progression...');
      
      print('Shift has ended, checking for recurring tasks to progress...');
      
      // Get all recurring tasks assigned to this caregiver that need progression
      // Look for tasks with status "Missed" or "Upcoming" (tasks that should be progressed)
      final tasksSnapshot = await _tasksRef
          .where('caregiver_id', isEqualTo: caregiverId)
          .get();
      
      print('Found ${tasksSnapshot.docs.length} total tasks assigned to caregiver $caregiverId');
      
      // Debug: Show all tasks and their statuses
      for (var doc in tasksSnapshot.docs) {
        final data = doc.data();
        final description = data['task_description'] ?? 'Unknown';
        final status = data['task_status'] ?? 'No Status';
        print('📋 Task: $description, Status: $status');
      }
      
      // Filter for tasks that need progression - only tasks that are overdue (not future tasks)
      final progressableTasks = tasksSnapshot.docs.where((doc) {
        final data = doc.data();
        final status = data['task_status'] as List<dynamic>? ?? [];
        final taskDate = (data['task_date'] as Timestamp?)?.toDate();
        final description = data['task_description'] ?? 'Unknown';
        
        // Only process recurring tasks
        final frequency = (data['task_frequency'] as List<dynamic>?)?.first ?? 'Only once';
        if (frequency == 'Only once') {
          return false; // Skip non-recurring tasks
        }
        
        // Only process tasks that have a date and are today or in the past
        if (taskDate == null) {
          return false;
        }
        
        final taskDateOnly = DateTime(taskDate.year, taskDate.month, taskDate.day);
        final todayOnly = DateTime(now.year, now.month, now.day);
        final isOverdue = taskDateOnly.isBefore(todayOnly) || taskDateOnly.isAtSameMomentAs(todayOnly);
        
        final hasCorrectStatus = status.contains('Missed') || 
                                status.contains('Complete') || 
                                status.contains('Incomplete');
        
        final shouldProgress = isOverdue && hasCorrectStatus;
        
        if (shouldProgress) {
          print('✅ Task "$description" eligible for progression (${status.first}, due: $taskDateOnly)');
        }
        
        // Only process tasks that are overdue AND have completed/missed/incomplete status
        return shouldProgress;
      }).toList();
      
      print('Tasks eligible for progression (overdue recurring tasks): ${progressableTasks.length}');
      
      int progressedCount = 0;
      
      for (var taskDoc in progressableTasks) {
        final taskData = taskDoc.data();
        final frequency = (taskData['task_frequency'] as List<dynamic>?)?.first ?? 'Only once';
        final taskDescription = taskData['task_description'] ?? 'Unknown Task';
        final taskStatus = taskData['task_status'] ?? 'No Status';
        
        print('Processing task: $taskDescription, frequency: $frequency, status: $taskStatus');
        
        // Only process recurring tasks
        if (frequency == 'Every Assigned Day' || frequency == 'Custom') {
          print('✅ Task $taskDescription is recurring, checking dates...');
          final taskDate = (taskData['task_date'] as Timestamp?)?.toDate();
          final nextTaskDate = (taskData['next_taskdate'] as Timestamp?)?.toDate();
          
          // Check if task was already progressed today (prevent duplicate processing)
          final lastProgressedAt = (taskData['last_progressed_at'] as Timestamp?)?.toDate();
          final todayOnly = DateTime(now.year, now.month, now.day);
          
          if (lastProgressedAt != null) {
            final lastProgressedDateOnly = DateTime(lastProgressedAt.year, lastProgressedAt.month, lastProgressedAt.day);
            if (lastProgressedDateOnly.isAtSameMomentAs(todayOnly)) {
              print('⏭️ Task $taskDescription already progressed today ($lastProgressedAt), skipping...');
              continue;
            }
          }
          
          print('📅 Task $taskDescription - task_date: $taskDate, next_taskdate: $nextTaskDate');
          print('🔍 Task status: ${taskData['task_status']}');
          
          if (taskDate != null) {
            print('✅ Task has task_date: $taskDate');
            
            // Calculate next_taskdate using the new date picker logic
            DateTime? calculatedNextTaskDate = nextTaskDate;
            
            if (calculatedNextTaskDate == null) {
              print('⚠️ next_taskdate is null, calculating using recurring_start_date...');
              final taskStart = (taskData['task_start'] as Timestamp?)?.toDate() ?? DateTime.now();
              final recurringStartDate = (taskData['recurring_start_date'] as Timestamp?)?.toDate();
              final customDays = List<String>.from(taskData['custom_days'] ?? []);
              
              print('🔧 Calculation inputs: recurringStartDate=$recurringStartDate, taskStart=$taskStart');
              print('🔧 Custom days: $customDays');
              
              if (recurringStartDate != null) {
                print('✅ Using recurring_start_date approach...');
                if (frequency == 'Every Assigned Day') {
                  // Get assigned days for this elderly-caregiver pair
                  final elderlyId = taskData['elderly_id'] ?? '';
                  final assignedDays = await _getAssignedDaysForElderlyAndCaregiverStatic(caregiverId, elderlyId);
                  print('🔧 Assigned days for Every Assigned Day: $assignedDays');
                  calculatedNextTaskDate = _calculateNextOccurrence(taskDate, recurringStartDate, frequency, customDays, taskStart, assignedDays: assignedDays);
                } else if (frequency == 'Custom' && customDays.isNotEmpty) {
                  // For Custom frequency, always check assignments
                  final elderlyId = taskData['elderly_id'] ?? '';
                  calculatedNextTaskDate = await _getNextCustomDate(elderlyId, caregiverId, taskStart, taskDate.add(Duration(days: 1)), customDays);
                  print('✅ Custom frequency: Using assignment-aware calculation');
                }
              } else {
                print('⚠️ No recurring_start_date found, using fallback logic...');
                // Fallback for older tasks without recurring_start_date
                if (frequency == 'Every Assigned Day') {
                  final elderlyId = taskData['elderly_id'] ?? '';
                  calculatedNextTaskDate = await _getNextAssignedDate(elderlyId, caregiverId, taskStart, taskDate.add(Duration(days: 1)));
                } else if (frequency == 'Custom' && customDays.isNotEmpty) {
                  final elderlyId = taskData['elderly_id'] ?? '';
                  calculatedNextTaskDate = await _getNextCustomDate(elderlyId, caregiverId, taskStart, taskDate.add(Duration(days: 1)), customDays);
                }
                
                // Final fallback: simple +1 day logic
                if (calculatedNextTaskDate == null) {
                  print('⚠️ All calculations failed, using simple +1 day fallback...');
                  calculatedNextTaskDate = DateTime(
                    taskDate.year, 
                    taskDate.month, 
                    taskDate.day + 1, 
                    taskStart.hour, 
                    taskStart.minute
                  );
                }
              }
              
              print('✅ Final calculated next_taskdate: $calculatedNextTaskDate');
            } else {
              print('✅ next_taskdate already exists: $calculatedNextTaskDate');
            }
            
            if (calculatedNextTaskDate != null) {
              print('✅ calculatedNextTaskDate is available');
              
              // Check if task date is today or in the past
              final taskDateOnly = DateTime(taskDate.year, taskDate.month, taskDate.day);
              final todayOnly = DateTime(now.year, now.month, now.day);
              
              print('📊 Date comparison:');
              print('   - taskDateOnly: $taskDateOnly');
              print('   - todayOnly: $todayOnly');
              print('   - isBefore: ${taskDateOnly.isBefore(todayOnly)}');
              print('   - isAtSameMomentAs: ${taskDateOnly.isAtSameMomentAs(todayOnly)}');
              
              if (taskDateOnly.isBefore(todayOnly) || taskDateOnly.isAtSameMomentAs(todayOnly)) {
                print('🚀 PROGRESSING task ${taskDoc.id} from $taskDate to $calculatedNextTaskDate');
                
                // Calculate the next occurrence after the calculated next date
                DateTime? newNextTaskDate;
                final taskStart = (taskData['task_start'] as Timestamp?)?.toDate() ?? DateTime.now();
                final recurringStartDate = (taskData['recurring_start_date'] as Timestamp?)?.toDate();
                final customDays = List<String>.from(taskData['custom_days'] ?? []);
                final elderlyId = taskData['elderly_id'] ?? '';
                
                if (recurringStartDate != null) {
                  if (frequency == 'Custom' && customDays.isNotEmpty) {
                    // Use assignment-aware Custom frequency calculation (Option B)
                    newNextTaskDate = await _getNextCustomDate(elderlyId, caregiverId, taskStart, calculatedNextTaskDate.add(Duration(days: 1)), customDays);
                  } else if (frequency == 'Every Assigned Day') {
                    // Get assigned days for Every Assigned Day frequency
                    final assignedDays = await _getAssignedDaysForElderlyAndCaregiverStatic(caregiverId, elderlyId);
                    newNextTaskDate = _calculateNextOccurrence(calculatedNextTaskDate, recurringStartDate, frequency, customDays, taskStart, assignedDays: assignedDays);
                  } else {
                    // Use standard calculation for other frequencies
                    newNextTaskDate = _calculateNextOccurrence(calculatedNextTaskDate, recurringStartDate, frequency, customDays, taskStart);
                  }
                } else {
                  // Fallback for older tasks without recurring_start_date
                  if (frequency == 'Every Assigned Day') {
                    newNextTaskDate = await _getNextAssignedDate(elderlyId, caregiverId, taskStart, calculatedNextTaskDate.add(Duration(days: 1)));
                  } else if (frequency == 'Custom' && customDays.isNotEmpty) {
                    newNextTaskDate = await _getNextCustomDate(elderlyId, caregiverId, taskStart, calculatedNextTaskDate.add(Duration(days: 1)), customDays);
                  }
                }
                
                // Update existing task to next occurrence (no more task duplication)
                try {
                  final currentStatus = List<String>.from(taskData['task_status'] ?? []);
                  final statusString = currentStatus.isNotEmpty ? currentStatus[0] : 'Unknown';
                  
                  print('💾 Updating existing $statusString task to next occurrence...');
                  print('📅 Task will be updated to: $calculatedNextTaskDate');
                  print('📅 Next occurrence after that: $newNextTaskDate');
                  
                  // Update the existing task to next occurrence and reset to Upcoming
                  await _tasksRef.doc(taskDoc.id).update({
                    'task_date': calculatedNextTaskDate,
                    'next_taskdate': newNextTaskDate,
                    'task_status': ['Upcoming'], // Reset all tasks to Upcoming
                    'inc_reason': '', // Clear any incomplete reason
                    'last_progressed_at': FieldValue.serverTimestamp(),
                    'updated_at': FieldValue.serverTimestamp(),
                  });
                  
                  print('✅ Successfully progressed task ${taskDoc.id}!');
                  progressedCount++;
                } catch (updateError) {
                  print('❌ Error updating task: $updateError');
                }
              } else {
                print('❌ Task $taskDescription not progressed - date check failed (task is in future)');
              }
            } else {
              print('❌ Task $taskDescription could not calculate next_taskdate');
            }
          } else {
            print('Task $taskDescription missing dates - task_date: $taskDate, next_taskdate: $nextTaskDate');
          }
        } else {
          print('Task $taskDescription skipped - not recurring (frequency: $frequency)');
        }
      }
      
      print('=== Progressive Task System: Completed - $progressedCount tasks progressed ===');
      return progressedCount;
      
    } catch (e) {
      print('Error in progressive task system: $e');
      return 0;
    }
  }

  /// Calculate the next occurrence of a recurring task based on user-selected start date
  static DateTime? _calculateNextOccurrence(DateTime currentTaskDate, DateTime recurringStartDate, String frequency, List<String> customDays, DateTime taskStart, {List<String>? assignedDays}) {
    print('🔧 _calculateNextOccurrence: currentTaskDate=$currentTaskDate, recurringStartDate=$recurringStartDate, frequency=$frequency');
    print('🔧 assignedDays provided: $assignedDays');

    if (frequency == 'Every Assigned Day') {
      // For "Every Assigned Day", find the next occurrence of ANY assigned day
      // assignedDays MUST be provided for this frequency to work correctly
      if (assignedDays != null && assignedDays.isNotEmpty) {
        print('✅ Using assignedDays logic for Every Assigned Day');
        DateTime nextDate = currentTaskDate.add(const Duration(days: 1));
        
        // Look for the next occurrence within the next 14 days
        for (int i = 0; i < 14; i++) {
          final dayOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][nextDate.weekday - 1];
          print('🔍 Checking day ${i + 1}: ${nextDate.toString().split(' ')[0]} ($dayOfWeek) - matches assigned days? ${assignedDays.contains(dayOfWeek)}');
          if (assignedDays.contains(dayOfWeek)) {
            final result = DateTime(nextDate.year, nextDate.month, nextDate.day, taskStart.hour, taskStart.minute);
            print('✅ Found next assigned day: $result ($dayOfWeek)');
            return result;
          }
          nextDate = nextDate.add(const Duration(days: 1));
        }
        print('❌ No matching assigned day found in next 14 days');
        return null; // Return null instead of falling back to incorrect logic
      } else {
        print('❌ ERROR: assignedDays is ${assignedDays == null ? "null" : "empty"} for Every Assigned Day frequency!');
        print('❌ This should never happen - assignedDays must be fetched before calling _calculateNextOccurrence');
        return null; // Return null to prevent incorrect date calculation
      }
    } else if (frequency == 'Custom' && customDays.isNotEmpty) {
      // For "Custom", find the next occurrence of any of the selected custom days
      DateTime nextDate = currentTaskDate.add(const Duration(days: 1));
      
      // Look for the next occurrence within the next 14 days
      for (int i = 0; i < 14; i++) {
        final dayOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][nextDate.weekday - 1];
        if (customDays.contains(dayOfWeek)) {
          return DateTime(nextDate.year, nextDate.month, nextDate.day, taskStart.hour, taskStart.minute);
        }
        nextDate = nextDate.add(const Duration(days: 1));
      }
    }
    
    print('❌ Could not calculate next occurrence');
    return null;
  }

  // Static helper method to get assigned days for use in static contexts
  static Future<List<String>> _getAssignedDaysForElderlyAndCaregiverStatic(String caregiverId, String elderlyId) async {
    try {
      print('🔍 DEBUG: Getting assigned days for caregiverId=$caregiverId, elderlyId=$elderlyId');
      
      // Query elderly_assignments collection for all days when this caregiver is assigned
      final elderlyAssignSnapshot = await FirebaseFirestore.instance
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .get();

      print('🔍 DEBUG: Found ${elderlyAssignSnapshot.docs.length} assignment documents for this caregiver');

      if (elderlyAssignSnapshot.docs.isEmpty) {
        print('🔍 DEBUG: No assignments found for this caregiver');
        return [];
      }

      // Extract all unique days where this specific elderly is assigned to this caregiver
      Set<String> assignedDaysSet = {};
      for (var doc in elderlyAssignSnapshot.docs) {
        final data = doc.data();
        final elderlyIds = List<String>.from(data['elderly_ids'] ?? []);
        final day = data['day'] as String?;
        
        // If this elderly is in the elderly_ids array for this day, add the day
        if (elderlyIds.contains(elderlyId) && day != null && day.isNotEmpty) {
          assignedDaysSet.add(day);
          print('🔍 DEBUG: Found assignment: elderly $elderlyId assigned on $day');
        }
      }

      List<String> assignedDays = assignedDaysSet.toList();
      print('🔍 DEBUG: Final assigned days for elderly $elderlyId: $assignedDays');
      
      return assignedDays;
    } catch (e) {
      print('Error getting assigned days for elderly and caregiver: $e');
      return [];
    }
  }

  // Helper method to get next assigned date for recurring tasks
  static Future<DateTime?> _getNextAssignedDate(String elderlyId, String caregiverId, DateTime taskStart, DateTime fromDate) async {
    try {
      for (int i = 0; i < 14; i++) {
        DateTime candidate = fromDate.add(Duration(days: i));
        
        // Check if caregiver is assigned to elderly on this day
        bool isAssigned = await _isAssignedOnDateShiftAware(elderlyId, caregiverId, candidate);
        
        if (isAssigned) {
          DateTime candidateStart = DateTime(
            candidate.year, 
            candidate.month, 
            candidate.day, 
            taskStart.hour, 
            taskStart.minute
          );
          
          // For today (i == 0), only use it if the task time hasn't passed yet
          if (i == 0 && DateTime.now().isBefore(candidateStart)) {
            return candidateStart;
          } else if (i > 0) {
            // For future days, use the date
            return candidateStart;
          }
        }
      }
    } catch (e) {
      print('Error calculating next assigned date: $e');
    }
    return null;
  }

  // Helper method to get next custom date
  static Future<DateTime?> _getNextCustomDate(String elderlyId, String caregiverId, DateTime taskStart, DateTime fromDate, List<String> customDays) async {
    try {
      for (int i = 0; i < 14; i++) {
        DateTime candidate = fromDate.add(Duration(days: i));
        String weekdayStr = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"][candidate.weekday - 1];
        
        // Check if this day is in custom selection AND caregiver is assigned
        if (customDays.contains(weekdayStr)) {
          bool isAssigned = await _isAssignedOnDateShiftAware(elderlyId, caregiverId, candidate);
          
          if (isAssigned) {
            DateTime candidateStart = DateTime(
              candidate.year, 
              candidate.month, 
              candidate.day, 
              taskStart.hour, 
              taskStart.minute
            );
            
            // For today (i == 0), only use it if the task time hasn't passed yet
            if (i == 0 && DateTime.now().isBefore(candidateStart)) {
              return candidateStart;
            } else if (i > 0) {
              // For future days, use the date
              return candidateStart;
            }
          }
        }
      }
    } catch (e) {
      print('Error calculating next custom date: $e');
    }
    return null;
  }

  // 🔧 FIX 3: Shift-aware helper functions for 3rd shift support
  
  /// Gets the correct shift day for assignment checking, considering overnight shifts
  static Future<String> _getShiftDay(String caregiverId, DateTime currentTime) async {
    try {
      // Get caregiver's shift information
      final houseSnapshot = await FirebaseFirestore.instance
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .where('is_current', isEqualTo: true)
          .limit(1)
          .get();
      
      if (houseSnapshot.docs.isEmpty) {
        return DateFormat('EEEE').format(currentTime);
      }
      
      final houseData = houseSnapshot.docs.first.data();
      final startTime = houseData['start_time'] as String?;
      final endTime = houseData['end_time'] as String?;
      
      if (startTime != null && endTime != null && startTime.isNotEmpty && endTime.isNotEmpty) {
        final startParts = startTime.split(':');
        final endParts = endTime.split(':');
        final shiftStartHour = int.parse(startParts[0]);
        final shiftEndHour = int.parse(endParts[0]);
        
        // Check if this is an overnight shift
        final isOvernightShift = shiftEndHour < shiftStartHour || 
            (shiftEndHour == shiftStartHour && int.parse(endParts[1]) <= int.parse(startParts[1]));
        
        if (isOvernightShift && currentTime.hour < shiftStartHour && currentTime.hour >= 0) {
          // We're in the "next day" portion of an overnight shift
          // Check the previous day's assignment
          print('🌙 Overnight shift detected: checking previous day assignment for current time ${currentTime.hour}:${currentTime.minute}');
          return DateFormat('EEEE').format(currentTime.subtract(Duration(days: 1)));
        }
      }
      
      return DateFormat('EEEE').format(currentTime);
    } catch (e) {
      print('Error determining shift day: $e');
      return DateFormat('EEEE').format(currentTime);
    }
  }
  
  /// Enhanced assignment check that considers shift periods for overnight shifts
  static Future<bool> _isAssignedOnDateShiftAware(String elderlyId, String caregiverId, DateTime date) async {
    try {
      // Get the correct day to check based on shift timing
      String dayToCheck = await _getShiftDay(caregiverId, date);
      
      print('  🔍 Shift-aware check: checking assignment for $dayToCheck (original date: ${DateFormat('EEEE').format(date)})');
      
      // SIMPLIFIED APPROACH: Check if elderly is in caregiver's assigned house on that day
      // Step 1: Get caregiver's house assignment
      final houseAssignSnapshot = await FirebaseFirestore.instance
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .limit(1)
          .get();
      
      if (houseAssignSnapshot.docs.isEmpty) {
        print('  ❌ No house assignment found for caregiver');
        return false;
      }
      
      final houseAssignData = houseAssignSnapshot.docs.first.data();
      final houseId = houseAssignData['house_id'] as String;
      final caregiverAssignedDays = List<String>.from(houseAssignData['days_assigned'] ?? []);
      
      // Step 2: Check if caregiver is assigned on the requested day
      if (!caregiverAssignedDays.contains(dayToCheck)) {
        print('  ❌ Caregiver not assigned on $dayToCheck');
        return false;
      }
      
      // Step 3: Check if elderly is in this house
      final elderlyDoc = await FirebaseFirestore.instance
          .collection('elderly')
          .doc(elderlyId)
          .get();
      
      if (!elderlyDoc.exists) {
        print('  ❌ Elderly document not found');
        return false;
      }
      
      final elderlyData = elderlyDoc.data();
      if (elderlyData == null) {
        print('  ❌ Elderly document has no data');
        return false;
      }
      
      final elderlyHouseId = elderlyData['house_id'] as String?;
      
      if (elderlyHouseId != houseId) {
        print('  ❌ Elderly not in caregiver\'s assigned house (elderly house: $elderlyHouseId)');
        return false;
      }
      
      print('  ✅ Found shift-aware assignment for $dayToCheck - elderly is in caregiver\'s house');
      return true;
      
    } catch (e) {
      print('Error in shift-aware assignment check: $e');
      return false;
    }
  }

  // 🔧 FIX 4: Helper function to get the correct task shift date for overnight shifts
  
  /// Gets the correct shift date for task creation, considering overnight shifts
  static Future<DateTime> _getTaskShiftDate(String caregiverId, DateTime currentTime) async {
    try {
      // Get caregiver's shift information
      final houseSnapshot = await FirebaseFirestore.instance
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .where('is_current', isEqualTo: true)
          .limit(1)
          .get();
      
      if (houseSnapshot.docs.isEmpty) {
        return currentTime;
      }
      
      final houseData = houseSnapshot.docs.first.data();
      final startTime = houseData['start_time'] as String?;
      final endTime = houseData['end_time'] as String?;
      
      if (startTime != null && endTime != null && startTime.isNotEmpty && endTime.isNotEmpty) {
        final startParts = startTime.split(':');
        final endParts = endTime.split(':');
        final shiftStartHour = int.parse(startParts[0]);
        final shiftEndHour = int.parse(endParts[0]);
        
        // Check if this is an overnight shift
        final isOvernightShift = shiftEndHour < shiftStartHour || 
            (shiftEndHour == shiftStartHour && int.parse(endParts[1]) <= int.parse(startParts[1]));
        
        if (isOvernightShift && currentTime.hour < shiftStartHour && currentTime.hour >= 0) {
          // We're in the "next day" portion of an overnight shift
          // Task belongs to the previous day's shift
          print('🌙 Task creation during overnight shift: using previous day for shift date');
          return currentTime.subtract(Duration(days: 1));
        }
      }
      
      return currentTime;
    } catch (e) {
      print('Error determining task shift date: $e');
      return currentTime;
    }
  }

  /// Marks a task as complete and updates its 'task_date' and 'next_taskdate'.
  /// Used for recurring tasks to set the next occurrence date.
  static Future<void> markTaskComplete(String docId, DateTime? newNextTaskDate) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final caregiverId = currentUser?.uid;
    
    // Get original task data
    final docSnap = await _tasksRef.doc(docId).get();
    final originalData = docSnap.data();
    
    if (originalData == null) return;
    
    // Mark current task as complete
    await _tasksRef.doc(docId).update({
      'task_status': ['Complete'],
      if (caregiverId != null) 'created_by': caregiverId,
    });

    // Create task log entry
    if (caregiverId != null) {
      try {
        final taskDate = (originalData['task_date'] as Timestamp?)?.toDate() ?? DateTime.now();
        await CaregiverShiftLogService.createTaskLog(
          taskId: docId,
          caregiverId: caregiverId,
          elderlyId: originalData['elderly_id'] ?? '',
          elderlyFname: originalData['elderly_fname'] ?? 'Unknown',
          taskDescription: originalData['task_description'] ?? 'Unknown Task',
          status: 'Complete',
          taskDate: taskDate,
        );
      } catch (e) {
        print('❌ Error creating task log for completed task: $e');
      }
    }

    // Create completion notification
    if (caregiverId != null) {
      try {
        await NotificationService().createTaskNotification(
          taskId: docId,
          userId: caregiverId,
          userType: 'caregiver',
          elderlyName: originalData['elderly_fname'] ?? 'Unknown',
          taskDescription: originalData['task_description'] ?? 'Unknown Task',
          type: NotificationType.taskCompleted,
        );
      } catch (e) {
        print('❌ Error creating completion notification: $e');
      }
    }

    // Cancel any scheduled reminders for this task
    try {
      await TaskReminderService().cancelTaskReminders(docId);
      print('✅ Task reminders cancelled for completed task: $docId');
    } catch (e) {
      print('❌ Error cancelling task reminders: $e');
    }
    
    // Don't update next_taskdate here - let Progressive Task System handle it when shift ends
    // This keeps the task showing current date in Complete screen until shift end
    print('✅ Task marked complete. Progressive Task System will handle recurrence when shift ends.');
  }

  /// Marks a task as incomplete and records the reason for incompletion.
  /// Updates 'inc_reason' and sets 'task_status' to ['Incomplete'].
  static Future<void> markTaskIncomplete(String docId, String reasonText) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final caregiverId = currentUser?.uid;
    
    // Get original task data for logging
    final docSnap = await _tasksRef.doc(docId).get();
    final originalData = docSnap.data();
    
    await _tasksRef.doc(docId).update({
      'inc_reason': reasonText,
      'task_status': ['Incomplete'],
      if (caregiverId != null) 'created_by': caregiverId,
    });

    // Create task log entry
    if (caregiverId != null && originalData != null) {
      try {
        final taskDate = (originalData['task_date'] as Timestamp?)?.toDate() ?? DateTime.now();
        await CaregiverShiftLogService.createTaskLog(
          taskId: docId,
          caregiverId: caregiverId,
          elderlyId: originalData['elderly_id'] ?? '',
          elderlyFname: originalData['elderly_fname'] ?? 'Unknown',
          taskDescription: originalData['task_description'] ?? 'Unknown Task',
          status: 'Incomplete',
          taskDate: taskDate,
          reason: reasonText,
        );
      } catch (e) {
        print('❌ Error creating task log for incomplete task: $e');
      }
    }

    // Create incomplete notification (task missed)
    if (caregiverId != null && originalData != null) {
      try {
        await NotificationService().createTaskNotification(
          taskId: docId,
          userId: caregiverId,
          userType: 'caregiver',
          elderlyName: originalData['elderly_fname'] ?? 'Unknown',
          taskDescription: originalData['task_description'] ?? 'Unknown Task',
          type: NotificationType.taskMissed,
          additionalInfo: 'Reason: $reasonText',
        );
      } catch (e) {
        print('❌ Error creating incomplete notification: $e');
      }
    }

    // Cancel any scheduled reminders for this task
    try {
      await TaskReminderService().cancelTaskReminders(docId);
      print('✅ Task reminders cancelled for incomplete task: $docId');
    } catch (e) {
      print('❌ Error cancelling task reminders: $e');
    }
  }

  /// Marks a task as incomplete and handles next occurrence for recurring tasks.
  /// For recurring tasks, creates a new upcoming task for the next occurrence.
  static Future<void> markTaskIncompleteWithNextOccurrence(String docId, String reasonText, DateTime? newNextTaskDate) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final caregiverId = currentUser?.uid;
    
    // Get original task data
    final docSnap = await _tasksRef.doc(docId).get();
    final originalData = docSnap.data();
    
    if (originalData == null) return;
    
    // Mark current task as incomplete
    await _tasksRef.doc(docId).update({
      'inc_reason': reasonText,
      'task_status': ['Incomplete'],
      if (caregiverId != null) 'created_by': caregiverId,
    });

    // Create task log entry
    if (caregiverId != null) {
      try {
        final taskDate = (originalData['task_date'] as Timestamp?)?.toDate() ?? DateTime.now();
        await CaregiverShiftLogService.createTaskLog(
          taskId: docId,
          caregiverId: caregiverId,
          elderlyId: originalData['elderly_id'] ?? '',
          elderlyFname: originalData['elderly_fname'] ?? 'Unknown',
          taskDescription: originalData['task_description'] ?? 'Unknown Task',
          status: 'Incomplete',
          taskDate: taskDate,
          reason: reasonText,
        );
      } catch (e) {
        print('❌ Error creating task log for incomplete task: $e');
      }
    }

    // Cancel any scheduled reminders for this task
    try {
      await TaskReminderService().cancelTaskReminders(docId);
      print('✅ Task reminders cancelled for incomplete task: $docId');
    } catch (e) {
      print('❌ Error cancelling task reminders: $e');
    }
    
    // Don't update next_taskdate here - let Progressive Task System handle it when shift ends
    // This keeps the task showing current date in Incomplete screen until shift end
    print('✅ Task marked incomplete. Progressive Task System will handle recurrence when shift ends.');
  }
}

// Task Action Buttons Widget
class TaskActionButtons extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClose;
  const TaskActionButtons({
    super.key,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.edit, size: 24, color: Color(0xFF22688E)),
          tooltip: 'Edit Task',
          onPressed: onEdit,
        ),
        IconButton(
          icon: const Icon(Icons.delete, size: 24, color: Color(0xFFB71C1C)),
          tooltip: 'Delete Task',
          onPressed: onDelete,
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 25, color: Color(0xFF22688E)),
          onPressed: onClose,
        ),
      ],
    );
  }
}

// Edit Task Dialog Widget
class EditTaskDialog extends StatefulWidget {
  final Map<String, dynamic> task;
  final BuildContext parentContext;
  const EditTaskDialog({super.key, required this.task, required this.parentContext});

  @override
  State<EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<EditTaskDialog> {
  late TextEditingController activityController;
  TimeOfDay? startTime;
  TimeOfDay? endTime;

  @override
  void initState() {
    super.initState();
    activityController = TextEditingController(text: widget.task['task_description'] ?? '');
    startTime = widget.task['task_start'] != null ? TimeOfDay.fromDateTime(widget.task['task_start']) : null;
    endTime = widget.task['task_end'] != null ? TimeOfDay.fromDateTime(widget.task['task_end']) : null;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        width: 350,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Edit Task', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF22688E))),
                  IconButton(
                    icon: const Icon(Icons.close, size: 25, color: Color(0xFF22688E)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.assignment, color: Color(0xFF22688E)),
                  const SizedBox(width: 8),
                  const Text('Activity:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: activityController,
                decoration: const InputDecoration(
                  hintText: 'Enter activity name',
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.access_time, color: Color(0xFF22688E)),
                  const SizedBox(width: 8),
                  const Text('Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: startTime ?? TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setState(() {
                            startTime = picked;
                          });
                        }
                      },
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(0xFFE6F3FA),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(startTime != null ? startTime!.format(context) : 'Start', style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: endTime ?? TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setState(() {
                            endTime = picked;
                          });
                        }
                      },
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(0xFFE6F3FA),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(endTime != null ? endTime!.format(context) : 'End', style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  final docId = widget.task['task_id'];
                  final tasksRef = FirebaseFirestore.instance.collection('care_tasks');
                  
                  // Get the current task date to preserve it
                  final taskDate = widget.task['task_date'] is Timestamp 
                      ? (widget.task['task_date'] as Timestamp).toDate() 
                      : (widget.task['task_date'] is DateTime ? widget.task['task_date'] : DateTime.now());
                  
                  final updateData = {
                    'task_description': activityController.text,
                    if (startTime != null) 'task_start': DateTime(taskDate.year, taskDate.month, taskDate.day, startTime!.hour, startTime!.minute),
                    if (endTime != null) 'task_end': DateTime(taskDate.year, taskDate.month, taskDate.day, endTime!.hour, endTime!.minute),
                  };
                  await tasksRef.doc(docId).update(updateData);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                  if (widget.parentContext.mounted) {
                    Navigator.of(widget.parentContext).pop();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF22688E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Helper formatting functions
String formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String formatTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

// Task Details Dialog Widget
class TaskDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onComplete;
  final VoidCallback onIncomplete;
  final VoidCallback onClose;
  final bool showReasonInput;
  final TextEditingController reasonController;
  const TaskDetailsDialog({
    super.key,
    required this.task,
    required this.onEdit,
    required this.onDelete,
    required this.onComplete,
    required this.onIncomplete,
    required this.onClose,
    required this.showReasonInput,
    required this.reasonController,
  });

  static String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : hour == 0 ? 12 : hour;
    return '$hour12:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 350,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Text(
                        'Task Details',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF22688E),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.edit, size: 24, color: Color(0xFF22688E)), tooltip: 'Edit Task', onPressed: onEdit),
                      IconButton(icon: const Icon(Icons.delete, size: 24, color: Color(0xFFB71C1C)), tooltip: 'Delete Task', onPressed: onDelete),
                      IconButton(icon: const Icon(Icons.check_circle, color: Color(0xFF22688E)), tooltip: 'Complete Task', onPressed: onComplete),
                      IconButton(icon: const Icon(Icons.cancel, color: Color(0xFFD32F2F)), tooltip: 'Incomplete Task', onPressed: onIncomplete),
                      IconButton(icon: const Icon(Icons.close, size: 25, color: Color(0xFF22688E)), onPressed: onClose),
                    ],
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.person, color: Color(0xFF22688E)),
                  const SizedBox(width: 8),
                  const Text('Name:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task['elderly_fname'] ?? '',
                      style: const TextStyle(fontSize: 16),
                      softWrap: true,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.assignment, color: Color(0xFF22688E)),
                  const SizedBox(width: 8),
                  const Text('Activity:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task['task_description'] ?? '',
                      style: const TextStyle(fontSize: 16),
                      softWrap: true,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.access_time, color: Color(0xFF22688E)),
                  const SizedBox(width: 8),
                  const Text('Time:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E)),),
                  const SizedBox(width: 8),
                  Text(
                    '${task['task_start'] != null ? _formatTime(task['task_start']) : ''} - ${task['task_end'] != null ? _formatTime(task['task_end']) : ''}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.repeat, color: Color(0xFF22688E)),
                  const SizedBox(width: 8),
                  const Text('Frequency:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (() {
                        final freqList = task['task_frequency'] as List<dynamic>? ?? [];
                        final freq = freqList.isNotEmpty ? freqList[0] as String : 'Only once';
                        if (freq == 'Only once') {
                          final onceDate = task['freq_once_date'];
                          if (onceDate != null) {
                            if (onceDate is DateTime) {
                              return 'Only once (${formatDate(onceDate)})';
                            } else if (onceDate is String) {
                              return 'Only once ($onceDate)';
                            }
                          }
                          return 'Only once';
                        } else if (freq == 'Every Assigned Day') {
                          return 'Every Assigned Day';
                        } else if (freq == 'Custom') {
                          final customDays = task['custom_days'] as List<dynamic>? ?? [];
                          if (customDays.isNotEmpty) {
                            return 'Custom days (${customDays.join(', ')})';
                          }
                          return 'Custom days';
                        }
                        return freq;
                      })(),
                      style: const TextStyle(fontSize: 16),
                      softWrap: true,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.calendar_today, color: Color(0xFF22688E)),
                  const SizedBox(width: 8),
                  const Text('Created:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                  const SizedBox(width: 8),
                  Text(
                    (() {
                      final created = task['created_at'];
                      if (created == null) return '';
                      if (created is DateTime) {
                        return '${formatDate(created)} at ${formatTime(created)}';
                      } else if (created is Timestamp) {
                        final dt = created.toDate();
                        return '${formatDate(dt)} at ${formatTime(dt)}';
                      }
                      return created.toString();
                    })(),
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // ...existing action buttons and reason input logic can be moved here as needed...
            ],
          ),
        ),
      ),
    );
  }
}
// ...imports already at top, remove these duplicates
class UpcomingTasksScreen extends StatefulWidget {
  const UpcomingTasksScreen({super.key});

  @override
  State<UpcomingTasksScreen> createState() => _UpcomingTasksScreenState();
}

class _UpcomingTasksScreenState extends State<UpcomingTasksScreen> with WidgetsBindingObserver {
  Timer? _refreshTimer;
  int _refreshKey = 0; // Simple key to force rebuilds

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Trigger initial progressive task system check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkProgressiveTaskSystem(context);
    });
    
    // Set up periodic refresh every 30 seconds
    _startPeriodicRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // App came back into focus, refresh the data
      print('🔄 App resumed, refreshing tasks...');
      // DON'T call _checkProgressiveTaskSystem here - it causes immediate task date updates
      // Only let the periodic timer handle progression checks (which respects shift end time)
      _triggerRefresh();
    }
  }

  void _startPeriodicRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 45), (timer) {
      if (mounted) {
        try {
          print('🔄 Periodic refresh triggered...');
          // Check if shift has ended and run progressive task system if needed
          _checkProgressiveTaskSystem(context);
          _triggerRefresh();
        } catch (e) {
          print('⚠️ Periodic refresh error (non-critical): $e');
          // Don't crash if refresh fails
        }
      }
    });
  }

  void _triggerRefresh() {
    if (mounted) {
      setState(() {
        _refreshKey++; // Force rebuild by changing key
      });
    }
  }

  Stream<List<Map<String, dynamic>>> getTasksStream() {
    final user = FirebaseAuth.instance.currentUser;
    final caregiverId = user?.uid;
    
    return FirebaseFirestore.instance
      .collection('care_tasks')
      .where('task_status', arrayContains: 'Upcoming')
      .where('caregiver_id', isEqualTo: caregiverId)
      .snapshots()
      .asyncMap((snapshot) => _processTasksFromSnapshot(snapshot));
  }

  Future<List<Map<String, dynamic>>> _processTasksFromSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) async {
    List<Map<String, dynamic>> tasks = [];
    final now = DateTime.now();
    
    print('🔍 Upcoming Tasks Query: Found ${snapshot.docs.length} tasks with Upcoming status');
    for (var doc in snapshot.docs) {
      final data = doc.data();
      print('📋 Task: ${data['task_description']}, Date: ${data['task_date']}, Status: ${data['task_status']}');
    }
    
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final elderlyId = data['elderly_id'];
      
      // Check if task should be marked as missed
      final taskEnd = (data['task_end'] is Timestamp) 
          ? (data['task_end'] as Timestamp).toDate() 
          : data['task_end'] as DateTime?;
      final taskDate = (data['task_date'] is Timestamp) 
          ? (data['task_date'] as Timestamp).toDate() 
          : data['task_date'] as DateTime?;
      
      // Determine the actual task execution date
      DateTime? actualTaskDate;
      final freqList = data['task_frequency'] as List<dynamic>? ?? [];
      final freq = freqList.isNotEmpty ? freqList[0] as String : 'Only once';
      
      if (freq == 'Only once') {
        actualTaskDate = data['freq_once_date'] != null 
            ? ((data['freq_once_date'] is Timestamp) 
                ? (data['freq_once_date'] as Timestamp).toDate() 
                : data['freq_once_date'] as DateTime)
            : taskDate;
      } else {
        // For recurring tasks, use task_date (the current occurrence)
        actualTaskDate = taskDate;
      }
      
      // Check if task is overdue and should be marked as missed
      if (taskEnd != null && actualTaskDate != null) {
        // 🔧 ENHANCED: Calculate task end time considering midnight crossover
        DateTime taskEndDateTime;
        
        // Get task start time for comparison
        final taskStart = (data['task_start'] is Timestamp) 
            ? (data['task_start'] as Timestamp).toDate() 
            : data['task_start'] as DateTime?;
            
        if (taskStart != null && taskEnd.hour < taskStart.hour) {
          // Task crosses midnight (e.g., 11:55 PM start, 12:03 AM end)
          // End time is on the next day
          taskEndDateTime = DateTime(
            actualTaskDate.year,
            actualTaskDate.month,
            actualTaskDate.day + 1, // Next day
            taskEnd.hour,
            taskEnd.minute,
          );
          print('🌙 Task crosses midnight: ${data['task_description']} ends ${taskEnd.hour}:${taskEnd.minute.toString().padLeft(2, '0')} next day');
        } else {
          // Regular task on same day
          taskEndDateTime = DateTime(
            actualTaskDate.year,
            actualTaskDate.month,
            actualTaskDate.day,
            taskEnd.hour,
            taskEnd.minute,
          );
          print('☀️ Regular task: ${data['task_description']} ends ${taskEnd.hour}:${taskEnd.minute.toString().padLeft(2, '0')} same day');
        }
        
        print('🔍 TASK MISSED DETECTION DEBUG:');
        print('   Task: ${data['task_description']}');
        print('   Task Date: $actualTaskDate');
        print('   Task Start: ${taskStart?.hour}:${taskStart?.minute.toString().padLeft(2, '0')}');
        print('   Task End: ${taskEnd.hour}:${taskEnd.minute.toString().padLeft(2, '0')}');
        print('   Calculated End DateTime: $taskEndDateTime');
        print('   Current Time: $now');
        print('   Would mark as missed: ${now.isAfter(taskEndDateTime)}');
        
        // 🔧 FIX 2: Enhanced missed task detection for overnight shifts
        bool shouldMarkAsMissed = false;
        
        // Get caregiver's shift information to determine if this is an overnight shift
        try {
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null) {
            final houseSnapshot = await FirebaseFirestore.instance
                .collection('house_shift_assignments')
                .where('user_id', isEqualTo: currentUser.uid)
                .where('user_type', isEqualTo: 'caregiver')
                .where('is_current', isEqualTo: true)
                .limit(1)
                .get();
            
            if (houseSnapshot.docs.isNotEmpty) {
              final houseData = houseSnapshot.docs.first.data();
              final startTime = houseData['start_time'] as String?;
              final endTime = houseData['end_time'] as String?;
              
              if (startTime != null && endTime != null && startTime.isNotEmpty && endTime.isNotEmpty) {
                final startParts = startTime.split(':');
                final endParts = endTime.split(':');
                final shiftStartHour = int.parse(startParts[0]);
                final shiftEndHour = int.parse(endParts[0]);
                final shiftEndMinute = int.parse(endParts[1]);
                
                // Check if this is an overnight shift
                final isOvernightShift = shiftEndHour < shiftStartHour || 
                    (shiftEndHour == shiftStartHour && int.parse(endParts[1]) <= int.parse(startParts[1]));
                
                if (isOvernightShift) {
                  // For overnight shifts, calculate the actual shift end time
                  // Use CURRENT TIME to determine which part of the shift we're in, not task time
                  DateTime actualShiftEnd;
                  
                  print('🔍 Overnight shift detected for task: ${data['task_description']}');
                  print('🔍 Current time: ${now.hour}:${now.minute.toString().padLeft(2, '0')}');
                  print('🔍 Shift: $shiftStartHour:00 - $shiftEndHour:${shiftEndMinute.toString().padLeft(2, '0')}');
                  print('🔍 Task end time: ${taskEndDateTime.hour}:${taskEndDateTime.minute.toString().padLeft(2, '0')}');
                  
                  if (now.hour >= shiftStartHour || now.hour < shiftEndHour) {
                    // We're currently in an active overnight shift
                    if (now.hour >= shiftStartHour) {
                      // We're in the "same day" portion (e.g., 10 PM - 11:59 PM)
                      // Shift ends tomorrow
                      actualShiftEnd = DateTime(
                        now.year,
                        now.month,
                        now.day + 1, // Next day
                        shiftEndHour,
                        shiftEndMinute,
                      );
                      print('🌙 Currently in same-day portion of shift, shift ends tomorrow at $actualShiftEnd');
                    } else {
                      // We're in the "next day" portion (e.g., 12:00 AM - 6:00 AM)
                      // Shift ends today
                      actualShiftEnd = DateTime(
                        now.year,
                        now.month,
                        now.day,
                        shiftEndHour,
                        shiftEndMinute,
                      );
                      print('🌙 Currently in next-day portion of shift, shift ends today at $actualShiftEnd');
                    }
                    
                    // During an active overnight shift, use normal task end time logic
                    // The task is missed when its individual end time passes
                    shouldMarkAsMissed = now.isAfter(taskEndDateTime);
                    
                    if (shouldMarkAsMissed) {
                      print('⏰ MISSED TASK (Overnight Shift - Task Time Passed): ${data['task_description']} - task ended at $taskEndDateTime, now $now');
                    } else {
                      print('✅ Task still valid (Overnight Shift): ${data['task_description']} - task ends $taskEndDateTime, now $now');
                    }
                  } else {
                    // We're outside shift hours, use task's original end time for comparison
                    print('🌙 Currently outside shift hours, using task end time');
                    shouldMarkAsMissed = now.isAfter(taskEndDateTime);
                    
                    if (shouldMarkAsMissed) {
                      print('⏰ MISSED TASK (Outside Shift): ${data['task_description']} - task end $taskEndDateTime has passed');
                    } else {
                      print('✅ Task still valid (Outside Shift): ${data['task_description']} - task end $taskEndDateTime');
                    }
                  }
                } else {
                  // Regular shift logic
                  shouldMarkAsMissed = now.isAfter(taskEndDateTime);
                  if (shouldMarkAsMissed) {
                    print('⏰ MISSED TASK (Regular Shift): ${data['task_description']} - end time $taskEndDateTime has passed');
                  }
                }
              } else {
                // Fallback to original logic if no time range data
                shouldMarkAsMissed = now.isAfter(taskEndDateTime);
              }
            } else {
              // Fallback to original logic if no assignment data
              shouldMarkAsMissed = now.isAfter(taskEndDateTime);
            }
          } else {
            // Fallback to original logic if no user
            shouldMarkAsMissed = now.isAfter(taskEndDateTime);
          }
        } catch (e) {
          print('❌ Error checking shift information for missed task detection: $e');
          // Fallback to original logic on error
          shouldMarkAsMissed = now.isAfter(taskEndDateTime);
        }
        
        if (shouldMarkAsMissed) {
          // Mark task as missed and handle recurring task logic
          await _markTaskAsMissed(doc.id, data);
          continue; // Skip adding to upcoming tasks
        }
      }
      
      // Fetch elderly profile picture
      String profilePicUrl = '';
      if (elderlyId != null) {
        try {
          final elderlyDoc = await FirebaseFirestore.instance
              .collection('elderly')
              .doc(elderlyId)
              .get();
          if (elderlyDoc.exists) {
            final elderlyData = elderlyDoc.data();
            profilePicUrl = elderlyData?['elderly_profilePic'] ?? elderlyData?['profile_pic'] ?? '';
          }
        } catch (e) {
          print('DEBUG: Error fetching elderly profile pic in upcoming_tasks: $e');
        }
      }
      
      tasks.add({
        'task_id': data['task_id'] ?? doc.id,
        'elderly_fname': data['elderly_fname'] ?? '',
        'task_description': data['task_description'] ?? '',
        'task_start': (data['task_start'] is Timestamp) ? (data['task_start'] as Timestamp).toDate() : data['task_start'],
        'task_end': (data['task_end'] is Timestamp) ? (data['task_end'] as Timestamp).toDate() : data['task_end'],
        'task_date': (data['task_date'] is Timestamp) ? (data['task_date'] as Timestamp).toDate() : data['task_date'],
        'freq_once_date': (data['freq_once_date'] is Timestamp) ? (data['freq_once_date'] as Timestamp).toDate() : data['freq_once_date'],
        'task_frequency': data['task_frequency'] ?? ['Only once'],
        'task_status': data['task_status'] ?? ['Upcoming'],
        'custom_days': data['custom_days'],
        'recurring_start_date': data['recurring_start_date'],
        'next_taskdate': data['next_taskdate'],
        'elderly_id': data['elderly_id'],
        'caregiver_id': data['caregiver_id'],
        'created_by': data['created_by'],
        'created_at': data['created_at'],
        'updated_at': data['updated_at'],
        'elderly_profilePic': profilePicUrl,
      });
    }
    
    return tasks;
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : hour == 0 ? 12 : hour;
    return '$hour12:$minute $ampm';
  }

  // Progressive task system check - called when screen loads
  void _checkProgressiveTaskSystem(BuildContext context) async {
    try {
      print('🔄 _checkProgressiveTaskSystem called at ${DateTime.now()}');
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        print('👤 Current user found: ${currentUser.uid}');
        
        // Sync task reminders in the background
        TaskReminderService().scheduleAllUpcomingTaskReminders().catchError((error) {
          print('❌ Error syncing task reminders: $error');
        });
        
        // Call the progressive task system in background (non-blocking)
        TaskService.checkAndProgressRecurringTasks(currentUser.uid).then((progressedTasks) {
          print('📊 Progressive system returned: $progressedTasks tasks progressed');
          if (progressedTasks > 0) {
            print('✅ Progressive Task System: $progressedTasks recurring tasks updated to next occurrence dates');
            // Show a brief notification that tasks were updated
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$progressedTasks recurring tasks updated to next occurrence dates'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
            }
          } else {
            print('ℹ️ No tasks were progressed by automatic system');
          }
        }).catchError((error) {
          print('❌ Progressive task system error: $error');
        });
      } else {
        print('❌ No current user found');
      }
    } catch (e) {
      print('❌ Error triggering progressive task system: $e');
    }
  }

  // Utility to parse "HH:mm" string to TimeOfDay
  TimeOfDay _parseTimeOfDay(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  // Removed unused _getCaregiverTimeRange function
  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return '';
    final year = dateTime.year;
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
  // Format header date from 'YYYY-MM-DD' to 'Month Day, Year'
  String formatHeaderDate(String key) {
    try {
      final date = DateTime.parse(key);
      const months = [
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      final monthName = months[date.month];
      return '$monthName ${date.day}, ${date.year}';
    } catch (e) {
      return key;
    }
  }
  
  Future<void> _onRefresh() async {
    // Trigger progressive task system when user pulls to refresh
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await TaskService.checkAndProgressRecurringTasks(currentUser.uid);
    }
    // Force refresh the data
    _triggerRefresh();
    // Add a small delay to ensure UI updates
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    // Progressive task system is triggered in initState, didChangeAppLifecycleState, and onRefresh
    // DO NOT call it here as build() runs frequently and would cause immediate task recurrence
    
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: StreamBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(_refreshKey), // Force rebuild when refresh key changes
      stream: getTasksStream(),
      builder: (context, snapshot) {
        // Show loading spinner while data is loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF22688E)),
            ),
          );
        }
        
        // Handle errors
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 60),
                const SizedBox(height: 16),
                Text(
                  'Error loading tasks',
                  style: const TextStyle(fontSize: 18, color: Colors.red, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  snapshot.error.toString(),
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        
        List<Map<String, dynamic>> tasks = snapshot.data ?? [];
        
        // Group tasks by their display date - when they should actually appear
        Map<String, List<Map<String, dynamic>>> grouped = {};
        for (var task in tasks) {
          DateTime? displayDate;
          final freqList = task['task_frequency'] as List<dynamic>? ?? [];
          final freq = freqList.isNotEmpty ? freqList[0] as String : 'Only once';
          
          // Debug: Print task data to understand date display issues
          if (task['task_description'].toString().toLowerCase().contains('test')) {
            print('=== TASK DATE DEBUG ===');
            print('Task: ${task['task_description']}');
            print('Frequency: $freq');
            print('task_date: ${task['task_date']}');
            print('freq_once_date: ${task['freq_once_date']}');
            print('next_taskdate: ${task['next_taskdate']}');
            print('Will display task_date for recurring tasks: ${freq != 'Only once'}');
            print('=======================');
          }
          
          // Determine the correct display date for this task
          if (freq == 'Only once') {
            // For "Only once" tasks, use the scheduled date
            displayDate = task['freq_once_date'] as DateTime? ?? task['task_date'] as DateTime?;
          } else {
            // For recurring tasks ("Every Assigned Day", "Custom", etc.)
            // Use task_date - this is the current occurrence date
            displayDate = task['task_date'] as DateTime?;
            
            // If task_date is null, this is a data issue - log and skip
            if (displayDate == null) {
              print('⚠️ Warning: Recurring task ${task['task_description']} has no task_date - skipping');
              continue;
            }
          }
          
          // Debug: Print final display date 
          if (task['task_description'].toString().toLowerCase().contains('test')) {
            print('✅ Final displayDate for ${task['task_description']}: $displayDate');
          }
          
          if (displayDate == null) continue;
          final key = "${displayDate.year}-${displayDate.month.toString().padLeft(2, '0')}-${displayDate.day.toString().padLeft(2, '0')}";
          grouped.putIfAbsent(key, () => []).add(task);
        }
        // Sort dates chronologically (earliest date first, prioritizing today and upcoming dates)
        final sortedKeys = grouped.keys.toList()
          ..sort((a, b) {
            final ad = DateTime.parse(a.replaceAll('-', ''));
            final bd = DateTime.parse(b.replaceAll('-', ''));
            return ad.compareTo(bd); // Simple chronological sort
          });
        return SizedBox.expand(
          child: Column(
            children: [
              Expanded(
                child: tasks.isEmpty
                  ? const Center(child: Text('No Upcoming Tasks', style: TextStyle(fontSize: 18, color: Color(0xFF22688E), fontWeight: FontWeight.bold)))
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      children: [
                        for (final key in sortedKeys)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6F3FA),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Text(
                                    formatHeaderDate(key),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF22688E)),
                                  ),
                                ),
                                for (final task in ((grouped[key] ?? [])..sort((a, b) {
                                  final aStart = a['task_start'] as DateTime? ?? DateTime.now();
                                  final bStart = b['task_start'] as DateTime? ?? DateTime.now();
                                  return aStart.compareTo(bStart);
                                })))
                                  InkWell(
                                    onTap: () {
                                      bool showReasonInput = false;
                                      TextEditingController reasonController = TextEditingController();
                                      showDialog(
                                        context: context,
                                        builder: (BuildContext ctx) {
                                          return StatefulBuilder(
                                            builder: (context, setState) {
                                              return Dialog(
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                                                child: Container(
                                                  width: 350,
                                                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  child: SingleChildScrollView(
                                                    child: Column(
                                                      mainAxisSize: MainAxisSize.min,
                                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                                      children: [
                                                        Row(
                                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                          children: [
                                                            Expanded(
                                                              child: Padding(
                                                                padding: const EdgeInsets.only(left: 8.0),
                                                                child: Text(
                                                                  'Task Details',
                                                                  style: const TextStyle(
                                                                    fontSize: 22,
                                                                    fontWeight: FontWeight.bold,
                                                                    color: Color(0xFF22688E),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                            TaskActionButtons(
                                                              onEdit: () async {
                                                                await showDialog(
                                                                  context: ctx,
                                                                  builder: (BuildContext editCtx) {
                                                                    return EditTaskDialog(task: task, parentContext: ctx);
                                                                  },
                                                                );
                                                              },
                                                              onDelete: () async {
                                                                final confirm = await showDialog<bool>(
                                                                  context: ctx,
                                                                  builder: (BuildContext confirmCtx) {
                                                                    return AlertDialog(
                                                                      shape: RoundedRectangleBorder(
                                                                        borderRadius: BorderRadius.circular(16),
                                                                      ),
                                                                      title: const Row(
                                                                        children: [
                                                                          Icon(
                                                                            Icons.delete_outline,
                                                                            color: Color(0xFFD32F2F),
                                                                            size: 28,
                                                                          ),
                                                                          SizedBox(width: 8),
                                                                          Text(
                                                                            'Delete Task',
                                                                            style: TextStyle(
                                                                              color: Color(0xFFD32F2F),
                                                                              fontWeight: FontWeight.bold,
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      content: const Text(
                                                                        'Are you sure you want to delete this task? This action cannot be undone.',
                                                                        style: TextStyle(fontSize: 16),
                                                                      ),
                                                                      actions: [
                                                                        TextButton(
                                                                          onPressed: () => Navigator.of(confirmCtx).pop(false),
                                                                          style: TextButton.styleFrom(
                                                                            foregroundColor: Colors.grey[600],
                                                                          ),
                                                                          child: const Text('Cancel'),
                                                                        ),
                                                                        TextButton(
                                                                          onPressed: () => Navigator.of(confirmCtx).pop(true),
                                                                          style: TextButton.styleFrom(
                                                                            backgroundColor: const Color(0xFFD32F2F),
                                                                            foregroundColor: Colors.white,
                                                                            shape: RoundedRectangleBorder(
                                                                              borderRadius: BorderRadius.circular(8),
                                                                            ),
                                                                          ),
                                                                          child: const Text('Delete'),
                                                                        ),
                                                                      ],
                                                                    );
                                                                  },
                                                                );
                                                                if (confirm == true) {
                                                                  // Soft delete: update 'task_status' to ['Deleted']
                                                                  final docId = task['task_id'];
                                                                  await TaskService.deleteTask(docId);
                                                                  
                                                                  // Check if widget is still mounted before popping
                                                                  if (mounted) {
                                                                    Navigator.of(ctx).pop();
                                                                  }
                                                                }
                                                              },
                                                              onClose: () => Navigator.of(ctx).pop(),
                                                            ),
                                                          ],
                                                        ),
                                                    const Divider(),
                                                    const SizedBox(height: 10),
                                                    Row(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Icon(Icons.person, color: Color(0xFF22688E)),
                                                        const SizedBox(width: 8),
                                                        const Text('Name:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                        const SizedBox(width: 8),
                                                        Expanded(
                                                          child: Text(
                                                            task['elderly_fname'] ?? '',
                                                            style: const TextStyle(fontSize: 16),
                                                            softWrap: true,
                                                            overflow: TextOverflow.visible,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Row(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Icon(Icons.assignment, color: Color(0xFF22688E)),
                                                        const SizedBox(width: 8),
                                                        const Text('Activity:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                        const SizedBox(width: 8),
                                                        Expanded(
                                                          child: Text(
                                                            task['task_description'] ?? '',
                                                            style: const TextStyle(fontSize: 16),
                                                            softWrap: true,
                                                            overflow: TextOverflow.visible,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.access_time, color: Color(0xFF22688E)),
                                                        const SizedBox(width: 8),
                                                        const Text('Time:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E)),),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          '${task['task_start'] != null ? _formatTime(task['task_start']) : ''} - ${task['task_end'] != null ? _formatTime(task['task_end']) : ''}',
                                                          style: const TextStyle(fontSize: 16),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Row(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Icon(Icons.repeat, color: Color(0xFF22688E)),
                                                        const SizedBox(width: 8),
                                                        const Text('Frequency:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                        const SizedBox(width: 8),
                                                        Expanded(
                                                          child: Text(
                                                            (() {
                                                              final freqList = task['task_frequency'] as List<dynamic>? ?? [];
                                                              final freq = freqList.isNotEmpty ? freqList[0] as String : 'Only once';
                                                              if (freq == 'Only once') {
                                                                final onceDate = task['freq_once_date'];
                                                                if (onceDate != null) {
                                                                  if (onceDate is DateTime) {
                                                                    return 'Only once (${_formatDate(onceDate)})';
                                                                  } else if (onceDate is String) {
                                                                    return 'Only once ($onceDate)';
                                                                  }
                                                                }
                                                                return 'Only once';
                                                              } else if (freq == 'Every Assigned Day') {
                                                                return 'Every day assigned to this elderly';
                                                              } else if (freq == 'Custom') {
                                                                final customDays = task['custom_days'] as List<dynamic>? ?? [];
                                                                if (customDays.isNotEmpty) {
                                                                  return 'Custom (${customDays.join(', ')})';
                                                                }
                                                                return 'Custom';
                                                              }
                                                              return freq;
                                                            })(),
                                                            style: const TextStyle(fontSize: 16),
                                                            softWrap: true,
                                                            overflow: TextOverflow.visible,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.calendar_today, color: Color(0xFF22688E)),
                                                        const SizedBox(width: 8),
                                                        const Text('Created:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          (() {
                                                            final created = task['created_at'];
                                                            if (created == null) return '';
                                                            if (created is DateTime) {
                                                              return '${_formatDate(created)} at ${_formatTime(created)}';
                                                            } else if (created is Timestamp) {
                                                              final dt = created.toDate();
                                                              return '${_formatDate(dt)} at ${_formatTime(dt)}';
                                                            }
                                                            return created.toString();
                                                          })(),
                                                          style: const TextStyle(fontSize: 16),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 20),
                                                    !showReasonInput
                                                        ? Row(
                                                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                            children: [
                                                              Flexible(
                                                                child: TextButton.icon(
                                                                  onPressed: () async {
                                                                    // Check if caregiver is on duty before allowing task completion
                                                                    final isOnDuty = await _isCaregiverOnDuty();
                                                                    if (!isOnDuty) {
                                                                      _showNotOnDutyDialog(ctx);
                                                                      return;
                                                                    }

                                                                    bool confirmChecked = false;
                                                                    await showDialog(
                                                                      context: ctx,
                                                                      builder: (BuildContext confirmCtx) {
                                                                        return StatefulBuilder(
                                                                          builder: (context, setState) {
                                                                            return AlertDialog(
                                                                              shape: RoundedRectangleBorder(
                                                                                borderRadius: BorderRadius.circular(16),
                                                                              ),
                                                                              title: const Row(
                                                                                children: [
                                                                                  Icon(
                                                                                    Icons.check_circle_outline,
                                                                                    color: Color(0xFF4CAF50),
                                                                                    size: 28,
                                                                                  ),
                                                                                  SizedBox(width: 8),
                                                                                  Text(
                                                                                    'Confirm Completion',
                                                                                    style: TextStyle(
                                                                                      color: Color(0xFF4CAF50),
                                                                                      fontWeight: FontWeight.bold,
                                                                                    ),
                                                                                  ),
                                                                                ],
                                                                              ),
                                                                              content: Column(
                                                                                mainAxisSize: MainAxisSize.min,
                                                                                children: [
                                                                                  const Text(
                                                                                    'Please confirm that you have completed this task.',
                                                                                    style: TextStyle(fontSize: 16),
                                                                                  ),
                                                                                  const SizedBox(height: 16),
                                                                                  CheckboxListTile(
                                                                                    value: confirmChecked,
                                                                                    onChanged: (checked) {
                                                                                      setState(() {
                                                                                        confirmChecked = checked ?? false;
                                                                                      });
                                                                                    },
                                                                                    title: const Text(
                                                                                      'I hereby confirm that the task is completed',
                                                                                      style: TextStyle(fontSize: 14),
                                                                                    ),
                                                                                    activeColor: const Color(0xFF4CAF50),
                                                                                    contentPadding: EdgeInsets.zero,
                                                                                  ),
                                                                                ],
                                                                              ),
                                                                              actions: [
                                                                                TextButton(
                                                                                  onPressed: () => Navigator.of(confirmCtx).pop(),
                                                                                  style: TextButton.styleFrom(
                                                                                    foregroundColor: Colors.grey[600],
                                                                                  ),
                                                                                  child: const Text('Cancel'),
                                                                                ),
                                                                                TextButton(
                                                                                  onPressed: confirmChecked
                                                                                      ? () async {
                                                                                          final docId = task['task_id'];
                                                                                          // Don't calculate next_taskdate here - let Progressive Task System handle it when shift ends
                                                                                          // This prevents the next date from showing in Complete screen before shift end
                                                                                          await TaskService.markTaskComplete(docId, null);
                                                                                          Navigator.of(confirmCtx).pop();
                                                                                          Navigator.of(ctx).pop();
                                                                                        }
                                                                                      : null,
                                                                                  style: TextButton.styleFrom(
                                                                                    backgroundColor: confirmChecked ? const Color(0xFF4CAF50) : Colors.grey[300],
                                                                                    foregroundColor: confirmChecked ? Colors.white : Colors.grey[600],
                                                                                    shape: RoundedRectangleBorder(
                                                                                      borderRadius: BorderRadius.circular(8),
                                                                                    ),
                                                                                  ),
                                                                                  child: const Text('Submit'),
                                                                                ),
                                                                              ],
                                                                            );
                                                                          },
                                                                        );
                                                                      },
                                                                    );
                                                                  },
                                                                  icon: const Icon(Icons.check_circle, color: Color(0xFF22688E)),
                                                                  label: const Text('Complete', style: TextStyle(color: Color(0xFF22688E), fontWeight: FontWeight.bold, fontSize: 16)),
                                                                  style: TextButton.styleFrom(
                                                                    backgroundColor: const Color(0xFFE6F3FA),
                                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(width: 8),
                                                              Flexible(
                                                                child: TextButton.icon(
                                                                  onPressed: () async {
                                                                    // Check if caregiver is on duty before allowing task to be marked incomplete
                                                                    final isOnDuty = await _isCaregiverOnDuty();
                                                                    if (!isOnDuty) {
                                                                      _showNotOnDutyDialog(ctx);
                                                                      return;
                                                                    }

                                                                    setState(() {
                                                                      showReasonInput = true;
                                                                    });
                                                                  },
                                                                  icon: const Icon(Icons.cancel, color: Color(0xFFD32F2F)),
                                                                  label: const Text('Incomplete', style: TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold, fontSize: 16)),
                                                                  style: TextButton.styleFrom(
                                                                    backgroundColor: const Color(0xFFFDEAEA),
                                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          )
                                                        : Column(
                                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                                            children: [
                                                              const Text('Reason for Incompletion:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFD32F2F))),
                                                              const SizedBox(height: 10),
                                                              Container(
                                                                decoration: BoxDecoration(
                                                                  color: Color(0xFFFDEAEA),
                                                                  borderRadius: BorderRadius.circular(12),
                                                                ),
                                                                child: TextField(
                                                                  controller: reasonController,
                                                                  maxLines: 3,
                                                                  decoration: const InputDecoration(
                                                                    hintText: 'Type reason here',
                                                                    hintStyle: TextStyle(fontStyle: FontStyle.italic),
                                                                    border: InputBorder.none,
                                                                    contentPadding: EdgeInsets.all(8),
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(height: 16),
                                                              SizedBox(
                                                                width: double.infinity,
                                                                height: 44,
                                                                child: ElevatedButton(
                                                                  onPressed: () async {
                                                                    // Check if caregiver is on duty before submitting incomplete reason
                                                                    final isOnDuty = await _isCaregiverOnDuty();
                                                                    if (!isOnDuty) {
                                                                      _showNotOnDutyDialog(ctx);
                                                                      return;
                                                                    }

                                                                    final reasonText = reasonController.text.trim();
                                                                    if (reasonText.isNotEmpty) {
                                                                      final docId = task['task_id'];
                                                                      
                                                                      // Don't calculate next_taskdate here - let Progressive Task System handle it when shift ends
                                                                      // This prevents the next date from showing in Incomplete screen before shift end
                                                                      await TaskService.markTaskIncompleteWithNextOccurrence(docId, reasonText, null);
                                                                      
                                                                      // Check if widget is still mounted before popping
                                                                      if (mounted) {
                                                                        Navigator.of(ctx).pop();
                                                                      }
                                                                    }
                                                                  },
                                                                  style: ElevatedButton.styleFrom(
                                                                    backgroundColor: const Color(0xFF22688E),
                                                                    shape: RoundedRectangleBorder(
                                                                      borderRadius: BorderRadius.circular(16),
                                                                    ),
                                                                  ),
                                                                  child: const Text('Submit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                                child: Card(
                                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  color: Colors.white,
                                  elevation: 2,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 56,
                                          height: 56,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Color(0xFF00588e),
                                          ),
                                          child: ClipOval(
                                            child: (task['profile_pic'] != null && task['profile_pic'].isNotEmpty)
                                                ? CachedNetworkImage(
                                                    imageUrl: task['profile_pic'],
                                                    width: 56,
                                                    height: 56,
                                                    fit: BoxFit.cover,
                                                    placeholder: (context, url) => Container(
                                                      width: 56,
                                                      height: 56,
                                                      color: Colors.grey[300],
                                                      child: const Icon(
                                                        Icons.person,
                                                        color: Colors.grey,
                                                        size: 28,
                                                      ),
                                                    ),
                                                    errorWidget: (context, url, error) => Image.asset(
                                                      'assets/images/people_icon.png',
                                                      width: 56,
                                                      height: 56,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  )
                                                : Image.asset(
                                                    'assets/images/people_icon.png',
                                                    width: 56,
                                                    height: 56,
                                                    fit: BoxFit.cover,
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                task['elderly_fname'] ?? '',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF00588e)),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                task['task_description'] ?? '',
                                                style: const TextStyle(fontSize: 15, color: Colors.black87),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  task['task_start'] != null ? _formatTime(task['task_start']) : '',
                                                  style: const TextStyle(fontSize: 14, color: Color(0xFF00588e), fontWeight: FontWeight.bold),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  width: 12,
                                                  height: 12,
                                                  decoration: const BoxDecoration(
                                                    color: Color(0xFF1B7F5A),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Text(
                                                  task['task_end'] != null ? _formatTime(task['task_end']) : '',
                                                  style: const TextStyle(fontSize: 14, color: Color(0xFF00588e), fontWeight: FontWeight.bold),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  width: 12,
                                                  height: 12,
                                                  decoration: const BoxDecoration(
                                                    color: Color(0xFFD32F2F),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    SizedBox(
                      width: 120,
                      child: ElevatedButton(
                        onPressed: () async {
                          // Show loading dialog first
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (BuildContext loadingContext) {
                              return Dialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const CircularProgressIndicator(
                                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF22688E)),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Loading elderly assignments...',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Color(0xFF22688E),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                          
                          try {
                            final caregiverId = await _getCurrentCaregiverId(context);
                            // Fetch caregiver's assigned days and time range first
                            List<String> caregiverAssignedDays = [];
                            Map<String, String> caregiverTimeRange = {'start': '00:00', 'end': '23:59'};
                            final assignSnap = await FirebaseFirestore.instance
                              .collection('house_shift_assignments')
                              .where('user_id', isEqualTo: caregiverId)
                              .where('user_type', isEqualTo: 'caregiver')
                              .get();
                            if (assignSnap.docs.isNotEmpty) {
                              final assignData = assignSnap.docs.first.data();
                              caregiverAssignedDays = List<String>.from(assignData['days_assigned'] ?? []);
                              final startTime = assignData['start_time'] as String? ?? '00:00';
                              final endTime = assignData['end_time'] as String? ?? '23:59';
                              caregiverTimeRange = {
                                'start': startTime,
                                'end': endTime,
                              };
                            }
                            // Now set selectedDay and fetch ALL assignedElderly with all their assigned days
                            final now = DateTime.now();
                            final todayName = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][now.weekday - 1];
                            print('🔍 DEBUG: caregiverAssignedDays = $caregiverAssignedDays');
                            print('🔍 DEBUG: Today is $todayName');
                            
                            // Keep selectedDay for the Assigned Days dropdown (but use different logic for elderly dropdown)
                            String selectedDay = caregiverAssignedDays.contains(todayName)
                              ? todayName
                              : (caregiverAssignedDays.isNotEmpty ? caregiverAssignedDays.first : 'Monday');
                            print('🔍 DEBUG: Selected day for Assigned Days dropdown = $selectedDay');
                            
                            // OPTIMIZATION: Preload ALL elderly data for ALL assigned days at once
                            Map<String, List<Map<String, dynamic>>> elderlyByDay = await _preloadAllElderlyForAllAssignedDays(caregiverId, caregiverAssignedDays);
                            List<Map<String, dynamic>> assignedElderly = elderlyByDay[selectedDay] ?? [];
                            print('🔍 DEBUG: assignedElderly result = ${assignedElderly.length} elderly found for $selectedDay');
                            for (var elderly in assignedElderly) {
                              print('🔍 DEBUG: Elderly: ${elderly['elderly_fname']} (ID: ${elderly['elderly_id']})');
                            }
                            final rangeStart = _parseTimeOfDay(caregiverTimeRange['start'] ?? '00:00');
                            final rangeEnd = _parseTimeOfDay(caregiverTimeRange['end'] ?? '23:59');
                            
                            // Close loading dialog
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                            
                          if (context.mounted) {
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (BuildContext ctx) {
                                String? selectedElderly;
                                String? selectedFrequency = 'Only once';
                                bool isTemporaryAssignment = false; // Track if selected elderly is temporary
                              TimeOfDay? startTime;
                              TimeOfDay? endTime;
                              TextEditingController activityController = TextEditingController();
                              final List<String> frequencyList = ['Only once', 'Every Assigned Day', 'Custom'];
                              DateTime? selectedDate;
                              List<String> selectedDaysBox = [];
                              DateTime? selectedRecurringStartDate;
                              return StatefulBuilder(
                                builder: (context, setState) {
                                  // Check if initial/auto-selected elderly is temporary
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (selectedElderly != null && assignedElderly.isNotEmpty) {
                                      final elderlyData = assignedElderly.firstWhere(
                                        (e) => e['elderly_id'] == selectedElderly,
                                        orElse: () => {},
                                      );
                                      
                                      final isTemp = elderlyData['is_temporary_assignment'] == true;
                                      
                                      if (isTemp != isTemporaryAssignment) {
                                        setState(() {
                                          isTemporaryAssignment = isTemp;
                                          if (isTemp) {
                                            selectedFrequency = 'Only once';
                                            selectedDate = DateTime.now();
                                            selectedRecurringStartDate = DateTime.now();
                                          }
                                        });
                                      }
                                    }
                                  });
                                  
                                  // OPTIMIZATION: Instant day switching using preloaded data
                                  void updateElderlyList(String newDay) {
                                    setState(() {
                                      selectedDay = newDay;
                                      assignedElderly = elderlyByDay[newDay] ?? [];
                                      selectedElderly = null; // Reset selected elderly when day changes
                                    });
                                  }
                                  return Dialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                                    child: Container(
                                      width: 350,
                                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: SingleChildScrollView(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Center(
                                                    child: Text(
                                                      'Add Task',
                                                      style: const TextStyle(
                                                        fontSize: 20,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFF22688E),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.close, size: 25, color: Color(0xFF22688E)),
                                                  onPressed: () => Navigator.of(ctx).pop(),
                                                ),
                                              ],
                                            ),
                                            const Divider(),
                                            const SizedBox(height: 10),
                                            // Day selector for assigned work days
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    const Icon(Icons.calendar_today, color: Color(0xFF22688E)),
                                                    const SizedBox(width: 8),
                                                    const Text('Assigned Day:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                    const SizedBox(width: 8),
                                                    DropdownButton<String>(
                                                      value: selectedDay,
                                                      items: (() {
                                                        const weekdayOrder = [
                                                          'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
                                                        ];
                                                        List<String> sortedDays = List<String>.from(caregiverAssignedDays);
                                                        sortedDays.sort((a, b) => weekdayOrder.indexOf(a).compareTo(weekdayOrder.indexOf(b)));
                                                        return sortedDays.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList();
                                                      })(),
                                                      onChanged: (val) {
                                                        if (val != null) {
                                                          updateElderlyList(val);
                                                        }
                                                      },
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.person, color: Color(0xFF22688E)),
                                                    const SizedBox(width: 8),
                                                    const Text('Name of the Elderly:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Container(
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFE6F3FA),
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  padding: EdgeInsets.zero,
                                                  child: DropdownButtonHideUnderline(
                                                    child: DropdownButton2<String>(
                                                      value: (() {
                                                        // Remove duplicates by elderly_id
                                                        final seen = <String>{};
                                                        List<Map<String, dynamic>> sortedElderly = List<Map<String, dynamic>>.from(assignedElderly)
                                                          .where((e) => e['elderly_id'] != null && seen.add(e['elderly_id'])).toList();
                                                        sortedElderly.sort((a, b) => (a['elderly_fname'] ?? '').toString().toLowerCase().compareTo((b['elderly_fname'] ?? '').toString().toLowerCase()));
                                                        final ids = sortedElderly.map((e) => e['elderly_id']).toList();
                                                        if (ids.isEmpty) return null;
                                                        if (selectedElderly == null || !ids.contains(selectedElderly)) {
                                                          // If current value is not in the list, default to first
                                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                                            setState(() {
                                                              selectedElderly = ids.first;
                                                            });
                                                          });
                                                          return ids.first;
                                                        }
                                                        return selectedElderly;
                                                      })(),
                                                      isExpanded: true,
                                                      hint: const Text('Select Elderly', style: TextStyle(color: Color.fromARGB(255, 0, 0, 0))),
                                                      buttonStyleData: const ButtonStyleData(
                                                        height: 40,
                                                        padding: EdgeInsets.zero,
                                                        decoration: BoxDecoration(
                                                          color: Color(0xFFE6F3FA),
                                                          borderRadius: BorderRadius.all(Radius.circular(20)),
                                                        ),
                                                      ),
                                                      dropdownStyleData: DropdownStyleData(
                                                        maxHeight: 200,
                                                        decoration: BoxDecoration(
                                                          color: Color(0xFFE6F3FA),
                                                          borderRadius: BorderRadius.circular(20),
                                                        ),
                                                      ),
                                                      items: (() {
                                                        final seen = <String>{};
                                                        List<Map<String, dynamic>> sortedElderly = List<Map<String, dynamic>>.from(assignedElderly)
                                                          .where((e) => e['elderly_id'] != null && seen.add(e['elderly_id'])).toList();
                                                        sortedElderly.sort((a, b) => (a['elderly_fname'] ?? '').toString().toLowerCase().compareTo((b['elderly_fname'] ?? '').toString().toLowerCase()));
                                                        return sortedElderly.map((elderly) {
                                                          final isTemporary = elderly['is_temporary_assignment'] == true;
                                                          return DropdownMenuItem<String>(
                                                            value: elderly['elderly_id'],
                                                            child: Row(
                                                              children: [
                                                                Expanded(
                                                                  child: Text(
                                                                    elderly['elderly_fname'],
                                                                    style: const TextStyle(color: Color.fromARGB(255, 0, 0, 0)),
                                                                  ),
                                                                ),
                                                                if (isTemporary)
                                                                  Container(
                                                                    width: 10,
                                                                    height: 10,
                                                                    margin: const EdgeInsets.only(left: 8),
                                                                    decoration: BoxDecoration(
                                                                      color: Colors.orange,
                                                                      shape: BoxShape.circle,
                                                                      border: Border.all(
                                                                        color: Colors.white,
                                                                        width: 1,
                                                                      ),
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                          );
                                                        }).toList();
                                                      })(),
                                                      onChanged: (value) {
                                                        setState(() {
                                                          selectedElderly = value;
                                                          
                                                          // Check if this elderly is temporarily assigned
                                                          if (value != null) {
                                                            final elderlyData = assignedElderly.firstWhere(
                                                              (e) => e['elderly_id'] == value,
                                                              orElse: () => {},
                                                            );
                                                            
                                                            // Check if marked as temporary assignment
                                                            final isTemp = elderlyData['is_temporary_assignment'] == true;
                                                            
                                                            isTemporaryAssignment = isTemp;
                                                            if (isTemp) {
                                                              // Auto-set to "Only once" for temporary elderly
                                                              selectedFrequency = 'Only once';
                                                              selectedDate = DateTime.now();
                                                              selectedRecurringStartDate = DateTime.now();
                                                            } else {
                                                              // Reset when switching back to regular elderly
                                                              // Keep current frequency but enable changes
                                                            }
                                                          }
                                                        });
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            // ...existing code...
                                            const SizedBox(height: 20),
                                            Row(
                                              children: [
                                                const Icon(Icons.access_time, color: Color(0xFF22688E)),
                                                const SizedBox(width: 8),
                                                const Text('Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      const Text('Start', style: TextStyle(fontWeight: FontWeight.bold)),
                                                      const SizedBox(height: 4),
                                                      Container(
                                                        height: 40,
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFE6F3FA),
                                                          borderRadius: BorderRadius.circular(14),
                                                        ),
                                                        child: InkWell(
                                                          onTap: () async {
                                                            final picked = await showTimePicker(
                                                              context: ctx,
                                                              initialTime: startTime ?? rangeStart,
                                                            );
                                                            if (picked != null) {
                                                              // Validate using caregiver's time_range
                                                              final pickedMinutes = picked.hour * 60 + picked.minute;
                                                              final minMinutes = rangeStart.hour * 60 + rangeStart.minute;
                                                              final maxMinutes = rangeEnd.hour * 60 + rangeEnd.minute;
                                                              bool withinRange;
                                                              if (maxMinutes >= minMinutes) {
                                                                // Normal shift (e.g., 8am-5pm)
                                                                withinRange = pickedMinutes >= minMinutes && pickedMinutes <= maxMinutes;
                                                              } else {
                                                                // Overnight shift (e.g., 10pm-6am)
                                                                withinRange = pickedMinutes >= minMinutes || pickedMinutes <= maxMinutes;
                                                              }
                                                              if (withinRange) {
                                                                setState(() {
                                                                  startTime = picked;
                                                                });
                                                              } else {
                                                                showDialog(
                                                                  context: ctx,
                                                                  builder: (context) => AlertDialog(
                                                                    shape: RoundedRectangleBorder(
                                                                      borderRadius: BorderRadius.circular(16),
                                                                    ),
                                                                    title: const Row(
                                                                      children: [
                                                                        Icon(
                                                                          Icons.access_time_outlined,
                                                                          color: Color(0xFFD32F2F),
                                                                          size: 28,
                                                                        ),
                                                                        SizedBox(width: 8),
                                                                        Text(
                                                                          'Invalid Time',
                                                                          style: TextStyle(
                                                                            color: Color(0xFFD32F2F),
                                                                            fontWeight: FontWeight.bold,
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                    content: Text(
                                                                      'The picked start time (${picked.format(ctx)}) is outside your allowed work hours (${rangeStart.format(ctx)} - ${rangeEnd.format(ctx)}). Please choose another.',
                                                                      style: const TextStyle(fontSize: 16),
                                                                    ),
                                                                    actions: [
                                                                      TextButton(
                                                                        onPressed: () => Navigator.of(context).pop(),
                                                                        style: TextButton.styleFrom(
                                                                          backgroundColor: const Color(0xFFD32F2F),
                                                                          foregroundColor: Colors.white,
                                                                          shape: RoundedRectangleBorder(
                                                                            borderRadius: BorderRadius.circular(8),
                                                                          ),
                                                                        ),
                                                                        child: const Text('OK'),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                );
                                                              }
                                                            }
                                                          },
                                                          child: Padding(
                                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                            child: Row(
                                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                              children: [
                                                                Text(
                                                                  startTime != null ? startTime!.format(ctx) : 'Select',
                                                                  style: const TextStyle(fontSize: 15),
                                                                ),
                                                                const Icon(Icons.arrow_drop_down, color: Color(0xFF22688E)),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      const Text('End', style: TextStyle(fontWeight: FontWeight.bold)),
                                                      const SizedBox(height: 4),
                                                      Container(
                                                        height: 40,
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFE6F3FA),
                                                          borderRadius: BorderRadius.circular(14),
                                                        ),
                                                        child: InkWell(
                                                          onTap: () async {
                                                            final picked = await showTimePicker(
                                                              context: ctx,
                                                              initialTime: endTime ?? rangeEnd,
                                                            );
                                                            if (picked != null) {
                                                              // Validate using caregiver's time_range
                                                              final pickedMinutes = picked.hour * 60 + picked.minute;
                                                              final minMinutes = rangeStart.hour * 60 + rangeStart.minute;
                                                              final maxMinutes = rangeEnd.hour * 60 + rangeEnd.minute;
                                                              bool withinRange;
                                                              if (maxMinutes >= minMinutes) {
                                                                // Normal shift (e.g., 8am-5pm)
                                                                withinRange = pickedMinutes >= minMinutes && pickedMinutes <= maxMinutes;
                                                              } else {
                                                                // Overnight shift (e.g., 10pm-6am)
                                                                withinRange = pickedMinutes >= minMinutes || pickedMinutes <= maxMinutes;
                                                              }
                                                              if (withinRange) {
                                                                setState(() {
                                                                  endTime = picked;
                                                                });
                                                              } else {
                                                                showDialog(
                                                                  context: ctx,
                                                                  builder: (context) => AlertDialog(
                                                                    shape: RoundedRectangleBorder(
                                                                      borderRadius: BorderRadius.circular(16),
                                                                    ),
                                                                    title: const Row(
                                                                      children: [
                                                                        Icon(
                                                                          Icons.access_time_outlined,
                                                                          color: Color(0xFFD32F2F),
                                                                          size: 28,
                                                                        ),
                                                                        SizedBox(width: 8),
                                                                        Text(
                                                                          'Invalid Time',
                                                                          style: TextStyle(
                                                                            color: Color(0xFFD32F2F),
                                                                            fontWeight: FontWeight.bold,
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                    content: Text(
                                                                      'The picked end time (${picked.format(ctx)}) is outside your allowed work hours (${rangeStart.format(ctx)} - ${rangeEnd.format(ctx)}). Please choose another.',
                                                                      style: const TextStyle(fontSize: 16),
                                                                    ),
                                                                    actions: [
                                                                      TextButton(
                                                                        onPressed: () => Navigator.of(context).pop(),
                                                                        style: TextButton.styleFrom(
                                                                          backgroundColor: const Color(0xFFD32F2F),
                                                                          foregroundColor: Colors.white,
                                                                          shape: RoundedRectangleBorder(
                                                                            borderRadius: BorderRadius.circular(8),
                                                                          ),
                                                                        ),
                                                                        child: const Text('OK'),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                );
                                                              }
                                                            }
                                                          },
                                                          child: Padding(
                                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                            child: Row(
                                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                              children: [
                                                                Text(
                                                                  endTime != null ? endTime!.format(ctx) : 'Select',
                                                                  style: const TextStyle(fontSize: 15),
                                                                ),
                                                                const Icon(Icons.arrow_drop_down, color: Color(0xFF22688E)),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 20),
                                            Row(
                                              children: [
                                                const Icon(Icons.date_range, color: Color(0xFF22688E)),
                                                const SizedBox(width: 8),
                                                const Text('Frequency', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Container(
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: isTemporaryAssignment ? const Color(0xFFE0E0E0) : const Color(0xFFE6F3FA),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              child: DropdownButtonHideUnderline(
                                                child: DropdownButton<String>(
                                                  value: selectedFrequency,
                                                  isExpanded: true,
                                                  icon: Icon(Icons.arrow_drop_down, color: isTemporaryAssignment ? Colors.grey : const Color(0xFF22688E)),
                                                  items: frequencyList.map((freq) {
                                                    return DropdownMenuItem<String>(
                                                      value: freq,
                                                      child: Text(
                                                        freq,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          color: isTemporaryAssignment ? Colors.grey : Colors.black,
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                                  onChanged: isTemporaryAssignment ? null : (value) {
                                                    setState(() {
                                                      selectedFrequency = value;
                                                    });
                                                  },
                                                ),
                                              ),
                                            ),
                                            // Every Assigned Day frequency: show date picker for start date
                                            if (selectedFrequency == 'Every Assigned Day') ...[
                                              const SizedBox(height: 16),
                                              Row(
                                                children: [
                                                  const Icon(Icons.calendar_today, color: Color(0xFF22688E)),
                                                  const SizedBox(width: 8),
                                                  const Text('Start Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              GestureDetector(
                                                behavior: HitTestBehavior.opaque,
                                                onTap: () async {
                                                  if (selectedElderly == null) {
                                                    showDialog(
                                                      context: ctx,
                                                      builder: (BuildContext context) => AlertDialog(
                                                        title: const Text('Selection Required'),
                                                        content: const Text('Please select an elderly first to see their assigned days.'),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () => Navigator.of(context).pop(),
                                                            child: const Text('OK'),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                    return;
                                                  }

                                                  // Get assigned days for validation - query elderly_assignments AND temporary_assignments
                                                  print('🔍 DEBUG: Every Assigned Day date picker validation');
                                                  print('🔍 DEBUG: selectedElderly = $selectedElderly');
                                                  print('🔍 DEBUG: caregiverId = $caregiverId');
                                                  
                                                  List<String> elderlyAssignedDays = [];
                                                  bool isTemporaryAssignment = false;
                                                  
                                                  try {
                                                    // Query elderly_assignments collection for all days this elderly is assigned to this caregiver
                                                    final assignmentSnapshot = await FirebaseFirestore.instance
                                                        .collection('elderly_assignments')
                                                        .where('user_id', isEqualTo: caregiverId)
                                                        .where('user_type', isEqualTo: 'caregiver')
                                                        .get();
                                                    
                                                    print('🔍 DEBUG: Found ${assignmentSnapshot.docs.length} assignment documents');
                                                    
                                                    // Look through all assignments to find days when this elderly is assigned to this caregiver
                                                    for (var doc in assignmentSnapshot.docs) {
                                                      final assignData = doc.data();
                                                      final elderlyIds = List<String>.from(assignData['elderly_ids'] ?? []);
                                                      final day = assignData['day'] as String?;
                                                      
                                                      // If this elderly is assigned to this caregiver on this day
                                                      if (elderlyIds.contains(selectedElderly) && day != null) {
                                                        elderlyAssignedDays.add(day);
                                                        print('🔍 DEBUG: Found regular assignment: $selectedElderly assigned on $day');
                                                      }
                                                    }
                                                    
                                                    // WORKAROUND: Check temporary_assignments for today
                                                    // If this elderly is temporarily assigned, allow creating task for today only
                                                    if (elderlyAssignedDays.isEmpty) {
                                                      print('🔍 DEBUG: No regular assignments found, checking temporary assignments...');
                                                      
                                                      final now = DateTime.now();
                                                      final todayDate = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
                                                      final todayWeekday = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][now.weekday - 1];
                                                      
                                                      final tempAssignmentSnapshot = await FirebaseFirestore.instance
                                                          .collection('temporary_assignments')
                                                          .where('to_user_id', isEqualTo: caregiverId)
                                                          .where('date', isEqualTo: todayDate)
                                                          .where('status', isEqualTo: 'active')
                                                          .get();
                                                      
                                                      print('🔍 DEBUG: Found ${tempAssignmentSnapshot.docs.length} temporary assignment documents for today');
                                                      
                                                      for (var doc in tempAssignmentSnapshot.docs) {
                                                        final tempData = doc.data();
                                                        final tempElderlyIds = List<String>.from(tempData['elderly_ids'] ?? []);
                                                        
                                                        if (tempElderlyIds.contains(selectedElderly)) {
                                                          elderlyAssignedDays.add(todayWeekday);
                                                          isTemporaryAssignment = true;
                                                          print('🔍 DEBUG: Found TEMPORARY assignment: $selectedElderly temporarily assigned for today ($todayWeekday)');
                                                          break;
                                                        }
                                                      }
                                                    }
                                                    
                                                    // Remove duplicates and sort
                                                    elderlyAssignedDays = elderlyAssignedDays.toSet().toList();
                                                    elderlyAssignedDays.sort((a, b) {
                                                      const weekdayOrder = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
                                                      return weekdayOrder.indexOf(a).compareTo(weekdayOrder.indexOf(b));
                                                    });
                                                    
                                                    print('🔍 DEBUG: Final elderlyAssignedDays = $elderlyAssignedDays');
                                                    print('🔍 DEBUG: Is temporary assignment = $isTemporaryAssignment');
                                                  } catch (e) {
                                                    print('🔍 ERROR: Failed to get assignment days: $e');
                                                  }
                                                  
                                                  if (elderlyAssignedDays.isEmpty) {
                                                    showDialog(
                                                      context: ctx,
                                                      builder: (BuildContext context) => AlertDialog(
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(16),
                                                        ),
                                                        title: const Row(
                                                          children: [
                                                            Icon(
                                                              Icons.warning_amber_rounded,
                                                              color: Colors.orange,
                                                              size: 28,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Flexible(
                                                              child: Text(
                                                                'No Assigned Days',
                                                                style: TextStyle(
                                                                  color: Colors.orange,
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        content: const Text(
                                                          'You are not currently assigned to this elderly on any days. Please check with your administrator about your schedule assignments.',
                                                          style: TextStyle(fontSize: 16),
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () => Navigator.of(context).pop(),
                                                            style: TextButton.styleFrom(
                                                              backgroundColor: Colors.orange,
                                                              foregroundColor: Colors.white,
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius: BorderRadius.circular(8),
                                                              ),
                                                            ),
                                                            child: const Text('OK'),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                    return;
                                                  }

                                                  // Find the first valid date to use as initial date
                                                  DateTime? validInitialDate = selectedRecurringStartDate;
                                                  if (validInitialDate == null) {
                                                    final now = DateTime.now();
                                                    // Look for the next valid date within the next 14 days
                                                    for (int i = 0; i < 14; i++) {
                                                      final testDate = now.add(Duration(days: i));
                                                      final dayOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][testDate.weekday - 1];
                                                      if (elderlyAssignedDays.contains(dayOfWeek)) {
                                                        validInitialDate = testDate;
                                                        break;
                                                      }
                                                    }
                                                    // Fallback to tomorrow if no valid date found
                                                    validInitialDate ??= now.add(const Duration(days: 1));
                                                  }

                                                  final DateTime? picked = await showDatePicker(
                                                    context: ctx,
                                                    initialDate: validInitialDate,
                                                    firstDate: DateTime.now(),
                                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                                    selectableDayPredicate: (DateTime date) {
                                                      // For temporary assignments, only allow today
                                                      if (isTemporaryAssignment) {
                                                        final now = DateTime.now();
                                                        return date.year == now.year && 
                                                               date.month == now.month && 
                                                               date.day == now.day;
                                                      }
                                                      // For regular assignments, allow dates that match assigned days
                                                      final dayOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][date.weekday - 1];
                                                      return elderlyAssignedDays.contains(dayOfWeek);
                                                    },
                                                  );

                                                  if (picked != null) {
                                                    print('🗓️ USER SELECTED DATE: $picked (weekday: ${picked.weekday})');
                                                    setState(() {
                                                      selectedRecurringStartDate = picked;
                                                    });
                                                  }
                                                },
                                                child: Container(
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFE6F3FA),
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text(
                                                        selectedRecurringStartDate != null 
                                                            ? '${selectedRecurringStartDate!.day}/${selectedRecurringStartDate!.month}/${selectedRecurringStartDate!.year}'
                                                            : 'Select Start Date',
                                                        style: const TextStyle(fontSize: 15),
                                                      ),
                                                      const Icon(Icons.calendar_today, color: Color(0xFF22688E)),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                              // Custom frequency: show multi-select days dropdown
                                              if (selectedFrequency == 'Custom') ...[
                                                const SizedBox(height: 16),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.event, color: Color(0xFF22688E)),
                                                    const SizedBox(width: 8),
                                                    const Text('Select Days', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                GestureDetector(
                                                  behavior: HitTestBehavior.opaque,
                                                  onTap: () async {
                                                    // Only show days that the selected elderly is assigned to the caregiver
                                                    if (selectedElderly == null) {
                                                      showDialog(
                                                        context: ctx,
                                                        builder: (BuildContext context) => AlertDialog(
                                                          title: const Text('Selection Required'),
                                                          content: const Text('Please select an elderly first to see their assigned days.'),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () => Navigator.of(context).pop(),
                                                              child: const Text('OK'),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                      return;
                                                    }
                                                    
                                                    // Get ALL assigned days between this caregiver and selected elderly
                                                    final elderlyAssignedDays = await _getAssignedDaysForElderlyAndCaregiver(caregiverId, selectedElderly!);
                                                    print('🔍 DEBUG: elderlyAssignedDays = $elderlyAssignedDays');
                                                    print('🔍 DEBUG: caregiverId = $caregiverId, selectedElderly = $selectedElderly');
                                                    
                                                    if (elderlyAssignedDays.isEmpty) {
                                                      showDialog(
                                                        context: ctx,
                                                        builder: (BuildContext context) => AlertDialog(
                                                          title: const Text('No Assigned Days'),
                                                          content: const Text('No assigned days found for selected elderly.'),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () => Navigator.of(context).pop(),
                                                              child: const Text('OK'),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                      return;
                                                    }
                                                    
                                                    List<String> tempSelectedDays = List<String>.from(selectedDaysBox);
                                                    // Filter tempSelectedDays to only include days the elderly is assigned to
                                                    tempSelectedDays.retainWhere((day) => elderlyAssignedDays.contains(day));
                                                    
                                                    // Sort assigned days in standard weekday order
                                                    const weekdayOrder = [
                                                      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
                                                    ];
                                                    List<String> sortedAssignedDays = List<String>.from(elderlyAssignedDays);
                                                    sortedAssignedDays.sort((a, b) =>
                                                      weekdayOrder.indexOf(a).compareTo(weekdayOrder.indexOf(b)));
                                                    
                                                    await showDialog(
                                                      context: ctx,
                                                      builder: (BuildContext dialogCtx) {
                                                        return StatefulBuilder(
                                                          builder: (dialogContext, setDialogState) {
                                                            return AlertDialog(
                                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                              title: const Text('Select Custom Days'),
                                                              content: SizedBox(
                                                                width: 250,
                                                                child: Column(
                                                                  mainAxisSize: MainAxisSize.min,
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  children: [
                                                                    Text(
                                                                      'Choose which days this task should appear when you\'re assigned to this elderly:',
                                                                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                                                    ),
                                                                    const SizedBox(height: 16),
                                                                    ...sortedAssignedDays.map((day) {
                                                                      return CheckboxListTile(
                                                                        title: Text(day),
                                                                        value: tempSelectedDays.contains(day),
                                                                        onChanged: (checked) {
                                                                          setDialogState(() {
                                                                            if (checked == true) {
                                                                              tempSelectedDays.add(day);
                                                                            } else {
                                                                              tempSelectedDays.remove(day);
                                                                            }
                                                                          });
                                                                        },
                                                                      );
                                                                    }),
                                                                  ],
                                                                ),
                                                              ),
                                                              actions: [
                                                                TextButton(
                                                                  onPressed: () {
                                                                    Navigator.of(dialogCtx).pop();
                                                                  },
                                                                  child: const Text('Done'),
                                                                ),
                                                              ],
                                                            );
                                                          },
                                                        );
                                                      },
                                                    );
                                                    setState(() {
                                                      selectedDaysBox
                                                        ..clear()
                                                        ..addAll(tempSelectedDays);
                                                    });
                                                  },
                                                  child: Container(
                                                    height: 40,
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFE6F3FA),
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            selectedDaysBox.isEmpty
                                                              ? 'Select Days'
                                                              : selectedDaysBox.map((d) {
                                                                  switch (d) {
                                                                    case 'Monday': return 'Mon';
                                                                    case 'Tuesday': return 'Tue';
                                                                    case 'Wednesday': return 'Wed';
                                                                    case 'Thursday': return 'Thu';
                                                                    case 'Friday': return 'Fri';
                                                                    case 'Saturday': return 'Sat';
                                                                    case 'Sunday': return 'Sun';
                                                                    default: return d;
                                                                  }
                                                                }).join(', '),
                                                            style: const TextStyle(fontSize: 15),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        const Icon(Icons.arrow_drop_down, color: Color(0xFF22688E)),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                // Date picker for Custom frequency start date
                                                const SizedBox(height: 16),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.calendar_today, color: Color(0xFF22688E)),
                                                    const SizedBox(width: 8),
                                                    const Text('Start Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                GestureDetector(
                                                  behavior: HitTestBehavior.opaque,
                                                  onTap: () async {
                                                    if (selectedDaysBox.isEmpty) {
                                                      showDialog(
                                                        context: ctx,
                                                        builder: (BuildContext context) => AlertDialog(
                                                          title: const Text('Selection Required'),
                                                          content: const Text('Please select custom days first.'),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () => Navigator.of(context).pop(),
                                                              child: const Text('OK'),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                      return;
                                                    }

                                                    // Find the first valid date to use as initial date
                                                    DateTime? validInitialDate = selectedRecurringStartDate;
                                                    if (validInitialDate == null) {
                                                      final now = DateTime.now();
                                                      // Look for the next valid date within the next 14 days
                                                      for (int i = 0; i < 14; i++) {
                                                        final testDate = now.add(Duration(days: i));
                                                        final dayOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][testDate.weekday - 1];
                                                        if (selectedDaysBox.contains(dayOfWeek)) {
                                                          validInitialDate = testDate;
                                                          break;
                                                        }
                                                      }
                                                      // Fallback to tomorrow if no valid date found
                                                      validInitialDate ??= now.add(const Duration(days: 1));
                                                    }

                                                    final DateTime? picked = await showDatePicker(
                                                      context: ctx,
                                                      initialDate: validInitialDate,
                                                      firstDate: DateTime.now(),
                                                      lastDate: DateTime.now().add(const Duration(days: 365)),
                                                      selectableDayPredicate: (DateTime date) {
                                                        // Only allow dates that match selected custom days
                                                        final dayOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][date.weekday - 1];
                                                        return selectedDaysBox.contains(dayOfWeek);
                                                      },
                                                    );

                                                    if (picked != null) {
                                                      print('🗓️ USER SELECTED CUSTOM DATE: $picked (weekday: ${picked.weekday})');
                                                      setState(() {
                                                        selectedRecurringStartDate = picked;
                                                      });
                                                    }
                                                  },
                                                  child: Container(
                                                    height: 40,
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFE6F3FA),
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Text(
                                                          selectedRecurringStartDate != null 
                                                              ? '${selectedRecurringStartDate!.day}/${selectedRecurringStartDate!.month}/${selectedRecurringStartDate!.year}'
                                                              : 'Select Start Date',
                                                          style: const TextStyle(fontSize: 15),
                                                        ),
                                                        const Icon(Icons.calendar_today, color: Color(0xFF22688E)),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            if (selectedFrequency == 'Only once') ...[
                                              const SizedBox(height: 16),
                                              Row(
                                                children: [
                                                  const Icon(Icons.event, color: Color(0xFF22688E)),
                                                  const SizedBox(width: 8),
                                                  const Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              GestureDetector(
                                                behavior: HitTestBehavior.opaque,
                                                onTap: () async {
                                                  // Only allow dates matching assigned days of selected elderly
                                                  if (selectedElderly == null) {
                                                    showDialog(
                                                      context: ctx,
                                                      builder: (BuildContext context) => AlertDialog(
                                                        title: const Text('Selection Required'),
                                                        content: const Text('Please select an elderly first to see their assigned days for date selection.'),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () => Navigator.of(context).pop(),
                                                            child: const Text('OK'),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                    return;
                                                  }
                                                  
                                                  // Get comprehensive assignment days for this elderly across all their assignments
                                                  List<String> elderlyAssignedDays = [];
                                                  
                                                  print('DEBUG: Selected elderly ID: $selectedElderly');
                                                  print('DEBUG: Caregiver ID: $caregiverId');
                                                  
                                                  try {
                                                    // Query elderly_assignments collection for all days this elderly is assigned to this caregiver
                                                    final assignmentSnapshot = await FirebaseFirestore.instance
                                                        .collection('elderly_assignments')
                                                        .where('user_id', isEqualTo: caregiverId)
                                                        .where('user_type', isEqualTo: 'caregiver')
                                                        .get();
                                                    
                                                    print('DEBUG: Found ${assignmentSnapshot.docs.length} assignment documents');
                                                    
                                                    // Look through all assignments to find days when this elderly is assigned to this caregiver
                                                    for (var doc in assignmentSnapshot.docs) {
                                                      final assignData = doc.data();
                                                      final elderlyIds = List<String>.from(assignData['elderly_ids'] ?? []);
                                                      final day = assignData['day'] as String?;
                                                      
                                                      // If this elderly is assigned to this caregiver on this day
                                                      if (elderlyIds.contains(selectedElderly) && day != null) {
                                                        elderlyAssignedDays.add(day);
                                                        print('DEBUG: Found assignment: $selectedElderly assigned on $day');
                                                      }
                                                    }
                                                    
                                                    // Remove duplicates and sort
                                                    elderlyAssignedDays = elderlyAssignedDays.toSet().toList();
                                                    elderlyAssignedDays.sort((a, b) {
                                                      const weekdayOrder = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
                                                      return weekdayOrder.indexOf(a).compareTo(weekdayOrder.indexOf(b));
                                                    });
                                                    
                                                    print('DEBUG: Final elderlyAssignedDays = $elderlyAssignedDays');
                                                  } catch (e) {
                                                    print('DEBUG: Error fetching assignment days: $e');
                                                  }
                                                  
                                                  if (elderlyAssignedDays.isEmpty) {
                                                    showDialog(
                                                      context: ctx,
                                                      builder: (BuildContext context) => AlertDialog(
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(16),
                                                        ),
                                                        title: const Row(
                                                          children: [
                                                            Icon(
                                                              Icons.warning_amber_rounded,
                                                              color: Colors.orange,
                                                              size: 28,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Flexible(
                                                              child: Text(
                                                                'No Assigned Days',
                                                                style: TextStyle(
                                                                  color: Colors.orange,
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        content: const Text(
                                                          'You are not currently assigned to this elderly on any days. Please check with your administrator about your schedule assignments.',
                                                          style: TextStyle(fontSize: 16),
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () => Navigator.of(context).pop(),
                                                            style: TextButton.styleFrom(
                                                              backgroundColor: Colors.orange,
                                                              foregroundColor: Colors.white,
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius: BorderRadius.circular(8),
                                                              ),
                                                            ),
                                                            child: const Text('OK'),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                    return;
                                                  }
                                                  
                                                  // Check if temporary assignment and show warning instead of date picker
                                                  if (isTemporaryAssignment) {
                                                    showDialog(
                                                      context: ctx,
                                                      builder: (BuildContext dialogContext) => AlertDialog(
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(16),
                                                        ),
                                                        title: const Row(
                                                          children: [
                                                            Icon(
                                                              Icons.info_outline,
                                                              color: Colors.orange,
                                                              size: 28,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Flexible(
                                                              child: Text(
                                                                'Temporary Assignment',
                                                                style: TextStyle(
                                                                  color: Colors.orange,
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        content: const Text(
                                                          'This elderly is only temporarily assigned for the day and cannot have a different task start date.\n\n'
                                                          'The task date is automatically set to TODAY only.',
                                                          style: TextStyle(fontSize: 16),
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () => Navigator.of(dialogContext).pop(),
                                                            style: TextButton.styleFrom(
                                                              backgroundColor: Colors.orange,
                                                              foregroundColor: Colors.white,
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius: BorderRadius.circular(8),
                                                              ),
                                                            ),
                                                            child: const Text('OK'),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                    return;
                                                  }
                                                  
                                                  final picked = await showDatePicker(
                                                    context: ctx,
                                                    initialDate: selectedDate ?? _getNextValidDate(elderlyAssignedDays),
                                                    firstDate: DateTime.now(), // Don't allow past dates
                                                    lastDate: DateTime.now().add(const Duration(days: 365)), // One year ahead
                                                    selectableDayPredicate: (DateTime date) {
                                                      // For temporary assignments, only allow today
                                                      if (isTemporaryAssignment) {
                                                        final now = DateTime.now();
                                                        return date.year == now.year && 
                                                               date.month == now.month && 
                                                               date.day == now.day;
                                                      }
                                                      // For regular assignments, only allow dates where elderly is assigned to caregiver
                                                      String weekday = [
                                                        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
                                                      ][date.weekday - 1];
                                                      
                                                      return elderlyAssignedDays.contains(weekday);
                                                    },
                                                    helpText: 'Select date for the task to occur:',
                                                    errorInvalidText: 'Select date for the task to occur:',
                                                    builder: (context, child) {
                                                      return Theme(
                                                        data: Theme.of(context).copyWith(
                                                          colorScheme: Theme.of(context).colorScheme.copyWith(
                                                            primary: const Color(0xFF22688E),
                                                          ),
                                                        ),
                                                        child: child!,
                                                      );
                                                    },
                                                  );
                                                  if (picked != null) {
                                                    setState(() {
                                                      selectedDate = picked;
                                                    });
                                                  }
                                                },
                                                child: Container(
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFE6F3FA),
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          selectedDate != null
                                                            ? "${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}"
                                                            : 'Select',
                                                          style: const TextStyle(fontSize: 15),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      const Icon(Icons.arrow_drop_down, color: Color(0xFF22688E)),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                            ],
                                            const SizedBox(height: 20),
                                            Row(
                                              children: [
                                                const Icon(Icons.emoji_people, color: Color(0xFF22688E)),
                                                const SizedBox(width: 8),
                                                const Text('What Activity?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Container(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFE6F3FA),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: TextField(
                                                controller: activityController,
                                                maxLines: 3,
                                                decoration: const InputDecoration(
                                                  hintText: 'Type here',
                                                  hintStyle: TextStyle(fontStyle: FontStyle.italic),
                                                  border: InputBorder.none,
                                                  contentPadding: EdgeInsets.all(8),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 20),
                                            SizedBox(
                                              width: double.infinity,
                                              height: 48,
                                              child: ElevatedButton(
                                                onPressed: () async {
                                                  // Show warning dialog if this is a temporary assignment
                                                  if (isTemporaryAssignment) {
                                                    final confirmTemp = await showDialog<bool>(
                                                      context: ctx,
                                                      builder: (BuildContext context) => AlertDialog(
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(16),
                                                        ),
                                                        title: Row(
                                                          children: const [
                                                            Icon(
                                                              Icons.info_outline,
                                                              color: Colors.orange,
                                                              size: 28,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Flexible(
                                                              child: Text(
                                                                'Temporary Assignment',
                                                                style: TextStyle(
                                                                  color: Colors.orange,
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        content: const Text(
                                                          'This elderly is temporarily assigned to you for today only.\n\n'
                                                          'The task will be created for TODAY and will be set as "Only once" frequency.\n\n'
                                                          'Do you want to continue?',
                                                          style: TextStyle(fontSize: 16),
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () => Navigator.of(context).pop(false),
                                                            style: TextButton.styleFrom(
                                                              foregroundColor: Colors.grey,
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius: BorderRadius.circular(8),
                                                              ),
                                                            ),
                                                            child: const Text('Cancel'),
                                                          ),
                                                          TextButton(
                                                            onPressed: () => Navigator.of(context).pop(true),
                                                            style: TextButton.styleFrom(
                                                              backgroundColor: Colors.orange,
                                                              foregroundColor: Colors.white,
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius: BorderRadius.circular(8),
                                                              ),
                                                            ),
                                                            child: const Text('Continue'),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                    
                                                    if (confirmTemp != true) {
                                                      return; // User cancelled
                                                    }
                                                  }
                                                  
                                                  bool valid = selectedElderly != null && startTime != null && endTime != null && selectedFrequency != null && activityController.text.isNotEmpty;
                                                  DateTime? saveDate;
                                                  List<String> saveFrequency = selectedFrequency != null ? [selectedFrequency!] : [];
                                                  Map<String, dynamic> extraFields = {};
                                                  if (selectedFrequency == 'Only once') {
                                                    valid = valid && selectedDate != null;
                                                    saveDate = selectedDate;
                                                    extraFields['freq_once_date'] = selectedDate;
                                                  } else if (selectedFrequency == 'Custom') {
                                                    valid = valid && selectedDaysBox.isNotEmpty && selectedRecurringStartDate != null;
                                                    saveDate = selectedRecurringStartDate ?? DateTime.now();
                                                    // Keep frequency as 'Custom', not the actual days
                                                    extraFields['custom_days'] = selectedDaysBox;
                                                    extraFields['recurring_start_date'] = selectedRecurringStartDate;
                                                  } else if (selectedFrequency == 'Every Assigned Day') {
                                                    valid = valid && selectedRecurringStartDate != null;
                                                    saveDate = selectedRecurringStartDate ?? DateTime.now();
                                                    // No need to store static assignment days anymore
                                                    extraFields['recurring_start_date'] = selectedRecurringStartDate;
                                                  }
                                                  if (valid) {
                                                    // Additional safety checks - return early if any required field is null
                                                    if (saveDate == null || startTime == null || endTime == null || selectedElderly == null) {
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          const SnackBar(content: Text('Missing required fields'), backgroundColor: Color(0xFFD32F2F)),
                                                        );
                                                      }
                                                      return;
                                                    }
                                                    
                                                    // At this point all required fields are verified non-null, safe to use ! operator
                                                    // TIME VALIDATION: Check if task time has passed for today's date
                                                    bool hasTimePassed = _hasTaskTimePassedToday(saveDate, startTime!);
                                                    
                                                    if (hasTimePassed) {
                                                      // Handle time validation based on frequency type
                                                      if (selectedFrequency == 'Only once') {
                                                        // For "Only once" - show blocking dialog and don't save
                                                        await _showOnlyOnceTimeValidationDialog(context);
                                                        return; // Exit without saving
                                                      } else if (selectedFrequency == 'Every Assigned Day' || selectedFrequency == 'Custom') {
                                                        // For recurring tasks - show confirmation dialog
                                                        bool shouldContinue = await _showRecurringTimeValidationDialog(context);
                                                        if (!shouldContinue) {
                                                          return; // User cancelled, exit without saving
                                                        }
                                                        // User chose to continue, proceed with normal saving
                                                      }
                                                    }
                                                    
                                                    final elderlyData = assignedElderly.firstWhere((e) => e['elderly_id'] == selectedElderly, orElse: () => {});
                                                    final elderlyFname = elderlyData['elderly_fname'] ?? '';
                                                    
                                                    // For recurring tasks, use the selected date for task times
                                                    final selectedDateForTimes = saveDate;
                                                    final taskStart = DateTime(selectedDateForTimes.year, selectedDateForTimes.month, selectedDateForTimes.day, startTime!.hour, startTime!.minute);
                                                    final taskEnd = DateTime(selectedDateForTimes.year, selectedDateForTimes.month, selectedDateForTimes.day, endTime!.hour, endTime!.minute);
                                                    await _saveCareTask(
                                                      elderlyId: selectedElderly!,
                                                      caregiverId: caregiverId,
                                                      elderlyFname: elderlyFname,
                                                      taskStart: taskStart,
                                                      taskEnd: taskEnd,
                                                      taskFrequency: saveFrequency,
                                                      taskDescription: activityController.text,
                                                      taskDate: saveDate,
                                                      extraFields: extraFields,
                                                      caregiverAssignedDays: caregiverAssignedDays,
                                                      customDays: selectedDaysBox,
                                                    );
                                                    // Save reference to ScaffoldMessenger before popping dialog
                                                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                                                    Navigator.of(ctx).pop();
                                                    scaffoldMessenger.showSnackBar(
                                                      const SnackBar(content: Text('Task saved successfully!'), backgroundColor: Color(0xFF22688E)),
                                                    );
                                                  } else {
                                                    String errorMessage = 'Please fill all fields';
                                                    if (selectedFrequency == 'Custom' && selectedRecurringStartDate == null) {
                                                      errorMessage = 'Please select a start date for custom frequency tasks';
                                                    } else if (selectedFrequency == 'Every Assigned Day' && selectedRecurringStartDate == null) {
                                                      errorMessage = 'Please select a start date for recurring tasks';
                                                    }
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(content: Text(errorMessage), backgroundColor: Color(0xFFD32F2F)),
                                                    );
                                                  }
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF22688E),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(32),
                                                  ),
                                                  elevation: 4,
                                                ),
                                                child: const Text(
                                                  'Save Task',
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                          }
                          } catch (e) {
                            // Close loading dialog if still open
                            if (Navigator.canPop(context)) {
                              Navigator.of(context).pop();
                            }
                            // Show error message
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error loading task data: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00588e),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          elevation: 4,
                        ),
                        child: const Text(
                          '+ Add Tasks',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
    );
  }

  Future<String> _getCurrentCaregiverId(BuildContext context) async {
  // Use FirebaseAuth to get the current caregiver's UID
  return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  // Helper function to get ALL assigned days between a caregiver and specific elderly
  Future<List<String>> _getAssignedDaysForElderlyAndCaregiver(String caregiverId, String elderlyId) async {
    return await _getAssignedDaysForElderlyAndCaregiverStatic(caregiverId, elderlyId);
  }

  // Static version for use in TaskService
  static Future<List<String>> _getAssignedDaysForElderlyAndCaregiverStatic(String caregiverId, String elderlyId) async {
    try {
      print('🔍 DEBUG: Getting assigned days for caregiverId=$caregiverId, elderlyId=$elderlyId');
      
      List<String> elderlyAssignedDays = [];
      
      // Query elderly_assignments collection for all days this elderly is assigned to this caregiver
      final assignmentSnapshot = await FirebaseFirestore.instance
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .get();
      
      print('🔍 DEBUG: Found ${assignmentSnapshot.docs.length} assignment documents');
      
      // Look through all assignments to find days when this elderly is assigned to this caregiver
      for (var doc in assignmentSnapshot.docs) {
        final assignData = doc.data();
        final elderlyIds = List<String>.from(assignData['elderly_ids'] ?? []);
        final day = assignData['day'] as String?;
        
        // If this elderly is assigned to this caregiver on this day
        if (elderlyIds.contains(elderlyId) && day != null) {
          elderlyAssignedDays.add(day);
          print('🔍 DEBUG: Found assignment: $elderlyId assigned on $day');
        }
      }
      
      // Remove duplicates and sort
      elderlyAssignedDays = elderlyAssignedDays.toSet().toList();
      elderlyAssignedDays.sort((a, b) {
        const weekdayOrder = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        return weekdayOrder.indexOf(a).compareTo(weekdayOrder.indexOf(b));
      });
      
      print('🔍 DEBUG: Final elderlyAssignedDays = $elderlyAssignedDays');
      return elderlyAssignedDays;
      
    } catch (e) {
      print('Error getting assigned days for elderly and caregiver: $e');
      return [];
    }
  }

  // OPTIMIZATION: Preload all elderly data for all assigned days at once to avoid repeated DB queries
  Future<Map<String, List<Map<String, dynamic>>>> _preloadAllElderlyForAllAssignedDays(String caregiverId, List<String> assignedDays) async {
    try {
      print('🚀 OPTIMIZATION: Preloading elderly data for all assigned days: $assignedDays');
      
      Map<String, List<Map<String, dynamic>>> elderlyByDay = {};
      
      // Initialize empty lists for all days
      for (String day in assignedDays) {
        elderlyByDay[day] = [];
      }
      
      // SIMPLIFIED APPROACH: Use house service to get all elderly for each day
      // This works regardless of whether elderly_assignments exists or not
      final houseService = HouseService();
      
      for (String day in assignedDays) {
        // Use getAssignedElderlyIncludingTemporary to include temporary elderly from absent caregivers
        final elderlyForDay = await houseService.getAssignedElderlyIncludingTemporary(caregiverId, day);
        
        // Convert to the format expected by the UI
        List<Map<String, dynamic>> formattedElderly = [];
        for (var elderly in elderlyForDay) {
          final sex = elderly['elderly_sex'] ?? '';
          final prefix = (sex == 'Male') ? 'Lolo ' : (sex == 'Female') ? 'Lola ' : '';
          
          formattedElderly.add({
            'elderly_id': elderly['elderly_id'],
            'caregiver_id': caregiverId,
            'elderly_fname': prefix + (elderly['elderly_fname'] ?? ''),
            'days_assigned': elderly['days_assigned'] ?? [day], // Use the caregiver's assigned days
            'is_temporary_assignment': elderly['is_temporary_assignment'] ?? false, // ← CRITICAL: Include temporary flag
          });
        }
        
        // Sort elderly by name for consistent ordering
        formattedElderly.sort((a, b) => 
          (a['elderly_fname'] ?? '').toString().toLowerCase()
              .compareTo((b['elderly_fname'] ?? '').toString().toLowerCase())
        );
        
        elderlyByDay[day] = formattedElderly;
        print('🚀 OPTIMIZATION: Day $day has ${formattedElderly.length} elderly');
      }

      return elderlyByDay;
    } catch (e) {
      print('Error in _preloadAllElderlyForAllAssignedDays: $e');
      // Return empty map with initialized lists for all days
      Map<String, List<Map<String, dynamic>>> elderlyByDay = {};
      for (String day in assignedDays) {
        elderlyByDay[day] = [];
      }
      return elderlyByDay;
    }
  }

  Future<void> _saveCareTask({
    required String elderlyId,
    required String caregiverId,
    required String elderlyFname,
    required DateTime taskStart,
    required DateTime taskEnd,
    required List<String> taskFrequency,
    required String taskDescription,
    required DateTime taskDate,
    Map<String, dynamic>? extraFields,
    List<String>? caregiverAssignedDays,
    List<String>? customDays,
  }) async {
    final tasksRef = FirebaseFirestore.instance.collection('care_tasks');
    final docRef = tasksRef.doc();
    DateTime now = DateTime.now();
    DateTime? nextTaskDate;
    
    // 🔧 FIX 4: Use shift-aware task date for overnight shifts
    DateTime actualTaskDate = await TaskService._getTaskShiftDate(caregiverId, taskDate);
    
    // Calculate next task date for recurring tasks
    String frequency = taskFrequency.isNotEmpty ? taskFrequency[0] : 'Only once';
    
    print('=== _saveCareTask DEBUG ===');
    print('frequency: $frequency');
    print('taskStart: $taskStart');
    print('taskDate: $taskDate');
    print('taskDate weekday: ${taskDate.weekday}'); // 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun
    List<String> dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    print('taskDate day name: ${dayNames[taskDate.weekday - 1]}');
    print('extraFields: $extraFields');
    print('extraFields recurring_start_date: ${extraFields?['recurring_start_date']}');
    
    // Smart date calculation: If task time has already passed for today, find next applicable date
    DateTime taskTimeToday = DateTime(now.year, now.month, now.day, taskStart.hour, taskStart.minute);
    bool taskTimeHasPassed = now.isAfter(taskTimeToday);
    
    print('🔍 Checking frequency conditions...');
    print('🔍 frequency == "Only once": ${frequency == 'Only once'}');
    print('🔍 frequency == "Every Assigned Day": ${frequency == 'Every Assigned Day'}');
    print('🔍 frequency.trim() == "Every Assigned Day": ${frequency.trim() == 'Every Assigned Day'}');
    
    if (frequency == 'Only once') {
      print('🎯 ENTERING Only once logic');
      // For "Only once" tasks, check if the selected date is today and time has passed
      if (taskDate.year == now.year && taskDate.month == now.month && taskDate.day == now.day && taskTimeHasPassed) {
        // Time has passed for today, but for "Only once" tasks, we can't move to next day
        // Keep the original date - user specifically selected this date
        print('Only once task for today but time has passed - keeping selected date');
      }
      // nextTaskDate remains null for "Only once" tasks
    } else if (frequency == 'Every Assigned Day') {
      print('🎯 ENTERING Every Assigned Day logic');
      print('🎯 Selected taskDate: $taskDate');
      print('🎯 Current time: $now');
      
      // Check if user provided a recurring_start_date (from date picker)
      DateTime? userSelectedStartDate = extraFields?['recurring_start_date'] as DateTime?;
      print('🎯 User selected start date from date picker: $userSelectedStartDate');
      
      if (userSelectedStartDate != null) {
        // Use the user-selected date directly - no complex validation needed
        print('✅ Using user-selected start date from date picker: $userSelectedStartDate');
        actualTaskDate = DateTime(userSelectedStartDate.year, userSelectedStartDate.month, userSelectedStartDate.day);
        
        // Calculate next occurrence for next_taskdate using correct assigned days logic
        // Get assigned days for this elderly-caregiver pair
        final assignedDays = await TaskService._getAssignedDaysForElderlyAndCaregiverStatic(caregiverId, elderlyId);
        print('🔧 Assigned days for calculating next occurrence: $assignedDays');
        
        // Use _calculateNextOccurrence to find the next assigned day
        nextTaskDate = TaskService._calculateNextOccurrence(
          userSelectedStartDate, 
          userSelectedStartDate, 
          'Every Assigned Day', 
          [], 
          taskStart, 
          assignedDays: assignedDays
        );
        
        print('✅ actualTaskDate set to: $actualTaskDate');
        print('✅ nextTaskDate calculated as: $nextTaskDate (next assigned day after start date)');
        print('🔍 FINAL CHECK - actualTaskDate before saving: $actualTaskDate');
      } else {
        // Fallback to old logic for backward compatibility
        print('⚠️ No recurring_start_date found, using fallback logic');
        
        // Check if user selected date is valid and in the future
        DateTime taskDateOnly = DateTime(taskDate.year, taskDate.month, taskDate.day);
        DateTime todayOnly = DateTime(now.year, now.month, now.day);
        
        DateTime searchFromDate;
        
        if (taskDateOnly.isAfter(todayOnly)) {
          // User selected a future date - check if it's an assigned day
          print('🗓️ User selected future date: $taskDate');
          print('🗓️ taskDateOnly: $taskDateOnly');
          print('🗓️ todayOnly: $todayOnly');
          print('🗓️ taskDateOnly.isAfter(todayOnly): ${taskDateOnly.isAfter(todayOnly)}');
          
          bool isSelectedDateAssigned = await TaskService._isAssignedOnDateShiftAware(elderlyId, caregiverId, taskDate);
          print('🗓️ isSelectedDateAssigned: $isSelectedDateAssigned');
          
          if (isSelectedDateAssigned) {
            print('✅ Selected date is assigned day - using selected date');
            actualTaskDate = DateTime(taskDate.year, taskDate.month, taskDate.day);
            searchFromDate = taskDate.add(Duration(days: 1)); // Search from day after selected date for next occurrence
            print('✅ actualTaskDate set to: $actualTaskDate');
            print('✅ searchFromDate set to: $searchFromDate');
        } else {
          print('❌ Selected date is not assigned day - finding next assigned day');
          searchFromDate = taskDate; // Start search from selected date
          print('❌ searchFromDate set to: $searchFromDate');
        }
      } else if (taskDateOnly.isAtSameMomentAs(todayOnly)) {
        // User selected today - check if time has passed and if it's assigned day
        if (taskTimeHasPassed) {
          print('🗓️ Selected today but time passed - finding next assigned day');
          searchFromDate = now.add(Duration(days: 1));
        } else {
          print('🗓️ Selected today and time not passed - checking if today is assigned');
          bool isTodayAssigned = await TaskService._isAssignedOnDateShiftAware(elderlyId, caregiverId, now);
          if (isTodayAssigned) {
            print('✅ Today is assigned day - using today');
            actualTaskDate = DateTime(now.year, now.month, now.day);
            searchFromDate = now.add(Duration(days: 1));
          } else {
            print('❌ Today is not assigned day - finding next assigned day');
            searchFromDate = now.add(Duration(days: 1));
          }
        }
      } else {
        // User selected past date - find next assigned day from tomorrow
        print('🗓️ Selected past date - finding next assigned day from tomorrow');
        searchFromDate = now.add(Duration(days: 1));
      }
      
      print('🔍 Final searchFromDate: $searchFromDate');
      print('🔍 Current actualTaskDate: $actualTaskDate');
      print('🔍 Original taskDate: $taskDate');
      print('🔍 actualTaskDate == taskDate: ${actualTaskDate == taskDate}');
      
      // If we haven't determined actualTaskDate yet, find the next assigned date
      if (actualTaskDate == taskDate) {
        print('🔍 Need to find next assigned date - Calling _getNextAssignedDate with:');
        print('  elderlyId: $elderlyId');
        print('  caregiverId: $caregiverId');
        print('  taskStart: $taskStart');
        print('  searchFromDate: $searchFromDate');
        
        try {
          DateTime? foundDate = await _getNextAssignedDate(elderlyId, caregiverId, taskStart, searchFromDate);
          print('🔍 _getNextAssignedDate returned: $foundDate');
          
          if (foundDate != null) {
            actualTaskDate = DateTime(foundDate.year, foundDate.month, foundDate.day);
            print('✅ Found next assigned date: $actualTaskDate');
          } else {
            print('❌ No assigned dates found - using fallback');
            actualTaskDate = now.add(Duration(days: 1)); // Fallback to tomorrow
          }
        } catch (e) {
          print('❌ ERROR in _getNextAssignedDate: $e');
          actualTaskDate = now.add(Duration(days: 1)); // Fallback to tomorrow
        }
      }
      
        // Calculate the next occurrence after actualTaskDate for the next_taskdate field
        try {
          nextTaskDate = await _getNextAssignedDate(elderlyId, caregiverId, taskStart, actualTaskDate.add(Duration(days: 1)));
          print('✅ Every Assigned Day task scheduled for: $actualTaskDate');
          print('✅ Next occurrence after that: $nextTaskDate');
        } catch (e) {
          print('❌ ERROR calculating next occurrence: $e');
          nextTaskDate = null;
        }
      }
    } else if (frequency == 'Custom' && customDays != null) {
      print('🎯 ENTERING Custom logic');
      
      // Check if user provided a recurring_start_date (from date picker)
      DateTime? userSelectedStartDate = extraFields?['recurring_start_date'] as DateTime?;
      print('🎯 User selected start date from date picker: $userSelectedStartDate');
      
      if (userSelectedStartDate != null) {
        // Use the user-selected date directly
        print('✅ Using user-selected start date from date picker: $userSelectedStartDate');
        actualTaskDate = DateTime(userSelectedStartDate.year, userSelectedStartDate.month, userSelectedStartDate.day);
        
        // Calculate next occurrence based on custom days AND assignment status
        // Use assignment-aware calculation
        nextTaskDate = await _getNextCustomDate(elderlyId, caregiverId, taskStart, userSelectedStartDate.add(Duration(days: 1)), customDays);
        
        print('✅ actualTaskDate set to: $actualTaskDate');
        print('✅ nextTaskDate calculated as: $nextTaskDate (next custom day when caregiver is assigned)');
      } else {
        // Fallback to old logic for backward compatibility
        print('⚠️ No recurring_start_date found, using fallback logic');
        
        // For custom tasks, if time has passed today, start from tomorrow
        DateTime searchFromDate = taskTimeHasPassed ? now.add(Duration(days: 1)) : now;
        nextTaskDate = await _getNextCustomDate(elderlyId, caregiverId, taskStart, searchFromDate, customDays);
        
        // Check if today matches custom days and time hasn't passed
        String todayWeekday = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"][now.weekday - 1];
        if (!taskTimeHasPassed && customDays.contains(todayWeekday) && await TaskService._isAssignedOnDateShiftAware(elderlyId, caregiverId, now)) {
          actualTaskDate = DateTime(now.year, now.month, now.day);
          nextTaskDate = await _getNextCustomDate(elderlyId, caregiverId, taskStart, now.add(Duration(days: 1)), customDays);
        } else if (nextTaskDate != null) {
          // Use the calculated next occurrence as the actual task date
          actualTaskDate = DateTime(nextTaskDate.year, nextTaskDate.month, nextTaskDate.day);
          nextTaskDate = await _getNextCustomDate(elderlyId, caregiverId, taskStart, nextTaskDate.add(Duration(days: 1)), customDays);
        }
      }
      print('nextTaskDate for Custom: $nextTaskDate');
    } else {
      print('🚨 UNKNOWN FREQUENCY PATH');
      print('🚨 frequency: "$frequency"');
      print('🚨 customDays: $customDays');
      print('🚨 None of the conditions matched!');
    }
    
    print('Final actualTaskDate: $actualTaskDate');
    print('Final nextTaskDate being saved: $nextTaskDate');
    print('🔍 ABOUT TO SAVE TO DATABASE:');
    print('  - task_date will be: $actualTaskDate');
    print('  - task_start will be: $taskStart');
    print('  - task_end will be: $taskEnd');
    
    final data = {
      'task_id': docRef.id,
      'elderly_id': elderlyId,
      'caregiver_id': caregiverId,
      'elderly_fname': elderlyFname,
      'task_start': taskStart,
      'task_end': taskEnd,
      'task_frequency': taskFrequency,
      'task_description': taskDescription,
      'task_date': actualTaskDate,
      'next_taskdate': nextTaskDate,
      'inc_reason': '',
      'created_at': FieldValue.serverTimestamp(),
      'task_status': ['Upcoming'],
      // Store custom days for reference (but don't use for filtering)
      'custom_days': customDays ?? [],
    };
    if (extraFields != null) {
      data.addAll(extraFields.map((key, value) => MapEntry(key, value as Object)));
    }
    await docRef.set(data);

    // Schedule task reminders
    try {
      final taskStartDateTime = DateTime(
        actualTaskDate.year, 
        actualTaskDate.month, 
        actualTaskDate.day, 
        taskStart.hour, 
        taskStart.minute
      );

      // Add default 30-minute task duration if end time not available
      final taskEndDateTime = taskStartDateTime.add(const Duration(minutes: 30));
      
      await TaskReminderService().scheduleTaskReminders(
        taskId: docRef.id,
        taskStartTime: taskStartDateTime,
        taskEndTime: taskEndDateTime,
        taskTitle: taskDescription,
        elderlyName: elderlyFname,
        taskDescription: taskDescription, // Use actual task description, not "Task for [name]"
      );

      print('✅ Task reminders scheduled for: $taskDescription at $taskStartDateTime');
    } catch (e) {
      print('❌ Error scheduling task reminders: $e');
      // Don't fail task creation if reminder scheduling fails
    }

    // Note: Task assignment notifications are now handled by the reminder service
    // when the task is actually due to start, not immediately upon creation
  }

  // Helper function to get next assigned date for recurring tasks
  Future<DateTime?> _getNextAssignedDate(String elderlyId, String caregiverId, DateTime taskStart, DateTime fromDate) async {
    try {
      print('=== _getNextAssignedDate DEBUG START ===');
      print('elderlyId: $elderlyId');
      print('caregiverId: $caregiverId');
      print('taskStart: $taskStart');
      print('fromDate: $fromDate');
      print('DateTime.now(): ${DateTime.now()}');
      print('=== Starting 14-day search ===');
      
      for (int i = 0; i < 14; i++) {
        DateTime candidate = fromDate.add(Duration(days: i));
        
        // Check if caregiver is assigned to elderly on this day
        bool isAssigned = await TaskService._isAssignedOnDateShiftAware(elderlyId, caregiverId, candidate);
        
        // Get day name for debugging
        List<String> dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        String dayName = dayNames[candidate.weekday - 1];
        
        print('Day $i: $candidate ($dayName), assigned: $isAssigned');
        
        if (isAssigned) {
          DateTime candidateStart = DateTime(
            candidate.year, 
            candidate.month, 
            candidate.day, 
            taskStart.hour, 
            taskStart.minute
          );
          
          print('✅ FOUND ASSIGNED DAY: $candidateStart ($dayName)');
          print('✅ RETURNING: $candidateStart');
          return candidateStart;
        }
      }
      print('=== No valid date found in 14 days, returning null ===');
    } catch (e) {
      print('❌ EXCEPTION in _getNextAssignedDate: $e');
      print('❌ Stack trace: ${StackTrace.current}');
    }
    return null;
  }

  // Helper function to get next custom date
  Future<DateTime?> _getNextCustomDate(String elderlyId, String caregiverId, DateTime taskStart, DateTime fromDate, List<String> customDays) async {
    try {
      print('=== _getNextCustomDate DEBUG ===');
      print('taskStart: $taskStart');
      print('fromDate: $fromDate');
      print('customDays: $customDays');
      print('DateTime.now(): ${DateTime.now()}');
      
      for (int i = 0; i < 14; i++) {
        DateTime candidate = fromDate.add(Duration(days: i));
        String weekdayStr = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"][candidate.weekday - 1];
        
        print('Day $i: $candidate ($weekdayStr), in customDays: ${customDays.contains(weekdayStr)}');
        
        // Check if this day is in custom selection AND caregiver is assigned
        if (customDays.contains(weekdayStr)) {
          bool isAssigned = await TaskService._isAssignedOnDateShiftAware(elderlyId, caregiverId, candidate);
          
          print('Day $i is in custom selection, assigned: $isAssigned');
          
          if (isAssigned) {
            DateTime candidateStart = DateTime(
              candidate.year, 
              candidate.month, 
              candidate.day, 
              taskStart.hour, 
              taskStart.minute
            );
            
            print('candidateStart: $candidateStart');
            print('DateTime.now().isBefore(candidateStart): ${DateTime.now().isBefore(candidateStart)}');
            
            // For today (i == 0), only use it if the task time hasn't passed yet
            if (i == 0 && DateTime.now().isBefore(candidateStart)) {
              print('Returning today: $candidateStart');
              return candidateStart;
            } else if (i > 0) {
              // For future days, use the date
              print('Returning future day: $candidateStart');
              return candidateStart;
            }
            // If i == 0 and task time has passed, continue to next day
            print('Today\'s time has passed, continuing to next day...');
          }
        }
      }
      print('No valid custom date found, returning null');
    } catch (e) {
      print('Error calculating next custom date: $e');
    }
    return null;
  }

  // Helper function to get the next valid date for date picker initialization
  DateTime _getNextValidDate(List<String> assignedDays) {
    if (assignedDays.isEmpty) return DateTime.now();
    
    final now = DateTime.now();
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    
    // Find the next date that matches one of the assigned days
    for (int i = 0; i < 14; i++) { // Check next 2 weeks
      final candidate = now.add(Duration(days: i));
      final weekdayName = weekdays[candidate.weekday - 1];
      
      if (assignedDays.contains(weekdayName)) {
        return candidate;
      }
    }
    
    return now; // Fallback
  }



  // Helper function to mark a task as missed (no next occurrence creation)
  Future<void> _markTaskAsMissed(String docId, Map<String, dynamic> data) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final caregiverId = currentUser?.uid;
      
      print('⏰ Marking task as missed: ${data['task_description']}');
      
      // Mark current task as missed and clear any existing next_taskdate
      await FirebaseFirestore.instance
          .collection('care_tasks')
          .doc(docId)
          .update({
        'task_status': ['Missed'],
        'next_taskdate': FieldValue.delete(), // Clear any existing next_taskdate to show original task_date
        if (caregiverId != null) 'created_by': caregiverId,
      });

      // Create task log entry
      if (caregiverId != null) {
        try {
          final taskDate = (data['task_date'] as Timestamp?)?.toDate() ?? DateTime.now();
          await CaregiverShiftLogService.createTaskLog(
            taskId: docId,
            caregiverId: caregiverId,
            elderlyId: data['elderly_id'] ?? '',
            elderlyFname: data['elderly_fname'] ?? 'Unknown',
            taskDescription: data['task_description'] ?? 'Unknown Task',
            status: 'Missed',
            taskDate: taskDate,
          );
        } catch (e) {
          print('❌ Error creating task log for missed task: $e');
        }
      }
      
      // Create Firestore notification for missed task (so it shows in notifications screen)
      if (caregiverId != null) {
        try {
          await NotificationService().createTaskNotification(
            taskId: docId,
            userId: caregiverId,
            userType: 'caregiver',
            elderlyName: data['elderly_fname'] ?? 'Unknown',
            taskDescription: data['task_description'] ?? 'Unknown Task',
            type: NotificationType.taskMissed,
            additionalInfo: 'Task was automatically marked as missed due to time expiration',
          );
          print('✅ Firestore missed task notification created');
        } catch (e) {
          print('❌ Error creating Firestore missed task notification: $e');
        }
      }

      // Send local push notification for missed task
      try {
        final taskStartTime = (data['task_start'] as Timestamp?)?.toDate() ?? DateTime.now();
        await TaskReminderService().showMissedTaskNotification(
          taskId: docId,
          elderlyName: data['elderly_fname'] ?? 'Elderly',
          taskStartTime: taskStartTime,
          taskTitle: data['task_description'] ?? 'Task',
          taskDescription: data['task_description'],
        );
        print('✅ Local push missed task notification sent');
      } catch (notificationError) {
        print('❌ Error sending local push missed task notification: $notificationError');
      }


      
      // For recurring tasks, the Progressive Task System will handle calculating and creating 
      // the next occurrence when the shift ends (same behavior as Complete and Incomplete tasks)
      print('✅ Task marked as missed. Next occurrence will be calculated and created when shift ends.');
      
      print('✅ Task successfully marked as missed');
    } catch (e) {
      print('❌ Error marking task as missed: $e');
    }
  }



  /// Helper function to check if the selected task time has already passed for today
  /// Only validates when the start date is set to today
  bool _hasTaskTimePassedToday(DateTime startDate, TimeOfDay startTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDate = DateTime(startDate.year, startDate.month, startDate.day);
    
    // Only validate if the selected date is today
    if (!selectedDate.isAtSameMomentAs(today)) {
      return false;
    }
    
    // Check if the selected start time has already passed today
    final taskTimeToday = DateTime(now.year, now.month, now.day, startTime.hour, startTime.minute);
    return now.isAfter(taskTimeToday);
  }

  /// Shows blocking validation dialog for "Only Once" frequency
  Future<void> _showOnlyOnceTimeValidationDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFD32F2F),
                size: 28,
              ),
              SizedBox(width: 8),
              Text(
                'Invalid Time',
                style: TextStyle(
                  color: Color(0xFFD32F2F),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            'The time that has been set for the task has already passed today. Please choose another start and end time for the task.',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF22688E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Shows confirmation dialog for "Every Assigned Day" and "Custom" frequencies
  Future<bool> _showRecurringTimeValidationDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Color(0xFFFF9800),
                size: 28,
              ),
              SizedBox(width: 8),
              Text(
                'Time Already Passed',
                style: TextStyle(
                  color: Color(0xFFFF9800),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            'The time that has been set for the task has already passed today. It will be marked as "Missed" and will recur again on the next applicable date. Continue?',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // User cancelled
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[600],
              ),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true); // User wants to continue
              },
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF22688E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    ) ?? false; // Return false if dialog is dismissed
  }

  /// Validates if the caregiver is currently on duty
  /// Returns true if on duty, false otherwise
  Future<bool> _isCaregiverOnDuty() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      final caregiverId = currentUser.uid;
      final now = DateTime.now();

      // Get caregiver's house assignment
      final houseSnapshot = await FirebaseFirestore.instance
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .where('is_current', isEqualTo: true)
          .limit(1)
          .get();

      if (houseSnapshot.docs.isEmpty) {
        return false;
      }

      final houseData = houseSnapshot.docs.first.data();
      final daysAssigned = List<String>.from(houseData['days_assigned'] ?? []);
      
      // Get dates from nested schedule_period object
      final schedulePeriod = houseData['schedule_period'] as Map<String, dynamic>?;
      
      if (schedulePeriod == null) {
        return false;
      }
      
      final startDateTimestamp = schedulePeriod['start_date'] as Timestamp?;
      final endDateTimestamp = schedulePeriod['end_date'] as Timestamp?;
      
      if (startDateTimestamp == null || endDateTimestamp == null) {
        return false;
      }
      
      final startDate = startDateTimestamp.toDate();
      final endDate = endDateTimestamp.toDate();

      // Normalize dates to compare only date parts (ignore time)
      final nowDate = DateTime(now.year, now.month, now.day);
      final normalizedStartDate = DateTime(startDate.year, startDate.month, startDate.day);
      final normalizedEndDate = DateTime(endDate.year, endDate.month, endDate.day);

      // Check if current date is within assignment period
      if (nowDate.isBefore(normalizedStartDate) || nowDate.isAfter(normalizedEndDate)) {
        return false;
      }

      // Check if current time is within shift hours
      final startTime = houseData['start_time'] as String?;
      final endTime = houseData['end_time'] as String?;
      int startHour = 6, startMinute = 0, endHour = 14, endMinute = 0;

      if (startTime != null && endTime != null && startTime.isNotEmpty && endTime.isNotEmpty) {
        final startParts = startTime.split(':');
        final endParts = endTime.split(':');
        startHour = int.parse(startParts[0]);
        startMinute = int.parse(startParts[1]);
        endHour = int.parse(endParts[0]);
        endMinute = int.parse(endParts[1]);
      }

      // Determine if this is an overnight shift
      final isOvernightShift = endHour < startHour || (endHour == startHour && endMinute <= startMinute);

      // For overnight shifts, determine which day to check based on current time
      String dayToCheck;
      if (isOvernightShift && now.hour >= 0 && now.hour < endHour) {
        // Current time is in the "end period" of an overnight shift (e.g., 12:01 AM - 6:00 AM)
        // Check if the previous day is assigned (e.g., if it's Monday 1 AM, check if Sunday is assigned)
        final previousDay = now.subtract(const Duration(days: 1));
        dayToCheck = DateFormat('EEEE').format(previousDay);
      } else {
        // Regular shift or "start period" of overnight shift or after shift ends
        dayToCheck = DateFormat('EEEE').format(now);
      }

      // Check if the determined day is an assigned day
      if (!daysAssigned.contains(dayToCheck)) {
        return false;
      }

      DateTime calculatedShiftStart = DateTime(
        now.year,
        now.month,
        now.day,
        startHour,
        startMinute,
      );
      DateTime calculatedShiftEnd = DateTime(
        now.year,
        now.month,
        now.day,
        endHour,
        endMinute,
      );

      // Handle overnight shifts (e.g., 22:00 - 06:00)
      if (calculatedShiftEnd.isBefore(calculatedShiftStart)) {
        if (now.isBefore(calculatedShiftEnd)) {
          calculatedShiftStart = calculatedShiftStart.subtract(const Duration(days: 1));
        } else {
          calculatedShiftEnd = calculatedShiftEnd.add(const Duration(days: 1));
        }
      }

      final isWithinShift = !(now.isBefore(calculatedShiftStart) || now.isAfter(calculatedShiftEnd));

      return isWithinShift;
    } catch (e) {
      print('Error checking duty status: $e');
      return false;
    }
  }

  /// Shows a dialog informing the user they are not on duty
  void _showNotOnDutyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.access_time_outlined,
                color: Color(0xFFD32F2F),
                size: 28,
              ),
              SizedBox(width: 8),
              Text(
                'Not On Duty',
                style: TextStyle(
                  color: Color(0xFFD32F2F),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            'You are currently not on duty. Cannot update this task\'s status.',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}