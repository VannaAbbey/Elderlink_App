import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import 'dart:async';

/// 🔄 BACKGROUND ATTENDANCE SERVICE
/// ================================
///
/// This service runs in the background to automatically mark users as absent
/// if they don't mark attendance within 15 minutes of their shift start.
///
/// **Key Features:**
/// - ✅ Runs even when app is closed
/// - ✅ Marks users absent EXACTLY 15 minutes after shift start
/// - ✅ Automatically marks absent if no response
/// - ✅ Works for all shifts (1st, 2nd, 3rd)
/// - ✅ Independent of user opening the app
///
/// **How It Works:**
/// 1. Runs frequently (every 5 minutes) to catch the 15-minute deadline
/// 2. For each shift, checks if EXACTLY 15+ minutes have passed since start
/// 3. Example: 1st shift starts 6:00 AM → Marks absent at/after 6:15 AM
/// 4. Example: 2nd shift starts 2:00 PM → Marks absent at/after 2:15 PM
/// 5. Example: 3rd shift starts 10:00 PM → Marks absent at/after 10:15 PM
/// 6. Only marks users who have NO attendance record yet

// Background task name
const String backgroundAttendanceTask = "background_attendance_check";

/// Background callback - runs independently of the app
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('🔄 BACKGROUND: Attendance check task started');

    try {
      // Initialize Firebase in background isolate if not already initialized
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        print('🔄 BACKGROUND: Firebase initialized in background isolate');
      }

      await BackgroundAttendanceService.checkAndMarkAbsentUsers();
      print('✅ BACKGROUND: Attendance check task completed');
      return Future.value(true);
    } catch (e) {
      print('❌ BACKGROUND: Error in attendance check task: $e');
      print('❌ BACKGROUND: Stack trace: ${StackTrace.current}');
      return Future.value(false);
    }
  });
}

class BackgroundAttendanceService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Initialize background service
  /// Call this from main.dart during app initialization
  static Future<void> initialize() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: true, // Set to true for debugging, false for production
      );

      // Register periodic task - runs every 15 minutes
      // Android minimum frequency is 15 minutes
      // This checks if users are past the 15-minute grace period and marks them absent
      await Workmanager().registerPeriodicTask(
        backgroundAttendanceTask,
        backgroundAttendanceTask,
        frequency: const Duration(minutes: 15), // Android minimum is 15 minutes
        constraints: Constraints(
          networkType: NetworkType.connected, // Requires internet
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );

      // Also run an immediate one-time check when app starts
      // This catches any users who should have been marked absent while app was closed
      await Workmanager().registerOneOffTask(
        '${backgroundAttendanceTask}_immediate',
        backgroundAttendanceTask,
        initialDelay: const Duration(
          seconds: 10,
        ), // Wait 10 seconds after app start
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

      print('✅ BACKGROUND: Attendance service initialized');
      print('📋 BACKGROUND: Periodic check every 15 minutes');
      print('📋 BACKGROUND: Immediate check in 10 seconds');
      print('⏰ BACKGROUND: Users marked absent at: 6:15 AM, 2:15 PM, 10:15 PM');
    } catch (e) {
      print('❌ BACKGROUND: Failed to initialize: $e');
    }
  }

  /// Cancel background service
  static Future<void> cancel() async {
    try {
      await Workmanager().cancelByUniqueName(backgroundAttendanceTask);
      print('🛑 BACKGROUND: Attendance service cancelled');
    } catch (e) {
      print('❌ BACKGROUND: Failed to cancel: $e');
    }
  }

  /// Main logic: Check all scheduled users and mark absent if needed
  ///
  /// **IMPORTANT:** This marks users absent if 15+ minutes have passed since shift start
  /// Example Timeline:
  /// - 6:00 AM: Shift starts
  /// - 6:00-6:15 AM: Grace period - users can mark attendance
  /// - 6:15 AM+: If user hasn't marked attendance, they get marked ABSENT
  ///
  /// The background task runs every 15 minutes, so it will mark users absent
  /// within a few minutes after the 15-minute deadline passes.
  static Future<void> checkAndMarkAbsentUsers() async {
    try {
      final now = DateTime.now();
      final currentHour = now.hour;
      final currentMinute = now.minute;

      print(
        '🔍 BACKGROUND: Checking at ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      );

      // Determine which shifts need checking based on current time
      // We check a shift ONLY if we're past the 15-minute grace period
      List<Map<String, dynamic>> shiftsToCheck = [];

      // 1st Shift: Starts 6:00 AM → Mark absent at/after 6:15 AM
      // Check if current time >= 6:15 AM and < 2:00 PM
      if (currentHour >= 6 && currentHour < 14) {
        if (currentHour > 6 || (currentHour == 6 && currentMinute >= 15)) {
          shiftsToCheck.add({
            'shift': '1st',
            'startTime': '06:00',
            'endTime': '14:00',
          });
          print('✅ BACKGROUND: 1st shift past 15-min window (6:15 AM+)');
        }
      }

      // 2nd Shift: Starts 2:00 PM → Mark absent at/after 2:15 PM
      // Check if current time >= 2:15 PM and < 10:00 PM
      if (currentHour >= 14 && currentHour < 22) {
        if (currentHour > 14 || (currentHour == 14 && currentMinute >= 15)) {
          shiftsToCheck.add({
            'shift': '2nd',
            'startTime': '14:00',
            'endTime': '22:00',
          });
          print('✅ BACKGROUND: 2nd shift past 15-min window (2:15 PM+)');
        }
      }

      // 3rd Shift: Starts 10:00 PM → Mark absent at/after 10:15 PM
      // Check if current time >= 10:15 PM or it's the next day (before 6:00 AM)
      if (currentHour >= 22 || currentHour < 6) {
        if ((currentHour == 22 && currentMinute >= 15) ||
            currentHour >= 23 ||
            currentHour < 6) {
          shiftsToCheck.add({
            'shift': '3rd',
            'startTime': '22:00',
            'endTime': '06:00',
          });
          print('✅ BACKGROUND: 3rd shift past 15-min window (10:15 PM+)');
        }
      }

      if (shiftsToCheck.isEmpty) {
        print(
          '⏸️ BACKGROUND: No shifts are past their 15-minute grace period yet',
        );
        return;
      }

      print(
        '📋 BACKGROUND: Processing shifts: ${shiftsToCheck.map((s) => s['shift']).toList()}',
      );

      // Process each shift that needs checking
      for (var shiftInfo in shiftsToCheck) {
        await _checkShiftAttendance(
          shift: shiftInfo['shift'] as String,
          startTime: shiftInfo['startTime'] as String,
        );
      }
    } catch (e) {
      print('❌ BACKGROUND: Error checking users: $e');
    }
  }

  /// Check attendance for a specific shift
  static Future<void> _checkShiftAttendance({
    required String shift,
    required String startTime,
  }) async {
    try {
      final now = DateTime.now();
      final dateString = _getDateString(now);
      final currentDayName = _getDayName(now.weekday);

      print('🔍 BACKGROUND: Checking $shift shift on $currentDayName');

      // Get all users assigned to this shift today
      final assignmentsQuery = await _firestore
          .collection('house_shift_assignments')
          .where('is_current', isEqualTo: true)
          .where('start_time', isEqualTo: startTime)
          .get();

      print(
        '📊 BACKGROUND: Found ${assignmentsQuery.docs.length} assignments for $shift shift',
      );

      int markedCount = 0;

      for (var assignmentDoc in assignmentsQuery.docs) {
        try {
          final assignmentData = assignmentDoc.data();
          final userId = assignmentData['user_id'] as String?;
          final daysAssigned = List<String>.from(
            assignmentData['days_assigned'] ?? [],
          );

          if (userId == null) continue;

          // Check if user is scheduled for today
          if (!daysAssigned.contains(currentDayName)) {
            continue; // User not scheduled today
          }

          // Check if user has already marked attendance
          final attendanceQuery = await _firestore
              .collection('attendance')
              .where('user_id', isEqualTo: userId)
              .where('date', isEqualTo: dateString)
              .where('shift', isEqualTo: shift)
              .limit(1)
              .get();

          if (attendanceQuery.docs.isNotEmpty) {
            // Already marked - skip
            continue;
          }

          // Calculate if 15 minutes have passed since shift start
          final shiftStartTime = _parseShiftTime(now, startTime);
          final fifteenMinutesAfter = shiftStartTime.add(
            const Duration(minutes: 15),
          );

          if (now.isAfter(fifteenMinutesAfter)) {
            // 15 minutes passed and no attendance - mark as absent
            await _markUserAsAbsent(
              userId: userId,
              shift: shift,
              dateString: dateString,
            );
            markedCount++;
          }
        } catch (e) {
          print('❌ BACKGROUND: Error processing assignment: $e');
          continue;
        }
      }

      print(
        '✅ BACKGROUND: Marked $markedCount users as absent for $shift shift',
      );
    } catch (e) {
      print('❌ BACKGROUND: Error checking shift attendance: $e');
    }
  }

  /// Mark a user as absent in the database
  static Future<void> _markUserAsAbsent({
    required String userId,
    required String shift,
    required String dateString,
  }) async {
    try {
      // Get user type
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userType = userDoc.exists
          ? (userDoc.data()?['user_type'] ?? 'unknown')
          : 'unknown';
      final userName = userDoc.exists
          ? (userDoc.data()?['name'] ?? 'Unknown')
          : 'Unknown';

      // Create attendance record
      final attendanceData = {
        'user_id': userId,
        'user_type': userType,
        'date': dateString,
        'shift': shift,
        'is_present': false,
        'timestamp': FieldValue.serverTimestamp(),
        'reason':
            'Auto-marked absent by system - No response within 15 minutes of shift start',
        'marked_by': 'system_background',
        'auto_marked': true,
      };

      await _firestore.collection('attendance').add(attendanceData);

      print(
        '📝 BACKGROUND: Marked $userName ($userId) as absent for $shift shift on $dateString',
      );
    } catch (e) {
      print('❌ BACKGROUND: Error marking user as absent: $e');
      rethrow;
    }
  }

  /// Parse shift time into DateTime for today
  static DateTime _parseShiftTime(DateTime now, String timeString) {
    final parts = timeString.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    DateTime shiftTime = DateTime(now.year, now.month, now.day, hour, minute);

    // Handle 3rd shift that starts late night
    if (hour >= 22 && now.hour < 6) {
      // If it's past midnight but shift started yesterday
      shiftTime = shiftTime.subtract(const Duration(days: 1));
    }

    return shiftTime;
  }

  /// Get date string in yyyy-MM-dd format
  static String _getDateString(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Get day name from weekday number
  static String _getDayName(int weekday) {
    switch (weekday) {
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

  /// Manual trigger for testing
  static Future<void> triggerManualCheck() async {
    print('🔧 BACKGROUND: Manual check triggered');
    await checkAndMarkAbsentUsers();
  }
}
