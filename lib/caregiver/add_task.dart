import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'caregiver_sidebar.dart';
import '../providers/auth_provider.dart';
import '../widgets/notification_icon_button.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'upcoming_tasks_screen.dart';
import 'complete_tasks_screen.dart';
import 'incomplete_tasks_screen.dart';
import 'missed_tasks_screen.dart';

class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({super.key});
  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  // ========================================================================
  // DATE FILTER FUNCTIONALITY - COMMENTED OUT
  // ========================================================================
  // 
  // REASON FOR REMOVAL: Date filtering was conflicting with the task grouping
  // system and the "All Dates" UI element was no longer functional.
  //
  // TO RESTORE DATE FILTERING FUNCTIONALITY:
  // 1. Uncomment the _selectedFilterDate variable below
  // 2. Uncomment the date filter UI (Padding widget with "All Dates" text and calendar icon)
  // 3. Uncomment the filtering logic in the _getTasks method
  // 4. Uncomment selectedFilterDate parameters in all task screen constructors:
  //    - UpcomingTasksScreen
  //    - CompleteTasksScreen  
  //    - IncompleteTasksScreen
  //    - MissedTasksScreen
  // 5. Uncomment the filtering logic in each task screen's getTasks method
  // 6. Test that filtering works properly with the task grouping system
  //
  // DateTime? _selectedFilterDate;
  
  // Unified task creation logic - matches upcoming_tasks_screen.dart implementation
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
      'nextuser_id': '',
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
      
      final assignSnapshot = await FirebaseFirestore.instance
          .collection('cg_house_assign')
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('elderly_id', isEqualTo: elderlyId)
          .get();
      
      if (assignSnapshot.docs.isEmpty) return false;
      
      for (var doc in assignSnapshot.docs) {
        final data = doc.data();
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
  Future<List<Map<String, dynamic>>> getAssignedElderlyForCaregiver(String caregiverId) async {
    final assignSnapshot = await FirebaseFirestore.instance
        .collection('cg_house_assign')
        .where('caregiver_id', isEqualTo: caregiverId)
        .get();

    // Collect all assigned elderly IDs
    final assignedIds = assignSnapshot.docs
        .map((doc) => doc.data()['elderly_id'] as String)
        .toList();

    if (assignedIds.isEmpty) return [];

    // Batch fetch all elderly details in chunks of 30 (Firestore limit)
    List<QuerySnapshot> elderlySnapshots = [];
    
    for (int i = 0; i < assignedIds.length; i += 30) {
      final chunk = assignedIds.skip(i).take(30).toList();
      final chunkSnapshot = await FirebaseFirestore.instance
          .collection('elderly')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      elderlySnapshots.add(chunkSnapshot);
    }

    // Map elderlyId to elderly data from all chunks
    final elderlyMap = <String, Map<String, dynamic>>{};
    for (var snapshot in elderlySnapshots) {
      for (var doc in snapshot.docs) {
        elderlyMap[doc.id] = doc.data() as Map<String, dynamic>;
      }
    }

    // Build the result list
    List<Map<String, dynamic>> assignedElderly = [];
    for (var doc in assignSnapshot.docs) {
      final assignData = doc.data();
      final elderlyId = assignData['elderly_id'];
      final elderlyData = elderlyMap[elderlyId];
      if (elderlyData != null) {
        final sex = elderlyData['elderly_sex'] ?? '';
        final prefix = (sex == 'Male') ? 'Lolo ' : (sex == 'Female') ? 'Lola ' : '';
        assignedElderly.add({
          'assign_id': assignData['assign_id'],
          'elderly_id': elderlyId,
          'caregiver_id': caregiverId,
          'elderly_fname': prefix + (elderlyData['elderly_fname'] ?? ''),
        });
      }
    }
    return assignedElderly;
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
        // DATE FILTER FUNCTIONALITY - COMMENTED OUT
        // Filter by selected date if set (frequency logic not yet working as intended)
        // if (_selectedFilterDate != null) {
        //   final filterDate = DateTime(_selectedFilterDate!.year, _selectedFilterDate!.month, _selectedFilterDate!.day);
        //   List<Map<String, dynamic>> filteredTasks = [];
        //   for (final task in tasks) {
        //     final taskDate = task['task_date'] as DateTime?;
        //     final freqList = task['task_frequency'] as List<dynamic>? ?? [];
        //     final freq = freqList.isNotEmpty ? freqList[0] as String : 'Only once';
        //     if (taskDate == null) continue;
        //     final startDate = DateTime(taskDate.year, taskDate.month, taskDate.day);
        //     bool shouldShow = false;
        //     switch (freq) {
        //       case 'Only once':
        //         shouldShow = filterDate.year == startDate.year && filterDate.month == startDate.month && filterDate.day == startDate.day;
        //         break;
        //       case 'Every Assigned Day':
        //         // For recurring tasks, check if this date matches the next occurrence
        //         final nextTaskDate = task['next_taskdate'] as DateTime?;
        //         if (nextTaskDate != null) {
        //           final nextTaskDateOnly = DateTime(nextTaskDate.year, nextTaskDate.month, nextTaskDate.day);
        //           shouldShow = filterDate.year == nextTaskDateOnly.year && 
        //                      filterDate.month == nextTaskDateOnly.month && 
        //                      filterDate.day == nextTaskDateOnly.day;
        //         } else {
        //           shouldShow = false;
        //         }
        //         break;
        //       case 'Custom': {
        //         // For custom tasks, check if this date matches the next occurrence
        //         final nextTaskDate = task['next_taskdate'] as DateTime?;
        //         if (nextTaskDate != null) {
        //           final nextTaskDateOnly = DateTime(nextTaskDate.year, nextTaskDate.month, nextTaskDate.day);
        //           shouldShow = filterDate.year == nextTaskDateOnly.year && 
        //                      filterDate.month == nextTaskDateOnly.month && 
        //                      filterDate.day == nextTaskDateOnly.day;
        //         } else {
        //           shouldShow = false;
        //         }
        //         break;
        //       }
        //       default:
        //         shouldShow = false;
        //     }
        //     if (shouldShow) {
        //       filteredTasks.add(task);
        //     }
        //   }
        //   tasks = filteredTasks;
        // }
        // Sort by task_start ascending, closest to now first
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
                    // DATE FILTER UI - COMMENTED OUT
                    // To restore: uncomment the Padding widget below and the _selectedFilterDate variable above
                    // Padding(
                    //   padding: const EdgeInsets.only(top: 8, right: 16, left: 16, bottom: 4),
                    //   child: Row(
                    //     mainAxisAlignment: MainAxisAlignment.end,
                    //     children: [
                    //       Text(
                    //         _selectedFilterDate != null
                    //           ? "${_selectedFilterDate!.year}-${_selectedFilterDate!.month.toString().padLeft(2, '0')}-${_selectedFilterDate!.day.toString().padLeft(2, '0')}"
                    //           : 'All Dates',
                    //         style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF22688E)),
                    //       ),
                    //       IconButton(
                    //         icon: const Icon(Icons.event, color: Color(0xFF22688E)),
                    //         onPressed: () async {
                    //           // Fetch caregiver assigned days from cg_house_assign
                    //           List<String> caregiverAssignedDays = [];
                    //           final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
                    //           final caregiverId = user?.uid;
                    //           if (caregiverId != null) {
                    //             final assignSnap = await FirebaseFirestore.instance
                    //               .collection('cg_house_assign')
                    //               .where('caregiver_id', isEqualTo: caregiverId)
                    //               .get();
                    //             if (assignSnap.docs.isNotEmpty) {
                    //               caregiverAssignedDays = List<String>.from(assignSnap.docs.first.data()['days_assigned'] ?? []);
                    //             }
                    //           }
                    //           final picked = await showDatePicker(
                    //             context: context,
                    //             initialDate: _selectedFilterDate ?? DateTime.now(),
                    //             firstDate: DateTime(2020),
                    //             lastDate: DateTime(2100),
                    //             selectableDayPredicate: (date) {
                    //               String weekday = [
                    //                 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
                    //               ][date.weekday - 1];
                    //               // Only allow days where caregiver is assigned
                    //               return caregiverAssignedDays.contains(weekday);
                    //             },
                    //           );
                    //           setState(() {
                    //             _selectedFilterDate = picked;
                    //           });
                    //         },
                    //       ),
                    //       if (_selectedFilterDate != null)
                    //         IconButton(
                    //           icon: const Icon(Icons.clear, color: Color(0xFFD32F2F)),
                    //           tooltip: 'Clear date filter',
                    //           onPressed: () {
                    //             setState(() {
                    //               _selectedFilterDate = null;
                    //             });
                    //           },
                    //         ),
                    //     ],
                    //   ),
                    // ),
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
