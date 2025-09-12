import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'caregiver_sidebar.dart';
import '../providers/auth_provider.dart';
import 'notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

    // Batch fetch all elderly details
    final elderlySnapshot = await FirebaseFirestore.instance
        .collection('elderly')
        .where(FieldPath.documentId, whereIn: assignedIds)
        .get();

    // Map elderlyId to elderly data
    final elderlyMap = {
      for (var doc in elderlySnapshot.docs) doc.id: doc.data()
    };

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
  Color _getCardColor(int tab) {
    switch (tab) {
      case 0: // Upcoming
      case 1: // Complete
        return const Color(0xFFE6F3FA); // Blue
      case 2: // Incomplete
        return const Color(0xFFE6FAF0); // Green
      case 3: // Missed
        return const Color(0xFFFDE6E6); // Red
      default:
        return Colors.white;
    }
  }

  Color _getTextColor(int tab) {
    switch (tab) {
      case 0:
      case 1:
        return const Color(0xFF00588e); // Blue text
      case 2:
        return const Color(0xFF1B7F5A); // Green text
      case 3:
        return const Color(0xFFD32F2F); // Red text
      default:
        return Colors.black;
    }
  }

  Stream<List<Map<String, dynamic>>> getUpcomingTasksStream() {
    return FirebaseFirestore.instance
      .collection('care_tasks')
      .where('task_status', arrayContains: 'Upcoming')
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
                  case 'Everyday':
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
                  filteredTasks.add({
                    ...task,
                    'task_date': filterDate,
                  });
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
  List<Map<String, String>> _getTasks(int tab) {
  // Provide placeholder data for non-Upcoming tabs
  switch (tab) {
    case 1: // Complete
      return [
        {'name': 'Lola Maria', 'task': 'Completed: Take morning medicine', 'time': '8:00 AM'},
        {'name': 'Lolo Juan', 'task': 'Completed: Read newspaper', 'time': '9:00 AM'},
      ];
    case 2: // Incomplete
      return [
        {'name': 'Lola Ana', 'task': 'Incomplete: Do stretching', 'time': '7:30 AM'},
      ];
    case 3: // Missed
      return [
        {'name': 'Lolo Pedro', 'task': 'Missed: Attend group activity', 'time': '10:00 AM'},
      ];
    default:
      return [];
  }
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : hour == 0 ? 12 : hour;
    return '$hour12:$minute $ampm';
  }

  Widget _buildTaskCard(Map<String, String> task, int tab) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _getCardColor(tab),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
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
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task['name'] ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: _getTextColor(tab),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  task['task'] ?? '',
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                task['time'] ?? '',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _getTextColor(tab),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
                  backgroundColor: Colors.transparent,
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
                        child: IntrinsicWidth(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: List.generate(_tabs.length, (index) {
                              final bool selected = _selectedTab == index;
                              return Padding(
                                padding: const EdgeInsets.only(left: 3.0, right: 3.0),
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedTab = index;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    decoration: selected
                                        ? BoxDecoration(
                                            color: const Color(0xFF00588e),
                                            borderRadius: BorderRadius.circular(20),
                                          )
                                        : null,
                                    child: Text(
                                      _tabs[index],
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
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedFilterDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
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
                          (_selectedTab == 0)
                              ? StreamBuilder<List<Map<String, dynamic>>>(
                                  stream: getUpcomingTasksStream(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState == ConnectionState.waiting) {
                                      return const Center(child: CircularProgressIndicator());
                                    }
                                    final tasks = snapshot.data ?? [];
                                    if (tasks.isEmpty) {
                                      return const Center(child: Text('No upcoming tasks.'));
                                    }
                                    // If All Dates filter, group by date and sort
                                    if (_selectedFilterDate == null) {
                                      // Group tasks by date
                                      Map<String, List<Map<String, dynamic>>> grouped = {};
                                      for (var task in tasks) {
                                        final date = task['task_date'] as DateTime?;
                                        if (date == null) continue;
                                        final key = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
                                        grouped.putIfAbsent(key, () => []).add(task);
                                      }
                                      // Sort dates closest to today first
                                      final now = DateTime.now();
                                      final sortedKeys = grouped.keys.toList()
                                        ..sort((a, b) {
                                          final ad = DateTime.parse(a.replaceAll('-', '')); // yyyyMMdd
                                          final bd = DateTime.parse(b.replaceAll('-', ''));
                                          return (ad.difference(now).inDays).abs().compareTo((bd.difference(now).inDays).abs());
                                        });
                                      return ListView(
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
                                                      key,
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF22688E)),
                                                    ),
                                                  ),
                                                  for (final task in grouped[key]!)
                                                    GestureDetector(
                                                      onTap: () {
                                                        showDialog(
                                                          context: context,
                                                          barrierDismissible: true,
                                                          builder: (BuildContext ctx) {
                                                            TextEditingController reasonController = TextEditingController();
                                                            bool showReason = false;
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
                                                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                                                        children: [
                                                                          Row(
                                                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                                            children: [
                                                                              Expanded(
                                                                                child: Center(
                                                                                  child: Text(
                                                                                    'Task Details',
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
                                                                          Row(
                                                                            children: [
                                                                              const Icon(Icons.person, color: Color(0xFF22688E)),
                                                                              const SizedBox(width: 8),
                                                                              const Text('Name:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                                              const SizedBox(width: 8),
                                                                              Text(task['elderly_fname'] ?? ''),
                                                                            ],
                                                                          ),
                                                                          const SizedBox(height: 10),
                                                                          Row(
                                                                            children: [
                                                                              const Icon(Icons.assignment, color: Color(0xFF22688E)),
                                                                              const SizedBox(width: 8),
                                                                              const Text('Activity:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                                              const SizedBox(width: 8),
                                                                              Flexible(
                                                                                child: Text(
                                                                                  task['task_description'] ?? '',
                                                                                  overflow: TextOverflow.ellipsis,
                                                                                  softWrap: true,
                                                                                  maxLines: 2,
                                                                                  style: const TextStyle(fontSize: 15),
                                                                                ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                          const SizedBox(height: 10),
                                                                          Row(
                                                                            children: [
                                                                              const Icon(Icons.event, color: Color(0xFF22688E)),
                                                                              const SizedBox(width: 8),
                                                                              const Text('Date:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                                              const SizedBox(width: 8),
                                                                              Text(task['task_date'] != null ? "${task['task_date'].year}-${task['task_date'].month.toString().padLeft(2, '0')}-${task['task_date'].day.toString().padLeft(2, '0')}" : ''),
                                                                            ],
                                                                          ),
                                                                          const SizedBox(height: 10),
                                                                          Row(
                                                                            children: [
                                                                              const Icon(Icons.access_time, color: Color(0xFF22688E)),
                                                                              const SizedBox(width: 8),
                                                                              const Text('Start:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                                              const SizedBox(width: 8),
                                                                              Text(task['task_start'] != null ? _formatTime(task['task_start']) : ''),
                                                                            ],
                                                                          ),
                                                                          const SizedBox(height: 10),
                                                                          Row(
                                                                            children: [
                                                                              const Icon(Icons.access_time, color: Color(0xFF22688E)),
                                                                              const SizedBox(width: 8),
                                                                              const Text('End:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                                              const SizedBox(width: 8),
                                                                              Text(task['task_end'] != null ? _formatTime(task['task_end']) : ''),
                                                                            ],
                                                                          ),
                                                                          const SizedBox(height: 10),
                                                                          // Removed 'Created' field
                                                                          const SizedBox(height: 18),
                                                                          Row(
                                                                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                                            children: [
                                                                              TextButton.icon(
                                                                                icon: const Icon(Icons.check_circle, color: Color(0xFF22688E)),
                                                                                label: const Text('Complete', style: TextStyle(color: Color(0xFF22688E), fontWeight: FontWeight.bold)),
                                                                                style: TextButton.styleFrom(
                                                                                  backgroundColor: const Color(0xFFE6F3FA),
                                                                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                                                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                                                ),
                                                                                onPressed: () {
                                                                                  // Complete logic: update Firestore task_status to ['Complete']
                                                                                  final id = task['task_id'] ?? task['id'];
                                                                                  if (id != null) {
                                                                                    FirebaseFirestore.instance
                                                                                      .collection('care_tasks')
                                                                                      .doc(id)
                                                                                      .update({'task_status': ['Complete']})
                                                                                      .then((_) {
                                                                                        if (mounted) setState(() {});
                                                                                        Navigator.of(ctx).pop();
                                                                                      })
                                                                                      .catchError((error) {
                                                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                                                          SnackBar(content: Text('Failed to mark as complete: '
                                                                                            + error.toString())));
                                                                                      });
                                                                                  } else {
                                                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                                                      const SnackBar(content: Text('Task ID not found.')));
                                                                                  }
                                                                                },
                                                                              ),
                                                                              TextButton.icon(
                                                                                icon: const Icon(Icons.cancel, color: Color(0xFFD32F2F)),
                                                                                label: const Text('Incomplete', style: TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
                                                                                style: TextButton.styleFrom(
                                                                                  backgroundColor: const Color(0xFFFDE6E6),
                                                                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                                                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                                                ),
                                                                                onPressed: () {
                                                                                  setState(() { showReason = true; });
                                                                                },
                                                                              ),
                                                                            ],
                                                                          ),
                                                                          if (showReason) ...[
                                                                            const SizedBox(height: 18),
                                                                            const Text('Reason for Incompletion:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                                            const SizedBox(height: 8),
                                                                            Container(
                                                                              decoration: BoxDecoration(
                                                                                color: const Color(0xFFE6F3FA),
                                                                                borderRadius: BorderRadius.circular(12),
                                                                              ),
                                                                              child: TextField(
                                                                                controller: reasonController,
                                                                                maxLines: 3,
                                                                                decoration: const InputDecoration(
                                                                                  hintText: 'Type here...',
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
                                                                                onPressed: () {
                                                                                  // TODO: Submit reason logic
                                                                                  Navigator.of(ctx).pop();
                                                                                },
                                                                                style: ElevatedButton.styleFrom(
                                                                                  backgroundColor: const Color(0xFF22688E),
                                                                                  shape: RoundedRectangleBorder(
                                                                                    borderRadius: BorderRadius.circular(32),
                                                                                  ),
                                                                                  elevation: 4,
                                                                                ),
                                                                                child: const Text(
                                                                                  'Submit',
                                                                                  style: TextStyle(
                                                                                    fontSize: 15,
                                                                                    fontWeight: FontWeight.w600,
                                                                                    color: Colors.white,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                            ),
                                                                          ],
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
                                                                  child: Image.asset(
                                                                    'assets/images/people_icon.png',
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
                                                                      Container(
                                                                        width: 12,
                                                                        height: 12,
                                                                        decoration: const BoxDecoration(
                                                                          color: Color(0xFF1B7F5A), // green
                                                                          shape: BoxShape.circle,
                                                                        ),
                                                                      ),
                                                                      const SizedBox(width: 6),
                                                                      Text(
                                                                        task['task_start'] != null ? _formatTime(task['task_start']) : '',
                                                                        style: const TextStyle(fontSize: 14, color: Color(0xFF00588e), fontWeight: FontWeight.bold),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  const SizedBox(height: 4),
                                                                  Row(
                                                                    children: [
                                                                      Container(
                                                                        width: 12,
                                                                        height: 12,
                                                                        decoration: const BoxDecoration(
                                                                          color: Color(0xFFD32F2F), // red
                                                                          shape: BoxShape.circle,
                                                                        ),
                                                                      ),
                                                                      const SizedBox(width: 6),
                                                                      Text(
                                                                        task['task_end'] != null ? _formatTime(task['task_end']) : '',
                                                                        style: const TextStyle(fontSize: 14, color: Color(0xFF00588e), fontWeight: FontWeight.bold),
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
                                      );
                                    }
                                    // Otherwise, show filtered tasks as before
                                    return ListView.builder(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      itemCount: tasks.length,
                                      itemBuilder: (context, index) {
                                        final task = tasks[index];
                                        return GestureDetector(
                                          onTap: () {
                                            showDialog(
                                              context: context,
                                              barrierDismissible: true,
                                              builder: (BuildContext ctx) {
                                                TextEditingController reasonController = TextEditingController();
                                                bool showReason = false;
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
                                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                                            children: [
                                                              Row(
                                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                                children: [
                                                                  Expanded(
                                                                    child: Center(
                                                                      child: Text(
                                                                        'Task Details',
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
                                                              const SizedBox(height: 15),
                                                              Row(
                                                                children: [
                                                                  const Icon(Icons.person, color: Color(0xFF22688E)),
                                                                  const SizedBox(width: 8),
                                                                  const Text('Name:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                                  const SizedBox(width: 8),
                                                                  Text(task['elderly_fname'] ?? ''),
                                                                ],
                                                              ),
                                                              const SizedBox(height: 15),
                                                              Row(
                                                                children: [
                                                                  const Icon(Icons.assignment, color: Color(0xFF22688E)),
                                                                  const SizedBox(width: 8),
                                                                  const Text('Activity:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                                  const SizedBox(width: 8),
                                                                  Text(task['task_description'] ?? ''),
                                                                ],
                                                              ),
                                                              const SizedBox(height: 15),
                                                              Row(
                                                                children: [
                                                                  const Icon(Icons.event, color: Color(0xFF22688E)),
                                                                  const SizedBox(width: 8),
                                                                  const Text('Date:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                                  const SizedBox(width: 8),
                                                                  Text(task['task_date'] != null ? "${task['task_date'].year}-${task['task_date'].month.toString().padLeft(2, '0')}-${task['task_date'].day.toString().padLeft(2, '0')}" : ''),
                                                                ],
                                                              ),
                                                              const SizedBox(height: 15),
                                                              Row(
                                                                children: [
                                                                  const Icon(Icons.access_time, color: Color(0xFF22688E)),
                                                                  const SizedBox(width: 8),
                                                                  const Text('Start:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                                  const SizedBox(width: 8),
                                                                  Text(task['task_start'] != null ? _formatTime(task['task_start']) : ''),
                                                                ],
                                                              ),
                                                              const SizedBox(height: 15),
                                                              Row(
                                                                children: [
                                                                  const Icon(Icons.access_time, color: Color(0xFF22688E)),
                                                                  const SizedBox(width: 8),
                                                                  const Text('End:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                                  const SizedBox(width: 8),
                                                                  Text(task['task_end'] != null ? _formatTime(task['task_end']) : ''),
                                                                ],
                                                              ),
                                                              const SizedBox(height: 18),
                                                              Row(
                                                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                                children: [
                                                                  TextButton.icon(
                                                                    icon: const Icon(Icons.check_circle, color: Color(0xFF22688E)),
                                                                    label: const Text('Complete', style: TextStyle(color: Color(0xFF22688E), fontWeight: FontWeight.bold)),
                                                                    style: TextButton.styleFrom(
                                                                      backgroundColor: const Color(0xFFE6F3FA),
                                                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                                    ),
                                                                    onPressed: () {
                                                                      // TODO: Complete logic
                                                                      Navigator.of(ctx).pop();
                                                                    },
                                                                  ),
                                                                  TextButton.icon(
                                                                    icon: const Icon(Icons.cancel, color: Color(0xFFD32F2F)),
                                                                    label: const Text('Incomplete', style: TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
                                                                    style: TextButton.styleFrom(
                                                                      backgroundColor: const Color(0xFFFDE6E6),
                                                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                                    ),
                                                                    onPressed: () {
                                                                      setState(() { showReason = true; });
                                                                    },
                                                                  ),
                                                                ],
                                                              ),
                                                              if (showReason) ...[
                                                                const SizedBox(height: 18),
                                                                const Text('Reason for Incompletion:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                                const SizedBox(height: 8),
                                                                Container(
                                                                  decoration: BoxDecoration(
                                                                    color: const Color(0xFFE6F3FA),
                                                                    borderRadius: BorderRadius.circular(12),
                                                                  ),
                                                                  child: TextField(
                                                                    controller: reasonController,
                                                                    maxLines: 3,
                                                                    decoration: const InputDecoration(
                                                                      hintText: 'Type here...',
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
                                                                    onPressed: () {
                                                                      // TODO: Submit reason logic
                                                                      Navigator.of(ctx).pop();
                                                                    },
                                                                    style: ElevatedButton.styleFrom(
                                                                      backgroundColor: const Color(0xFF22688E),
                                                                      shape: RoundedRectangleBorder(
                                                                        borderRadius: BorderRadius.circular(32),
                                                                      ),
                                                                      elevation: 4,
                                                                    ),
                                                                    child: const Text(
                                                                      'Submit',
                                                                      style: TextStyle(
                                                                        fontSize: 15,
                                                                        fontWeight: FontWeight.w600,
                                                                        color: Colors.white,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
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
                                            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                            color: const Color(0xFFE6F3FA),
                                            elevation: 2,
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  // Left side: elderly image
                                                  Container(
                                                    width: 56,
                                                    height: 56,
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF00588e),
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.circular(12),
                                                      child: Image.asset(
                                                        'assets/images/people_icon.png',
                                                        fit: BoxFit.cover,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  // Middle: elderly name and description
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
                                                  // Right side: start/end time
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.end,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Container(
                                                            width: 12,
                                                            height: 12,
                                                            decoration: const BoxDecoration(
                                                              color: Color(0xFF1B7F5A), // green
                                                              shape: BoxShape.circle,
                                                            ),
                                                          ),
                                                          const SizedBox(width: 6),
                                                          Text(
                                                            task['task_start'] != null ? _formatTime(task['task_start']) : '',
                                                            style: const TextStyle(fontSize: 14, color: Color(0xFF00588e), fontWeight: FontWeight.bold),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Row(
                                                        children: [
                                                          Container(
                                                            width: 12,
                                                            height: 12,
                                                            decoration: const BoxDecoration(
                                                              color: Color(0xFFD32F2F), // red
                                                              shape: BoxShape.circle,
                                                            ),
                                                          ),
                                                          const SizedBox(width: 6),
                                                          Text(
                                                            task['task_end'] != null ? _formatTime(task['task_end']) : '',
                                                            style: const TextStyle(fontSize: 14, color: Color(0xFF00588e), fontWeight: FontWeight.bold),
                                                          ),
                                                        ],
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
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  itemCount: _getTasks(_selectedTab).length,
                                  itemBuilder: (context, index) {
                                    final task = _getTasks(_selectedTab)[index];
                                    return _buildTaskCard(task, _selectedTab);
                                  },
                                ),
                          if (_selectedTab == 0)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    SizedBox(
                                      width: 180,
                                      child: ElevatedButton(
                                        onPressed: () async {
                                          final authProvider = Provider.of<AuthProvider>(context, listen: false);
                                          final caregiverId = authProvider.currentUser?.uid ?? '';
                                          List<Map<String, dynamic>> assignedElderly = [];
                                          if (caregiverId.isNotEmpty) {
                                            assignedElderly = await getAssignedElderlyForCaregiver(caregiverId);
                                            // Filter out any elderly not assigned to this caregiver (extra safety)
                                            assignedElderly = assignedElderly.where((e) => e['caregiver_id'] == caregiverId).toList();
                                          }
                                          showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (BuildContext ctx) {
                                              String? selectedElderly;
                                              String? selectedFrequency = 'Only once';
                                              TimeOfDay? startTime;
                                              TimeOfDay? endTime;
                                              TextEditingController activityController = TextEditingController();
                                              final List<String> frequencyList = ['Only once', 'Everyday', 'Every other day', 'Once a week'];
                                              DateTime? selectedDate;
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
                                                              padding: const EdgeInsets.symmetric(horizontal: 16),
                                                              child: DropdownButtonHideUnderline(
                                                                child: DropdownButton<String>(
                                                                  value: selectedElderly,
                                                                  hint: const Text('Select Elderly'),
                                                                  isExpanded: false,
                                                                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF22688E)),
                                                                  items: assignedElderly.map((elderly) {
                                                                    return DropdownMenuItem<String>(
                                                                      value: elderly['elderly_id'],
                                                                      child: Text(elderly['elderly_fname']),
                                                                    );
                                                                  }).toList(),
                                                                  onChanged: (value) {
                                                                    setState(() {
                                                                      selectedElderly = value;
                                                                    });
                                                                  },
                                                                ),
                                                              ),
                                                            ),
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
                                                                      // Start time dropdown box
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
                                                                              initialTime: startTime ?? TimeOfDay.now(),
                                                                            );
                                                                            if (picked != null) {
                                                                              setState(() {
                                                                                startTime = picked;
                                                                              });
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
                                                                      // End time dropdown box
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
                                                                              initialTime: endTime ?? TimeOfDay.now(),
                                                                            );
                                                                            if (picked != null) {
                                                                              setState(() {
                                                                                endTime = picked;
                                                                              });
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
                                                                const SizedBox(width: 32),
                                                                const Icon(Icons.event, color: Color(0xFF22688E)),
                                                                const SizedBox(width: 8),
                                                                const Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                              ],
                                                            ),
                                                            const SizedBox(height: 8),
                                                            Row(
                                                              children: [
                                                                Expanded(
                                                                  child: Container(
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
                                                                ),
                                                                const SizedBox(width: 12),
                                                                Expanded(
                                                                  child: Container(
                                                                    height: 40,
                                                                    decoration: BoxDecoration(
                                                                      color: const Color(0xFFE6F3FA),
                                                                      borderRadius: BorderRadius.circular(20),
                                                                    ),
                                                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                                                    child: InkWell(
                                                                      onTap: () async {
                                                                        final picked = await showDatePicker(
                                                                          context: ctx,
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
                                                                ),
                                                              ],
                                                            ),
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
                                                              // Text field for activity
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
                                                                  if (selectedElderly != null && startTime != null && endTime != null && selectedFrequency != null && selectedDate != null && activityController.text.isNotEmpty) {
                                                                    final elderlyData = assignedElderly.firstWhere((e) => e['elderly_id'] == selectedElderly, orElse: () => {});
                                                                    final elderlyFname = elderlyData['elderly_fname'] ?? '';
                                                                    final authProvider = Provider.of<AuthProvider>(context, listen: false);
                                                                    final caregiverId = authProvider.currentUser?.uid ?? '';
                                                                    final now = DateTime.now();
                                                                    final taskStart = DateTime(now.year, now.month, now.day, startTime!.hour, startTime!.minute);
                                                                    final taskEnd = DateTime(now.year, now.month, now.day, endTime!.hour, endTime!.minute);
                                                                    await saveCareTask(
                                                                      elderlyId: selectedElderly!,
                                                                      caregiverId: caregiverId,
                                                                      elderlyFname: elderlyFname,
                                                                      taskStart: taskStart,
                                                                      taskEnd: taskEnd,
                                                                      taskFrequency: [selectedFrequency!],
                                                                      taskDescription: activityController.text,
                                                                      taskDate: selectedDate!,
                                                                    );
                                                                    Navigator.of(ctx).pop();
                                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                                      const SnackBar(content: Text('Task saved successfully!'), backgroundColor: Color(0xFF22688E)),
                                                                    );
                                                                  } else {
                                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                                      const SnackBar(content: Text('Please fill all fields.'), backgroundColor: Color(0xFFD32F2F)),
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
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          elevation: 4,
                                        ),
                                        child: const Text(
                                          'Add More Tasks',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    SizedBox(
                                      width: 180,
                                      child: ElevatedButton(
                                        onPressed: () {
                                          // TODO: Delete task logic
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFD32F2F),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(30),
                                          ),
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          elevation: 4,
                                        ),
                                        child: const Text(
                                          'Delete Task',
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
                            ),
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
