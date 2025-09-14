import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MissedTasksScreen extends StatelessWidget {
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
  final DateTime? selectedFilterDate;
  const MissedTasksScreen({Key? key, this.selectedFilterDate}) : super(key: key);

  Stream<List<Map<String, dynamic>>> getTasksStream() {
    return FirebaseFirestore.instance
      .collection('care_tasks')
      .where('task_status', arrayContains: 'Missed')
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
            'task_frequency': data['task_frequency'] ?? ['Only once'],
          };
        }).toList();
        // Filter by selected date if set
        if (selectedFilterDate != null) {
          final filterDate = DateTime(selectedFilterDate!.year, selectedFilterDate!.month, selectedFilterDate!.day);
          tasks = tasks.where((task) {
            final taskDate = task['task_date'] as DateTime?;
            final freqList = task['task_frequency'] as List<dynamic>? ?? [];
            final freq = freqList.isNotEmpty ? freqList[0] as String : 'Only once';
            if (taskDate == null) return false;
            final startDate = DateTime(taskDate.year, taskDate.month, taskDate.day);
            switch (freq) {
              case 'Only once':
                return filterDate.year == startDate.year && filterDate.month == startDate.month && filterDate.day == startDate.day;
              case 'Everyday':
                return !filterDate.isBefore(startDate);
              case 'Every other day': {
                final diff = filterDate.difference(startDate).inDays;
                return diff >= 0 && diff % 2 == 0;
              }
              case 'Once a week': {
                final diff = filterDate.difference(startDate).inDays;
                return diff >= 0 && filterDate.weekday == startDate.weekday;
              }
              default:
                return false;
            }
          }).toList();
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

  @override
  Widget build(BuildContext context) {
    // Placeholder data for demonstration
    final List<Map<String, dynamic>> tasks = [
      {
        'elderly_fname': 'Lola Maria',
        'task_description': 'Missed morning medicine',
        'task_start': DateTime(2025, 9, 13, 8, 0),
        'task_end': DateTime(2025, 9, 13, 8, 30),
        'task_date': DateTime(2025, 9, 13),
      },
      {
        'elderly_fname': 'Lolo Juan',
        'task_description': 'Missed physical therapy',
        'task_start': DateTime(2025, 9, 13, 10, 0),
        'task_end': DateTime(2025, 9, 13, 11, 0),
        'task_date': DateTime(2025, 9, 13),
      },
      {
        'elderly_fname': 'Lola Maria',
        'task_description': 'Missed evening walk',
        'task_start': DateTime(2025, 9, 14, 18, 0),
        'task_end': DateTime(2025, 9, 14, 18, 30),
        'task_date': DateTime(2025, 9, 14),
      },
    ];

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
        final ad = DateTime.parse(a.replaceAll('-', ''));
        final bd = DateTime.parse(b.replaceAll('-', ''));
        return (ad.difference(now).inDays).abs().compareTo((bd.difference(now).inDays).abs());
      });
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
                                              (task['task_frequency'] is List && task['task_frequency'].isNotEmpty)
                                                ? (task['task_frequency'] as List).join(', ')
                                                : (task['task_frequency']?.toString() ?? ''),
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
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(255, 255, 176, 176),
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

  }


  String _formatSingleTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : hour == 0 ? 12 : hour;
    return '$hour12:$minute $ampm';
  }
  }
