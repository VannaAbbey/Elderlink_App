import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

/// 📋 ATTENDANCE CHECK SERVICE
/// ===========================
///
/// Service to manage attendance check functionality for nurses and caregivers
///
/// **Key Features:**
/// - ✅ Automatic attendance dialog at shift start (15-min window)
/// - ⏰ Auto-mark absent after 15 minutes of no response
/// - 👥 Works for both nurses and caregivers
/// - 🔒 Modal dialog (cannot dismiss until answered)
/// - 📊 Records attendance to Firestore
///
/// **Shift Times:**
/// - 1st Shift: 6:00 AM - 2:00 PM
/// - 2nd Shift: 2:00 PM - 10:00 PM
/// - 3rd Shift: 10:00 PM - 6:00 AM
///
/// **How to Use:**
/// ```dart
/// // In your home screen's initState:
/// WidgetsBinding.instance.addPostFrameCallback((_) {
///   _checkAndShowAttendance();
/// });
///
/// Future<void> _checkAndShowAttendance() async {
///   if (_hasCheckedAttendance) return;
///
///   final scheduled = await AttendanceCheckService.isScheduledToday();
///   final atShiftStart = await AttendanceCheckService.isAtShiftStart();
///   final alreadyMarked = await AttendanceCheckService.hasMarkedAttendanceToday();
///
///   if (scheduled && atShiftStart && !alreadyMarked) {
///     if (mounted) {
///       await AttendanceCheckService.showAttendanceDialog(
///         context: context,
///         onDismissed: () => setState(() => _hasCheckedAttendance = true),
///       );
///     }
///   }
/// }
/// ```
class AttendanceCheckService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Timer? _attendanceTimer;
  static Timer?
  _periodicCheckTimer; // Timer to periodically check for shift start
  static bool _isDialogShown = false;
  static DateTime? _dialogShowTime; // Track when dialog was first shown

  /// Determines the current shift based on current time
  /// Returns: "1st", "2nd", or "3rd"
  static String getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

  /// Gets the start time for a given shift
  /// Returns: Time in HH:mm format (e.g., "06:00", "14:00", "22:00")
  static String getShiftStartTime(String shift) {
    switch (shift) {
      case "1st":
        return "06:00";
      case "2nd":
        return "14:00";
      case "3rd":
        return "22:00";
      default:
        return "06:00";
    }
  }

  /// Gets the end time for a given shift
  /// Returns: Time in HH:mm format
  static String getShiftEndTime(String shift) {
    switch (shift) {
      case "1st":
        return "14:00";
      case "2nd":
        return "22:00";
      case "3rd":
        return "06:00";
      default:
        return "14:00";
    }
  }

  /// Checks if it's the start of the user's shift
  /// Returns true if within 15 minutes of shift start
  static Future<bool> isAtShiftStart() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('🔴 ATTENDANCE: No user logged in');
        return false;
      }

      final now = DateTime.now();
      print('🔍 ATTENDANCE: Checking shift start at ${now.toString()}');

      // Get user's house assignment
      final houseSnapshot = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: currentUser.uid)
          .where('is_current', isEqualTo: true)
          .limit(1)
          .get();

      if (houseSnapshot.docs.isEmpty) {
        print('🔴 ATTENDANCE: No house assignment found');
        return false;
      }

      final houseData = houseSnapshot.docs.first.data();
      final startTime = houseData['start_time'] as String?;

      if (startTime == null || startTime.isEmpty) {
        print('🔴 ATTENDANCE: No start time found in assignment');
        return false;
      }

      // Parse shift start time
      final timeParts = startTime.split(':');
      final shiftStartHour = int.parse(timeParts[0]);
      final shiftStartMinute = int.parse(timeParts[1]);

      // Create DateTime for shift start
      final shiftStart = DateTime(
        now.year,
        now.month,
        now.day,
        shiftStartHour,
        shiftStartMinute,
      );

      // Check if current time is within 15 minutes of shift start
      // (from shift start to 15 minutes after)
      final timeDifference = now.difference(shiftStart);
      final isWithinWindow =
          timeDifference.inMinutes >= 0 && timeDifference.inMinutes <= 15;

      print('🔍 ATTENDANCE: Shift starts at $shiftStart');
      print(
        '🔍 ATTENDANCE: Time difference: ${timeDifference.inMinutes} minutes',
      );
      print('🔍 ATTENDANCE: Within window: $isWithinWindow');

      return isWithinWindow;
    } catch (e) {
      print('🔴 ATTENDANCE Error checking shift start: $e');
      return false;
    }
  }

  /// Checks if user should be on duty today based on their schedule
  static Future<bool> isScheduledToday() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      // ⚠️ TEMPORARY FOR TESTING - BYPASS SCHEDULE CHECK ⚠️
      // TODO: Remove this after adding proper schedule data to Firestore!
      print('⚠️ ATTENDANCE: BYPASSING SCHEDULE CHECK FOR TESTING');
      return true;

      // ORIGINAL CODE BELOW - Uncomment after testing:
      /*
      final now = DateTime.now();

      // Get user's house assignment
      final houseSnapshot = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: currentUser.uid)
          .where('is_current', isEqualTo: true)
          .limit(1)
          .get();

      if (houseSnapshot.docs.isEmpty) {
        print('🔴 ATTENDANCE: No house assignment found for user ${currentUser.uid}');
        return false;
      }

      final houseData = houseSnapshot.docs.first.data();
      final daysAssigned = List<String>.from(houseData['days_assigned'] ?? []);

      // Get current day name
      final currentDay = _getDayName(now.weekday);
      
      print('📅 ATTENDANCE: Today is $currentDay, assigned days: $daysAssigned');

      // Check if today is in assigned days
      return daysAssigned.contains(currentDay);
      */
    } catch (e) {
      print('🔴 ATTENDANCE Error checking schedule: $e');
      return false;
    }
  }

  /// Records attendance in Firestore
  static Future<void> recordAttendance({
    required bool isPresent,
    String? reason,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('🔴 ATTENDANCE: Cannot record - no user logged in');
        return;
      }

      final now = DateTime.now();
      final dateString = _getDateString(now);

      // Get user data to determine type
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        print('🔴 ATTENDANCE: User document not found');
        return;
      }

      final userData = userDoc.data()!;
      final userType = userData['user_type'] as String?;
      final shift = getCurrentShift();

      // Create attendance record
      final attendanceData = {
        'user_id': currentUser.uid,
        'user_type': userType ?? 'unknown',
        'date': dateString,
        'shift': shift,
        'is_present': isPresent,
        'timestamp': FieldValue.serverTimestamp(),
        'reason': reason ?? '',
        'marked_by': 'system', // Can be 'user' or 'system' (auto-absent)
      };

      // Save to attendance collection
      await _firestore.collection('attendance').add(attendanceData);

      print('✅ ATTENDANCE: Recorded - Present: $isPresent, Shift: $shift');
    } catch (e) {
      print('🔴 ATTENDANCE Error recording attendance: $e');
      rethrow;
    }
  }

  /// Checks if user has already marked attendance for today's shift
  static Future<bool> hasMarkedAttendanceToday() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      final now = DateTime.now();
      final dateString = _getDateString(now);
      final shift = getCurrentShift();

      final attendanceQuery = await _firestore
          .collection('attendance')
          .where('user_id', isEqualTo: currentUser.uid)
          .where('date', isEqualTo: dateString)
          .where('shift', isEqualTo: shift)
          .limit(1)
          .get();

      final hasMarked = attendanceQuery.docs.isNotEmpty;
      print('🔍 ATTENDANCE: Already marked for today: $hasMarked');

      return hasMarked;
    } catch (e) {
      print('🔴 ATTENDANCE Error checking attendance: $e');
      return false;
    }
  }

  /// Shows the attendance check dialog
  static Future<void> showAttendanceDialog(
    BuildContext context, {
    required VoidCallback onDismissed,
  }) async {
    if (_isDialogShown) {
      print('⚠️ ATTENDANCE: Dialog already shown');
      return;
    }

    // Check if dialog was shown before and 15 minutes already elapsed
    if (_dialogShowTime != null) {
      final elapsed = DateTime.now().difference(_dialogShowTime!);
      if (elapsed.inMinutes >= 15) {
        print(
          '⏰ ATTENDANCE: 15 minutes already elapsed - auto-marking as absent',
        );
        await recordAttendance(
          isPresent: false,
          reason: 'Auto-marked absent - no response within 15 minutes',
        );
        _dialogShowTime = null;
        _isDialogShown = false;
        onDismissed();
        return;
      }
    }

    // Set the time when dialog is first shown
    _dialogShowTime ??= DateTime.now();
    _isDialogShown = true;

    // Start 15-minute timer for auto-absent
    _startAutoAbsentTimer(context, onDismissed);

    try {
      await showDialog(
        context: context,
        barrierDismissible: false, // Prevent dismissing by tapping outside
        builder: (BuildContext dialogContext) {
          return WillPopScope(
            onWillPop: () async => false, // Prevent back button
            child: AttendanceCheckDialog(
              onAttendanceMarked: () {
                _cancelAutoAbsentTimer();
                _dialogShowTime = null; // Reset the show time
                _isDialogShown = false;
                onDismissed();
              },
            ),
          );
        },
      );
    } catch (e) {
      print('🔴 ATTENDANCE Error showing dialog: $e');
      _isDialogShown = false;
      _cancelAutoAbsentTimer();
    }
  }

  /// Starts a 15-minute timer that auto-marks user as absent
  static void _startAutoAbsentTimer(
    BuildContext context,
    VoidCallback onDismissed,
  ) {
    _cancelAutoAbsentTimer(); // Cancel any existing timer

    print('⏱️ ATTENDANCE: Starting 15-minute auto-absent timer');

    _attendanceTimer = Timer(const Duration(minutes: 15), () async {
      print('⏰ ATTENDANCE: 15 minutes elapsed - auto-marking as absent');

      // Record as absent
      await recordAttendance(
        isPresent: false,
        reason: 'Auto-marked absent - no response within 15 minutes',
      );

      // Reset dialog show time
      _dialogShowTime = null;

      // Close dialog if still showing
      if (_isDialogShown && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _isDialogShown = false;

        // Show notification that they were marked absent
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ You have been marked as absent for not responding within 15 minutes',
              style: TextStyle(fontSize: 16),
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }

      onDismissed();
    });
  }

  /// Cancels the auto-absent timer
  static void _cancelAutoAbsentTimer() {
    if (_attendanceTimer != null && _attendanceTimer!.isActive) {
      _attendanceTimer!.cancel();
      print('🛑 ATTENDANCE: Auto-absent timer cancelled');
    }
    _attendanceTimer = null;
  }

  /// Resets the dialog shown flag (for testing or manual reset)
  static void resetDialogState() {
    _isDialogShown = false;
    _dialogShowTime = null;
    _cancelAutoAbsentTimer();
  }

  /// Starts a periodic timer to check for shift start every minute
  /// This ensures attendance dialog appears automatically when shift time arrives
  /// Call this from initState of nurse/caregiver home screens
  static void startPeriodicAttendanceCheck(
    BuildContext context,
    VoidCallback onAttendanceChecked,
  ) {
    // Cancel any existing timer
    stopPeriodicAttendanceCheck();

    print('🔄 ATTENDANCE: Starting periodic attendance check (every minute)');

    // Check immediately
    _performPeriodicAttendanceCheck(context, onAttendanceChecked);

    // Then check every minute
    _periodicCheckTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _performPeriodicAttendanceCheck(context, onAttendanceChecked);
    });
  }

  /// Performs the periodic attendance check
  static Future<void> _performPeriodicAttendanceCheck(
    BuildContext context,
    VoidCallback onAttendanceChecked,
  ) async {
    try {
      // Skip if dialog already shown
      if (_isDialogShown) return;

      // Check if user is scheduled to work today
      final isScheduled = await isScheduledToday();
      if (!isScheduled) return;

      // Check if at shift start time
      final atShiftStart = await isAtShiftStart();
      if (!atShiftStart) return;

      // Check if already marked attendance today
      final hasMarked = await hasMarkedAttendanceToday();
      if (hasMarked) {
        // Stop checking if already marked
        stopPeriodicAttendanceCheck();
        return;
      }

      // All conditions met - show attendance dialog
      print('🎯 ATTENDANCE: Conditions met! Auto-showing attendance dialog...');

      if (context.mounted) {
        await showAttendanceDialog(
          context,
          onDismissed: () {
            onAttendanceChecked();
            // Stop periodic checks after attendance is marked
            stopPeriodicAttendanceCheck();
          },
        );
      }
    } catch (e) {
      print('❌ ATTENDANCE: Error in periodic check: $e');
    }
  }

  /// Stops the periodic attendance check timer
  /// Call this from dispose of nurse/caregiver home screens
  static void stopPeriodicAttendanceCheck() {
    if (_periodicCheckTimer != null && _periodicCheckTimer!.isActive) {
      _periodicCheckTimer!.cancel();
      print('🛑 ATTENDANCE: Stopped periodic attendance check');
    }
    _periodicCheckTimer = null;
  }

  /// Helper: Get date string in yyyy-MM-dd format
  static String _getDateString(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Helper: Get day name from weekday number
  /// Currently unused but needed when schedule checking is enabled
  // ignore: unused_element
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
}

/// Widget for the attendance check dialog
class AttendanceCheckDialog extends StatefulWidget {
  final VoidCallback onAttendanceMarked;

  const AttendanceCheckDialog({super.key, required this.onAttendanceMarked});

  @override
  State<AttendanceCheckDialog> createState() => _AttendanceCheckDialogState();
}

class _AttendanceCheckDialogState extends State<AttendanceCheckDialog> {
  bool _isLoading = false;
  int _remainingSeconds = 15 * 60; // 15 minutes in seconds
  Timer? _countdownTimer;
  bool _showAbsentReason = false;
  String? _selectedReason;
  final TextEditingController _customReasonController = TextEditingController();

  // Common absence reasons
  final List<String> _absentReasons = [
    'Sick/Not feeling well',
    'Family emergency',
    'Transportation issue',
    'Personal matter',
    'Other (specify below)',
  ];

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _customReasonController.dispose();
    super.dispose();
  }

  /// Starts the countdown timer display
  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  /// Formats remaining time as MM:SS
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// Handles attendance marking
  Future<void> _markAttendance(bool isPresent) async {
    if (_isLoading) return;

    // If marking absent, show reason selection first
    if (!isPresent && !_showAbsentReason) {
      setState(() {
        _showAbsentReason = true;
      });
      return;
    }

    // Validate reason if absent
    if (!isPresent) {
      if (_selectedReason == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a reason for absence'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // If "Other" is selected, require custom reason
      if (_selectedReason == 'Other (specify below)' &&
          _customReasonController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please specify your reason'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Determine the reason text
      String reason;
      if (isPresent) {
        reason = 'Marked present at shift start';
      } else {
        if (_selectedReason == 'Other (specify below)') {
          reason = _customReasonController.text.trim();
        } else {
          reason = _selectedReason!;
        }
      }

      await AttendanceCheckService.recordAttendance(
        isPresent: isPresent,
        reason: reason,
      );

      if (mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPresent
                  ? '✅ Attendance marked - You are present for your shift'
                  : '⚠️ You have been marked as absent',
              style: const TextStyle(fontSize: 16),
            ),
            backgroundColor: isPresent ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );

        // Close dialog
        Navigator.of(context).pop();
        widget.onAttendanceMarked();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error marking attendance: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shift = AttendanceCheckService.getCurrentShift();
    final shiftName = shift == "1st"
        ? "1st Shift (6:00 AM - 2:00 PM)"
        : shift == "2nd"
        ? "2nd Shift (2:00 PM - 10:00 PM)"
        : "3rd Shift (10:00 PM - 6:00 AM)";

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 350,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFB3E0E8),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.access_time_filled,
                  size: 50,
                  color: Color(0xFF00588E),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              const Text(
                'Attendance Check',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00588E),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Shift Info
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F4F8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  shiftName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF00588E),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),

              // Message
              const Text(
                'Please confirm your attendance for your shift today.',
                style: TextStyle(fontSize: 16, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Timer Display
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _remainingSeconds <= 60
                      ? Colors.red.withOpacity(0.1)
                      : const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _remainingSeconds <= 60 ? Colors.red : Colors.orange,
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      color: _remainingSeconds <= 60
                          ? Colors.red
                          : Colors.orange,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Time remaining: ${_formatTime(_remainingSeconds)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _remainingSeconds <= 60
                            ? Colors.red
                            : Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Auto-marked absent if no response',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Buttons or Reason Selection
              if (_isLoading)
                const CircularProgressIndicator(color: Color(0xFF00588E))
              else if (_showAbsentReason)
                // Absent Reason Selection
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Please select a reason for absence:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF00588E),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Reason Dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          hint: const Text('Select reason'),
                          value: _selectedReason,
                          items: _absentReasons.map((String reason) {
                            return DropdownMenuItem<String>(
                              value: reason,
                              child: Text(reason),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedReason = newValue;
                            });
                          },
                        ),
                      ),
                    ),

                    // Custom Reason TextField (if "Other" selected)
                    if (_selectedReason == 'Other (specify below)') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _customReasonController,
                        decoration: InputDecoration(
                          hintText: 'Enter your reason here...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        maxLines: 2,
                        maxLength: 100,
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Action Buttons
                    Row(
                      children: [
                        // Back Button
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _showAbsentReason = false;
                                _selectedReason = null;
                                _customReasonController.clear();
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: const BorderSide(color: Colors.grey),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Back',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Confirm Button
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () => _markAttendance(false),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 3,
                            ),
                            child: const Text(
                              'Confirm Absent',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    // Present Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => _markAttendance(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF22688E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 3,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.white,
                              size: 24,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'I am Present',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Absent Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => _markAttendance(false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 3,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cancel, color: Colors.white, size: 24),
                            SizedBox(width: 8),
                            Text(
                              'I am Absent',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
