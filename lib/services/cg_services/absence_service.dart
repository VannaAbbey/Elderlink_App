import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/cg_models/nurse_cg_absence.dart';
import '../../models/cg_models/temporary_assignment.dart';

/// Service to handle absence and temporary assignment operations
/// This service manages the nurse_cg_absence and temporary_assignments collections
class AbsenceService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Check if a caregiver/nurse is marked as absent for today
  /// Returns the absence record if found, null otherwise
  static Future<NurseCgAbsence?> checkTodayAbsence(String userId) async {
    try {
      final today = _formatDate(DateTime.now());
      print('🔍 Checking absence for user $userId on date: $today');

      final querySnapshot = await _firestore
          .collection('nurse_cg_absence')
          .where('user_id', isEqualTo: userId)
          .where('absence_date', isEqualTo: today)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        print('✅ No absence record found for today');
        return null;
      }

      final absence = NurseCgAbsence.fromFirestore(querySnapshot.docs.first);
      print('⚠️ User is marked as ${absence.absenceType} for today');
      return absence;
    } catch (e) {
      print('❌ Error checking today\'s absence: $e');
      rethrow;
    }
  }

  /// Check if a caregiver/nurse is absent for a specific date
  static Future<NurseCgAbsence?> checkAbsenceForDate(
    String userId,
    DateTime date,
  ) async {
    try {
      final dateStr = _formatDate(date);
      print('🔍 Checking absence for user $userId on date: $dateStr');

      final querySnapshot = await _firestore
          .collection('nurse_cg_absence')
          .where('user_id', isEqualTo: userId)
          .where('absence_date', isEqualTo: dateStr)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      return NurseCgAbsence.fromFirestore(querySnapshot.docs.first);
    } catch (e) {
      print('❌ Error checking absence for date: $e');
      rethrow;
    }
  }

  /// Stream to listen for real-time absence status updates for today
  /// This stream automatically updates when the date changes (at midnight)
  static Stream<NurseCgAbsence?> listenToTodayAbsence(String userId) {
    // Use a StreamController to handle date changes
    late StreamController<NurseCgAbsence?> controller;
    StreamSubscription<QuerySnapshot>? subscription;
    Timer? midnightTimer;
    String? currentDate;

    void updateListener() {
      final today = _formatDate(DateTime.now());
      
      print('🔍 updateListener called - currentDate: $currentDate, today: $today');
      
      // Only update if date has changed
      if (currentDate == today) {
        print('⏭️ Date unchanged, skipping update');
        return;
      }
      
      currentDate = today;
      print('🔄 Updating absence listener for user: $userId, date: $today');

      // Cancel previous subscription
      subscription?.cancel();

      // Create new subscription for current date
      subscription = _firestore
          .collection('nurse_cg_absence')
          .where('user_id', isEqualTo: userId)
          .where('absence_date', isEqualTo: today)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .snapshots()
          .listen(
        (snapshot) {
          print('📡 Firestore snapshot received: ${snapshot.docs.length} documents');
          if (!controller.isClosed) {
            if (snapshot.docs.isEmpty) {
              print('✅ No absence for $today - emitting null');
              controller.add(null);
            } else {
              final absence = NurseCgAbsence.fromFirestore(snapshot.docs.first);
              print('⚠️ Absence found for $today: ${absence.absenceType}');
              controller.add(absence);
            }
          } else {
            print('⚠️ Controller is closed, not emitting data');
          }
        },
        onError: (error) {
          print('❌ Firestore error: $error');
          if (!controller.isClosed) {
            controller.addError(error);
          }
        },
      );
    }

    void scheduleNextMidnight() {
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final timeUntilMidnight = tomorrow.difference(now);
      
      print('⏰ Scheduling absence check for midnight in ${timeUntilMidnight.inHours}h ${timeUntilMidnight.inMinutes % 60}m (at $tomorrow)');
      
      midnightTimer?.cancel();
      midnightTimer = Timer(timeUntilMidnight, () {
        print('🌅 Midnight reached! Current time: ${DateTime.now()}');
        updateListener();
        scheduleNextMidnight(); // Schedule next midnight check
      });
    }

    controller = StreamController<NurseCgAbsence?>.broadcast(
      onListen: () {
        print('👂 Absence stream listener attached for user: $userId');
        updateListener();
        scheduleNextMidnight();
      },
      onCancel: () {
        print('🔌 Absence stream cancelled for user: $userId');
        subscription?.cancel();
        midnightTimer?.cancel();
      },
    );

    return controller.stream;
  }

  /// Get all absence records for a specific user
  static Stream<List<NurseCgAbsence>> getUserAbsenceRecords(String userId) {
    return _firestore
        .collection('nurse_cg_absence')
        .where('user_id', isEqualTo: userId)
        .orderBy('absence_date', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => NurseCgAbsence.fromFirestore(doc))
          .toList();
    });
  }

  /// Get temporary assignments TO a caregiver for today
  /// (Elderly temporarily assigned to them from absent caregivers)
  static Future<List<TemporaryAssignment>> getTodayTemporaryAssignmentsTo(
    String userId,
  ) async {
    try {
      final today = _formatDate(DateTime.now());
      print('🔍 Getting temporary assignments TO user $userId for: $today');

      final querySnapshot = await _firestore
          .collection('temporary_assignments')
          .where('to_user_id', isEqualTo: userId)
          .where('date', isEqualTo: today)
          .where('status', isEqualTo: 'active')
          .get();

      final assignments = querySnapshot.docs
          .map((doc) => TemporaryAssignment.fromFirestore(doc))
          .toList();

      print('✅ Found ${assignments.length} temporary assignment(s)');
      return assignments;
    } catch (e) {
      print('❌ Error getting temporary assignments: $e');
      rethrow;
    }
  }

  /// Stream to listen for temporary assignments in real-time
  /// Stream to listen for real-time temporary assignments for today
  /// This stream automatically updates when the date changes (at midnight)
  static Stream<List<TemporaryAssignment>> listenToTodayTemporaryAssignmentsTo(
    String userId,
  ) {
    // Use a StreamController to handle date changes
    late StreamController<List<TemporaryAssignment>> controller;
    StreamSubscription<QuerySnapshot>? subscription;
    Timer? midnightTimer;
    String? currentDate;

    void updateListener() {
      final today = _formatDate(DateTime.now());
      
      print('🔍 updateListener (temp assignments) called - currentDate: $currentDate, today: $today');
      
      // Only update if date has changed
      if (currentDate == today) {
        print('⏭️ Date unchanged, skipping update');
        return;
      }
      
      currentDate = today;
      print('🔄 Updating temporary assignments listener for user: $userId, date: $today');

      // Cancel previous subscription
      subscription?.cancel();

      // Create new subscription for current date
      subscription = _firestore
          .collection('temporary_assignments')
          .where('to_user_id', isEqualTo: userId)
          .where('date', isEqualTo: today)
          .where('status', isEqualTo: 'active')
          .snapshots()
          .listen(
        (snapshot) {
          print('📡 Temporary assignments snapshot received: ${snapshot.docs.length} assignments');
          if (!controller.isClosed) {
            final assignments = snapshot.docs
                .map((doc) => TemporaryAssignment.fromFirestore(doc))
                .toList();
            print('✅ Emitting ${assignments.length} temporary assignments');
            controller.add(assignments);
          } else {
            print('⚠️ Controller is closed, not emitting data');
          }
        },
        onError: (error) {
          print('❌ Firestore error (temp assignments): $error');
          if (!controller.isClosed) {
            controller.addError(error);
          }
        },
      );
    }

    void scheduleNextMidnight() {
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final timeUntilMidnight = tomorrow.difference(now);
      
      print('⏰ Scheduling temporary assignments check for midnight in ${timeUntilMidnight.inHours}h ${timeUntilMidnight.inMinutes % 60}m (at $tomorrow)');
      
      midnightTimer?.cancel();
      midnightTimer = Timer(timeUntilMidnight, () {
        print('🌅 Midnight reached! Current time: ${DateTime.now()}');
        updateListener();
        scheduleNextMidnight(); // Schedule next midnight check
      });
    }

    controller = StreamController<List<TemporaryAssignment>>.broadcast(
      onListen: () {
        print('👂 Temporary assignments stream listener attached for user: $userId');
        updateListener();
        scheduleNextMidnight();
      },
      onCancel: () {
        print('🔌 Temporary assignments stream cancelled for user: $userId');
        subscription?.cancel();
        midnightTimer?.cancel();
      },
    );

    return controller.stream;
  }

  /// Get all elderly IDs that are temporarily assigned to a caregiver today
  static Future<List<String>> getTodayTemporaryElderlyIds(String userId) async {
    try {
      final assignments = await getTodayTemporaryAssignmentsTo(userId);
      
      // Flatten all elderly IDs from all assignments
      final elderlyIds = <String>{};
      for (final assignment in assignments) {
        elderlyIds.addAll(assignment.elderlyIds);
      }
      
      print('✅ Found ${elderlyIds.length} temporarily assigned elderly');
      return elderlyIds.toList();
    } catch (e) {
      print('❌ Error getting temporary elderly IDs: $e');
      return [];
    }
  }

  /// Get temporary assignments FROM a caregiver (when they are absent)
  static Future<List<TemporaryAssignment>> getTodayTemporaryAssignmentsFrom(
    String userId,
  ) async {
    try {
      final today = _formatDate(DateTime.now());

      final querySnapshot = await _firestore
          .collection('temporary_assignments')
          .where('from_user_id', isEqualTo: userId)
          .where('date', isEqualTo: today)
          .where('status', isEqualTo: 'active')
          .get();

      return querySnapshot.docs
          .map((doc) => TemporaryAssignment.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ Error getting assignments from user: $e');
      rethrow;
    }
  }

  /// Get all absence records for a date range
  static Future<List<NurseCgAbsence>> getAbsenceRecordsForDateRange(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final startDateStr = _formatDate(startDate);
      final endDateStr = _formatDate(endDate);

      final querySnapshot = await _firestore
          .collection('nurse_cg_absence')
          .where('user_id', isEqualTo: userId)
          .where('absence_date', isGreaterThanOrEqualTo: startDateStr)
          .where('absence_date', isLessThanOrEqualTo: endDateStr)
          .orderBy('absence_date')
          .get();

      return querySnapshot.docs
          .map((doc) => NurseCgAbsence.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ Error getting absence records for date range: $e');
      rethrow;
    }
  }

  /// Check if user has any active absences in the future
  static Future<List<NurseCgAbsence>> getUpcomingAbsences(String userId) async {
    try {
      final today = _formatDate(DateTime.now());

      final querySnapshot = await _firestore
          .collection('nurse_cg_absence')
          .where('user_id', isEqualTo: userId)
          .where('absence_date', isGreaterThanOrEqualTo: today)
          .where('status', isEqualTo: 'active')
          .orderBy('absence_date')
          .get();

      return querySnapshot.docs
          .map((doc) => NurseCgAbsence.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ Error getting upcoming absences: $e');
      rethrow;
    }
  }

  /// Helper method to format date as "YYYY-MM-DD"
  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Helper method to parse date string to DateTime
  static DateTime parseDate(String dateStr) {
    return DateTime.parse(dateStr);
  }

  /// Get count of active absences for today
  static Future<int> getTodayAbsenceCount(String userId) async {
    final absence = await checkTodayAbsence(userId);
    return absence != null ? 1 : 0;
  }

  /// Check if user is currently on shift and not absent
  static Future<bool> isUserAvailableToday(String userId) async {
    final absence = await checkTodayAbsence(userId);
    return absence == null;
  }

  /// Automatically mark all tasks as incomplete for an absent caregiver on a specific date
  /// This includes both regular tasks and recurring tasks scheduled for that day
  /// For recurring tasks, also progress them to the next working day
  static Future<void> markTasksIncompleteForAbsentDay(
    String caregiverId,
    DateTime absenceDate,
    String absenceType, // 'absent' or 'leave'
  ) async {
    try {
      final dateStr = _formatDate(absenceDate);
      print('🔄 Marking tasks as incomplete for caregiver $caregiverId on $dateStr due to $absenceType');

      // Normalize the absence date to start of day for comparison
      final absenceDateNormalized = DateTime(
        absenceDate.year,
        absenceDate.month,
        absenceDate.day,
      );

      // Query all tasks for this caregiver on this date
      final tasksSnapshot = await _firestore
          .collection('care_tasks')
          .where('caregiver_id', isEqualTo: caregiverId)
          .get();

      int markedCount = 0;
      int progressedCount = 0;

      for (var taskDoc in tasksSnapshot.docs) {
        final taskData = taskDoc.data();
        final taskStatus = List<String>.from(taskData['task_status'] ?? []);
        
        // Skip if already marked as Incomplete
        if (taskStatus.contains('Incomplete')) {
          continue;
        }

        // Get task date
        final taskDate = (taskData['task_date'] as Timestamp?)?.toDate();
        if (taskDate == null) continue;

        // Normalize task date for comparison
        final taskDateNormalized = DateTime(
          taskDate.year,
          taskDate.month,
          taskDate.day,
        );

        // Check if this task is scheduled for the absence date
        if (taskDateNormalized.isAtSameMomentAs(absenceDateNormalized)) {
          // Check if this is a recurring task
          final frequency = (taskData['task_frequency'] as List<dynamic>?)?.first ?? 'Only once';
          final isRecurring = frequency != 'Only once';
          
          if (isRecurring) {
            // For recurring tasks: progress to next occurrence instead of marking incomplete
            print('  🔄 Progressing recurring task ${taskDoc.id} to next occurrence');
            
            try {
              final nextTaskDate = (taskData['next_taskdate'] as Timestamp?)?.toDate();
              
              if (nextTaskDate != null) {
                // Calculate the occurrence after next_taskdate
                final taskStart = (taskData['task_start'] as Timestamp?)?.toDate() ?? DateTime.now();
                final recurringStartDate = (taskData['recurring_start_date'] as Timestamp?)?.toDate();
                final customDays = List<String>.from(taskData['custom_days'] ?? []);
                final elderlyId = taskData['elderly_id'] ?? '';
                
                DateTime? newNextTaskDate;
                
                if (recurringStartDate != null) {
                  if (frequency == 'Custom' && customDays.isNotEmpty) {
                    newNextTaskDate = await _getNextCustomDateForAbsence(
                      elderlyId, 
                      caregiverId, 
                      taskStart, 
                      nextTaskDate.add(Duration(days: 1)), 
                      customDays
                    );
                  } else if (frequency == 'Every Assigned Day') {
                    final assignedDays = await _getAssignedDaysForElderlyAndCaregiverForAbsence(caregiverId, elderlyId);
                    newNextTaskDate = _calculateNextOccurrenceForAbsence(
                      nextTaskDate, 
                      recurringStartDate, 
                      frequency, 
                      customDays, 
                      taskStart, 
                      assignedDays: assignedDays
                    );
                  } else {
                    newNextTaskDate = _calculateNextOccurrenceForAbsence(
                      nextTaskDate, 
                      recurringStartDate, 
                      frequency, 
                      customDays, 
                      taskStart
                    );
                  }
                }
                
                // Progress the task to next occurrence
                await taskDoc.reference.update({
                  'task_date': nextTaskDate,
                  'next_taskdate': newNextTaskDate,
                  'task_status': ['Upcoming'], // Reset to Upcoming
                  'inc_reason': '', // Clear any incomplete reason
                  'progressed_due_to_absence': true,
                  'absence_progression_date': FieldValue.serverTimestamp(),
                  'updated_at': FieldValue.serverTimestamp(),
                });
                
                progressedCount++;
                print('  ✅ Progressed recurring task ${taskDoc.id} from $taskDate to $nextTaskDate');
              } else {
                // Fallback: mark as incomplete if we can't calculate next date
                print('  ⚠️ Could not progress task ${taskDoc.id} - missing next_taskdate, marking incomplete');
                await _markTaskIncomplete(taskDoc.reference, absenceType);
                markedCount++;
              }
            } catch (e) {
              print('  ❌ Error progressing recurring task ${taskDoc.id}: $e');
              // Fallback: mark as incomplete
              await _markTaskIncomplete(taskDoc.reference, absenceType);
              markedCount++;
            }
          } else {
            // For non-recurring tasks: mark as incomplete
            await _markTaskIncomplete(taskDoc.reference, absenceType);
            markedCount++;
            print('  ✓ Marked non-recurring task ${taskDoc.id} as incomplete');
          }
        }
      }

      print('✅ Successfully processed tasks: $markedCount marked incomplete, $progressedCount progressed to next occurrence for $dateStr');
    } catch (e) {
      print('❌ Error marking tasks as incomplete: $e');
      rethrow;
    }
  }
  
  /// Helper method to mark a task as incomplete
  static Future<void> _markTaskIncomplete(
    DocumentReference taskRef,
    String absenceType,
  ) async {
    final incReason = absenceType == 'leave'
        ? 'Caregiver is on leave'
        : 'Caregiver is absent';
    
    await taskRef.update({
      'task_status': ['Incomplete'],
      'inc_reason': incReason,
      'auto_marked_incomplete': true,
      'auto_marked_at': FieldValue.serverTimestamp(),
    });
  }
  
  /// Helper method to get assigned days for a caregiver-elderly pair (for absence handling)
  static Future<List<String>> _getAssignedDaysForElderlyAndCaregiverForAbsence(
    String caregiverId,
    String elderlyId,
  ) async {
    try {
      final assignmentSnapshot = await _firestore
          .collection('caregiver_elderly_assignments')
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('elderly_id', isEqualTo: elderlyId)
          .limit(1)
          .get();
      
      if (assignmentSnapshot.docs.isNotEmpty) {
        final data = assignmentSnapshot.docs.first.data();
        return List<String>.from(data['assigned_days'] ?? []);
      }
      
      return [];
    } catch (e) {
      print('Error getting assigned days: $e');
      return [];
    }
  }
  
  /// Helper method to calculate next occurrence for recurring tasks (for absence handling)
  static DateTime? _calculateNextOccurrenceForAbsence(
    DateTime currentTaskDate,
    DateTime recurringStartDate,
    String frequency,
    List<String> customDays,
    DateTime taskStart,
    {List<String>? assignedDays}
  ) {
    if (frequency == 'Every Assigned Day' && assignedDays != null && assignedDays.isNotEmpty) {
      DateTime nextDate = currentTaskDate.add(const Duration(days: 1));
      
      for (int i = 0; i < 14; i++) {
        final dayOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][nextDate.weekday - 1];
        if (assignedDays.contains(dayOfWeek)) {
          return DateTime(nextDate.year, nextDate.month, nextDate.day, taskStart.hour, taskStart.minute);
        }
        nextDate = nextDate.add(const Duration(days: 1));
      }
    } else if (frequency == 'Custom' && customDays.isNotEmpty) {
      DateTime nextDate = currentTaskDate.add(const Duration(days: 1));
      
      for (int i = 0; i < 14; i++) {
        final dayOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][nextDate.weekday - 1];
        if (customDays.contains(dayOfWeek)) {
          return DateTime(nextDate.year, nextDate.month, nextDate.day, taskStart.hour, taskStart.minute);
        }
        nextDate = nextDate.add(const Duration(days: 1));
      }
    }
    
    return null;
  }
  
  /// Helper method to get next custom date (for absence handling)
  static Future<DateTime?> _getNextCustomDateForAbsence(
    String elderlyId,
    String caregiverId,
    DateTime taskStart,
    DateTime startSearchDate,
    List<String> customDays,
  ) async {
    try {
      // Get assigned days for this caregiver-elderly pair
      final assignedDays = await _getAssignedDaysForElderlyAndCaregiverForAbsence(caregiverId, elderlyId);
      
      if (assignedDays.isEmpty) {
        // No assignment found, use custom days only
        DateTime nextDate = startSearchDate;
        for (int i = 0; i < 14; i++) {
          final dayOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][nextDate.weekday - 1];
          if (customDays.contains(dayOfWeek)) {
            return DateTime(nextDate.year, nextDate.month, nextDate.day, taskStart.hour, taskStart.minute);
          }
          nextDate = nextDate.add(const Duration(days: 1));
        }
        return null;
      }
      
      // Find next date that matches both custom days and assigned days
      DateTime nextDate = startSearchDate;
      for (int i = 0; i < 14; i++) {
        final dayOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][nextDate.weekday - 1];
        if (customDays.contains(dayOfWeek) && assignedDays.contains(dayOfWeek)) {
          return DateTime(nextDate.year, nextDate.month, nextDate.day, taskStart.hour, taskStart.minute);
        }
        nextDate = nextDate.add(const Duration(days: 1));
      }
      
      return null;
    } catch (e) {
      print('Error getting next custom date: $e');
      return null;
    }
  }

  /// Mark tasks as incomplete when caregiver becomes absent (to be called automatically)
  static Future<void> autoMarkTasksForAbsence(
    String userId,
    DateTime absenceDate,
    String absenceType,
  ) async {
    try {
      // Mark tasks for the absence date
      await markTasksIncompleteForAbsentDay(userId, absenceDate, absenceType);
    } catch (e) {
      print('❌ Error in auto-marking tasks for absence: $e');
      // Don't rethrow - this is a background operation
    }
  }
}
