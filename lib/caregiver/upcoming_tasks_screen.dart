import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

/*
 * TASK FREQUENCY SYSTEM - Updated Implementation
 * 
 * This system now supports three frequency options that always respect current assignments:
 * 
 * 1. "Only once" - Task appears only on the selected date, only if caregiver is assigned to elderly that day
 * 2. "Every Assigned Day" - Task appears every day the caregiver is currently assigned to the elderly
 * 3. "Custom" - Task appears on selected custom days, only when caregiver is assigned to elderly
 * 
 * Key Features:
 * - All frequency types check current assignments dynamically (no static assignment storage)
 * - Tasks automatically adapt to assignment changes
 * - Tasks never appear when caregiver is not assigned to elderly
 * - Simple, predictable behavior for caregivers
 * 
 * Database Fields:
 * - task_frequency: ['Only once'] | ['Every Assigned Day'] | ['Custom']
 * - custom_days: [] (for Custom frequency only)
 * - freq_once_date: DateTime (for Only once frequency only)
 * 
 * Note: 'everyday_days' field is deprecated but kept for backward compatibility
 */

// Helper function to create a new task and set 'created_by' to the current caregiver's UID
Future<void> createTaskWithCreator(Map<String, dynamic> taskData) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final caregiverId = currentUser?.uid;
  final dataWithCreator = Map<String, dynamic>.from(taskData);
  if (caregiverId != null) {
    dataWithCreator['created_by'] = caregiverId;
  }
  await FirebaseFirestore.instance.collection('care_tasks').add(dataWithCreator);
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
    await _tasksRef.doc(docId).update({'task_status': ['Deleted']});
  }

  /// Updates a task document with the provided data map.
  /// Used for editing task details or other field updates.
  static Future<void> updateTask(String docId, Map<String, dynamic> updateData) async {
    await _tasksRef.doc(docId).update(updateData);
  }

  /// Progressive Task System: Updates recurring tasks to next occurrence when shift ends
  static Future<int> checkAndProgressRecurringTasks(String caregiverId) async {
    try {
      print('=== Progressive Task System: Starting shift end check ===');
      
      // Get caregiver's shift time_range
      final assignSnapshot = await FirebaseFirestore.instance
          .collection('cg_house_assign')
          .where('caregiver_id', isEqualTo: caregiverId)
          .get();
      
      if (assignSnapshot.docs.isEmpty) {
        print('No assignment found for caregiver: $caregiverId');
        return 0;
      }
      
      final assignData = assignSnapshot.docs.first.data();
      final timeRange = assignData['time_range'] as Map<String, dynamic>? ?? {};
      final shiftEndTime = timeRange['end'] ?? '23:59';
      
      // Parse shift end time
      final endTimeParts = shiftEndTime.split(':');
      final endHour = int.parse(endTimeParts[0]);
      final endMinute = int.parse(endTimeParts[1]);
      
      final now = DateTime.now();
      final shiftEndToday = DateTime(now.year, now.month, now.day, endHour, endMinute);
      
      print('Shift ends at: $shiftEndTime ($shiftEndToday)');
      print('Current time: $now');
      print('now.isAfter(shiftEndToday): ${now.isAfter(shiftEndToday)}');
      
      // Check if current time has passed the shift end time
      if (!now.isAfter(shiftEndToday)) {
        print('⏰ Shift has not ended yet, no progression needed (current: ${now.hour}:${now.minute.toString().padLeft(2, '0')}, shift ends: $shiftEndTime)');
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
                    'nextuser_id': '', // Clear any next user assignment
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

    if (frequency == 'Every Assigned Day') {
      // For "Every Assigned Day", find the next occurrence of ANY assigned day
      // If assignedDays are provided, use them; otherwise fall back to original logic for compatibility
      if (assignedDays != null && assignedDays.isNotEmpty) {
        DateTime nextDate = currentTaskDate.add(const Duration(days: 1));
        
        // Look for the next occurrence within the next 14 days
        for (int i = 0; i < 14; i++) {
          final dayOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][nextDate.weekday - 1];
          if (assignedDays.contains(dayOfWeek)) {
            return DateTime(nextDate.year, nextDate.month, nextDate.day, taskStart.hour, taskStart.minute);
          }
          nextDate = nextDate.add(const Duration(days: 1));
        }
      } else {
        // Fallback to original logic (find next occurrence of same weekday)
        final startDayOfWeek = recurringStartDate.weekday; // 1=Monday, 7=Sunday
        DateTime nextDate = currentTaskDate.add(const Duration(days: 1));
        
        // Find the next occurrence of the same weekday
        while (nextDate.weekday != startDayOfWeek) {
          nextDate = nextDate.add(const Duration(days: 1));
        }
        
        return DateTime(nextDate.year, nextDate.month, nextDate.day, taskStart.hour, taskStart.minute);
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
      
      // First, check if there's a relationship between caregiver and elderly
      final elderlyAssignSnapshot = await FirebaseFirestore.instance
          .collection('elderly_caregiver_assign')
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('elderly_id', isEqualTo: elderlyId)
          .get();

      print('🔍 DEBUG: Found ${elderlyAssignSnapshot.docs.length} assignment documents');

      if (elderlyAssignSnapshot.docs.isEmpty) {
        print('🔍 DEBUG: No assignments found for this elderly-caregiver pair');
        return [];
      }

      // Extract all unique days from the assignment documents
      Set<String> assignedDaysSet = {};
      for (var doc in elderlyAssignSnapshot.docs) {
        final data = doc.data();
        final day = data['day'] as String?;
        if (day != null && day.isNotEmpty) {
          assignedDaysSet.add(day);
        }
      }

      List<String> assignedDays = assignedDaysSet.toList();
      print('🔍 DEBUG: Assigned days: $assignedDays');
      
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
        bool isAssigned = await _isAssignedOnDate(elderlyId, caregiverId, candidate);
        
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
          bool isAssigned = await _isAssignedOnDate(elderlyId, caregiverId, candidate);
          
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

  // Helper method to check if caregiver is assigned to elderly on a specific date
  static Future<bool> _isAssignedOnDate(String elderlyId, String caregiverId, DateTime date) async {
    try {
      String weekdayStr = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"][date.weekday - 1];
      
      final assignSnapshot = await FirebaseFirestore.instance
          .collection('elderly_caregiver_assign')
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('elderly_id', isEqualTo: elderlyId)
          .get();
      
      if (assignSnapshot.docs.isEmpty) return false;
      
      for (var doc in assignSnapshot.docs) {
        final data = doc.data();
        
        // Check individual 'day' field first (your data structure)
        final individualDay = data['day'] as String?;
        if (individualDay == weekdayStr) {
          return true;
        }
        
        // Fallback to 'days_assigned' array
        final daysAssigned = List<String>.from(data['days_assigned'] ?? []);
        if (daysAssigned.contains(weekdayStr)) {
          return true;
        }
      }
      
      return false;
    } catch (e) {
      print('Error checking assignment on date: $e');
      return false;
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
    
    // For recurring tasks, store the next_taskdate but don't create new task yet
    // The Progressive Task System will handle creating the next occurrence when shift ends
    if (newNextTaskDate != null) {
      await _tasksRef.doc(docId).update({
        'next_taskdate': newNextTaskDate,
      });
      print('✅ Task marked complete. Next occurrence ($newNextTaskDate) will be created when shift ends.');
      print('🔍 DEBUG: Task Complete - updated next_taskdate to: $newNextTaskDate');
    } else {
      print('🔍 DEBUG: Task Complete - no next occurrence (likely "Only once" task)');
    }
  }

  /// Marks a task as incomplete and records the reason for incompletion.
  /// Updates 'inc_reason' and sets 'task_status' to ['Incomplete'].
  static Future<void> markTaskIncomplete(String docId, String reasonText) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final caregiverId = currentUser?.uid;
    await _tasksRef.doc(docId).update({
      'inc_reason': reasonText,
      'task_status': ['Incomplete'],
      if (caregiverId != null) 'created_by': caregiverId,
    });
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
    
    // For recurring tasks, store the next_taskdate but don't create new task yet
    // The Progressive Task System will handle creating the next occurrence when shift ends
    if (newNextTaskDate != null) {
      await _tasksRef.doc(docId).update({
        'next_taskdate': newNextTaskDate,
      });
      print('✅ Task marked incomplete. Next occurrence ($newNextTaskDate) will be created when shift ends.');
      print('🔍 DEBUG: Task Incomplete - updated next_taskdate to: $newNextTaskDate');
    } else {
      print('🔍 DEBUG: Task Incomplete - no next occurrence (likely "Only once" task)');
    }
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
  String? selectedFrequency;
  DateTime? selectedDate;
  List<String> selectedDaysBox = [];
  DateTime? selectedRecurringStartDate;
  List<String> everydayDays = [];

  @override
  void initState() {
    super.initState();
    activityController = TextEditingController(text: widget.task['task_description'] ?? '');
    startTime = widget.task['task_start'] != null ? TimeOfDay.fromDateTime(widget.task['task_start']) : null;
    endTime = widget.task['task_end'] != null ? TimeOfDay.fromDateTime(widget.task['task_end']) : null;
    selectedFrequency = (widget.task['task_frequency'] is List && widget.task['task_frequency'].isNotEmpty) ? widget.task['task_frequency'][0] : 'Only once';
    selectedDate = widget.task['freq_once_date'] is DateTime ? widget.task['freq_once_date'] : null;
    selectedDaysBox = List<String>.from(widget.task['custom_days'] ?? []);
    everydayDays = List<String>.from(widget.task['everyday_days'] ?? []);
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
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.date_range, color: Color(0xFF22688E)),
                  const SizedBox(width: 8),
                  const Text('Frequency', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: selectedFrequency,
                isExpanded: true,
                items: ['Only once', 'Every Assigned Day', 'Custom'].map((freq) {
                  return DropdownMenuItem<String>(
                    value: freq,
                    child: Text(freq),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedFrequency = value;
                  });
                },
              ),
              if (selectedFrequency == 'Custom') ...[
                const SizedBox(height: 8),
                Text('Selected Days: ${selectedDaysBox.join(", ")}', style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () async {
                    const allDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
                    List<String> tempSelectedDays = List<String>.from(selectedDaysBox);
                    await showDialog(
                      context: context,
                      builder: (BuildContext daysCtx) {
                        return AlertDialog(
                          title: const Text('Select Days'),
                          content: SizedBox(
                            width: double.maxFinite,
                            child: ListView(
                              shrinkWrap: true,
                              children: allDays.map((day) {
                                return CheckboxListTile(
                                  title: Text(day),
                                  value: tempSelectedDays.contains(day),
                                  onChanged: (checked) {
                                    if (checked == true) {
                                      tempSelectedDays.add(day);
                                    } else {
                                      tempSelectedDays.remove(day);
                                    }
                                    (daysCtx as Element).markNeedsBuild();
                                  },
                                );
                              }).toList(),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(daysCtx).pop();
                              },
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  selectedDaysBox = List<String>.from(tempSelectedDays);
                                });
                                Navigator.of(daysCtx).pop();
                              },
                              child: const Text('OK'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Color(0xFFE6F3FA),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Pick Days', style: TextStyle(color: Color(0xFF000000))),
                ),
              ],
              if (selectedFrequency == 'Only once') ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
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
                      color: Color(0xFFE6F3FA),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(selectedDate != null ? formatDate(selectedDate!) : 'Select Date', style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  final docId = widget.task['task_id'];
                  final tasksRef = FirebaseFirestore.instance.collection('care_tasks');
                  final updateData = {
                    'task_description': activityController.text,
                    'task_start': startTime != null ? DateTime(selectedDate?.year ?? DateTime.now().year, selectedDate?.month ?? DateTime.now().month, selectedDate?.day ?? DateTime.now().day, startTime!.hour, startTime!.minute) : widget.task['task_start'],
                    'task_end': endTime != null ? DateTime(selectedDate?.year ?? DateTime.now().year, selectedDate?.month ?? DateTime.now().month, selectedDate?.day ?? DateTime.now().day, endTime!.hour, endTime!.minute) : widget.task['task_end'],
                    'task_frequency': [selectedFrequency ?? 'Only once'],
                    'freq_once_date': selectedFrequency == 'Only once' ? selectedDate : null,
                    'custom_days': selectedFrequency == 'Custom' ? selectedDaysBox : [],
                    'everyday_days': selectedFrequency == 'Every Assigned Day' ? [] : [], // No longer storing static assignment days
                  };
                  await tasksRef.doc(docId).update(updateData);
                  Navigator.of(context).pop();
                  Navigator.of(widget.parentContext).pop();
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
                    '${task['task_start'] != null ? UpcomingTasksScreen._formatTime(task['task_start']) : ''} - ${task['task_end'] != null ? UpcomingTasksScreen._formatTime(task['task_end']) : ''}',
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
                          return 'Every day assigned to this elderly';
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
class UpcomingTasksScreen extends StatelessWidget {
  // Progressive task system check - called when screen loads
  void _checkProgressiveTaskSystem(BuildContext context) async {
    try {
      print('🔄 _checkProgressiveTaskSystem called at ${DateTime.now()}');
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        print('👤 Current user found: ${currentUser.uid}');
        // Call the progressive task system in background (non-blocking)
        TaskService.checkAndProgressRecurringTasks(currentUser.uid).then((progressedTasks) {
          print('📊 Progressive system returned: $progressedTasks tasks progressed');
          if (progressedTasks > 0) {
            print('✅ Progressive Task System: $progressedTasks recurring tasks updated to next occurrence dates');
            // Show a brief notification that tasks were updated
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$progressedTasks recurring tasks updated to next occurrence dates'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
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

  // COMMENTED OUT: COMPREHENSIVE TASK DIAGNOSTICS TOOL (kept for future debugging)
  /*
  void _runTaskDiagnostics(BuildContext context) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      print('❌ No current user found');
      return;
    }

    final caregiverId = currentUser.uid;
    print('\n🔍 === COMPREHENSIVE TASK DIAGNOSTICS ===');
    print('👤 Caregiver ID: $caregiverId');
    print('📅 Current Date/Time: ${DateTime.now()}');

    try {
      // 1. Get ALL tasks in the database to understand the structure
      print('\n📊 1. ANALYZING ALL TASKS IN DATABASE...');
      final allTasksSnapshot = await FirebaseFirestore.instance.collection('care_tasks').get();
      print('   Total tasks in database: ${allTasksSnapshot.docs.length}');

      // Analyze task structure from first few tasks
      if (allTasksSnapshot.docs.isNotEmpty) {
        print('\n🔬 2. TASK STRUCTURE ANALYSIS (first 3 tasks):');
        for (int i = 0; i < 3 && i < allTasksSnapshot.docs.length; i++) {
          final taskData = allTasksSnapshot.docs[i].data();
          print('   Task ${i + 1} fields: ${taskData.keys.toList()}');
          if (taskData.containsKey('task_description')) {
            print('   - Description: ${taskData['task_description']}');
          }
          if (taskData.containsKey('caregiver_id')) {
            print('   - caregiver_id: ${taskData['caregiver_id']}');
          }
          if (taskData.containsKey('created_by')) {
            print('   - created_by: ${taskData['created_by']}');
          }
          if (taskData.containsKey('assigned_to')) {
            print('   - assigned_to: ${taskData['assigned_to']}');
          }
          if (taskData.containsKey('task_status')) {
            print('   - task_status: ${taskData['task_status']}');
          }
          if (taskData.containsKey('task_frequency')) {
            print('   - task_frequency: ${taskData['task_frequency']}');
          }
          print('   ---');
        }
      }

      // 3. Test different query strategies
      print('\n🎯 3. TESTING DIFFERENT QUERY STRATEGIES...');
      
      // Strategy 1: caregiver_id
      final strategy1 = await FirebaseFirestore.instance.collection('care_tasks')
          .where('caregiver_id', isEqualTo: caregiverId).get();
      print('   Strategy 1 (caregiver_id = $caregiverId): ${strategy1.docs.length} tasks');

      // Strategy 2: created_by
      final strategy2 = await FirebaseFirestore.instance.collection('care_tasks')
          .where('created_by', isEqualTo: caregiverId).get();
      print('   Strategy 2 (created_by = $caregiverId): ${strategy2.docs.length} tasks');

      // Strategy 3: Look for tasks containing Testing
      final strategy3 = await FirebaseFirestore.instance.collection('care_tasks').get();
      final testingTasks = strategy3.docs.where((doc) {
        final data = doc.data();
        final description = data['task_description']?.toString() ?? '';
        return description.toLowerCase().contains('testing');
      }).toList();
      print('   Strategy 3 (tasks containing "testing"): ${testingTasks.length} tasks');

      // 4. Analyze the Testing tasks specifically
      if (testingTasks.isNotEmpty) {
        print('\n🧪 4. ANALYZING "TESTING" TASKS:');
        for (var testTask in testingTasks) {
          final data = testTask.data();
          print('   📝 Task: ${data['task_description']}');
          print('      - ID: ${testTask.id}');
          print('      - caregiver_id: ${data['caregiver_id']}');
          print('      - created_by: ${data['created_by']}');
          print('      - task_status: ${data['task_status']}');
          print('      - task_frequency: ${data['task_frequency']}');
          print('      - task_date: ${data['task_date']}');
          print('      - next_taskdate: ${data['next_taskdate']}');
          print('      - All fields: ${data.keys.toList()}');
          print('   ---');
        }

        // 5. Test manual progression on Testing tasks
        print('\n⚡ 5. TESTING MANUAL PROGRESSION ON TESTING TASKS...');
        for (var testTask in testingTasks) {
          final data = testTask.data();
          final frequency = (data['task_frequency'] as List<dynamic>?)?.first ?? 'Only once';
          
          if (frequency == 'Every Assigned Day' || frequency == 'Custom') {
            print('   🔄 Attempting to progress: ${data['task_description']}');
            
            final taskDate = (data['task_date'] as Timestamp?)?.toDate();
            final nextTaskDate = (data['next_taskdate'] as Timestamp?)?.toDate();
            
            if (taskDate != null && nextTaskDate != null) {
              // Force update this task
              await FirebaseFirestore.instance.collection('care_tasks').doc(testTask.id).update({
                'task_date': nextTaskDate,
                'next_taskdate': Timestamp.fromDate(nextTaskDate.add(Duration(days: 1))), // Simple +1 day for testing
                'updated_at': FieldValue.serverTimestamp(),
                'diagnostic_update': 'Updated by diagnostic tool at ${DateTime.now()}',
              });
              print('   ✅ Successfully updated task dates!');
            } else {
              print('   ❌ Missing task_date or next_taskdate');
            }
          } else {
            print('   ⏭️ Skipping non-recurring task');
          }
        }
      }

      print('\n🎉 DIAGNOSTICS COMPLETE - Check console output above!');
      
      // Show summary in UI
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Diagnostics complete! Check console for detailed analysis.'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 5),
        ),
      );

    } catch (e) {
      print('❌ Error in diagnostics: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Diagnostics error: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }
  */

  // COMMENTED OUT: FORCE TASK PROGRESSION - Bypasses all time checks (kept for future debugging)
  /*
  void _forceTaskProgression(BuildContext context) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      print('\n🚀 === FORCING TASK PROGRESSION ===');
      
      // Get all tasks with "Testing" in description
      final allTasks = await FirebaseFirestore.instance.collection('care_tasks').get();
      final testingTasks = allTasks.docs.where((doc) {
        final data = doc.data();
        final description = data['task_description']?.toString().toLowerCase() ?? '';
        return description.contains('testing');
      }).toList();

      print('Found ${testingTasks.length} testing tasks to force progress');

      int progressedCount = 0;
      for (var taskDoc in testingTasks) {
        final data = taskDoc.data();
        final description = data['task_description'] ?? 'Unknown';
        final frequency = (data['task_frequency'] as List<dynamic>?)?.first ?? 'Only once';
        
        if (frequency == 'Every Assigned Day' || frequency == 'Custom') {
          print('🔄 Force progressing: $description');
          
          final taskDate = (data['task_date'] as Timestamp?)?.toDate();
          if (taskDate != null) {
            // Calculate next occurrence (simple: add 1 day for testing)
            final nextOccurrence = taskDate.add(Duration(days: 1));
            final futureOccurrence = nextOccurrence.add(Duration(days: 1));
            
            await FirebaseFirestore.instance.collection('care_tasks').doc(taskDoc.id).update({
              'task_date': Timestamp.fromDate(nextOccurrence),
              'next_taskdate': Timestamp.fromDate(futureOccurrence),
              'task_status': ['Upcoming'],
              'updated_at': FieldValue.serverTimestamp(),
              'force_progressed': 'Force progressed at ${DateTime.now()}',
            });
            
            progressedCount++;
            print('✅ Successfully force progressed $description');
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Force progressed $progressedCount tasks! Check Upcoming tab.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 5),
        ),
      );

    } catch (e) {
      print('❌ Error in force progression: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Force progression error: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
  */

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
  static String formatHeaderDate(String key) {
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
  
  final DateTime? selectedFilterDate;
  
  const UpcomingTasksScreen({super.key, this.selectedFilterDate});

  Stream<List<Map<String, dynamic>>> getTasksStream() {
    final user = FirebaseAuth.instance.currentUser;
    final caregiverId = user?.uid;
    return FirebaseFirestore.instance
      .collection('care_tasks')
      .where('task_status', arrayContains: 'Upcoming')
      .where('caregiver_id', isEqualTo: caregiverId)
      .snapshots()
      .asyncMap((snapshot) async {
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
            final taskEndDateTime = DateTime(
              actualTaskDate.year,
              actualTaskDate.month,
              actualTaskDate.day,
              taskEnd.hour,
              taskEnd.minute,
            );
            
            if (now.isAfter(taskEndDateTime)) {
              // Mark task as missed and handle recurring task logic
              print('⏰ MISSED TASK DETECTED: ${data['task_description']} - end time $taskEndDateTime has passed');
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
            'created_at': (data['created_at'] is Timestamp) ? (data['created_at'] as Timestamp).toDate() : data['created_at'],
            'task_frequency': data['task_frequency'] ?? [],
            'custom_days': data['custom_days'] ?? [],
            'everyday_days': data['everyday_days'] ?? [],
            'freq_once_date': (data['freq_once_date'] is Timestamp) ? (data['freq_once_date'] as Timestamp).toDate() : data['freq_once_date'],
            'next_taskdate': (data['next_taskdate'] is Timestamp) ? (data['next_taskdate'] as Timestamp).toDate() : data['next_taskdate'],
            'profile_pic': profilePicUrl,
          });
        }
        
        // Note: Removing date filtering to allow tasks to be grouped by their actual occurrence dates
        // If date filtering is needed, it should be handled differently to not conflict with grouping
        // DateTime? filterDate;
        // if (selectedFilterDate != null) {
        //   filterDate = DateTime(selectedFilterDate!.year, selectedFilterDate!.month, selectedFilterDate!.day);
        //   tasks = await _filterTasksByAssignment(tasks, filterDate);
        // }
        
        return tasks;
      });
  }

  Future<void> _onRefresh() async {
    // Trigger progressive task system when user pulls to refresh
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await TaskService.checkAndProgressRecurringTasks(currentUser.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Trigger progressive task system check once when screen loads (includes shift time validation)
    _checkProgressiveTaskSystem(context);
    
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: StreamBuilder<List<Map<String, dynamic>>>(
      stream: getTasksStream(),
      builder: (context, snapshot) {
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
        // Sort dates closest to today first
        final now = DateTime.now();
        final sortedKeys = grouped.keys.toList()
          ..sort((a, b) {
            final ad = DateTime.parse(a.replaceAll('-', ''));
            final bd = DateTime.parse(b.replaceAll('-', ''));
            return (ad.difference(now).inDays).abs().compareTo((bd.difference(now).inDays).abs());
          });
        return SizedBox.expand(
          child: Column(
            children: [
              // COMMENTED OUT: Diagnostic and Force Progress buttons (kept for future debugging if needed)
              // if (true) // Set to true if you need diagnostic tools again
              // Container(
              //   margin: EdgeInsets.all(8),
              //   child: Row(
              //     children: [
              //       Expanded(
              //         child: ElevatedButton(
              //           style: ElevatedButton.styleFrom(
              //             backgroundColor: Colors.orange,
              //             foregroundColor: Colors.white,
              //           ),
              //           onPressed: () => _runTaskDiagnostics(context),
              //           child: Text('🔍 Diagnostics'),
              //         ),
              //       ),
              //       SizedBox(width: 8),
              //       Expanded(
              //         child: ElevatedButton(
              //           style: ElevatedButton.styleFrom(
              //             backgroundColor: Colors.red,
              //             foregroundColor: Colors.white,
              //           ),
              //           onPressed: () => _forceTaskProgression(context),
              //           child: Text('🚀 Force Progress'),
              //         ),
              //       ),
              //     ],
              //   ),
              // ),
              // Only one set of Add/Delete Task buttons at the top
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
                                    UpcomingTasksScreen.formatHeaderDate(key),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF22688E)),
                                  ),
                                ),
                                for (final task in (grouped[key]!..sort((a, b) {
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
                                                                      title: const Text('Delete Task'),
                                                                      content: const Text('Are you sure you want to delete this task?'),
                                                                      actions: [
                                                                        TextButton(
                                                                          onPressed: () => Navigator.of(confirmCtx).pop(false),
                                                                          child: const Text('Cancel'),
                                                                        ),
                                                                        ElevatedButton(
                                                                          style: ElevatedButton.styleFrom(
                                                                            backgroundColor: Color(0xFFB71C1C),
                                                                          ),
                                                                          onPressed: () => Navigator.of(confirmCtx).pop(true),
                                                                          child: const Text('Delete', style: TextStyle(color: Colors.white)),
                                                                        ),
                                                                      ],
                                                                    );
                                                                  },
                                                                );
                                                                if (confirm == true) {
                                                                  // Soft delete: update 'task_status' to ['Deleted']
                                                                  final docId = task['task_id'];
                                                                  await TaskService.deleteTask(docId);
                                                                  Navigator.of(ctx).pop();
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
                                                          '${task['task_start'] != null ? UpcomingTasksScreen._formatTime(task['task_start']) : ''} - ${task['task_end'] != null ? UpcomingTasksScreen._formatTime(task['task_end']) : ''}',
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
                                                              return '${_formatDate(created)} at ${UpcomingTasksScreen._formatTime(created)}';
                                                            } else if (created is Timestamp) {
                                                              final dt = created.toDate();
                                                              return '${_formatDate(dt)} at ${UpcomingTasksScreen._formatTime(dt)}';
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
                                                                    bool confirmChecked = false;
                                                                    await showDialog(
                                                                      context: ctx,
                                                                      builder: (BuildContext confirmCtx) {
                                                                        return StatefulBuilder(
                                                                          builder: (context, setState) {
                                                                            return AlertDialog(
                                                                              title: const Text('Confirm Completion'),
                                                                              content: Column(
                                                                                mainAxisSize: MainAxisSize.min,
                                                                                children: [
                                                                                  const Text('Please confirm that you have completed this task.'),
                                                                                  CheckboxListTile(
                                                                                    value: confirmChecked,
                                                                                    onChanged: (checked) {
                                                                                      setState(() {
                                                                                        confirmChecked = checked ?? false;
                                                                                      });
                                                                                    },
                                                                                    title: const Text('I hereby confirm that the task is completed'),
                                                                                  ),
                                                                                ],
                                                                              ),
                                                                              actions: [
                                                                                TextButton(
                                                                                  onPressed: () => Navigator.of(confirmCtx).pop(),
                                                                                  child: const Text('Cancel'),
                                                                                ),
                                                                                ElevatedButton(
                                                                                  onPressed: confirmChecked
                                                                                      ? () async {
                                                                                          final docId = task['task_id'];
                                                                                          // Get current next_taskdate and frequency info
                                                                                          final docSnap = await TaskService._tasksRef.doc(docId).get();
                                                                                          final data = docSnap.data();
                                                                                          DateTime? prevNextTaskDate;
                                                                                          if (data != null && data['next_taskdate'] != null) {
                                                                                            prevNextTaskDate = (data['next_taskdate'] is Timestamp)
                                                                                              ? (data['next_taskdate'] as Timestamp).toDate()
                                                                                              : data['next_taskdate'] as DateTime;
                                                                                          }
                                                                                          // Calculate new next_taskdate for recurring tasks
                                                                                          List<String> customDays = List<String>.from(data?['custom_days'] ?? []);
                                                                                          List<String> taskFrequency = List<String>.from(data?['task_frequency'] ?? []);
                                                                                          DateTime now = DateTime.now();
                                                                                          DateTime? newNextTaskDate;
                                                                                          DateTime taskStart = (data?['task_start'] is Timestamp)
                                                                                            ? (data?['task_start'] as Timestamp).toDate()
                                                                                            : data?['task_start'] as DateTime;
                                                                                          
                                                                                          String elderlyId = data?['elderly_id'] ?? '';
                                                                                          String caregiverId = data?['caregiver_id'] ?? '';
                                                                                          String frequency = taskFrequency.isNotEmpty ? taskFrequency[0] : 'Only once';
                                                                                          
                                                                                          // Calculate next occurrence using new date picker logic
                                                                                          final recurringStartDate = (data?['recurring_start_date'] as Timestamp?)?.toDate();
                                                                                          final currentTaskDate = (data?['task_date'] as Timestamp?)?.toDate();
                                                                                          
                                                                                          if (recurringStartDate != null && currentTaskDate != null) {
                                                                                            // Use new calculation method
                                                                                            if (frequency == 'Every Assigned Day') {
                                                                                              // Get assigned days for Every Assigned Day frequency
                                                                                              final assignedDays = await TaskService._getAssignedDaysForElderlyAndCaregiverStatic(caregiverId, elderlyId);
                                                                                              newNextTaskDate = TaskService._calculateNextOccurrence(currentTaskDate, recurringStartDate, frequency, customDays, taskStart, assignedDays: assignedDays);
                                                                                            } else {
                                                                                              newNextTaskDate = TaskService._calculateNextOccurrence(currentTaskDate, recurringStartDate, frequency, customDays, taskStart);
                                                                                            }
                                                                                          } else {
                                                                                            // Fallback to old method for tasks without recurring_start_date
                                                                                            if (frequency == 'Every Assigned Day') {
                                                                                              newNextTaskDate = await _getNextAssignedDate(elderlyId, caregiverId, taskStart, prevNextTaskDate ?? now);
                                                                                            } else if (frequency == 'Custom' && customDays.isNotEmpty) {
                                                                                              newNextTaskDate = await _getNextCustomDate(elderlyId, caregiverId, taskStart, prevNextTaskDate ?? now, customDays);
                                                                                            }
                                                                                          }
                                                                                          // For 'Only once', newNextTaskDate remains null
                                                                                          await TaskService.markTaskComplete(docId, newNextTaskDate);
                                                                                          Navigator.of(confirmCtx).pop();
                                                                                          Navigator.of(ctx).pop();
                                                                                        }
                                                                                      : null,
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
                                                                  onPressed: () {
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
                                                                    final reasonText = reasonController.text.trim();
                                                                    if (reasonText.isNotEmpty) {
                                                                      final docId = task['task_id'];
                                                                      
                                                                      // Get current task data for recurring task calculation
                                                                      final docSnap = await TaskService._tasksRef.doc(docId).get();
                                                                      final data = docSnap.data();
                                                                      DateTime? prevNextTaskDate;
                                                                      if (data != null && data['next_taskdate'] != null) {
                                                                        prevNextTaskDate = (data['next_taskdate'] is Timestamp)
                                                                          ? (data['next_taskdate'] as Timestamp).toDate()
                                                                          : data['next_taskdate'] as DateTime;
                                                                      }
                                                                      
                                                                      // Calculate new next_taskdate for recurring tasks
                                                                      List<String> customDays = List<String>.from(data?['custom_days'] ?? []);
                                                                      List<String> taskFrequency = List<String>.from(data?['task_frequency'] ?? []);
                                                                      DateTime now = DateTime.now();
                                                                      DateTime? newNextTaskDate;
                                                                      DateTime taskStart = (data?['task_start'] is Timestamp)
                                                                        ? (data?['task_start'] as Timestamp).toDate()
                                                                        : data?['task_start'] as DateTime;
                                                                      
                                                                      String elderlyId = data?['elderly_id'] ?? '';
                                                                      String caregiverId = data?['caregiver_id'] ?? '';
                                                                      String frequency = taskFrequency.isNotEmpty ? taskFrequency[0] : 'Only once';
                                                                      
                                                                      // Calculate next occurrence using new date picker logic
                                                                      final recurringStartDate = (data?['recurring_start_date'] as Timestamp?)?.toDate();
                                                                      final currentTaskDate = (data?['task_date'] as Timestamp?)?.toDate();
                                                                      
                                                                      if (recurringStartDate != null && currentTaskDate != null) {
                                                                        // Use new calculation method
                                                                        if (frequency == 'Every Assigned Day') {
                                                                          // Get assigned days for Every Assigned Day frequency
                                                                          final assignedDays = await TaskService._getAssignedDaysForElderlyAndCaregiverStatic(caregiverId, elderlyId);
                                                                          newNextTaskDate = TaskService._calculateNextOccurrence(currentTaskDate, recurringStartDate, frequency, customDays, taskStart, assignedDays: assignedDays);
                                                                        } else {
                                                                          newNextTaskDate = TaskService._calculateNextOccurrence(currentTaskDate, recurringStartDate, frequency, customDays, taskStart);
                                                                        }
                                                                      } else {
                                                                        // Fallback to old method for tasks without recurring_start_date
                                                                        if (frequency == 'Every Assigned Day') {
                                                                          newNextTaskDate = await _getNextAssignedDate(elderlyId, caregiverId, taskStart, prevNextTaskDate ?? now);
                                                                        } else if (frequency == 'Custom' && customDays.isNotEmpty) {
                                                                          newNextTaskDate = await _getNextCustomDate(elderlyId, caregiverId, taskStart, prevNextTaskDate ?? now, customDays);
                                                                        }
                                                                      }
                                                                      
                                                                      // Mark as incomplete and potentially create next occurrence
                                                                      await TaskService.markTaskIncompleteWithNextOccurrence(docId, reasonText, newNextTaskDate);
                                                                      Navigator.of(ctx).pop();
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
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF00588e),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
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
                                                    errorWidget: (context, url, error) => Container(
                                                      width: 56,
                                                      height: 56,
                                                      decoration: const BoxDecoration(
                                                        color: Colors.white,
                                                      ),
                                                      child: ClipRRect(
                                                        borderRadius: BorderRadius.circular(12),
                                                        child: Image.asset(
                                                          'assets/images/people_icon.png',
                                                          fit: BoxFit.cover,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                : Container(
                                                    width: 56,
                                                    height: 56,
                                                    decoration: const BoxDecoration(
                                                      color: Colors.white,
                                                    ),
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.circular(12),
                                                      child: Image.asset(
                                                        'assets/images/people_icon.png',
                                                        fit: BoxFit.cover,
                                                      ),
                                                    ),
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
                                                  task['task_start'] != null ? UpcomingTasksScreen._formatTime(task['task_start']) : '',
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
                                                  task['task_end'] != null ? UpcomingTasksScreen._formatTime(task['task_end']) : '',
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
                      width: 140,
                      child: ElevatedButton(
                        onPressed: () async {
                          final caregiverId = await _getCurrentCaregiverId(context);
                          // Fetch caregiver's assigned days and time range first
                          List<String> caregiverAssignedDays = [];
                          Map<String, String> caregiverTimeRange = {'start': '00:00', 'end': '23:59'};
                          final assignSnap = await FirebaseFirestore.instance
                            .collection('cg_house_assign')
                            .where('caregiver_id', isEqualTo: caregiverId)
                            .get();
                          if (assignSnap.docs.isNotEmpty) {
                            caregiverAssignedDays = List<String>.from(assignSnap.docs.first.data()['days_assigned'] ?? []);
                            final timeRange = assignSnap.docs.first.data()['time_range'] as Map<String, dynamic>? ?? {};
                            caregiverTimeRange = {
                              'start': timeRange['start'] ?? '00:00',
                              'end': timeRange['end'] ?? '23:59',
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
                          
                          // Get ALL elderly assigned to this caregiver (from elderly_caregiver_assign collection)
                          List<Map<String, dynamic>> assignedElderly = await _getAllAssignedElderlyFromElderlyCaregiver(caregiverId);
                          print('🔍 DEBUG: assignedElderly result = ${assignedElderly.length} elderly found');
                          for (var elderly in assignedElderly) {
                            print('🔍 DEBUG: Elderly: ${elderly['elderly_fname']} (ID: ${elderly['elderly_id']})');
                          }
                          final rangeStart = _parseTimeOfDay(caregiverTimeRange['start']!);
                          final rangeEnd = _parseTimeOfDay(caregiverTimeRange['end']!);
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (BuildContext ctx) {
                              String? selectedElderly;
                              String? selectedFrequency = 'Only once';
                              TimeOfDay? startTime;
                              TimeOfDay? endTime;
                              TextEditingController activityController = TextEditingController();
                              final List<String> frequencyList = ['Only once', 'Every Assigned Day', 'Custom'];
                              DateTime? selectedDate;
                              List<String> selectedDaysBox = [];
                              DateTime? selectedRecurringStartDate;
                              return StatefulBuilder(
                                builder: (context, setState) {
                                  Future<void> updateElderlyList(String newDay) async {
                                    assignedElderly = await _getAssignedElderlyForCaregiverDay(caregiverId, newDay);
                                    setState(() {
                                      selectedDay = newDay;
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
                                                      onChanged: (val) async {
                                                        if (val != null) {
                                                          await updateElderlyList(val);
                                                          setState(() {});
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
                                                          return DropdownMenuItem<String>(
                                                            value: elderly['elderly_id'],
                                                            child: Text(elderly['elderly_fname'], style: const TextStyle(color: Color.fromARGB(255, 0, 0, 0))),
                                                          );
                                                        }).toList();
                                                      })(),
                                                      onChanged: (value) {
                                                        setState(() {
                                                          selectedElderly = value;
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
                                                                    title: const Text('Invalid Time'),
                                                                    content: Text('The picked start time (${picked.format(ctx)}) is outside your allowed work hours (${rangeStart.format(ctx)} - ${rangeEnd.format(ctx)}). Please choose another.'),
                                                                    actions: [
                                                                      TextButton(
                                                                        onPressed: () => Navigator.of(context).pop(),
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
                                                                    title: const Text('Invalid Time'),
                                                                    content: Text('The picked end time (${picked.format(ctx)}) is outside your allowed work hours (${rangeStart.format(ctx)} - ${rangeEnd.format(ctx)}). Please choose another.'),
                                                                    actions: [
                                                                      TextButton(
                                                                        onPressed: () => Navigator.of(context).pop(),
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
                                                color: const Color(0xFFE6F3FA),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              child: DropdownButtonHideUnderline(
                                                child: DropdownButton<String>(
                                                  value: selectedFrequency,
                                                  isExpanded: true,
                                                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF22688E)),
                                                  items: frequencyList.map((freq) {
                                                    return DropdownMenuItem<String>(
                                                      value: freq,
                                                      child: Text(freq, overflow: TextOverflow.ellipsis),
                                                    );
                                                  }).toList(),
                                                  onChanged: (value) {
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

                                                  // Get assigned days for validation
                                                  final elderlyData = assignedElderly.firstWhere((e) => e['elderly_id'] == selectedElderly, orElse: () => {});
                                                  final elderlyAssignedDays = List<String>.from(elderlyData['days_assigned'] ?? []);
                                                  
                                                  print('🔍 DEBUG: Every Assigned Day date picker validation');
                                                  print('🔍 DEBUG: selectedElderly = $selectedElderly');
                                                  print('🔍 DEBUG: elderlyData = $elderlyData');
                                                  print('🔍 DEBUG: elderlyAssignedDays = $elderlyAssignedDays'); 
                                                  
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
                                                      // Only allow dates that match assigned days
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
                                                  
                                                  // First, try to get from current assignedElderly data (which we know works)
                                                  final elderlyData = assignedElderly.firstWhere((e) => e['elderly_id'] == selectedElderly, orElse: () => {});
                                                  elderlyAssignedDays = List<String>.from(elderlyData['days_assigned'] ?? []);
                                                  
                                                  print('DEBUG: Selected elderly ID: $selectedElderly');
                                                  print('DEBUG: Elderly data found: ${elderlyData.isNotEmpty}');
                                                  print('DEBUG: Assigned days from elderly data: $elderlyAssignedDays');
                                                  
                                                  // If empty, try to fetch from Firestore for comprehensive data
                                                  if (elderlyAssignedDays.isEmpty) {
                                                    try {
                                                      final assignSnapshot = await FirebaseFirestore.instance
                                                          .collection('cg_house_assign')
                                                          .where('caregiver_id', isEqualTo: caregiverId)
                                                          .where('elderly_id', isEqualTo: selectedElderly)
                                                          .get();
                                                      
                                                      Set<String> allAssignedDays = {};
                                                      for (var doc in assignSnapshot.docs) {
                                                        final data = doc.data();
                                                        final daysAssigned = List<String>.from(data['days_assigned'] ?? []);
                                                        allAssignedDays.addAll(daysAssigned);
                                                      }
                                                      elderlyAssignedDays = allAssignedDays.toList();
                                                    } catch (e) {
                                                      print('Error fetching assignment days: $e');
                                                    }
                                                  }
                                                  
                                                  if (elderlyAssignedDays.isEmpty) {
                                                    showDialog(
                                                      context: ctx,
                                                      builder: (BuildContext context) => AlertDialog(
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                        title: Row(
                                                          children: const [
                                                            Icon(Icons.warning_amber, color: Colors.orange),
                                                            SizedBox(width: 8),
                                                            Text('No Assigned Days'),
                                                          ],
                                                        ),
                                                        content: Text(
                                                          'Debug Info:\n'
                                                          'Selected Elderly: $selectedElderly\n'
                                                          'Assigned Days Found: $elderlyAssignedDays\n'
                                                          'AssignedElderly Count: ${assignedElderly.length}\n\n'
                                                          'You are not currently assigned to this elderly on any days. '
                                                          'Please check with your administrator about your schedule assignments.',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () => Navigator.of(context).pop(),
                                                            child: const Text('OK', style: TextStyle(color: Color(0xFF22688E))),
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
                                                      // Only allow dates where elderly is assigned to caregiver
                                                      String weekday = [
                                                        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
                                                      ][date.weekday - 1];
                                                      
                                                      return elderlyAssignedDays.contains(weekday);
                                                    },
                                                    helpText: 'Select a date when you\'re assigned to this elderly',
                                                    errorInvalidText: 'Select a day when you\'re assigned to this elderly',
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
                                              if (selectedElderly != null)
                                                FutureBuilder<List<String>>(
                                                  future: _getElderlyAssignedDays(selectedElderly!),
                                                  builder: (context, snapshot) {
                                                    if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                                                      return Text(
                                                        'Available days: ${snapshot.data!.join(', ')}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.grey[600],
                                                          fontStyle: FontStyle.italic,
                                                        ),
                                                      );
                                                    }
                                                    return const SizedBox.shrink();
                                                  },
                                                ),
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
                                                  bool valid = selectedElderly != null && startTime != null && endTime != null && selectedFrequency != null && activityController.text.isNotEmpty;
                                                  DateTime? saveDate;
                                                  List<String> saveFrequency = [selectedFrequency!];
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
                                                    final elderlyData = assignedElderly.firstWhere((e) => e['elderly_id'] == selectedElderly, orElse: () => {});
                                                    final elderlyFname = elderlyData['elderly_fname'] ?? '';
                                                    final now = DateTime.now();
                                                    
                                                    // For recurring tasks, use the selected date for task times
                                                    final selectedDateForTimes = saveDate ?? now;
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
                                                      taskDate: saveDate!,
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
      
      // First, check if there's a relationship between caregiver and elderly
      final elderlyAssignSnapshot = await FirebaseFirestore.instance
          .collection('elderly_caregiver_assign')
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('elderly_id', isEqualTo: elderlyId)
          .get();

      print('🔍 DEBUG: Found ${elderlyAssignSnapshot.docs.length} elderly-caregiver relationships');
      
      if (elderlyAssignSnapshot.docs.isEmpty) {
        print('🔍 DEBUG: No relationship found between caregiver and elderly');
        return [];
      }

      // Extract specific days from elderly_caregiver_assign documents
      Set<String> elderlySpecificDays = {};
      for (var doc in elderlyAssignSnapshot.docs) {
        final data = doc.data();
        print('🔍 DEBUG: Elderly-caregiver assignment doc: $data');
        
        // Check for individual 'day' field (your data structure)
        final individualDay = data['day'] as String?;
        if (individualDay != null && individualDay.isNotEmpty) {
          elderlySpecificDays.add(individualDay);
          print('🔍 DEBUG: Found individual day: $individualDay');
        }
        
        // Also check for 'days_assigned' array (fallback)
        final daysAssignedArray = List<String>.from(data['days_assigned'] ?? []);
        if (daysAssignedArray.isNotEmpty) {
          elderlySpecificDays.addAll(daysAssignedArray);
          print('🔍 DEBUG: Found days_assigned array: $daysAssignedArray');
        }
      }

      // Sort days in proper order
      const weekOrder = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      final sortedDays = elderlySpecificDays.toList();
      sortedDays.sort((a, b) => weekOrder.indexOf(a).compareTo(weekOrder.indexOf(b)));
      
      print('🔍 DEBUG: Final assigned days for this elderly: $sortedDays');
      return sortedDays;
    } catch (e) {
      print('Error getting assigned days for elderly and caregiver: $e');
      return [];
    }
  }





  Future<List<Map<String, dynamic>>> _getAssignedElderlyForCaregiverDay(String caregiverId, String day) async {
    try {
      print('🔍 DEBUG: _getAssignedElderlyForCaregiverDay called with caregiverId=$caregiverId, day=$day');
      
      // Query elderly_caregiver_assign collection for this specific day
      final assignSnapshot = await FirebaseFirestore.instance
          .collection('elderly_caregiver_assign')
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('day', isEqualTo: day)
          .get();

      print('🔍 DEBUG: Found ${assignSnapshot.docs.length} assignment documents for $day');

      if (assignSnapshot.docs.isEmpty) {
        print('🔍 DEBUG: No assignments found for day $day');
        return [];
      }

      // Extract elderly IDs from assignments
      final assignedIds = assignSnapshot.docs
          .map((doc) => doc.data()['elderly_id'])
          .where((id) => id != null)
          .cast<String>()
          .toSet()
          .toList();
      
      print('🔍 DEBUG: Found ${assignedIds.length} assigned elderly IDs: $assignedIds');

      if (assignedIds.isEmpty) return [];

      // Fetch elderly details in chunks of 30 (Firestore limit)
      List<QuerySnapshot> elderlySnapshots = [];
      
      for (int i = 0; i < assignedIds.length; i += 30) {
        final chunk = assignedIds.skip(i).take(30).toList();
        final chunkSnapshot = await FirebaseFirestore.instance
            .collection('elderly')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        elderlySnapshots.add(chunkSnapshot);
      }

      // Build result from elderly data and get ALL assigned days for each elderly
      List<Map<String, dynamic>> assignedElderly = [];
      for (var snapshot in elderlySnapshots) {
        for (var doc in snapshot.docs) {
          final elderlyData = doc.data() as Map<String, dynamic>;
          final elderlyId = doc.id;
          final sex = elderlyData['elderly_sex'] ?? '';
          final prefix = (sex == 'Male') ? 'Lolo ' : (sex == 'Female') ? 'Lola ' : '';
          
          // Get ALL assigned days for this elderly-caregiver pair
          final allAssignedDays = await _getAssignedDaysForElderlyAndCaregiver(caregiverId, elderlyId);
          
          assignedElderly.add({
            'elderly_id': elderlyId,
            'caregiver_id': caregiverId,
            'elderly_fname': prefix + (elderlyData['elderly_fname'] ?? ''),
            'days_assigned': allAssignedDays, // Include ALL assigned days, not just the queried day
          });
        }
      }
      
      return assignedElderly;
    } catch (e) {
      print('Error in _getAssignedElderlyForCaregiverDay: $e');
      return [];
    }
  }

  // Get ALL elderly assigned to this caregiver from elderly_caregiver_assign collection
  Future<List<Map<String, dynamic>>> _getAllAssignedElderlyFromElderlyCaregiver(String caregiverId) async {
    try {
      print('🔍 DEBUG: _getAllAssignedElderlyFromElderlyCaregiver called with caregiverId=$caregiverId');
      
      // Get all assignments for this caregiver from elderly_caregiver_assign collection
      final assignSnapshot = await FirebaseFirestore.instance
          .collection('elderly_caregiver_assign')
          .where('caregiver_id', isEqualTo: caregiverId)
          .get();

      print('🔍 DEBUG: Found ${assignSnapshot.docs.length} elderly assignment documents');

      if (assignSnapshot.docs.isEmpty) return [];

      // Get unique elderly IDs from all assignments
      Set<String> uniqueElderlyIds = {};
      Map<String, List<String>> elderlyDaysMap = {}; // Track days for each elderly

      for (var doc in assignSnapshot.docs) {
        final assignData = doc.data();
        print('🔍 DEBUG: Elderly assignment document data: $assignData');
        
        final elderlyId = assignData['elderly_id'] as String?;
        final day = assignData['day'] as String?; // Use 'day' field instead of 'days_assigned'
        print('🔍 DEBUG: Extracted elderly_id: $elderlyId, day: $day');
        
        if (elderlyId != null && elderlyId.isNotEmpty && day != null && day.isNotEmpty) {
          uniqueElderlyIds.add(elderlyId);
          // Add this day to the elderly's day list
          if (!elderlyDaysMap.containsKey(elderlyId)) {
            elderlyDaysMap[elderlyId] = [];
          }
          if (!elderlyDaysMap[elderlyId]!.contains(day)) {
            elderlyDaysMap[elderlyId]!.add(day);
          }
          print('🔍 DEBUG: Days assigned for elderly $elderlyId: ${elderlyDaysMap[elderlyId]}');
        } else {
          print('🔍 DEBUG: No valid elderly_id or day found in this document');
        }
      }

      print('🔍 DEBUG: Found ${uniqueElderlyIds.length} unique elderly IDs: $uniqueElderlyIds');

      if (uniqueElderlyIds.isEmpty) return [];

      // Fetch elderly details in chunks of 30 (Firestore limit)
      List<QuerySnapshot> elderlySnapshots = [];
      final elderlyIds = uniqueElderlyIds.toList();
      
      for (int i = 0; i < elderlyIds.length; i += 30) {
        final chunk = elderlyIds.skip(i).take(30).toList();
        final chunkSnapshot = await FirebaseFirestore.instance
            .collection('elderly')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        elderlySnapshots.add(chunkSnapshot);
      }

      // Build result
      List<Map<String, dynamic>> assignedElderly = [];
      for (var snapshot in elderlySnapshots) {
        for (var doc in snapshot.docs) {
          final elderlyData = doc.data() as Map<String, dynamic>;
          final elderlyId = doc.id;
          final sex = elderlyData['elderly_sex'] ?? '';
          final prefix = (sex == 'Male') ? 'Lolo ' : (sex == 'Female') ? 'Lola ' : '';
          
          assignedElderly.add({
            'elderly_id': elderlyId,
            'caregiver_id': caregiverId,
            'elderly_fname': prefix + (elderlyData['elderly_fname'] ?? ''),
            'days_assigned': elderlyDaysMap[elderlyId] ?? [],
          });
        }
      }

      print('🔍 DEBUG: Returning ${assignedElderly.length} elderly for dropdown');
      return assignedElderly;
    } catch (e) {
      print('Error in _getAllAssignedElderlyFromElderlyCaregiver: $e');
      return [];
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
    DateTime actualTaskDate = taskDate;
    
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
        
        // Calculate next occurrence for next_taskdate
        DateTime nextOccurrence = userSelectedStartDate.add(const Duration(days: 7)); // Next week same day
        nextTaskDate = DateTime(nextOccurrence.year, nextOccurrence.month, nextOccurrence.day, taskStart.hour, taskStart.minute);
        
        print('✅ actualTaskDate set to: $actualTaskDate');
        print('✅ nextTaskDate calculated as: $nextTaskDate');
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
          
          bool isSelectedDateAssigned = await _isAssignedOnDate(elderlyId, caregiverId, taskDate);
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
          bool isTodayAssigned = await _isAssignedOnDate(elderlyId, caregiverId, now);
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
        
        // Calculate next occurrence based on custom days
        DateTime nextOccurrence = userSelectedStartDate.add(const Duration(days: 1));
        // Find the next occurrence of any custom day
        for (int i = 0; i < 14; i++) {
          final dayOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][nextOccurrence.weekday - 1];
          if (customDays.contains(dayOfWeek)) {
            nextTaskDate = DateTime(nextOccurrence.year, nextOccurrence.month, nextOccurrence.day, taskStart.hour, taskStart.minute);
            break;
          }
          nextOccurrence = nextOccurrence.add(const Duration(days: 1));
        }
        
        print('✅ actualTaskDate set to: $actualTaskDate');
        print('✅ nextTaskDate calculated as: $nextTaskDate');
      } else {
        // Fallback to old logic for backward compatibility
        print('⚠️ No recurring_start_date found, using fallback logic');
        
        // For custom tasks, if time has passed today, start from tomorrow
        DateTime searchFromDate = taskTimeHasPassed ? now.add(Duration(days: 1)) : now;
        nextTaskDate = await _getNextCustomDate(elderlyId, caregiverId, taskStart, searchFromDate, customDays);
        
        // Check if today matches custom days and time hasn't passed
        String todayWeekday = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"][now.weekday - 1];
        if (!taskTimeHasPassed && customDays.contains(todayWeekday) && await _isAssignedOnDate(elderlyId, caregiverId, now)) {
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
      'nextuser_id': '',
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
        bool isAssigned = await _isAssignedOnDate(elderlyId, caregiverId, candidate);
        
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
          bool isAssigned = await _isAssignedOnDate(elderlyId, caregiverId, candidate);
          
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

  // Helper function to check if caregiver is assigned to elderly on a specific date
  Future<bool> _isAssignedOnDate(String elderlyId, String caregiverId, DateTime date) async {
    try {
      String weekdayStr = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"][date.weekday - 1];
      
      print('  🔍 Checking if assigned on $weekdayStr for elderly $elderlyId');
      
      // Use elderly_caregiver_assign collection for caregiver-elderly assignments
      final assignSnapshot = await FirebaseFirestore.instance
          .collection('elderly_caregiver_assign')
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('elderly_id', isEqualTo: elderlyId)
          .get();
      
      print('  📋 Found ${assignSnapshot.docs.length} assignment records');
      
      if (assignSnapshot.docs.isEmpty) {
        print('  ❌ No assignments found');
        return false;
      }
      
      for (var doc in assignSnapshot.docs) {
        final data = doc.data();
        // Try both possible field structures
        final daysAssigned = List<String>.from(data['days_assigned'] ?? []);
        final singleDay = data['day'];
        
        print('  📅 Assignment: days_assigned=$daysAssigned, day=$singleDay');
        
        // Check both structures
        bool isAssignedViaArray = daysAssigned.contains(weekdayStr);
        bool isAssignedViaSingleDay = singleDay == weekdayStr;
        
        if (isAssignedViaArray || isAssignedViaSingleDay) {
          print('  ✅ $weekdayStr IS assigned! (array: $isAssignedViaArray, single: $isAssignedViaSingleDay)');
          return true;
        }
      }
      
      print('  ❌ $weekdayStr is NOT assigned');
      return false;
    } catch (e) {
      print('Error checking assignment on date: $e');
      return false;
    }
  }



  // Helper function to get all assigned days for an elderly-caregiver pair
  Future<List<String>> _getElderlyAssignedDays(String elderlyId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return [];
      
      // Use the same collection as the dropdown for consistency
      final assignSnapshot = await FirebaseFirestore.instance
          .collection('cg_house_assign')
          .where('caregiver_id', isEqualTo: currentUser.uid)
          .where('elderly_id', isEqualTo: elderlyId)
          .get();
      
      Set<String> allAssignedDays = {};
      for (var doc in assignSnapshot.docs) {
        final data = doc.data();
        final daysAssigned = List<String>.from(data['days_assigned'] ?? []);
        allAssignedDays.addAll(daysAssigned);
      }
      
      // Sort days in proper order
      const weekOrder = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      final sortedDays = allAssignedDays.toList();
      sortedDays.sort((a, b) => weekOrder.indexOf(a).compareTo(weekOrder.indexOf(b)));
      
      return sortedDays;
    } catch (e) {
      print('Error getting elderly assigned days: $e');
      return [];
    }
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
      
      // For recurring tasks, the Progressive Task System will handle calculating and creating 
      // the next occurrence when the shift ends (same behavior as Complete and Incomplete tasks)
      print('✅ Task marked as missed. Next occurrence will be calculated and created when shift ends.');
      
      print('✅ Task successfully marked as missed');
    } catch (e) {
      print('❌ Error marking task as missed: $e');
    }
  }

  static String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : hour == 0 ? 12 : hour;
    return '$hour12:$minute $ampm';
  }
}