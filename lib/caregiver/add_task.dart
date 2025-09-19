import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'caregiver_sidebar.dart';
import '../providers/auth_provider.dart';
import 'notifications.dart';
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
  DateTime? _selectedFilterDate;
  Future<void> saveCareTask({
  required String elderlyId,
  required String caregiverId,
  required String elderlyFname,
  required DateTime taskStart,
  required DateTime taskEnd,
  required List<String> taskFrequency,
  required String taskDescription,
  required DateTime taskDate,
  }) async {
    final tasksRef = FirebaseFirestore.instance.collection('care_tasks');
    final docRef = tasksRef.doc();
    await docRef.set({
      'task_id': docRef.id,
      'elderly_id': elderlyId,
      'caregiver_id': caregiverId,
      'elderly_fname': elderlyFname,
      'task_start': taskStart,
      'task_end': taskEnd,
      'task_frequency': taskFrequency,
      'task_description': taskDescription,
      'task_date': taskDate,
      'nextuser_id': '',
      'inc_reason': '',
      'created_at': FieldValue.serverTimestamp(),
      'task_status': ['Upcoming'],
    });
  }
  Future<List<Map<String, dynamic>>> getAssignedElderlyForCaregiver(String caregiverId) async {
    final assignSnapshot = await FirebaseFirestore.instance
        .collection('elderly_caregiver_assign')
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
        // Filter by selected date if set (frequency logic not yet working as intended)
        if (_selectedFilterDate != null) {
          final filterDate = DateTime(_selectedFilterDate!.year, _selectedFilterDate!.month, _selectedFilterDate!.day);
          List<Map<String, dynamic>> filteredTasks = [];
          for (final task in tasks) {
            final taskDate = task['task_date'] as DateTime?;
            final freqList = task['task_frequency'] as List<dynamic>? ?? [];
            final freq = freqList.isNotEmpty ? freqList[0] as String : 'Only once';
            if (taskDate == null) continue;
            final startDate = DateTime(taskDate.year, taskDate.month, taskDate.day);
            bool shouldShow = false;
            switch (freq) {
              case 'Only once':
                shouldShow = filterDate.year == startDate.year && filterDate.month == startDate.month && filterDate.day == startDate.day;
                break;
              case 'Every Workday':
                shouldShow = !filterDate.isBefore(startDate);
                break;
              case 'Every other day': {
                final diff = filterDate.difference(startDate).inDays;
                shouldShow = diff >= 0 && diff % 2 == 0;
                break;
              }
              case 'Once a week': {
                final diff = filterDate.difference(startDate).inDays;
                shouldShow = diff >= 0 && filterDate.weekday == startDate.weekday;
                break;
              }
              default:
                shouldShow = false;
            }
            if (shouldShow) {
              filteredTasks.add(task);
            }
          }
          tasks = filteredTasks;
        }
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
                  backgroundColor: Colors.white,
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
                    IconButton(
                      icon: const Icon(Icons.notifications, color: Color(0xFF00588e), size: 35),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const NotificationsScreen(),
                          ),
                        );
                      },
                    ),
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
                    // Date filter row (moved below tabs, above cards)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, right: 16, left: 16, bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            _selectedFilterDate != null
                              ? "${_selectedFilterDate!.year}-${_selectedFilterDate!.month.toString().padLeft(2, '0')}-${_selectedFilterDate!.day.toString().padLeft(2, '0')}"
                              : 'All Dates',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF22688E)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.event, color: Color(0xFF22688E)),
                            onPressed: () async {
                              // Fetch caregiver assigned days from cg_house_assign
                              List<String> caregiverAssignedDays = [];
                              final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
                              final caregiverId = user?.uid;
                              if (caregiverId != null) {
                                final assignSnap = await FirebaseFirestore.instance
                                  .collection('cg_house_assign')
                                  .where('caregiver_id', isEqualTo: caregiverId)
                                  .get();
                                if (assignSnap.docs.isNotEmpty) {
                                  caregiverAssignedDays = List<String>.from(assignSnap.docs.first.data()['days_assigned'] ?? []);
                                }
                              }
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedFilterDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                                selectableDayPredicate: (date) {
                                  String weekday = [
                                    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
                                  ][date.weekday - 1];
                                  // Only allow days where caregiver is assigned
                                  return caregiverAssignedDays.contains(weekday);
                                },
                              );
                              setState(() {
                                _selectedFilterDate = picked;
                              });
                            },
                          ),
                          if (_selectedFilterDate != null)
                            IconButton(
                              icon: const Icon(Icons.clear, color: Color(0xFFD32F2F)),
                              tooltip: 'Clear date filter',
                              onPressed: () {
                                setState(() {
                                  _selectedFilterDate = null;
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          (() {
                            switch (_selectedTab) {
                              case 0:
                                return UpcomingTasksScreen(selectedFilterDate: _selectedFilterDate);
                              case 1:
                                return CompleteTasksScreen(selectedFilterDate: _selectedFilterDate);
                              case 2:
                                return IncompleteTasksScreen(selectedFilterDate: _selectedFilterDate);
                              case 3:
                                return MissedTasksScreen(selectedFilterDate: _selectedFilterDate);
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
