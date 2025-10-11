import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'upcoming_tasks_screen.dart';

class IncompleteTasksScreen extends StatefulWidget {
  const IncompleteTasksScreen({super.key});

  @override
  State<IncompleteTasksScreen> createState() => _IncompleteTasksScreenState();
}

class _IncompleteTasksScreenState extends State<IncompleteTasksScreen> with WidgetsBindingObserver {
  Timer? _refreshTimer;
  int _refreshKey = 0;

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
      _checkProgressiveTaskSystem(context);
      _triggerRefresh();
    }
  }

  void _startPeriodicRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _triggerRefresh();
      }
    });
  }

  void _triggerRefresh() {
    if (mounted) {
      setState(() {
        _refreshKey++;
      });
    }
  }
  void _checkProgressiveTaskSystem(BuildContext context) async {
    try {
      print('🔄 IncompleteTasksScreen: Progressive system triggered at ${DateTime.now()}');
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        // Call the Progressive Task System from UpcomingTasksScreen
        final progressedTasks = await TaskService.checkAndProgressRecurringTasks(currentUser.uid);
        if (progressedTasks > 0) {
          print('✅ IncompleteTasksScreen: Progressed $progressedTasks recurring tasks');
        } else {
          print('ℹ️ IncompleteTasksScreen: No tasks needed progression');
        }
      }
    } catch (e) {
      print('❌ IncompleteTasksScreen: Error in progressive system: $e');
    }
  }

  String _formatSingleTime(DateTime? dateTime) {
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

  String _formatFrequency(Map<String, dynamic> task) {
    final frequency = task['task_frequency'];
    
    if (frequency is List && frequency.isNotEmpty) {
      final firstFreq = frequency[0].toString();
      if (firstFreq == 'Custom') {
        final customDays = task['custom_days'] as List<dynamic>? ?? [];
        if (customDays.isNotEmpty) {
          return 'Custom (${customDays.join(', ')})';
        }
        return 'Custom';
      }
      return frequency.join(', ');
    }
    
    return frequency?.toString() ?? '';
  }

  String _getNextRecurringDate(Map<String, dynamic> task) {
    final nextTaskDate = task['next_taskdate'];
    
    if (nextTaskDate != null) {
      DateTime dateTime;
      if (nextTaskDate is Timestamp) {
        dateTime = nextTaskDate.toDate();
      } else if (nextTaskDate is DateTime) {
        dateTime = nextTaskDate;
      } else {
        return '';
      }
      
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    }
    
    return '';
  }

  // Format header date from 'YYYY-MM-DD' to 'Month Day, Year'
  String formatHeaderDate(String key) {
    try {
      final date = DateTime.parse(key);
      const months = [
        '',
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      final monthName = months[date.month];
      return '$monthName ${date.day}, ${date.year}';
    } catch (e) {
      return key;
    }
  }

  // DATE FILTER FUNCTIONALITY - COMMENTED OUT
  // final DateTime? selectedFilterDate;


  /// Returns a stream of incomplete tasks created by the current caregiver only.
  Stream<List<Map<String, dynamic>>> getTasksStream() {
    final currentUser = FirebaseAuth.instance.currentUser;
    final caregiverId = currentUser?.uid;
    if (caregiverId == null) {
      // If not logged in, return empty stream
      return Stream.value([]);
    }
    return FirebaseFirestore.instance
        .collection('care_tasks')
        .where('task_status', arrayContains: 'Incomplete')
        .where('created_by', isEqualTo: caregiverId)
        .snapshots()
        .asyncMap((snapshot) async {
          final now = DateTime.now();
          List<Map<String, dynamic>> tasks = [];
          
          for (var doc in snapshot.docs) {
            final data = doc.data();
            
            // Fetch elderly profile picture
            String? profilePicUrl;
            try {
              final elderlyQuery = await FirebaseFirestore.instance
                  .collection('elderly')
                  .where('elderly_fname', isEqualTo: data['elderly_fname'] ?? '')
                  .limit(1)
                  .get();
              
              if (elderlyQuery.docs.isNotEmpty) {
                final elderlyData = elderlyQuery.docs.first.data();
                profilePicUrl = elderlyData['elderly_profilePic'] as String?;
              }
            } catch (e) {
              print('Error fetching elderly profile picture: $e');
            }
            
            tasks.add({
              'task_id': data['task_id'] ?? doc.id,
              'elderly_fname': data['elderly_fname'] ?? '',
              'task_description': data['task_description'] ?? '',
              'task_start': (data['task_start'] is Timestamp)
                  ? (data['task_start'] as Timestamp).toDate()
                  : data['task_start'],
              'task_end': (data['task_end'] is Timestamp)
                  ? (data['task_end'] as Timestamp).toDate()
                  : data['task_end'],
              'task_date': (data['task_date'] is Timestamp)
                  ? (data['task_date'] as Timestamp).toDate()
                  : data['task_date'],
              'task_frequency': data['task_frequency'] ?? ['Only once'],
              'custom_days': data['custom_days'] ?? [],
              'next_taskdate': data['next_taskdate'],
              'inc_reason': data['inc_reason'] ?? '',
              'elderly_profilePic': profilePicUrl,
            });
          }
          // Sort by task_start ascending
          tasks.sort((a, b) {
            final aStart = a['task_start'] as DateTime? ?? now;
            final bStart = b['task_start'] as DateTime? ?? now;
            return aStart.compareTo(bStart);
          });
          return tasks;
        });
  }

  Future<void> _onRefresh(BuildContext context) async {
    // Trigger progressive task system when user pulls to refresh
    _checkProgressiveTaskSystem(context);
  }

  @override
  Widget build(BuildContext context) {
    _checkProgressiveTaskSystem(context);
    // Placeholder data for demonstration
    return RefreshIndicator(
      onRefresh: () => _onRefresh(context),
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
                  'Error loading incomplete tasks',
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
        
        final tasks = snapshot.data ?? [];
        // Group tasks by date
        Map<String, List<Map<String, dynamic>>> grouped = {};
        for (var task in tasks) {
          final date = task['task_date'] as DateTime?;
          if (date == null) continue;
          final key =
              "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
          grouped.putIfAbsent(key, () => []).add(task);
        }
        // Sort dates closest to today first
        final now = DateTime.now();
        final sortedKeys = grouped.keys.toList()
          ..sort((a, b) {
            final ad = DateTime.parse(a.replaceAll('-', ''));
            final bd = DateTime.parse(b.replaceAll('-', ''));
            return (ad.difference(now).inDays).abs().compareTo(
              (bd.difference(now).inDays).abs(),
            );
          });
        if (tasks.isEmpty) {
          return const Center(
            child: Text(
              'No Incomplete Tasks',
              style: TextStyle(fontSize: 18, color: Color(0xFF22688E), fontWeight: FontWeight.bold),
            ),
          );
        }
        return SizedBox.expand(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            children: [
              for (final key in sortedKeys)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 255, 243, 200),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Text(
                          formatHeaderDate(key),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Color(0xFF22688E),
                          ),
                        ),
                      ),
                      for (final task in grouped[key]!)
                        InkWell(
                          onTap: () {
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
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                      horizontal: 18,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Padding(
                                                  padding: const EdgeInsets.only(left: 8.0),
                                                  child: Text(
                                                    'Task Details',
                                                    style: const TextStyle(
                                                      fontSize: 22,
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                onPressed: () =>
                                                    Navigator.of(ctx).pop(),
                                              ),
                                            ],
                                          ),
                                          const Divider(),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.person,
                                                color: Color(0xFF22688E),
                                              ),
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
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                  ),
                                                  softWrap: true,
                                                  overflow: TextOverflow.visible,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.assignment,
                                                color: Color(0xFF22688E),
                                              ),
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
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                  ),
                                                  softWrap: true,
                                                  overflow: TextOverflow.visible,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.access_time,
                                                color: Color(0xFF22688E),
                                              ),
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
                                              Expanded(
                                                child: Text(
                                                  '${_formatSingleTime(task['task_start'])} - ${_formatSingleTime(task['task_end'])}',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                  ),
                                                  softWrap: true,
                                                  overflow: TextOverflow.visible,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.repeat,
                                                color: Color(0xFF22688E),
                                              ),
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
                                                  _formatFrequency(task),
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                  ),
                                                  softWrap: true,
                                                  overflow: TextOverflow.visible,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Icon(
                                                Icons.error_outline,
                                                color: Color(0xFFD32F2F),
                                              ),
                                              const SizedBox(width: 8),
                                              const Text(
                                                'Reason:',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: Color(0xFFD32F2F),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  task['inc_reason'] != null && task['inc_reason'].toString().trim().isNotEmpty
                                                    ? task['inc_reason']
                                                    : 'No reason provided.',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    color: Color(0xFFD32F2F),
                                                  ),
                                                  softWrap: true,
                                                  overflow: TextOverflow.visible,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.calendar_today,
                                                color: Color(0xFF22688E),
                                              ),
                                              const SizedBox(width: 8),
                                              const Text(
                                                'Date:',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: Color(0xFF22688E),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                task['task_date'] != null
                                                    ? '${task['task_date'].year}-${task['task_date'].month.toString().padLeft(2, '0')}-${task['task_date'].day.toString().padLeft(2, '0')}'
                                                    : '',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.schedule,
                                                color: Color(0xFF22688E),
                                              ),
                                              const SizedBox(width: 8),
                                              const Text(
                                                'Next Recurring:',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: Color(0xFF22688E),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _getNextRecurringDate(task),
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                  ),
                                                  softWrap: true,
                                                  overflow: TextOverflow.visible,
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
                          child: Card(
                            margin: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
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
                                      color: Color(0xFF1B7F5A),
                                    ),
                                    child: ClipOval(
                                      child: task['elderly_profilePic'] != null && task['elderly_profilePic'].toString().isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: task['elderly_profilePic'],
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          task['elderly_fname'] ?? '',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                            color: Color(0xFF22688E),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          task['task_description'] ?? '',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Reason: ${task['inc_reason'] ?? 'No reason provided'}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey,
                                          ),
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
                                            _formatSingleTime(
                                              task['task_start'],
                                            ),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Color(0xFF00588e),
                                              fontWeight: FontWeight.bold,
                                            ),
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
                                            _formatSingleTime(task['task_end']),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Color(0xFF00588e),
                                              fontWeight: FontWeight.bold,
                                            ),
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
        );
      },
    ),
    );
  }
}
