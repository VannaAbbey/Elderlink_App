import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/cg_providers/absence_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'edit_profile.dart';
import 'leave_form.dart' as app_leave_form;
import 'add_task.dart';
import 'incident.dart';
import 'shift.dart';
import '../widgets/cg_widgets/notification_icon_button.dart';
import 'caregiver_bottom_navbar.dart';
import 'houses.dart';
import '../services/cg_services/house_service.dart';
import 'emergency_handler.dart';
import '../services/attendance_check_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:confetti/confetti.dart';

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CaregiverHomeScreen(),
    ),
  );
}

class CaregiverHomeScreen extends StatefulWidget {
  const CaregiverHomeScreen({super.key});

  @override
  State<CaregiverHomeScreen> createState() => _CaregiverHomeScreenState();
}

class _CaregiverHomeScreenState extends State<CaregiverHomeScreen> {
  bool _hasCheckedAttendance = false; // Track if attendance check was performed
  List<Map<String, dynamic>> _todaysBirthdays = []; // Store today's birthdays
  late ConfettiController _confettiController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Get assigned house for caregiver
  Future<Map<String, dynamic>?> getAssignedHouse() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final caregiverId = authProvider.currentUser?.uid;
    if (caregiverId == null) return null;
    final houseService = HouseService();
    return await houseService.getAssignedHouseForCaregiver(caregiverId);
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12
        ? hour - 12
        : hour == 0
        ? 12
        : hour;
    return '$hour12:$minute $ampm';
  }

  // Helper formatting functions for task dialog
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatTimeDialog(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // Convert 24-hour format to 12-hour format for shift schedule
  String _convertTo12HourFormat(String time24) {
    if (time24.isEmpty) return '';

    try {
      final parts = time24.split(':');
      if (parts.length < 2) return time24;

      final hour = int.parse(parts[0]);
      final minute = parts[1];

      if (hour == 0) {
        return '12:$minute AM';
      } else if (hour < 12) {
        return '$hour:$minute AM';
      } else if (hour == 12) {
        return '12:$minute PM';
      } else {
        return '${hour - 12}:$minute PM';
      }
    } catch (e) {
      return time24; // Return original if parsing fails
    }
  }

  // Get caregiver's status information from house_shift_assignments
  Future<Map<String, dynamic>?> getCaregiverStatus() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final caregiverId = authProvider.currentUser?.uid;
    if (caregiverId == null) return null;

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first.data();
      }
    } catch (e) {
      // Log error silently
    }
    return null;
  }

  // Show task details dialog similar to upcoming tasks screen
  void _showTaskDetailsDialog(BuildContext context, Map<String, dynamic> task) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 40,
          ),
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
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 25,
                          color: Color(0xFF22688E),
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
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
                      const Text(
                        'Name:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF22688E),
                        ),
                      ),
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
                      const Text(
                        'Activity:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF22688E),
                        ),
                      ),
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
                      const Text(
                        'Time:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF22688E),
                        ),
                      ),
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
                      const Text(
                        'Frequency:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF22688E),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          (() {
                            final freqList =
                                task['task_frequency'] as List<dynamic>? ?? [];
                            final freq = freqList.isNotEmpty
                                ? (freqList[0] is String
                                      ? freqList[0] as String
                                      : freqList[0].toString())
                                : 'Only once';
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
                              final customDays =
                                  task['custom_days'] as List<dynamic>? ?? [];
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
                      const Icon(
                        Icons.calendar_today,
                        color: Color(0xFF22688E),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Created:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF22688E),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        (() {
                          final created = task['created_at'];
                          if (created == null) return '';
                          if (created is DateTime) {
                            return '${_formatDate(created)} at ${_formatTimeDialog(created)}';
                          }
                          return created.toString();
                        })(),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    
    Future.microtask(() {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.refreshUserData();
    });
    
    // Check and show attendance dialog if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForBirthday(); // Check for birthdays on app start
      _checkAndShowAttendance();
    });
  }
  
  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }
  
  /// Check if caregiver should mark attendance and show dialog
  Future<void> _checkAndShowAttendance() async {
    // Skip if already checked this session
    if (_hasCheckedAttendance) return;

    try {
      print('🔍 CAREGIVER: Checking attendance conditions...');

      // Check if user is scheduled to work today
      final isScheduled = await AttendanceCheckService.isScheduledToday();
      print('📅 CAREGIVER: Is scheduled today: $isScheduled');

      if (!isScheduled) {
        print('⏭️ CAREGIVER: Not scheduled today, skipping attendance check');
        return;
      }

      // Check if at shift start time
      final isAtShiftStart = await AttendanceCheckService.isAtShiftStart();
      print('⏰ CAREGIVER: Is at shift start: $isAtShiftStart');

      if (!isAtShiftStart) {
        print('⏭️ CAREGIVER: Not at shift start time, skipping attendance check');
        return;
      }

      // Check if already marked attendance today
      final hasMarked = await AttendanceCheckService.hasMarkedAttendanceToday();
      print('✅ CAREGIVER: Already marked attendance: $hasMarked');

      if (hasMarked) {
        print('⏭️ CAREGIVER: Already marked attendance today, skipping');
        _hasCheckedAttendance = true;
        return;
      }

      // All conditions met - show attendance dialog
      print('🎯 CAREGIVER: All conditions met! Showing attendance dialog...');

      if (mounted) {
        await AttendanceCheckService.showAttendanceDialog(
          context,
          onDismissed: () {
            if (mounted) {
              setState(() {
                _hasCheckedAttendance = true;
              });
            }
          },
        );
      }
    } catch (e) {
      print('❌ CAREGIVER: Error checking attendance: $e');
    }
  }

  // ---------------------- BIRTHDAY FUNCTIONS ----------------------
  
  /// Get current shift based on time
  String _getCurrentShift() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 14) return '1st';
    if (hour >= 14 && hour < 22) return '2nd';
    return '3rd';
  }

  /// Get caregiver ID from auth
  Future<String?> _getCaregiverIdFromAuth() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    return authProvider.currentUser?.uid;
  }

  /// Check for birthdays of assigned elderly
  Future<void> _checkForBirthday() async {
    try {
      // 🧪 TEST MODE: Uncomment lines below to test UI with fake birthday data
      // setState(() => _todaysBirthdays = [
      //   {'id': 'test1', 'name': 'Lolo Test Juan', 'birthday': DateTime.now()},
      //   {'id': 'test2', 'name': 'Lola Test Maria', 'birthday': DateTime.now()},
      // ]);
      // final names = _todaysBirthdays.map((b) => b['name'] as String).toList();
      // await _showBirthdayDialog(names, 'birthday_test_${DateTime.now().day}', isManualTap: false);
      // return; // Comment this line to run actual birthday check
      // 🧪 END TEST MODE
      
      final caregiverId = await _getCaregiverIdFromAuth();
      if (caregiverId == null) {
        debugPrint('Birthday check: No caregiver ID found');
        return;
      }
      debugPrint('Birthday check: Caregiver ID = $caregiverId');

      final currentShift = _getCurrentShift();
      debugPrint('Birthday check: Current shift = $currentShift');

      // Get elderly_assignments for this caregiver (use elderly_assignments, not house_shift_assignments)
      // First try with all filters
      var assignQuery = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .get();

      debugPrint(
        'Birthday check: Found ${assignQuery.docs.length} assignment docs with full filters',
      );

      // If no results, try without shift filter
      if (assignQuery.docs.isEmpty) {
        debugPrint('Birthday check: Trying without shift filter...');
        assignQuery = await _firestore
            .collection('elderly_assignments')
            .where('user_id', isEqualTo: caregiverId)
            .where('user_type', isEqualTo: 'caregiver')
            .where('is_current', isEqualTo: true)
            .get();
        debugPrint(
          'Birthday check: Found ${assignQuery.docs.length} assignment docs without shift filter',
        );
      }

      // If still no results, try with just user_id and user_type
      if (assignQuery.docs.isEmpty) {
        debugPrint('Birthday check: Trying with minimal filters...');
        assignQuery = await _firestore
            .collection('elderly_assignments')
            .where('user_id', isEqualTo: caregiverId)
            .where('user_type', isEqualTo: 'caregiver')
            .get();
        debugPrint(
          'Birthday check: Found ${assignQuery.docs.length} assignment docs with minimal filters',
        );
      }

      if (assignQuery.docs.isEmpty) {
        debugPrint('Birthday check: No assignments found for caregiver');
        setState(() => _todaysBirthdays = []);
        return;
      }

      // Collect all elderly IDs from assignments
      final Set<String> elderlyIds = {};
      for (final doc in assignQuery.docs) {
        final data = doc.data();
        debugPrint('Birthday check: Assignment ${doc.id} full data: $data');
        debugPrint('Birthday check: Available keys: ${data.keys.toList()}');
        
        // Try different possible field names for elderly IDs
        List<String> ids = [];
        
        if (data['elderly_ids'] != null) {
          ids = List<String>.from(data['elderly_ids']);
          debugPrint('Birthday check: Found elderly_ids (array): $ids');
        } else if (data['elderlyIds'] != null) {
          ids = List<String>.from(data['elderlyIds']);
          debugPrint('Birthday check: Found elderlyIds (array): $ids');
        } else if (data['elderly_id'] != null) {
          ids = [data['elderly_id'] as String];
          debugPrint('Birthday check: Found elderly_id (single): $ids');
        } else {
          debugPrint('Birthday check: ⚠️ No elderly ID field found in this assignment!');
        }
        
        elderlyIds.addAll(ids);
        debugPrint('Birthday check: Assignment ${doc.id} contributed ${ids.length} elderly IDs');
      }

      debugPrint('Birthday check: Total elderly IDs: $elderlyIds');

      if (elderlyIds.isEmpty) {
        debugPrint('Birthday check: No elderly assigned to caregiver');
        setState(() => _todaysBirthdays = []);
        return;
      }

      // Query elderly for birthdays in chunks of 10
      final List<Map<String, dynamic>> birthdays = [];
      final elderlyList = elderlyIds.toList();
      for (var i = 0; i < elderlyList.length; i += 10) {
        final end = (i + 10 < elderlyList.length) ? i + 10 : elderlyList.length;
        final chunk = elderlyList.sublist(i, end);

        final elderlyQuery = await _firestore
            .collection('elderly')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        debugPrint(
          'Birthday check: Chunk ${i ~/ 10 + 1} - Found ${elderlyQuery.docs.length} elderly docs',
        );

        for (final doc in elderlyQuery.docs) {
          final data = doc.data();
          final birthday = data['elderly_bday'] ?? data['birthdate'];
          debugPrint(
            'Birthday check: Elderly ${doc.id} - ${data['elderly_fname']} ${data['elderly_lname']}, birthday: $birthday',
          );

          if (_isBirthdayToday(birthday)) {
            final gender = data['elderly_sex'] ?? 'male';
            debugPrint('Birthday check: Elderly ${doc.id} gender: $gender');
            final prefix = gender.toLowerCase().startsWith('f') ? 'Lola' : 'Lolo';
            final fullName = '$prefix ${data['elderly_fname']} ${data['elderly_lname']}';
            birthdays.add({
              'id': doc.id,
              'name': fullName,
              'birthday': birthday,
            });
            debugPrint('Birthday check: Today is $fullName\'s birthday!');
          } else {
            debugPrint(
              'Birthday check: Not birthday today for ${data['elderly_fname']} ${data['elderly_lname']}',
            );
          }
        }
      }

      setState(() => _todaysBirthdays = birthdays);
      if (birthdays.isNotEmpty) {
        final names = birthdays.map((b) => b['name'] as String).toList();
        final today = DateTime.now().toIso8601String().split('T')[0];
        final acknowledgedKey = 'birthday_acknowledged_all_$today';
        await _showBirthdayDialog(names, acknowledgedKey, isManualTap: false);
      }
    } catch (e) {
      debugPrint('Error checking for birthday: $e');
      setState(() => _todaysBirthdays = []);
    }
  }

  /// Check if a birthday is today
  bool _isBirthdayToday(dynamic birthday) {
    if (birthday == null) {
      debugPrint('Birthday check: Birthday is null');
      return false;
    }

    DateTime birthDate;
    if (birthday is Timestamp) {
      birthDate = birthday.toDate();
    } else if (birthday is DateTime) {
      birthDate = birthday;
    } else {
      debugPrint(
        'Birthday check: Birthday is not Timestamp or DateTime: $birthday (type: ${birthday.runtimeType})',
      );
      return false;
    }

    final now = DateTime.now();
    final isToday = birthDate.month == now.month && birthDate.day == now.day;
    debugPrint(
      'Birthday check: Birth date: ${birthDate.month}/${birthDate.day}, Today: ${now.month}/${now.day}, Is today: $isToday',
    );
    return isToday;
  }

  /// Show birthday dialog with confetti
  Future<void> _showBirthdayDialog(
    List<String> names,
    String acknowledgedKey, {
    bool isManualTap = false,
  }) async {
    // Check if already acknowledged (only for auto-show, not manual tap)
    if (!isManualTap) {
      final prefs = await SharedPreferences.getInstance();
      final alreadyAcknowledged = prefs.getBool(acknowledgedKey) ?? false;
      if (alreadyAcknowledged) {
        debugPrint('Birthday already acknowledged for today');
        return;
      }
    }

    _confettiController.play();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Stack(
          children: [
            // Confetti overlay
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                particleDrag: 0.05,
                emissionFrequency: 0.05,
                numberOfParticles: 50,
                gravity: 0.1,
                shouldLoop: false,
                colors: const [
                  Colors.red,
                  Colors.blue,
                  Colors.green,
                  Colors.yellow,
                  Colors.pink,
                  Colors.purple,
                  Colors.orange,
                ],
              ),
            ),
            // Birthday dialog
            AlertDialog(
              backgroundColor: Colors.transparent,
              contentPadding: EdgeInsets.zero,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 100),
              content: Container(
                constraints: const BoxConstraints(maxWidth: 380, minHeight: 300),
                decoration: BoxDecoration(
                  image: const DecorationImage(
                    image: AssetImage('assets/images/birthdaybg.png'),
                    fit: BoxFit.cover,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 100), // Space for background image top decoration
                      // Main content
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                          // Title with emojis
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Text(
                                '🎉 ',
                                style: TextStyle(fontSize: 28),
                              ),
                              Flexible(
                                child: Text(
                                  'Happy Birthday!',
                                  style: TextStyle(
                                    color: Color(0xFF0066A1),
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Poppins',
                                    fontSize: 26,
                                  ),
                                ),
                              ),
                              Text(
                                ' 🎂',
                                style: TextStyle(fontSize: 28),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Birthday message
                          Text(
                            names.length == 1
                                ? "Today is ${names[0]}'s birthday! 🎈🥳"
                                : names.length == 2
                                    ? "Today is ${names[0]} and ${names[1]}'s birthday! 🎈🥳"
                                    : "Today is ${names.sublist(0, names.length - 1).join(', ')} and ${names.last}'s birthday! 🎈🥳",
                            style: const TextStyle(
                              fontSize: 17,
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          // Warm message
                          const Text(
                            'Greet them with a warm hug and love.',
                            style: TextStyle(
                              fontSize: 15,
                              fontFamily: 'Poppins',
                              fontStyle: FontStyle.italic,
                              color: Colors.black54,
                              height: 1.3,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          // Emoji decorations
                          Wrap(
                            spacing: 12,
                            alignment: WrapAlignment.center,
                            children: const [
                              Text('🎂', style: TextStyle(fontSize: 28)),
                              Text('🍰', style: TextStyle(fontSize: 28)),
                              Text('🎈', style: TextStyle(fontSize: 28)),
                              Text('🥳', style: TextStyle(fontSize: 28)),
                              Text('🎊', style: TextStyle(fontSize: 28)),
                            ],
                          ),
                          const SizedBox(height: 32),
                          // Acknowledge button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0066A1),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 40,
                                  vertical: 16,
                                ),
                                elevation: 3,
                              ),
                              onPressed: () async {
                                // Mark as acknowledged
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setBool(acknowledgedKey, true);
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              },
                              child: const Text(
                                'Acknowledge 🎉',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Poppins',
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ), // End SingleChildScrollView
              ), // End Container (content)
            ), // End AlertDialog
          ],
        );
      },
    );
  }

  // ---------------------- END BIRTHDAY FUNCTIONS ----------------------

  // Helper to get upcoming tasks from AddTaskScreen logic with elderly profile pictures
  Stream<List<Map<String, dynamic>>> getUpcomingTasksStream() {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    final caregiverId = user?.uid;
    return FirebaseFirestore.instance
        .collection('care_tasks')
        .where('task_status', arrayContains: 'Upcoming')
        .where('caregiver_id', isEqualTo: caregiverId)
        .snapshots()
        .asyncMap((snapshot) async {
          final now = DateTime.now();
          List<Map<String, dynamic>> tasks = [];

          for (var doc in snapshot.docs) {
            final data = doc.data();
            final elderlyId = data['elderly_id'];

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
                  profilePicUrl =
                      elderlyData?['elderly_profilePic'] ??
                      elderlyData?['profile_pic'] ??
                      '';
                }
              } catch (e) {
                // Error fetching profile pic, continue with empty string
              }
            }

            final taskStart = (data['task_start'] is Timestamp)
                ? (data['task_start'] as Timestamp).toDate()
                : data['task_start'] as DateTime?;
            final taskDate = (data['task_date'] is Timestamp)
                ? (data['task_date'] as Timestamp).toDate()
                : data['task_date'] as DateTime?;

            // For recurring tasks, the actual execution date might be in task_date
            // For one-time tasks, it might be in task_start or freq_once_date
            final freqOnceDate = (data['freq_once_date'] is Timestamp)
                ? (data['freq_once_date'] as Timestamp).toDate()
                : data['freq_once_date'] as DateTime?;

            // Determine the actual scheduled execution date
            final effectiveDateTime = taskDate ?? taskStart ?? freqOnceDate;

            // Include tasks from today onwards (more inclusive approach for "Upcoming")
            // This allows caregivers to see tasks scheduled for today even if the specific time has passed
            bool shouldInclude = false;
            if (effectiveDateTime != null) {
              final taskDay = DateTime(effectiveDateTime.year, effectiveDateTime.month, effectiveDateTime.day);
              final currentDay = DateTime(now.year, now.month, now.day);
              
              // Include tasks from today onwards
              shouldInclude = taskDay.isAfter(currentDay) || taskDay.isAtSameMomentAs(currentDay);
            }

            if (shouldInclude) {
              tasks.add({
                // Basic task info for display
                'elderly_fname': data['elderly_fname'] ?? '',
                'task_description': data['task_description'] ?? '',
                'task_start': taskStart,
                'task_date': taskDate,
                'profile_pic': profilePicUrl,
                // Complete task data for dialog
                'task_id': doc.id,
                'task_end': (data['task_end'] is Timestamp)
                    ? (data['task_end'] as Timestamp).toDate()
                    : data['task_end'],
                'task_frequency': data['task_frequency'] ?? ['Only once'],
                'freq_once_date': (data['freq_once_date'] is Timestamp)
                    ? (data['freq_once_date'] as Timestamp).toDate()
                    : data['freq_once_date'],
                'custom_days': data['custom_days'] ?? [],
                'created_at': (data['created_at'] is Timestamp)
                    ? (data['created_at'] as Timestamp).toDate()
                    : data['created_at'],
                'task_status': data['task_status'] ?? [],
                'caregiver_id': data['caregiver_id'] ?? '',
                'elderly_id': data['elderly_id'] ?? '',
              });
            }
          }

          // Sort by task start time (chronological order - earliest first)
          // This matches the sorting logic in upcoming_tasks_screen.dart
          tasks.sort((a, b) {
            final aStart = a['task_start'] as DateTime? ?? DateTime.now();
            final bStart = b['task_start'] as DateTime? ?? DateTime.now();
            return aStart.compareTo(bStart);
          });
          return tasks;
        });
  }

  bool isSidebarOpen = false;
  int selectedIndex = 0;

  // Refresh handler for pull-to-refresh
  Future<void> _handleRefresh() async {
    // Trigger a rebuild by calling setState
    // This will cause all StreamBuilders and FutureBuilders to re-fetch data
    setState(() {});
    // Refresh birthdays
    await _checkForBirthday();
    // Add a small delay to ensure smooth refresh animation
    await Future.delayed(const Duration(milliseconds: 500));
  }

  void resetToHome() {
    setState(() {
      selectedIndex = 0;
    });
  }

  // Add the list of screens for navigation
  List<Widget> get _screens => [
    SizedBox.shrink(), // Home
    AddTaskScreen(onResetToHome: resetToHome),
    // Emergency is now a modal, not a screen
    IncidentScreen(onResetToHome: resetToHome),
    ShiftScreen(onResetToHome: resetToHome),
  ];

  void toggleSidebar() {
    setState(() {
      isSidebarOpen = !isSidebarOpen;
    });
  }

  void onNavTap(int index) {
    if (index == 2) {
      // Emergency button pressed, show modal
      openEmergencyIfAllowed(context);
      return;
    }
    setState(() {
      selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (isSidebarOpen) {
          setState(() => isSidebarOpen = false);
        }
      },
      child: Scaffold(
        body: selectedIndex == 0
            ? Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/background1.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: RefreshIndicator(
                        onRefresh: _handleRefresh,
                        color: const Color(0xFF00588e),
                        child: ListView(
                          children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Consumer<AuthProvider>(
                                    builder: (context, authProvider, child) {
                                      final profilePicUrl =
                                          authProvider.userProfilePic;
                                      return GestureDetector(
                                        onTap: toggleSidebar,
                                        child: CircleAvatar(
                                          radius: 24,
                                          backgroundColor: Colors.grey[200],
                                          child: ClipOval(
                                            child: profilePicUrl.isNotEmpty
                                                ? CachedNetworkImage(
                                                    imageUrl: profilePicUrl,
                                                    width: 48,
                                                    height: 48,
                                                    fit: BoxFit.cover,
                                                    placeholder: (context, url) =>
                                                        const CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                    errorWidget:
                                                        (
                                                          context,
                                                          url,
                                                          error,
                                                        ) => Image.asset(
                                                          'assets/images/people_icon.png',
                                                          width: 48,
                                                          height: 48,
                                                          fit: BoxFit.cover,
                                                        ),
                                                  )
                                                : Image.asset(
                                                    'assets/images/people_icon.png',
                                                    width: 48,
                                                    height: 48,
                                                    fit: BoxFit.cover,
                                                  ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Consumer<AuthProvider>(
                                        builder: (context, authProvider, child) {
                                          // Wait for user data to be loaded
                                          if (authProvider.userData == null) {
                                            return const Text(
                                              'Hello Caregiver,',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            );
                                          }

                                          final firstName =
                                              authProvider.userFirstName;
                                          // Ensure firstName is not empty or default
                                          final displayName =
                                              (firstName.isEmpty ||
                                                  firstName == 'User')
                                              ? ''
                                              : firstName;

                                          return Text(
                                            displayName.isEmpty
                                                ? 'Hello Caregiver,'
                                                : 'Hello Caregiver $displayName,',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          );
                                        },
                                      ),
                                      const Text('Hope you are doing well'),
                                    ],
                                  ),
                                ],
                              ),
                              const NotificationIconButton(),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Color(0x3EB7DDF5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: const [
                                Text(
                                  'Welcome to ElderLink!',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF00588E),
                                  ),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  'Manage your tasks, view your schedule, and stay connected with your elderly residents.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ✅ BIRTHDAY SECTION
                          _birthdaySection(),

                          // ✅ MODIFIED: Light blue background for "Upcoming Tasks"
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Color(0x3EB7DDF5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: const [
                                        Icon(
                                          Icons.task,
                                          color: Color(0xFF00588E),
                                          size: 45,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          "Upcoming Tasks",
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          selectedIndex =
                                              1; // 1 is the index for AddTaskScreen (Upcoming Tasks tab)
                                        });
                                      },
                                      child: const Text(
                                        "See All",
                                        style: TextStyle(
                                          color: Colors.blue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // Show first 3 upcoming tasks as cards
                                StreamBuilder<List<Map<String, dynamic>>>(
                                  stream: getUpcomingTasksStream(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    }
                                    final tasks = snapshot.data ?? [];
                                    if (tasks.isEmpty) {
                                      return const Center(
                                        child: Text('No upcoming tasks.'),
                                      );
                                    }
                                    return Column(
                                      children: tasks
                                          .take(3)
                                          .map(
                                            (task) => _taskCard(
                                              task['elderly_fname'] ?? '',
                                              task['task_description'] ?? '',
                                              task['task_start'] != null
                                                  ? (task['task_start']
                                                            is DateTime
                                                        ? _formatTime(
                                                            task['task_start'],
                                                          )
                                                        : task['task_start']
                                                              .toString())
                                                  : '',
                                              Color(0xFFB7DDF5),
                                              task['profile_pic'] ?? '',
                                              task, // Pass complete task data for dialog
                                            ),
                                          )
                                          .toList(),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 30),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Color(0x3EB7DDF5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(
                                      Icons.home,
                                      color: Color(0xFF00588E),
                                      size: 45,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      "Elderly Houses",
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                FutureBuilder<Map<String, dynamic>?>(
                                  future: getAssignedHouse(),
                                  builder: (context, snapshot) {
                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                HousesScreen(),
                                          ),
                                        );
                                      },
                                      child:
                                          snapshot.connectionState ==
                                              ConnectionState.waiting
                                          ? const Card(
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.all(
                                                  Radius.circular(16),
                                                ),
                                              ),
                                              color: Color(0xFFB7DDF5),
                                              child: Padding(
                                                padding: EdgeInsets.symmetric(
                                                  vertical: 18,
                                                  horizontal: 20,
                                                ),
                                                child: Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                              ),
                                            )
                                          : (snapshot.data == null
                                                ? Card(
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                    ),
                                                    color: const Color(
                                                      0xFFB7DDF5,
                                                    ),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 18,
                                                            horizontal: 20,
                                                          ),
                                                      child: Row(
                                                        children: const [
                                                          Icon(
                                                            Icons.home,
                                                            size: 50,
                                                            color: Color(
                                                              0xFF00588E,
                                                            ),
                                                          ),
                                                          SizedBox(width: 12),
                                                          Expanded(
                                                            child: Text(
                                                              'No house assigned',
                                                              style: TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Color(
                                                                  0xFF00588e,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  )
                                                : Card(
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                    ),
                                                    color: const Color(
                                                      0xFFB7DDF5,
                                                    ),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 18,
                                                            horizontal: 20,
                                                          ),
                                                      child: Row(
                                                        children: [
                                                          SizedBox(
                                                            width: 50,
                                                            height: 50,
                                                            child: Image.asset(
                                                              'assets/houses_img/${snapshot.data!['house_name'] ?? 'Unknown'}.png',
                                                              fit: BoxFit
                                                                  .contain,
                                                              errorBuilder:
                                                                  (
                                                                    context,
                                                                    error,
                                                                    stackTrace,
                                                                  ) => const Icon(
                                                                    Icons.home,
                                                                    size: 50,
                                                                    color: Color(
                                                                      0xFF00588E,
                                                                    ),
                                                                  ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 12,
                                                          ),
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  'House of ${snapshot.data!['house_name'] ?? 'Unknown'}',
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        16,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    color: Color(
                                                                      0xFF00588e,
                                                                    ),
                                                                  ),
                                                                ),
                                                                if (snapshot
                                                                        .data!['house_desc'] !=
                                                                    null)
                                                                  Padding(
                                                                    padding:
                                                                        const EdgeInsets.only(
                                                                          top:
                                                                              4,
                                                                        ),
                                                                    child: Text(
                                                                      snapshot
                                                                          .data!['house_desc'],
                                                                      style: const TextStyle(
                                                                        fontSize:
                                                                            14,
                                                                      ),
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  )),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 30),

                          // Your Status Section
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Color(0x3EB7DDF5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(
                                      Icons.accessibility,
                                      color: Color(0xFF00588E),
                                      size: 45,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      "Your Status",
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 15),

                                FutureBuilder<Map<String, dynamic>?>(
                                  future: getCaregiverStatus(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    }

                                    final statusData = snapshot.data;
                                    final daysAssigned =
                                        statusData?['days_assigned']
                                            as List<dynamic>? ??
                                        [];

                                    // Handle shift field - could be String or Map
                                    final shiftData = statusData?['shift'];
                                    final shift = shiftData is String
                                        ? shiftData
                                        : shiftData is Map<String, dynamic>
                                        ? (shiftData['name'] ??
                                              shiftData['shift_name'] ??
                                              'Not assigned')
                                        : 'Not assigned';

                                    // Handle start_time and end_time fields (NEW structure)
                                    final startTime = statusData?['start_time'] as String? ?? '';
                                    final endTime = statusData?['end_time'] as String? ?? '';
                                    
                                    final timeRange = (startTime.isNotEmpty && endTime.isNotEmpty)
                                        ? '${_convertTo12HourFormat(startTime)} - ${_convertTo12HourFormat(endTime)}'
                                        : 'Not specified';

                                    return Column(
                                      children: [
                                        // Current Work Schedule
                                        Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Color(0xFFB7DDF5),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Current Work Schedule',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF00588E),
                                                ),
                                              ),
                                              const SizedBox(height: 15),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceEvenly,
                                                children: [
                                                  for (int i = 0; i < 7; i++)
                                                    Column(
                                                      children: [
                                                        Container(
                                                          width: 32,
                                                          height: 32,
                                                          decoration: BoxDecoration(
                                                            shape:
                                                                BoxShape.circle,
                                                            color:
                                                                daysAssigned.contains(
                                                                  [
                                                                    'Sunday',
                                                                    'Monday',
                                                                    'Tuesday',
                                                                    'Wednesday',
                                                                    'Thursday',
                                                                    'Friday',
                                                                    'Saturday',
                                                                  ][i],
                                                                )
                                                                ? Color(
                                                                    0xFF00588E,
                                                                  )
                                                                : Colors
                                                                      .grey
                                                                      .shade300,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          [
                                                            'Sun',
                                                            'Mon',
                                                            'Tue',
                                                            'Wed',
                                                            'Thu',
                                                            'Fri',
                                                            'Sat',
                                                          ][i],
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color: Color(
                                                              0xFF00588E,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        const SizedBox(height: 15),

                                        // Current Shift Schedule
                                        Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Color(0xFFB7DDF5),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.access_time,
                                                color: Color(0xFF00588E),
                                                size: 70,
                                              ),
                                              const SizedBox(width: 20),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    const Text(
                                                      'Current Shift Schedule',
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Color(
                                                          0xFF00588E,
                                                        ),
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      '${shift.toUpperCase()} SHIFT',
                                                      style: TextStyle(
                                                        fontSize: 24,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Color(
                                                          0xFF00588E,
                                                        ),
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      timeRange,
                                                      style: TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Color(
                                                          0xFF00588E,
                                                        ),
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        
                                        const SizedBox(height: 15),
                                        
                                        // Absence Status & Temporary Assignments
                                        Consumer<AbsenceProvider>(
                                          builder: (context, absenceProvider, child) {
                                            // Show absence status if absent
                                            if (absenceProvider.isAbsentToday) {
                                              return Container(
                                                padding: const EdgeInsets.all(16),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange[100],
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: Colors.orange,
                                                    width: 2,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      absenceProvider.absenceType == 'leave'
                                                          ? Icons.event_busy
                                                          : Icons.cancel_outlined,
                                                      color: Colors.orange,
                                                      size: 40,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: const [
                                                          Text(
                                                            'Not Present at Work',
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight: FontWeight.bold,
                                                              color: Colors.black87,
                                                            ),
                                                          ),
                                                          SizedBox(height: 4),
                                                          Text(
                                                            'You are marked absent/on leave for today',
                                                            style: TextStyle(
                                                              fontSize: 14,
                                                              color: Colors.black54,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                            
                                            // Show temporary assignments if any
                                            final tempCount = absenceProvider.temporaryElderlyIds.length;
                                            print('🏠 Home.dart: Temporary elderly count = $tempCount');
                                            print('🏠 Home.dart: hasTemporaryAssignments = ${absenceProvider.hasTemporaryAssignments}');
                                            
                                            if (absenceProvider.hasTemporaryAssignments && tempCount > 0) {
                                              return Container(
                                                padding: const EdgeInsets.all(16),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue[50],
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: Colors.blue,
                                                    width: 2,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.people,
                                                      color: Colors.blue,
                                                      size: 40,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          const Text(
                                                            'Temporary Assignments',
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight: FontWeight.bold,
                                                              color: Colors.black87,
                                                            ),
                                                          ),
                                                          const SizedBox(height: 4),
                                                          Text(
                                                            'You have ${absenceProvider.temporaryElderlyIds.length} temporary elderly today',
                                                            style: const TextStyle(
                                                              fontSize: 14,
                                                              color: Colors.black54,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                            
                                            // Check if caregiver is scheduled for today
                                            final now = DateTime.now();
                                            final daysOfWeek = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
                                            final todayName = daysOfWeek[now.weekday % 7]; // Convert weekday to day name
                                            final isScheduledToday = daysAssigned.contains(todayName);
                                            
                                            // Show not on duty status if not scheduled for today
                                            if (!isScheduledToday) {
                                              return Container(
                                                padding: const EdgeInsets.all(16),
                                                decoration: BoxDecoration(
                                                  color: Colors.red[50],
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: Colors.red,
                                                    width: 2,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: const [
                                                    Icon(
                                                      Icons.event_busy,
                                                      color: Colors.red,
                                                      size: 40,
                                                    ),
                                                    SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            'Not On Duty',
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight: FontWeight.bold,
                                                              color: Colors.black87,
                                                            ),
                                                          ),
                                                          SizedBox(height: 4),
                                                          Text(
                                                            'You are not on duty for today',
                                                            style: TextStyle(
                                                              fontSize: 14,
                                                              color: Colors.black54,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                            
                                            // Check if shift has started or ended
                                            bool shiftNotStarted = false;
                                            bool shiftEnded = false;
                                            
                                            if (startTime.isNotEmpty && endTime.isNotEmpty) {
                                              try {
                                                final now = DateTime.now();
                                                
                                                // Parse shift times
                                                final startParts = startTime.split(':');
                                                final shiftStartHour = int.parse(startParts[0]);
                                                final shiftStartMinute = int.parse(startParts[1]);
                                                
                                                final endParts = endTime.split(':');
                                                final shiftEndHour = int.parse(endParts[0]);
                                                final shiftEndMinute = int.parse(endParts[1]);
                                                
                                                DateTime shiftStartDateTime = DateTime(
                                                  now.year,
                                                  now.month,
                                                  now.day,
                                                  shiftStartHour,
                                                  shiftStartMinute,
                                                );
                                                
                                                DateTime shiftEndDateTime = DateTime(
                                                  now.year,
                                                  now.month,
                                                  now.day,
                                                  shiftEndHour,
                                                  shiftEndMinute,
                                                );
                                                
                                                // Determine if it's an overnight shift
                                                final isOvernightShift = shiftEndHour < shiftStartHour || 
                                                    (shiftEndHour == shiftStartHour && shiftEndMinute <= shiftStartMinute);
                                                
                                                if (isOvernightShift) {
                                                  // Overnight shift logic
                                                  if (now.hour < shiftEndHour || (now.hour == shiftEndHour && now.minute < shiftEndMinute)) {
                                                    // Current time is in the "end period" (before shift end) - shift is active
                                                    shiftNotStarted = false;
                                                    shiftEnded = false;
                                                  } else if (now.hour >= shiftStartHour || (now.hour == shiftStartHour && now.minute >= shiftStartMinute)) {
                                                    // Current time is in the "start period" (after shift start) - shift is active
                                                    shiftNotStarted = false;
                                                    shiftEnded = false;
                                                  } else {
                                                    // Time is between end and start
                                                    // Check if we're before start or after end
                                                    if (now.hour < shiftStartHour) {
                                                      shiftNotStarted = true;
                                                      shiftEnded = false;
                                                    } else {
                                                      shiftNotStarted = false;
                                                      shiftEnded = true;
                                                    }
                                                  }
                                                } else {
                                                  // Regular shift (not overnight)
                                                  if (now.isBefore(shiftStartDateTime)) {
                                                    shiftNotStarted = true;
                                                    shiftEnded = false;
                                                  } else if (now.isAfter(shiftEndDateTime)) {
                                                    shiftNotStarted = false;
                                                    shiftEnded = true;
                                                  } else {
                                                    // Currently within shift hours
                                                    shiftNotStarted = false;
                                                    shiftEnded = false;
                                                  }
                                                }
                                              } catch (e) {
                                                print('Error checking shift times: $e');
                                                shiftNotStarted = false;
                                                shiftEnded = false;
                                              }
                                            }
                                            
                                            // Show shift not started status
                                            if (shiftNotStarted) {
                                              return Container(
                                                padding: const EdgeInsets.all(16),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber[50],
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: Colors.amber,
                                                    width: 2,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: const [
                                                    Icon(
                                                      Icons.schedule,
                                                      color: Colors.amber,
                                                      size: 40,
                                                    ),
                                                    SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            'Shift Not Started',
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight: FontWeight.bold,
                                                              color: Colors.black87,
                                                            ),
                                                          ),
                                                          SizedBox(height: 4),
                                                          Text(
                                                            'Your shift hasn\'t started yet for today',
                                                            style: TextStyle(
                                                              fontSize: 14,
                                                              color: Colors.black54,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                            
                                            // Show shift ended status
                                            if (shiftEnded) {
                                              return Container(
                                                padding: const EdgeInsets.all(16),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey[200],
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: Colors.grey,
                                                    width: 2,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: const [
                                                    Icon(
                                                      Icons.work_off,
                                                      color: Colors.grey,
                                                      size: 40,
                                                    ),
                                                    SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            'Shift Ended',
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight: FontWeight.bold,
                                                              color: Colors.black87,
                                                            ),
                                                          ),
                                                          SizedBox(height: 4),
                                                          Text(
                                                            'Your shift has ended for today',
                                                            style: TextStyle(
                                                              fontSize: 14,
                                                              color: Colors.black54,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                            
                                            // Show normal status (on duty)
                                            return Container(
                                              padding: const EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                color: Colors.green[50],
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.green,
                                                  width: 2,
                                                ),
                                              ),
                                              child: Row(
                                                children: const [
                                                  Icon(
                                                    Icons.check_circle,
                                                    color: Colors.green,
                                                    size: 40,
                                                  ),
                                                  SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          'On Duty',
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            fontWeight: FontWeight.bold,
                                                            color: Colors.black87,
                                                          ),
                                                        ),
                                                        SizedBox(height: 4),
                                                        Text(
                                                          'You are on duty today',
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            color: Colors.black54,
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
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                        ),
                      ),
                    ),
                  ),

                  CaregiverSidebar(
                    onLogout: () async {
                      final authProvider = Provider.of<AuthProvider>(
                        context,
                        listen: false,
                      );
                      await authProvider.signOut();
                      if (mounted) {
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/get_started',
                          (route) => false,
                        );
                      }
                    },
                    isSidebarOpen: isSidebarOpen,
                    toggleSidebar: toggleSidebar,
                    parentContext: context,
                  ),
                ],
              )
            : _screens[selectedIndex > 2 ? selectedIndex - 1 : selectedIndex],
        bottomNavigationBar: CaregiverBottomNavBar(
          selectedIndex: selectedIndex,
          onNavTap: onNavTap,
        ),
      ),
    );
  }

  // ---------------------- BIRTHDAY SECTION WIDGET ----------------------
  Widget _birthdaySection() {
    if (_todaysBirthdays.isEmpty) {
      return const SizedBox.shrink(); // Don't show section if no birthdays
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFE4E1), // Light pink background for birthday
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(
                    Icons.cake,
                    color: Color(0xFFFF6B35), // Orange color for birthday
                    size: 45,
                  ),
                  SizedBox(width: 8),
                  Text(
                    "Today's Birthdays",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF6B35),
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  final names = _todaysBirthdays
                      .map((b) => b['name'] as String)
                      .toList();
                  final today = DateTime.now().toIso8601String().split('T')[0];
                  final acknowledgedKey = 'birthday_acknowledged_all_$today';
                  _showBirthdayDialog(names, acknowledgedKey, isManualTap: true);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '🎂 Happy Birthday! 🎉',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF6B35),
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ),
                          Icon(
                            Icons.celebration,
                            color: Color(0xFFFF6B35),
                            size: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._todaysBirthdays.map((birthday) {
                        final name = birthday['name'] as String;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Poppins',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
  // ---------------------- END BIRTHDAY SECTION WIDGET ----------------------

  Widget _taskCard(
    String name,
    String task,
    String time,
    Color bgColor,
    String profilePicUrl,
    Map<String, dynamic> taskData,
  ) {
    return GestureDetector(
      onTap: () => _showTaskDetailsDialog(context, taskData),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: Colors.grey[200],
              child: ClipOval(
                child: profilePicUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: profilePicUrl,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 50,
                          height: 50,
                          color: Colors.grey[300],
                          child: const Icon(
                            Icons.person,
                            color: Colors.grey,
                            size: 25,
                          ),
                        ),
                        errorWidget: (context, url, error) => Image.asset(
                          'assets/images/people_icon.png',
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Image.asset(
                        'assets/images/people_icon.png',
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    task,
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10), // Add spacing between text and time
            Text(time, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// Move CaregiverSidebar to top-level
class CaregiverSidebar extends StatelessWidget {
  final VoidCallback onLogout;
  final bool isSidebarOpen;
  final VoidCallback toggleSidebar;
  final BuildContext parentContext;

  const CaregiverSidebar({
    required this.onLogout,
    required this.isSidebarOpen,
    required this.toggleSidebar,
    required this.parentContext,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!isSidebarOpen) return SizedBox.shrink();
    return Stack(
      children: [
        GestureDetector(
          onTap: toggleSidebar,
          child: Container(color: Colors.black54),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          child: Material(
            elevation: 5,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(10),
              bottomRight: Radius.circular(10),
            ),
            child: Container(
              width: 250,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 50),
                  Center(
                    child: Consumer<AuthProvider>(
                      builder: (context, authProvider, child) {
                        if (authProvider.userData == null) {
                          return const Text(
                            'Caregiver',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                              fontFamily: 'Poppins',
                            ),
                          );
                        }
                        final firstName = authProvider.userFirstName;
                        final displayName =
                            (firstName.isEmpty || firstName == 'User')
                            ? ''
                            : firstName;
                        return Text(
                          displayName.isEmpty
                              ? 'Caregiver'
                              : 'Caregiver $displayName',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            fontFamily: 'Poppins',
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(Icons.edit, color: Color(0xFF00588e)),
                    title: Text('Edit Profile'),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(
                        parentContext,
                        MaterialPageRoute(
                          builder: (context) => const EditProfile(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.calendar_today,
                      color: Color(0xFF00588e),
                    ),
                    title: Text('Request Leave'),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(
                        parentContext,
                        MaterialPageRoute(
                          builder: (context) =>
                              const app_leave_form.LeaveForm(),
                        ),
                      );
                    },
                  ),
                  // Help & Support removed
                  const Divider(),
                  const SizedBox(height: 20),
                  Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D5B78),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 60,
                        ),
                      ),
                      onPressed: onLogout,
                      child: const Text(
                        'LOGOUT',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
