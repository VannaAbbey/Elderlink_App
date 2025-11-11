import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'caregiver_sidebar.dart';
import '../providers/auth_provider.dart';
import '../providers/cg_providers/absence_provider.dart';
import '../widgets/cg_widgets/notification_icon_button.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/cg_services/house_service.dart';
import 'upcoming_tasks_screen.dart';
import 'complete_tasks_screen.dart';
import 'incomplete_tasks_screen.dart';
import 'missed_tasks_screen.dart';

class AddTaskScreen extends StatefulWidget {
  final VoidCallback? onResetToHome;
  
  const AddTaskScreen({super.key, this.onResetToHome});
  
  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    // Check absence status after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAbsenceStatus();
      // Set up listener for absence status changes
      _setupAbsenceListener();
    });
  }
  
  void _setupAbsenceListener() {
    print('👂 [AddTask] Setting up absence listener');
    // Listen to absence provider changes
    final absenceProvider = Provider.of<AbsenceProvider>(context, listen: false);
    absenceProvider.addListener(_onAbsenceStatusChanged);
    print('✅ [AddTask] Absence listener attached');
  }
  
  void _onAbsenceStatusChanged() {
    print('🔔 [AddTask] Absence status changed callback fired');
    print('   mounted: $mounted, _dialogShown: $_dialogShown');
    
    if (!mounted) {
      print('⚠️ [AddTask] Widget not mounted, ignoring');
      return;
    }
    
    final absenceProvider = Provider.of<AbsenceProvider>(context, listen: false);
    print('   isAbsentToday: ${absenceProvider.isAbsentToday}');
    print('   absenceType: ${absenceProvider.absenceType}');
    
    // If caregiver becomes absent and dialog not yet shown
    if (absenceProvider.isAbsentToday && !_dialogShown) {
      print('✅ [AddTask] Will show absence dialog');
      _dialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          print('📱 [AddTask] Showing absence dialog now');
          _showAbsenceDialog(context, absenceProvider.absenceType ?? 'absent');
        } else {
          print('⚠️ [AddTask] Widget unmounted before showing dialog');
        }
      });
    }
    
    // If caregiver is no longer absent, reset dialog flag
    if (!absenceProvider.isAbsentToday && _dialogShown) {
      print('✅ [AddTask] Resetting dialog flag (no longer absent)');
      _dialogShown = false;
    }
  }
  
  @override
  void dispose() {
    // Remove listener to prevent memory leaks
    try {
      final absenceProvider = Provider.of<AbsenceProvider>(context, listen: false);
      absenceProvider.removeListener(_onAbsenceStatusChanged);
    } catch (e) {
      // Context might be invalid during disposal, ignore
    }
    super.dispose();
  }

  void _checkAbsenceStatus() {
    if (_dialogShown) return;
    
    final absenceProvider = Provider.of<AbsenceProvider>(context, listen: false);
    if (absenceProvider.isAbsentToday) {
      _dialogShown = true;
      _showAbsenceDialog(context, absenceProvider.absenceType ?? 'absent');
    }
  }

  Future<void> saveCareTask({
    required String elderlyId,
    required String caregiverId,
    required String elderlyFname,
    required DateTime taskStart,
    required DateTime taskEnd,
    required List<String> taskFrequency,
    required String taskDescription,
    required DateTime taskDate,
    Map<String, dynamic>? extraFields,
    List<String>? customDays,
  }) async {
    final tasksRef = FirebaseFirestore.instance.collection('care_tasks');
    final docRef = tasksRef.doc();
    DateTime now = DateTime.now();
    DateTime? nextTaskDate;
    DateTime actualTaskDate = taskDate;
    
    // Calculate next task date for recurring tasks
    String frequency = taskFrequency.isNotEmpty ? taskFrequency[0] : 'Only once';
    
    // Smart date calculation: If task time has already passed for today, find next applicable date
    DateTime taskTimeToday = DateTime(now.year, now.month, now.day, taskStart.hour, taskStart.minute);
    bool taskTimeHasPassed = now.isAfter(taskTimeToday);
    
    if (frequency == 'Only once') {
      // For "Only once" tasks, check if the selected date is today and time has passed
      if (taskDate.year == now.year && taskDate.month == now.month && taskDate.day == now.day && taskTimeHasPassed) {
        // Time has passed for today, but for "Only once" tasks, we can't move to next day
        // Keep the original date - user specifically selected this date
      }
      // nextTaskDate remains null for "Only once" tasks
    } else if (frequency == 'Every Assigned Day') {
      // For recurring tasks, if time has passed today, start from tomorrow
      DateTime searchFromDate = taskTimeHasPassed ? now.add(Duration(days: 1)) : now;
      nextTaskDate = await _getNextAssignedDate(elderlyId, caregiverId, taskStart, searchFromDate);
      
      // If time hasn't passed today AND caregiver is assigned today, use today
      if (!taskTimeHasPassed && await _isAssignedOnDate(elderlyId, caregiverId, now)) {
        actualTaskDate = DateTime(now.year, now.month, now.day);
        nextTaskDate = await _getNextAssignedDate(elderlyId, caregiverId, taskStart, now.add(Duration(days: 1)));
      } else if (nextTaskDate != null) {
        // Use the calculated next occurrence as the actual task date
        actualTaskDate = DateTime(nextTaskDate.year, nextTaskDate.month, nextTaskDate.day);
        nextTaskDate = await _getNextAssignedDate(elderlyId, caregiverId, taskStart, nextTaskDate.add(Duration(days: 1)));
      }
    } else if (frequency == 'Custom' && customDays != null) {
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
      for (int i = 0; i < 14; i++) {
        DateTime candidate = fromDate.add(Duration(days: i));
        bool isAssigned = await _isAssignedOnDate(elderlyId, caregiverId, candidate);
        
        if (isAssigned) {
          DateTime candidateStart = DateTime(candidate.year, candidate.month, candidate.day, taskStart.hour, taskStart.minute);
          
          if (i == 0 && DateTime.now().isBefore(candidateStart)) {
            return candidateStart;
          } else if (i > 0) {
            return candidateStart;
          }
        }
      }
    } catch (e) {
      print('Error calculating next assigned date: $e');
    }
    return null;
  }

  // Helper function to get next custom date
  Future<DateTime?> _getNextCustomDate(String elderlyId, String caregiverId, DateTime taskStart, DateTime fromDate, List<String> customDays) async {
    try {
      for (int i = 0; i < 14; i++) {
        DateTime candidate = fromDate.add(Duration(days: i));
        String weekdayStr = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"][candidate.weekday - 1];
        
        if (customDays.contains(weekdayStr)) {
          bool isAssigned = await _isAssignedOnDate(elderlyId, caregiverId, candidate);
          
          if (isAssigned) {
            DateTime candidateStart = DateTime(candidate.year, candidate.month, candidate.day, taskStart.hour, taskStart.minute);
            
            if (i == 0 && DateTime.now().isBefore(candidateStart)) {
              return candidateStart;
            } else if (i > 0) {
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

  // Helper function to check if caregiver is assigned to elderly on a specific date
  Future<bool> _isAssignedOnDate(String elderlyId, String caregiverId, DateTime date) async {
    try {
      String weekdayStr = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"][date.weekday - 1];
      
      // CORRECTED APPROACH: Check elderly_assignments collection with array structure
      print('DEBUG AddTask: Checking if elderly $elderlyId is assigned to caregiver $caregiverId on $weekdayStr');
      
      // Step 1: Check specific elderly assignments from array structure
      final elderlyAssignSnapshot = await FirebaseFirestore.instance
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .where('day', isEqualTo: weekdayStr)
          .get();
      
      if (elderlyAssignSnapshot.docs.isNotEmpty) {
        // Check if elderly is in the assigned arrays for this day
        for (var doc in elderlyAssignSnapshot.docs) {
          final assignData = doc.data();
          final elderlyIds = List<String>.from(assignData['elderly_ids'] ?? []);
          
          if (elderlyIds.contains(elderlyId)) {
            print('DEBUG AddTask: ✅ Elderly $elderlyId is specifically assigned on $weekdayStr');
            return true;
          }
        }
        
        print('DEBUG AddTask: ❌ Elderly $elderlyId is NOT in assigned list for $weekdayStr');
        return false;
      }
      
      // Step 2: Fallback for new caregivers - use house-based approach
      print('DEBUG AddTask: No specific assignments found, using house-based fallback for $weekdayStr');
      
      // Get caregiver's house assignment
      final houseAssignSnapshot = await FirebaseFirestore.instance
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .limit(1)
          .get();
      
      if (houseAssignSnapshot.docs.isEmpty) {
        print('DEBUG AddTask: No house assignment found for caregiver');
        return false;
      }
      
      final houseAssignData = houseAssignSnapshot.docs.first.data();
      final houseId = houseAssignData['house_id'] as String;
      final caregiverAssignedDays = List<String>.from(houseAssignData['days_assigned'] ?? []);
      
      // Check if caregiver is assigned on this day
      if (!caregiverAssignedDays.contains(weekdayStr)) {
        print('DEBUG AddTask: Caregiver not assigned on $weekdayStr');
        return false;
      }
      
      // Check if elderly is in this house AND not assigned to other caregivers
      final elderlyDoc = await FirebaseFirestore.instance
          .collection('elderly')
          .doc(elderlyId)
          .get();
      
      if (!elderlyDoc.exists) {
        print('DEBUG AddTask: Elderly document not found');
        return false;
      }
      
      final elderlyData = elderlyDoc.data();
      if (elderlyData == null) {
        print('DEBUG AddTask: Elderly document has no data');
        return false;
      }
      
      final elderlyHouseId = elderlyData['house_id'] as String?;
      
      if (elderlyHouseId != houseId) {
        print('DEBUG AddTask: Elderly not in caregiver\'s house');
        return false;
      }
      
      // Check if elderly is specifically assigned to OTHER caregivers on this day
      final otherAssignments = await FirebaseFirestore.instance
          .collection('elderly_assignments')
          .where('day', isEqualTo: weekdayStr)
          .get();
      
      for (var doc in otherAssignments.docs) {
        final assignData = doc.data();
        final assignmentCaregiverId = assignData['user_id'] as String?;
        final assignmentUserType = assignData['user_type'] as String?;
        final elderlyIds = List<String>.from(assignData['elderly_ids'] ?? []);
        
        if (assignmentCaregiverId != caregiverId && assignmentUserType == 'caregiver' && elderlyIds.contains(elderlyId)) {
          print('DEBUG AddTask: ❌ Elderly $elderlyId is assigned to another caregiver on $weekdayStr');
          return false;
        }
      }
      
      print('DEBUG AddTask: ✅ Elderly $elderlyId is available (house-based) on $weekdayStr');
      return true;
      
    } catch (e) {
      print('DEBUG AddTask: Error checking assignment on date: $e');
      return false;
    }
  }
  Future<List<Map<String, dynamic>>> getAssignedElderlyForCaregiver(String caregiverId) async {
    try {
      // SIMPLIFIED APPROACH: Use house service to get all assigned elderly
      // This works regardless of whether elderly_assignments exists or not
      final houseService = HouseService();
      final assignedElderly = await houseService.getAssignedElderlyForCaregiver(caregiverId);
      
      // Convert to the format expected by the task UI
      List<Map<String, dynamic>> formattedElderly = [];
      for (var elderly in assignedElderly) {
        final sex = elderly['elderly_sex'] ?? '';
        final prefix = (sex == 'Male') ? 'Lolo ' : (sex == 'Female') ? 'Lola ' : '';
        
        formattedElderly.add({
          'assign_id': elderly['assign_id'] ?? '',
          'elderly_id': elderly['elderly_id'],
          'caregiver_id': caregiverId,
          'elderly_fname': prefix + (elderly['elderly_fname'] ?? ''),
        });
      }
      
      return formattedElderly;
    } catch (e) {
      print('Error in getAssignedElderlyForCaregiver: $e');
      return [];
    }
  }

  Stream<List<Map<String, dynamic>>> getTasksStream(String status) {
    return FirebaseFirestore.instance
      .collection('care_tasks')
      .where('task_status', arrayContains: status)
      .snapshots()
      .map((snapshot) {
        final now = DateTime.now();
        List<Map<String, dynamic>> tasks = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'task_id': data['task_id'] ?? doc.id,
            'elderly_fname': data['elderly_fname'] ?? '',
            'task_description': data['task_description'] ?? '',
            'task_start': (data['task_start'] is Timestamp) ? (data['task_start'] as Timestamp).toDate() : data['task_start'],
            'task_end': (data['task_end'] is Timestamp) ? (data['task_end'] as Timestamp).toDate() : data['task_end'],
            'task_date': (data['task_date'] is Timestamp) ? (data['task_date'] as Timestamp).toDate() : data['task_date'],
          };
        }).toList();

        tasks.sort((a, b) {
          final aStart = a['task_start'] as DateTime? ?? now;
          final bStart = b['task_start'] as DateTime? ?? now;
          return aStart.compareTo(bStart);
        });
        return tasks;
      });
  }

  // Restore _getTasks for non-Upcoming tabs
  int _selectedTab = 0;
  final List<String> _tabs = ['Upcoming', 'Complete', 'Incomplete', 'Missed'];
  bool isSidebarOpen = false;
  void toggleSidebar() => setState(() => isSidebarOpen = !isSidebarOpen);

  void _showAbsenceDialog(BuildContext context, String absenceType) {
    print('📱 [AddTask] _showAbsenceDialog called, absenceType: $absenceType');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  absenceType == 'leave' ? Icons.event_busy : Icons.cancel_outlined,
                  color: Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    absenceType == 'leave' ? 'On Leave Today' : 'Marked Absent Today',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            content: const Text(
              'You are currently Absent/On Leave for the day, come back soon!',
              style: TextStyle(fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  print('🔘 [AddTask] Dialog OK button clicked');
                  Navigator.of(dialogContext).pop(); // Close dialog only
                  print('✅ [AddTask] Dialog closed');
                },
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
      },
    ).then((_) {
      print('🔙 [AddTask] Dialog dismissed, attempting to reset to home');
      print('   mounted: $mounted, onResetToHome: ${widget.onResetToHome != null}');
      // After dialog closes, reset to home tab
      // Use post frame callback to avoid crashes during build/dispose
      if (mounted && widget.onResetToHome != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            try {
              print('🏠 [AddTask] Calling onResetToHome');
              widget.onResetToHome?.call();
              print('✅ [AddTask] Successfully reset to home');
            } catch (e) {
              print('❌ [AddTask] Error resetting to home: $e');
            }
          } else {
            print('⚠️ [AddTask] Widget unmounted, cannot reset to home');
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Future<void> handleLogout() async {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/get_started',
          (route) => false,
        );
      }
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/background1.png',
            fit: BoxFit.cover,
          ),
        ),
        Column(
          children: [
            const SizedBox(height: 16), // Add space above AppBar
            Expanded(
              child: Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  backgroundColor: const Color(0x00FFFFFF),
                  surfaceTintColor: Colors.white,
                  scrolledUnderElevation: 0,
                  elevation: 0,
                  title: const Text('List of Tasks',
                      style: TextStyle(
                          color: Color(0xFF00588e),
                          fontWeight: FontWeight.bold)),
                  centerTitle: true,
                  leading: IconButton(
                    icon: const Icon(Icons.menu, color: Color(0xFF00588e)),
                    onPressed: toggleSidebar,
                  ),
                  actions: [
                    const NotificationIconButton(),
                  ],
                ),
                body: Column(
                  children: [
                    const SizedBox(height: 12),
                    // Navigation tabs
                      Container(
                        color: const Color(0xFFE6F3FA),
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(_tabs.length, (index) {
                              final bool selected = _selectedTab == index;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 3.0),
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedTab = index;
                                    });
                                  },
                                  child: Container(
                                    constraints: const BoxConstraints(minWidth: 80, maxWidth: 140),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    decoration: selected
                                        ? BoxDecoration(
                                            color: const Color(0xFF00588e),
                                            borderRadius: BorderRadius.circular(20),
                                          )
                                        : null,
                                    child: Text(
                                      _tabs[index],
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected ? Colors.white : const Color(0xFF00588e),
                                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                    Expanded(
                      child: Stack(
                        children: [
                          (() {
                            switch (_selectedTab) {
                              case 0:
                                return const UpcomingTasksScreen(/* selectedFilterDate: _selectedFilterDate */);
                              case 1:
                                return const CompleteTasksScreen(/* selectedFilterDate: _selectedFilterDate */);
                              case 2:
                                return const IncompleteTasksScreen(/* selectedFilterDate: _selectedFilterDate */);
                              case 3:
                                return const MissedTasksScreen(/* selectedFilterDate: _selectedFilterDate */);
                              default:
                                return const Center(child: Text('Invalid tab selection.'));
                            }
                          })(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        CaregiverSidebar(
          onLogout: handleLogout,
          isSidebarOpen: isSidebarOpen,
          toggleSidebar: toggleSidebar,
          parentContext: context,
        ),
      ],
    );
  }
}