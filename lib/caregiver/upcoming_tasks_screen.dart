import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Helper function to create a new task and set 'created_by' to the current caregiver's UID
Future<void> createTaskWithCreator(Map<String, dynamic> taskData) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final caregiverId = currentUser?.uid;
  final dataWithCreator = Map<String, dynamic>.from(taskData);
  if (caregiverId != null) {
    dataWithCreator['created_by'] = caregiverId;
  }
  await FirebaseFirestore.instance.collection('care_tasks').add(dataWithCreator);
}

// Firestore helper/service class for task updates

class TaskService {
  // Reference to the 'care_tasks' collection in Firestore
  static final _tasksRef = FirebaseFirestore.instance.collection('care_tasks');

  /// Soft deletes a task by updating its 'task_status' to ['Deleted'].
  /// This keeps the task in the database but marks it as deleted for filtering.
  static Future<void> deleteTask(String docId) async {
    await _tasksRef.doc(docId).update({'task_status': ['Deleted']});
  }

  /// Updates a task document with the provided data map.
  /// Used for editing task details or other field updates.
  static Future<void> updateTask(String docId, Map<String, dynamic> updateData) async {
    await _tasksRef.doc(docId).update(updateData);
  }

  /// Marks a task as complete and updates its 'task_date' and 'next_taskdate'.
  /// Used for recurring tasks to set the next occurrence date.
  static Future<void> markTaskComplete(String docId, DateTime? newTaskDate, DateTime? newNextTaskDate) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final caregiverId = currentUser?.uid;
    await _tasksRef.doc(docId).update({
      'task_status': ['Complete'],
      'task_date': newTaskDate,
      'next_taskdate': newNextTaskDate,
      if (caregiverId != null) 'created_by': caregiverId,
    });
  }

  /// Marks a task as incomplete and records the reason for incompletion.
  /// Updates 'inc_reason' and sets 'task_status' to ['Incomplete'].
  static Future<void> markTaskIncomplete(String docId, String reasonText) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final caregiverId = currentUser?.uid;
    await _tasksRef.doc(docId).update({
      'inc_reason': reasonText,
      'task_status': ['Incomplete'],
      if (caregiverId != null) 'created_by': caregiverId,
    });
  }
}

// Task Action Buttons Widget
class TaskActionButtons extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClose;
  const TaskActionButtons({
    super.key,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.edit, size: 24, color: Color(0xFF22688E)),
          tooltip: 'Edit Task',
          onPressed: onEdit,
        ),
        IconButton(
          icon: const Icon(Icons.delete, size: 24, color: Color(0xFFB71C1C)),
          tooltip: 'Delete Task',
          onPressed: onDelete,
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 25, color: Color(0xFF22688E)),
          onPressed: onClose,
        ),
      ],
    );
  }
}

// Edit Task Dialog Widget
class EditTaskDialog extends StatefulWidget {
  final Map<String, dynamic> task;
  final BuildContext parentContext;
  const EditTaskDialog({super.key, required this.task, required this.parentContext});

  @override
  State<EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<EditTaskDialog> {
  late TextEditingController activityController;
  TimeOfDay? startTime;
  TimeOfDay? endTime;
  String? selectedFrequency;
  DateTime? selectedDate;
  List<String> selectedDaysBox = [];
  List<String> everydayDays = [];

  @override
  void initState() {
    super.initState();
    activityController = TextEditingController(text: widget.task['task_description'] ?? '');
    startTime = widget.task['task_start'] != null ? TimeOfDay.fromDateTime(widget.task['task_start']) : null;
    endTime = widget.task['task_end'] != null ? TimeOfDay.fromDateTime(widget.task['task_end']) : null;
    selectedFrequency = (widget.task['task_frequency'] is List && widget.task['task_frequency'].isNotEmpty) ? widget.task['task_frequency'][0] : 'Only once';
    selectedDate = widget.task['freq_once_date'] is DateTime ? widget.task['freq_once_date'] : null;
    selectedDaysBox = List<String>.from(widget.task['custom_days'] ?? []);
    everydayDays = List<String>.from(widget.task['everyday_days'] ?? []);
  }

  @override
  Widget build(BuildContext context) {
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
                  const Text('Edit Task', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF22688E))),
                  IconButton(
                    icon: const Icon(Icons.close, size: 25, color: Color(0xFF22688E)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.assignment, color: Color(0xFF22688E)),
                  const SizedBox(width: 8),
                  const Text('Activity:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: activityController,
                decoration: const InputDecoration(
                  hintText: 'Enter activity name',
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: 16),
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
                    child: InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: startTime ?? TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setState(() {
                            startTime = picked;
                          });
                        }
                      },
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(0xFFE6F3FA),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(startTime != null ? startTime!.format(context) : 'Start', style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: endTime ?? TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setState(() {
                            endTime = picked;
                          });
                        }
                      },
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(0xFFE6F3FA),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(endTime != null ? endTime!.format(context) : 'End', style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.date_range, color: Color(0xFF22688E)),
                  const SizedBox(width: 8),
                  const Text('Frequency', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: selectedFrequency,
                isExpanded: true,
                items: ['Only once', 'Everyday', 'Custom'].map((freq) {
                  return DropdownMenuItem<String>(
                    value: freq,
                    child: Text(freq),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedFrequency = value;
                  });
                },
              ),
              if (selectedFrequency == 'Custom') ...[
                const SizedBox(height: 8),
                Text('Selected Days: ${selectedDaysBox.join(", ")}', style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () async {
                    const allDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
                    List<String> tempSelectedDays = List<String>.from(selectedDaysBox);
                    await showDialog(
                      context: context,
                      builder: (BuildContext daysCtx) {
                        return AlertDialog(
                          title: const Text('Select Days'),
                          content: SizedBox(
                            width: double.maxFinite,
                            child: ListView(
                              shrinkWrap: true,
                              children: allDays.map((day) {
                                return CheckboxListTile(
                                  title: Text(day),
                                  value: tempSelectedDays.contains(day),
                                  onChanged: (checked) {
                                    if (checked == true) {
                                      tempSelectedDays.add(day);
                                    } else {
                                      tempSelectedDays.remove(day);
                                    }
                                    (daysCtx as Element).markNeedsBuild();
                                  },
                                );
                              }).toList(),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(daysCtx).pop();
                              },
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  selectedDaysBox = List<String>.from(tempSelectedDays);
                                });
                                Navigator.of(daysCtx).pop();
                              },
                              child: const Text('OK'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Color(0xFFE6F3FA),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Pick Days', style: TextStyle(color: Color(0xFF000000))),
                ),
              ],
              if (selectedFrequency == 'Only once') ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
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
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(0xFFE6F3FA),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(selectedDate != null ? formatDate(selectedDate!) : 'Select Date', style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  final docId = widget.task['task_id'];
                  final tasksRef = FirebaseFirestore.instance.collection('care_tasks');
                  final updateData = {
                    'task_description': activityController.text,
                    'task_start': startTime != null ? DateTime(selectedDate?.year ?? DateTime.now().year, selectedDate?.month ?? DateTime.now().month, selectedDate?.day ?? DateTime.now().day, startTime!.hour, startTime!.minute) : widget.task['task_start'],
                    'task_end': endTime != null ? DateTime(selectedDate?.year ?? DateTime.now().year, selectedDate?.month ?? DateTime.now().month, selectedDate?.day ?? DateTime.now().day, endTime!.hour, endTime!.minute) : widget.task['task_end'],
                    'task_frequency': [selectedFrequency ?? 'Only once'],
                    'freq_once_date': selectedFrequency == 'Only once' ? selectedDate : null,
                    'custom_days': selectedFrequency == 'Custom' ? selectedDaysBox : [],
                    'everyday_days': selectedFrequency == 'Everyday' ? everydayDays : [],
                  };
                  await tasksRef.doc(docId).update(updateData);
                  Navigator.of(context).pop();
                  Navigator.of(widget.parentContext).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF22688E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Helper formatting functions
String formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String formatTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

// Task Details Dialog Widget
class TaskDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onComplete;
  final VoidCallback onIncomplete;
  final VoidCallback onClose;
  final bool showReasonInput;
  final TextEditingController reasonController;
  const TaskDetailsDialog({
    super.key,
    required this.task,
    required this.onEdit,
    required this.onDelete,
    required this.onComplete,
    required this.onIncomplete,
    required this.onClose,
    required this.showReasonInput,
    required this.reasonController,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.edit, size: 24, color: Color(0xFF22688E)), tooltip: 'Edit Task', onPressed: onEdit),
                      IconButton(icon: const Icon(Icons.delete, size: 24, color: Color(0xFFB71C1C)), tooltip: 'Delete Task', onPressed: onDelete),
                      IconButton(icon: const Icon(Icons.check_circle, color: Color(0xFF22688E)), tooltip: 'Complete Task', onPressed: onComplete),
                      IconButton(icon: const Icon(Icons.cancel, color: Color(0xFFD32F2F)), tooltip: 'Incomplete Task', onPressed: onIncomplete),
                      IconButton(icon: const Icon(Icons.close, size: 25, color: Color(0xFF22688E)), onPressed: onClose),
                    ],
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
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.access_time, color: Color(0xFF22688E)),
                  const SizedBox(width: 8),
                  const Text('Time:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E)),),
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
                  const Text('Frequency:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (() {
                        final freqList = task['task_frequency'] as List<dynamic>? ?? [];
                        final freq = freqList.isNotEmpty ? freqList[0] as String : 'Only once';
                        if (freq == 'Only once') {
                          final onceDate = task['freq_once_date'];
                          if (onceDate != null) {
                            if (onceDate is DateTime) {
                              return 'Only once (${formatDate(onceDate)})';
                            } else if (onceDate is String) {
                              return 'Only once ($onceDate)';
                            }
                          }
                          return 'Only once';
                        } else if (freq == 'Every Workday') {
                          final everydayDays = task['everyday_days'] as List<dynamic>? ?? [];
                          if (everydayDays.isNotEmpty) {
                            return 'Every Workday (${everydayDays.join(', ')})';
                          }
                          return 'Every Workday';
                        } else if (freq == 'Custom') {
                          final customDays = task['custom_days'] as List<dynamic>? ?? [];
                          if (customDays.isNotEmpty) {
                            return 'Custom (${customDays.join(', ')})';
                          }
                          return 'Custom';
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
                  const Icon(Icons.calendar_today, color: Color(0xFF22688E)),
                  const SizedBox(width: 8),
                  const Text('Created:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                  const SizedBox(width: 8),
                  Text(
                    (() {
                      final created = task['created_at'];
                      if (created == null) return '';
                      if (created is DateTime) {
                        return '${formatDate(created)} at ${formatTime(created)}';
                      } else if (created is Timestamp) {
                        final dt = created.toDate();
                        return '${formatDate(dt)} at ${formatTime(dt)}';
                      }
                      return created.toString();
                    })(),
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // ...existing action buttons and reason input logic can be moved here as needed...
            ],
          ),
        ),
      ),
    );
  }
}
// ...imports already at top, remove these duplicates
class UpcomingTasksScreen extends StatelessWidget {
  // Utility to parse "HH:mm" string to TimeOfDay
  TimeOfDay _parseTimeOfDay(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  // Utility to check if a TimeOfDay is within a range
  bool _isTimeWithinRange(TimeOfDay picked, TimeOfDay start, TimeOfDay end) {
    final pickedMinutes = picked.hour * 60 + picked.minute;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    return pickedMinutes >= startMinutes && pickedMinutes <= endMinutes;
  }

  // Removed unused _getCaregiverTimeRange function
  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return '';
    final year = dateTime.year;
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
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
  final DateTime? selectedFilterDate;
  const UpcomingTasksScreen({super.key, this.selectedFilterDate});

  Stream<List<Map<String, dynamic>>> getTasksStream() {
    final user = FirebaseAuth.instance.currentUser;
    final caregiverId = user?.uid;
    return FirebaseFirestore.instance
      .collection('care_tasks')
      .where('task_status', arrayContains: 'Upcoming')
      .where('caregiver_id', isEqualTo: caregiverId)
      .snapshots()
      .map((snapshot) {
        List<Map<String, dynamic>> tasks = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'task_id': data['task_id'] ?? doc.id,
            'elderly_fname': data['elderly_fname'] ?? '',
            'task_description': data['task_description'] ?? '',
            'task_start': (data['task_start'] is Timestamp) ? (data['task_start'] as Timestamp).toDate() : data['task_start'],
            'task_end': (data['task_end'] is Timestamp) ? (data['task_end'] as Timestamp).toDate() : data['task_end'],
            'task_date': (data['task_date'] is Timestamp) ? (data['task_date'] as Timestamp).toDate() : data['task_date'],
            'created_at': (data['created_at'] is Timestamp) ? (data['created_at'] as Timestamp).toDate() : data['created_at'],
            'task_frequency': data['task_frequency'] ?? [],
            'custom_days': data['custom_days'] ?? [],
            'everyday_days': data['everyday_days'] ?? [],
            'freq_once_date': (data['freq_once_date'] is Timestamp) ? (data['freq_once_date'] as Timestamp).toDate() : data['freq_once_date'],
          };
        }).toList();
        // ...existing filter and sort logic...
        return tasks;
      });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: getTasksStream(),
      builder: (context, snapshot) {
        List<Map<String, dynamic>> tasks = snapshot.data ?? [];
        // Apply date filter if provided
        if (selectedFilterDate != null) {
          final filterDate = DateTime(selectedFilterDate!.year, selectedFilterDate!.month, selectedFilterDate!.day);
          // Get caregiver assigned days from parent/dialog context (must be passed in)
          // For this example, we'll assume caregiverAssignedDays is available as a static list (replace with your actual source)
          final List<String> caregiverAssignedDays = [
            'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday' // Example, replace with actual
          ];
          final weekdayName = [
            'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
          ][filterDate.weekday - 1];
          tasks = tasks.where((task) {
            final taskDate = task['task_date'] as DateTime?;
            final freqList = task['task_frequency'] as List<dynamic>? ?? [];
            final freq = freqList.isNotEmpty ? freqList[0] as String : 'Only once';
            final customDays = task['custom_days'] as List<dynamic>? ?? [];
            if (taskDate == null) return false;
            final startDate = DateTime(taskDate.year, taskDate.month, taskDate.day);
            switch (freq) {
              case 'Only once':
                return filterDate.year == startDate.year && filterDate.month == startDate.month && filterDate.day == startDate.day;
              case 'Every Workday': {
                // Show on all assigned days after start date
                if (!filterDate.isBefore(startDate) && caregiverAssignedDays.contains(weekdayName)) {
                  // If the task's start date is before or equal to the filter date, and the filter date is a working day
                  return true;
                }
                return false;
              }
              case 'Custom': {
                // Show only on selected and assigned days after start date
                if (!filterDate.isBefore(startDate) && customDays.contains(weekdayName) && caregiverAssignedDays.contains(weekdayName)) {
                  return true;
                }
                return false;
              }
              default:
                return false;
            }
          }).toList();
        }
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
          child: Column(
            children: [
              // Only one set of Add/Delete Task buttons at the top
              Expanded(
                child: tasks.isEmpty
                  ? const Center(child: Text('No Upcoming Tasks', style: TextStyle(fontSize: 18, color: Color(0xFF22688E), fontWeight: FontWeight.bold)))
                  : ListView(
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
                                    UpcomingTasksScreen.formatHeaderDate(key),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF22688E)),
                                  ),
                                ),
                                for (final task in (grouped[key]!..sort((a, b) {
                                  final aStart = a['task_start'] as DateTime? ?? DateTime.now();
                                  final bStart = b['task_start'] as DateTime? ?? DateTime.now();
                                  return aStart.compareTo(bStart);
                                })))
                                  InkWell(
                                    onTap: () {
                                      bool showReasonInput = false;
                                      TextEditingController reasonController = TextEditingController();
                                      showDialog(
                                        context: context,
                                        builder: (BuildContext ctx) {
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
                                                            TaskActionButtons(
                                                              onEdit: () async {
                                                                await showDialog(
                                                                  context: ctx,
                                                                  builder: (BuildContext editCtx) {
                                                                    return EditTaskDialog(task: task, parentContext: ctx);
                                                                  },
                                                                );
                                                              },
                                                              onDelete: () async {
                                                                final confirm = await showDialog<bool>(
                                                                  context: ctx,
                                                                  builder: (BuildContext confirmCtx) {
                                                                    return AlertDialog(
                                                                      title: const Text('Delete Task'),
                                                                      content: const Text('Are you sure you want to delete this task?'),
                                                                      actions: [
                                                                        TextButton(
                                                                          onPressed: () => Navigator.of(confirmCtx).pop(false),
                                                                          child: const Text('Cancel'),
                                                                        ),
                                                                        ElevatedButton(
                                                                          style: ElevatedButton.styleFrom(
                                                                            backgroundColor: Color(0xFFB71C1C),
                                                                          ),
                                                                          onPressed: () => Navigator.of(confirmCtx).pop(true),
                                                                          child: const Text('Delete', style: TextStyle(color: Colors.white)),
                                                                        ),
                                                                      ],
                                                                    );
                                                                  },
                                                                );
                                                                if (confirm == true) {
                                                                  // Soft delete: update 'task_status' to ['Deleted']
                                                                  final docId = task['task_id'];
                                                                  await TaskService.deleteTask(docId);
                                                                  Navigator.of(ctx).pop();
                                                                }
                                                              },
                                                              onClose: () => Navigator.of(ctx).pop(),
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
                                                    const SizedBox(height: 12),
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
                                                    const SizedBox(height: 12),
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.access_time, color: Color(0xFF22688E)),
                                                        const SizedBox(width: 8),
                                                        const Text('Time:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E)),),
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
                                                        const Text('Frequency:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                        const SizedBox(width: 8),
                                                        Expanded(
                                                          child: Text(
                                                            (() {
                                                              final freqList = task['task_frequency'] as List<dynamic>? ?? [];
                                                              final freq = freqList.isNotEmpty ? freqList[0] as String : 'Only once';
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
                                                              } else if (freq == 'Every Workday') {
                                                                final everydayDays = task['everyday_days'] as List<dynamic>? ?? [];
                                                                if (everydayDays.isNotEmpty) {
                                                                  return 'Every Workday (${everydayDays.join(', ')})';
                                                                }
                                                                return 'Every Workday';
                                                              } else if (freq == 'Custom') {
                                                                final customDays = task['custom_days'] as List<dynamic>? ?? [];
                                                                if (customDays.isNotEmpty) {
                                                                  return 'Custom (${customDays.join(', ')})';
                                                                }
                                                                return 'Custom';
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
                                                        const Icon(Icons.calendar_today, color: Color(0xFF22688E)),
                                                        const SizedBox(width: 8),
                                                        const Text('Created:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          (() {
                                                            final created = task['created_at'];
                                                            if (created == null) return '';
                                                            if (created is DateTime) {
                                                              return '${_formatDate(created)} at ${_formatTime(created)}';
                                                            } else if (created is Timestamp) {
                                                              final dt = created.toDate();
                                                              return '${_formatDate(dt)} at ${_formatTime(dt)}';
                                                            }
                                                            return created.toString();
                                                          })(),
                                                          style: const TextStyle(fontSize: 16),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 20),
                                                    !showReasonInput
                                                        ? Row(
                                                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                            children: [
                                                              Flexible(
                                                                child: TextButton.icon(
                                                                  onPressed: () async {
                                                                    bool confirmChecked = false;
                                                                    await showDialog(
                                                                      context: ctx,
                                                                      builder: (BuildContext confirmCtx) {
                                                                        return StatefulBuilder(
                                                                          builder: (context, setState) {
                                                                            return AlertDialog(
                                                                              title: const Text('Confirm Completion'),
                                                                              content: Column(
                                                                                mainAxisSize: MainAxisSize.min,
                                                                                children: [
                                                                                  const Text('Please confirm that you have completed this task.'),
                                                                                  CheckboxListTile(
                                                                                    value: confirmChecked,
                                                                                    onChanged: (checked) {
                                                                                      setState(() {
                                                                                        confirmChecked = checked ?? false;
                                                                                      });
                                                                                    },
                                                                                    title: const Text('I hereby confirm that the task is completed'),
                                                                                  ),
                                                                                ],
                                                                              ),
                                                                              actions: [
                                                                                TextButton(
                                                                                  onPressed: () => Navigator.of(confirmCtx).pop(),
                                                                                  child: const Text('Cancel'),
                                                                                ),
                                                                                ElevatedButton(
                                                                                  onPressed: confirmChecked
                                                                                      ? () async {
                                                                                          final docId = task['task_id'];
                                                                                          // Get current next_taskdate and frequency info
                                                                                          final docSnap = await TaskService._tasksRef.doc(docId).get();
                                                                                          final data = docSnap.data();
                                                                                          DateTime? prevNextTaskDate;
                                                                                          if (data != null && data['next_taskdate'] != null) {
                                                                                            prevNextTaskDate = (data['next_taskdate'] is Timestamp)
                                                                                              ? (data['next_taskdate'] as Timestamp).toDate()
                                                                                              : data['next_taskdate'] as DateTime;
                                                                                          }
                                                                                          // Calculate new next_taskdate for recurring tasks
                                                                                          List<String> caregiverAssignedDays = List<String>.from(data?['everyday_days'] ?? []);
                                                                                          List<String> customDays = List<String>.from(data?['custom_days'] ?? []);
                                                                                          List<String> taskFrequency = List<String>.from(data?['task_frequency'] ?? []);
                                                                                          DateTime now = DateTime.now();
                                                                                          DateTime? newNextTaskDate;
                                                                                          DateTime? newTaskDate = prevNextTaskDate;
                                                                                          DateTime taskStart = (data?['task_start'] is Timestamp)
                                                                                            ? (data?['task_start'] as Timestamp).toDate()
                                                                                            : data?['task_start'] as DateTime;
                                                                                          // Helper weekday string
                                                                                          String weekdayStr(DateTime d) => ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"][d.weekday-1];
                                                                                          if (taskFrequency.contains('Every Workday') && caregiverAssignedDays.isNotEmpty) {
                                                                                            for (int i = 1; i < 15; i++) {
                                                                                              DateTime candidate = (prevNextTaskDate ?? now).add(Duration(days: i));
                                                                                              String wd = weekdayStr(candidate);
                                                                                              if (caregiverAssignedDays.contains(wd)) {
                                                                                                newNextTaskDate = DateTime(candidate.year, candidate.month, candidate.day, taskStart.hour, taskStart.minute);
                                                                                                break;
                                                                                              }
                                                                                            }
                                                                                          } else if (taskFrequency.contains('Custom') && caregiverAssignedDays.isNotEmpty && customDays.isNotEmpty) {
                                                                                            for (int i = 1; i < 15; i++) {
                                                                                              DateTime candidate = (prevNextTaskDate ?? now).add(Duration(days: i));
                                                                                              String wd = weekdayStr(candidate);
                                                                                              if (caregiverAssignedDays.contains(wd) && customDays.contains(wd)) {
                                                                                                newNextTaskDate = DateTime(candidate.year, candidate.month, candidate.day, taskStart.hour, taskStart.minute);
                                                                                                break;
                                                                                              }
                                                                                            }
                                                                                          }
                                                                                          await TaskService.markTaskComplete(docId, newTaskDate, newNextTaskDate);
                                                                                          Navigator.of(confirmCtx).pop();
                                                                                          Navigator.of(ctx).pop();
                                                                                        }
                                                                                      : null,
                                                                                  child: const Text('Submit'),
                                                                                ),
                                                                              ],
                                                                            );
                                                                          },
                                                                        );
                                                                      },
                                                                    );
                                                                  },
                                                                  icon: const Icon(Icons.check_circle, color: Color(0xFF22688E)),
                                                                  label: const Text('Complete', style: TextStyle(color: Color(0xFF22688E), fontWeight: FontWeight.bold, fontSize: 16)),
                                                                  style: TextButton.styleFrom(
                                                                    backgroundColor: const Color(0xFFE6F3FA),
                                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(width: 8),
                                                              Flexible(
                                                                child: TextButton.icon(
                                                                  onPressed: () {
                                                                    setState(() {
                                                                      showReasonInput = true;
                                                                    });
                                                                  },
                                                                  icon: const Icon(Icons.cancel, color: Color(0xFFD32F2F)),
                                                                  label: const Text('Incomplete', style: TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold, fontSize: 16)),
                                                                  style: TextButton.styleFrom(
                                                                    backgroundColor: const Color(0xFFFDEAEA),
                                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          )
                                                        : Column(
                                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                                            children: [
                                                              const Text('Reason for Incompletion:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFD32F2F))),
                                                              const SizedBox(height: 10),
                                                              Container(
                                                                decoration: BoxDecoration(
                                                                  color: Color(0xFFFDEAEA),
                                                                  borderRadius: BorderRadius.circular(12),
                                                                ),
                                                                child: TextField(
                                                                  controller: reasonController,
                                                                  maxLines: 3,
                                                                  decoration: const InputDecoration(
                                                                    hintText: 'Type reason here',
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
                                                                  onPressed: () async {
                                                                    final reasonText = reasonController.text.trim();
                                                                    if (reasonText.isNotEmpty) {
                                                                      final docId = task['task_id'];
                                                                      await TaskService.markTaskIncomplete(docId, reasonText);
                                                                      Navigator.of(ctx).pop();
                                                                    }
                                                                  },
                                                                  style: ElevatedButton.styleFrom(
                                                                    backgroundColor: const Color(0xFF22688E),
                                                                    shape: RoundedRectangleBorder(
                                                                      borderRadius: BorderRadius.circular(16),
                                                                    ),
                                                                  ),
                                                                  child: const Text('Submit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
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
                                                Text(
                                                  task['task_start'] != null ? _formatTime(task['task_start']) : '',
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
                                                  task['task_end'] != null ? _formatTime(task['task_end']) : '',
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
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    SizedBox(
                      width: 140,
                      child: ElevatedButton(
                        onPressed: () async {
                          final caregiverId = await _getCurrentCaregiverId(context);
                          List<Map<String, dynamic>> assignedElderly = await _getAssignedElderlyForCaregiver(caregiverId);
                          List<String> caregiverAssignedDays = [];
                          Map<String, String> caregiverTimeRange = {'start': '00:00', 'end': '23:59'};
                          final assignSnap = await FirebaseFirestore.instance
                            .collection('cg_house_assign')
                            .where('caregiver_id', isEqualTo: caregiverId)
                            .get();
                          if (assignSnap.docs.isNotEmpty) {
                            caregiverAssignedDays = List<String>.from(assignSnap.docs.first.data()['days_assigned'] ?? []);
                            final timeRange = assignSnap.docs.first.data()['time_range'] as Map<String, dynamic>? ?? {};
                            caregiverTimeRange = {
                              'start': timeRange['start'] ?? '00:00',
                              'end': timeRange['end'] ?? '23:59',
                            };
                          }
                          final rangeStart = _parseTimeOfDay(caregiverTimeRange['start']!);
                          final rangeEnd = _parseTimeOfDay(caregiverTimeRange['end']!);
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (BuildContext ctx) {
                              String? selectedElderly;
                              String? selectedFrequency = 'Only once';
                              TimeOfDay? startTime;
                              TimeOfDay? endTime;
                              TextEditingController activityController = TextEditingController();
                              final List<String> frequencyList = ['Only once', 'Every Workday', 'Custom'];
                              DateTime? selectedDate;
                              List<String> selectedDaysBox = [];
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
                                              padding: EdgeInsets.zero,
                                              child: DropdownButtonHideUnderline(
                                                child: DropdownButton2<String>(
                                                  value: selectedElderly,
                                                  isExpanded: true,
                                                  hint: const Text('Select Elderly', style: TextStyle(color: Color.fromARGB(255, 0, 0, 0))),
                                                  buttonStyleData: const ButtonStyleData(
                                                    height: 40,
                                                    padding: EdgeInsets.zero,
                                                    decoration: BoxDecoration(
                                                      color: Color(0xFFE6F3FA),
                                                      borderRadius: BorderRadius.all(Radius.circular(20)),
                                                    ),
                                                  ),
                                                  dropdownStyleData: DropdownStyleData(
                                                    maxHeight: 200,
                                                    decoration: BoxDecoration(
                                                      color: Color(0xFFE6F3FA),
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                  ),
                                                  items: assignedElderly.map((elderly) {
                                                    return DropdownMenuItem<String>(
                                                      value: elderly['elderly_id'],
                                                      child: Text(elderly['elderly_fname'], style: const TextStyle(color: Color.fromARGB(255, 0, 0, 0))),
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
                                                              initialTime: startTime ?? rangeStart,
                                                            );
                                                            if (picked != null) {
                                                              if (_isTimeWithinRange(picked, rangeStart, rangeEnd)) {
                                                                setState(() {
                                                                  startTime = picked;
                                                                });
                                                              } else {
                                                                showDialog(
                                                                  context: ctx,
                                                                  builder: (context) => AlertDialog(
                                                                    title: const Text('Invalid Time'),
                                                                    content: const Text('The picked task time is beyond your work hours. Please choose another for the task.'),
                                                                    actions: [
                                                                      TextButton(
                                                                        onPressed: () => Navigator.of(context).pop(),
                                                                        child: const Text('OK'),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                );
                                                              }
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
                                                              initialTime: endTime ?? rangeEnd,
                                                            );
                                                            if (picked != null) {
                                                              if (_isTimeWithinRange(picked, rangeStart, rangeEnd)) {
                                                                setState(() {
                                                                  endTime = picked;
                                                                });
                                                              } else {
                                                                showDialog(
                                                                  context: ctx,
                                                                  builder: (context) => AlertDialog(
                                                                    title: const Text('Invalid Time'),
                                                                    content: const Text('The picked task time is beyond your work hours. Please choose another for the task.'),
                                                                    actions: [
                                                                      TextButton(
                                                                        onPressed: () => Navigator.of(context).pop(),
                                                                        child: const Text('OK'),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                );
                                                              }
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
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Container(
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
                                              // Custom frequency: show multi-select days dropdown
                                              if (selectedFrequency == 'Custom') ...[
                                                const SizedBox(height: 16),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.event, color: Color(0xFF22688E)),
                                                    const SizedBox(width: 8),
                                                    const Text('Select Days', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Container(
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFE6F3FA),
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  child: InkWell(
                                                    onTap: () async {
                                                      List<String> tempSelectedDays = List<String>.from(selectedDaysBox);
                                                      // Sort assigned days in standard weekday order
                                                      const weekdayOrder = [
                                                        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
                                                      ];
                                                      List<String> sortedAssignedDays = List<String>.from(caregiverAssignedDays);
                                                      sortedAssignedDays.sort((a, b) =>
                                                        weekdayOrder.indexOf(a).compareTo(weekdayOrder.indexOf(b)));
                                                      await showDialog(
                                                        context: ctx,
                                                        builder: (BuildContext dialogCtx) {
                                                          return StatefulBuilder(
                                                            builder: (dialogContext, setDialogState) {
                                                              return AlertDialog(
                                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                                title: const Text('Select Days'),
                                                                content: SizedBox(
                                                                  width: 250,
                                                                  child: ListView(
                                                                    shrinkWrap: true,
                                                                    children: sortedAssignedDays.map((day) {
                                                                      return CheckboxListTile(
                                                                        title: Text(day),
                                                                        value: tempSelectedDays.contains(day),
                                                                        onChanged: (checked) {
                                                                          setDialogState(() {
                                                                            if (checked == true) {
                                                                              tempSelectedDays.add(day);
                                                                            } else {
                                                                              tempSelectedDays.remove(day);
                                                                            }
                                                                          });
                                                                        },
                                                                      );
                                                                    }).toList(),
                                                                  ),
                                                                ),
                                                                actions: [
                                                                  TextButton(
                                                                    onPressed: () {
                                                                      Navigator.of(dialogCtx).pop();
                                                                    },
                                                                    child: const Text('Done'),
                                                                  ),
                                                                ],
                                                              );
                                                            },
                                                          );
                                                        },
                                                      );
                                                      setState(() {
                                                        selectedDaysBox
                                                          ..clear()
                                                          ..addAll(tempSelectedDays);
                                                      });
                                                    },
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            selectedDaysBox.isEmpty
                                                              ? 'Select Days'
                                                              : selectedDaysBox.map((d) {
                                                                  switch (d) {
                                                                    case 'Monday': return 'Mon';
                                                                    case 'Tuesday': return 'Tue';
                                                                    case 'Wednesday': return 'Wed';
                                                                    case 'Thursday': return 'Thu';
                                                                    case 'Friday': return 'Fri';
                                                                    case 'Saturday': return 'Sat';
                                                                    case 'Sunday': return 'Sun';
                                                                    default: return d;
                                                                  }
                                                                }).join(', '),
                                                            style: const TextStyle(fontSize: 15),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        const Icon(Icons.arrow_drop_down, color: Color(0xFF22688E)),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            if (selectedFrequency == 'Only once') ...[
                                              const SizedBox(height: 16),
                                              Row(
                                                children: [
                                                  const Icon(Icons.event, color: Color(0xFF22688E)),
                                                  const SizedBox(width: 8),
                                                  const Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Container(
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
                                                      selectableDayPredicate: (DateTime date) {
                                                        // Map weekday int to name
                                                        String weekday = [
                                                          'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
                                                        ][date.weekday - 1];
                                                        return caregiverAssignedDays.contains(weekday);
                                                      },
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
                                            ],
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
                                                  bool valid = selectedElderly != null && startTime != null && endTime != null && selectedFrequency != null && activityController.text.isNotEmpty;
                                                  DateTime? saveDate;
                                                  List<String> saveFrequency = [selectedFrequency!];
                                                  Map<String, dynamic> extraFields = {};
                                                  if (selectedFrequency == 'Only once') {
                                                    valid = valid && selectedDate != null;
                                                    saveDate = selectedDate;
                                                    extraFields['freq_once_date'] = selectedDate;
                                                  } else if (selectedFrequency == 'Custom') {
                                                    valid = valid && selectedDaysBox.isNotEmpty;
                                                    saveFrequency = selectedDaysBox;
                                                    saveDate = DateTime.now();
                                                    extraFields['custom_days'] = selectedDaysBox;
                                                  } else if (selectedFrequency == 'Every Workday') {
                                                    saveDate = DateTime.now();
                                                    extraFields['everyday_days'] = caregiverAssignedDays;
                                                  }
                                                  if (valid) {
                                                    final elderlyData = assignedElderly.firstWhere((e) => e['elderly_id'] == selectedElderly, orElse: () => {});
                                                    final elderlyFname = elderlyData['elderly_fname'] ?? '';
                                                    final now = DateTime.now();
                                                    final taskStart = DateTime(now.year, now.month, now.day, startTime!.hour, startTime!.minute);
                                                    final taskEnd = DateTime(now.year, now.month, now.day, endTime!.hour, endTime!.minute);
                                                    await _saveCareTask(
                                                      elderlyId: selectedElderly!,
                                                      caregiverId: caregiverId,
                                                      elderlyFname: elderlyFname,
                                                      taskStart: taskStart,
                                                      taskEnd: taskEnd,
                                                      taskFrequency: saveFrequency,
                                                      taskDescription: activityController.text,
                                                      taskDate: saveDate!,
                                                      extraFields: extraFields,
                                                      caregiverAssignedDays: caregiverAssignedDays,
                                                      customDays: selectedDaysBox,
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
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          elevation: 4,
                        ),
                        child: const Text(
                          '+ Add Tasks',
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
            ],
          ),
        );
      },
    );
  }

  Future<String> _getCurrentCaregiverId(BuildContext context) async {
  // Use FirebaseAuth to get the current caregiver's UID
  return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  Future<List<Map<String, dynamic>>> _getAssignedElderlyForCaregiver(String caregiverId) async {
    final assignSnapshot = await FirebaseFirestore.instance
        .collection('elderly_caregiver_assign')
        .where('caregiver_id', isEqualTo: caregiverId)
        .get();

    final assignedIds = assignSnapshot.docs
        .map((doc) => doc.data()['elderly_id'] as String)
        .toList();

    if (assignedIds.isEmpty) return [];

    final elderlySnapshot = await FirebaseFirestore.instance
        .collection('elderly')
        .where(FieldPath.documentId, whereIn: assignedIds)
        .get();

    final elderlyMap = {
      for (var doc in elderlySnapshot.docs) doc.id: doc.data()
    };

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

  Future<void> _saveCareTask({
    required String elderlyId,
    required String caregiverId,
    required String elderlyFname,
    required DateTime taskStart,
    required DateTime taskEnd,
    required List<String> taskFrequency,
    required String taskDescription,
    required DateTime taskDate,
    Map<String, dynamic>? extraFields,
    List<String>? caregiverAssignedDays,
    List<String>? customDays,
  }) async {
    final tasksRef = FirebaseFirestore.instance.collection('care_tasks');
    final docRef = tasksRef.doc();
    DateTime now = DateTime.now();
    DateTime? nextTaskDate;
    // Helper to get weekday int from string
    // Find next valid date for recurring tasks
    if (taskFrequency.contains('Every Workday') && caregiverAssignedDays != null) {
      for (int i = 0; i < 14; i++) {
        DateTime candidate = now.add(Duration(days: i));
        int weekday = candidate.weekday;
        String weekdayStr = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"][weekday-1];
        if (caregiverAssignedDays.contains(weekdayStr)) {
          DateTime candidateStart = DateTime(candidate.year, candidate.month, candidate.day, taskStart.hour, taskStart.minute);
          if (i == 0 && now.isBefore(candidateStart)) {
            nextTaskDate = candidateStart;
            break;
          } else if (i > 0) {
            nextTaskDate = candidateStart;
            break;
          }
        }
      }
    } else if (taskFrequency.contains('Custom') && caregiverAssignedDays != null && customDays != null) {
      for (int i = 0; i < 14; i++) {
        DateTime candidate = now.add(Duration(days: i));
        int weekday = candidate.weekday;
        String weekdayStr = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"][weekday-1];
        if (caregiverAssignedDays.contains(weekdayStr) && customDays.contains(weekdayStr)) {
          DateTime candidateStart = DateTime(candidate.year, candidate.month, candidate.day, taskStart.hour, taskStart.minute);
          if (i == 0 && now.isBefore(candidateStart)) {
            nextTaskDate = candidateStart;
            break;
          } else if (i > 0) {
            nextTaskDate = candidateStart;
            break;
          }
        }
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
      'task_date': taskDate,
      'next_taskdate': nextTaskDate,
      'nextuser_id': '',
      'inc_reason': '',
      'created_at': FieldValue.serverTimestamp(),
      'task_status': ['Upcoming'],
    };
    if (extraFields != null) {
      data.addAll(extraFields.map((key, value) => MapEntry(key, value as Object)));
    }
    await docRef.set(data);
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
