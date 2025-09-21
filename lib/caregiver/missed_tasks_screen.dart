import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'upcoming_tasks_screen.dart';

class MissedTasksScreen extends StatelessWidget {
  void _checkProgressiveTaskSystem(BuildContext context) async {
    try {
      print('🔄 MissedTasksScreen: Progressive system triggered at ${DateTime.now()}');
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        // Call the Progressive Task System from UpcomingTasksScreen
        final progressedTasks = await TaskService.checkAndProgressRecurringTasks(currentUser.uid);
        if (progressedTasks > 0) {
          print('✅ MissedTasksScreen: Progressed $progressedTasks recurring tasks');
        } else {
          print('ℹ️ MissedTasksScreen: No tasks needed progression');
        }
      }
    } catch (e) {
      print('❌ MissedTasksScreen: Error in progressive system: $e');
    }
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
  // DATE FILTER FUNCTIONALITY - COMMENTED OUT
  // final DateTime? selectedFilterDate;
  const MissedTasksScreen({super.key /*, this.selectedFilterDate*/});

  Stream<List<Map<String, dynamic>>> getTasksStream() {
    final user = FirebaseAuth.instance.currentUser;
    final caregiverId = user?.uid;
    
    return FirebaseFirestore.instance
      .collection('care_tasks')
      .where('task_status', arrayContains: 'Missed')
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
                profilePicUrl = elderlyData?['elderly_profilePic'] ?? elderlyData?['profile_pic'] ?? '';
              }
            } catch (e) {
              print('Error fetching elderly profile picture: $e');
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
            'freq_once_date': (data['freq_once_date'] is Timestamp) ? (data['freq_once_date'] as Timestamp).toDate() : data['freq_once_date'],
            'next_taskdate': (data['next_taskdate'] is Timestamp) ? (data['next_taskdate'] as Timestamp).toDate() : data['next_taskdate'],
            'profile_pic': profilePicUrl,
          });
        }
        // DATE FILTER FUNCTIONALITY - COMMENTED OUT
        // Filter by selected date if set
        // if (selectedFilterDate != null) {
        //   final filterDate = DateTime(selectedFilterDate!.year, selectedFilterDate!.month, selectedFilterDate!.day);
        //   tasks = tasks.where((task) {
        //     final taskDate = task['task_date'] as DateTime?;
        //     final freqList = task['task_frequency'] as List<dynamic>? ?? [];
        //     final freq = freqList.isNotEmpty ? freqList[0] as String : 'Only once';
        //     if (taskDate == null) return false;
        //     final startDate = DateTime(taskDate.year, taskDate.month, taskDate.day);
        //     switch (freq) {
        //       case 'Only once':
        //         return filterDate.year == startDate.year && filterDate.month == startDate.month && filterDate.day == startDate.day;
        //       case 'Every Assigned Day':
        //         return filterDate.year == startDate.year && filterDate.month == startDate.month && filterDate.day == startDate.day;
        //       case 'Custom':
        //         return filterDate.year == startDate.year && filterDate.month == startDate.month && filterDate.day == startDate.day;
        //       default:
        //         return false;
        //     }
        //   }).toList();
        // }
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
    return RefreshIndicator(
      onRefresh: () => _onRefresh(context),
      child: StreamBuilder<List<Map<String, dynamic>>>(
      stream: getTasksStream(),
      builder: (context, snapshot) {
        List<Map<String, dynamic>> tasks = snapshot.data ?? [];
        
        // Group tasks by their display date
        Map<String, List<Map<String, dynamic>>> grouped = {};
        for (var task in tasks) {
          DateTime? displayDate;
          final freqList = task['task_frequency'] as List<dynamic>? ?? [];
          final freq = freqList.isNotEmpty ? freqList[0] as String : 'Only once';
          
          // For missed tasks, use the date when they were supposed to occur
          if (freq == 'Only once') {
            displayDate = task['freq_once_date'] as DateTime? ?? task['task_date'] as DateTime?;
          } else {
            // For recurring tasks, use next_taskdate or task_date
            displayDate = task['next_taskdate'] as DateTime? ?? task['task_date'] as DateTime?;
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

        if (tasks.isEmpty) {
          return const Center(
            child: Text(
              'No Missed Tasks',
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
                color: const Color(0xFFFDE6E6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(
                      MissedTasksScreen.formatHeaderDate(key),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF22688E)),
                    ),
                  ),
                  for (final task in grouped[key]!)
                    InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext ctx) {
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
                                            child: Center(
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
                                            icon: const Icon(Icons.close, size: 25, color: Color(0xFF22688E)),
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
                                      const SizedBox(height: 10),
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
                                      const SizedBox(height: 10),
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.repeat, color: Color(0xFF22688E)),
                                          const SizedBox(width: 8),
                                          const Text('Frequency:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _formatFrequency(task),
                                              style: const TextStyle(fontSize: 16),
                                              softWrap: true,
                                              overflow: TextOverflow.visible,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          const Icon(Icons.access_time, color: Color(0xFF22688E)),
                                          const SizedBox(width: 8),
                                          const Text('Time:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${_formatSingleTime(task['task_start'])} - ${_formatSingleTime(task['task_end'])}',
                                            style: const TextStyle(fontSize: 16),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          const Icon(Icons.calendar_today, color: Color(0xFF22688E)),
                                          const SizedBox(width: 8),
                                          const Text('Date:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                          const SizedBox(width: 8),
                                          Text(
                                            task['task_date'] != null
                                              ? '${task['task_date'].year}-${task['task_date'].month.toString().padLeft(2, '0')}-${task['task_date'].day.toString().padLeft(2, '0')}'
                                              : '',
                                            style: const TextStyle(fontSize: 16),
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
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color.fromARGB(255, 255, 176, 176),
                                ),
                                child: ClipOval(
                                  child: task['profile_pic'] != null && task['profile_pic'].toString().isNotEmpty
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task['elderly_fname'] ?? '',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF22688E)),
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
                                        _formatSingleTime(task['task_start']),
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
                                        _formatSingleTime(task['task_end']),
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
    );
      },
    ),
    );
  }


  String _formatSingleTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : hour == 0 ? 12 : hour;
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


  }
