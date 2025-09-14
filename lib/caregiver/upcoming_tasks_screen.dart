import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
class UpcomingTasksScreen extends StatelessWidget {
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
  const UpcomingTasksScreen({Key? key, this.selectedFilterDate}) : super(key: key);

  Stream<List<Map<String, dynamic>>> getTasksStream() {
    return FirebaseFirestore.instance
      .collection('care_tasks')
      .where('task_status', arrayContains: 'Upcoming')
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        List<Map<String, dynamic>> tasks = snapshot.data ?? [];
        // Apply date filter if provided
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
        if (tasks.isEmpty) {
          return const Center(child: Text('No upcoming tasks.'));
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
              Expanded(
                child: ListView(
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
                            for (final task in grouped[key]!)
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
                                                        const Text('Time:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
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
                                                    const SizedBox(height: 12),
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.calendar_today, color: Color(0xFF22688E)),
                                                        const SizedBox(width: 8),
                                                        const Text('Created:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          task['created_at'] != null
                                                            ? (task['created_at'] is DateTime
                                                                ? '${_formatDate(task['created_at'])} ${_formatTime(task['created_at'])}'
                                                                : task['created_at'].toString())
                                                            : '',
                                                          style: const TextStyle(fontSize: 16),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 20),
                                                    !showReasonInput
                                                        ? Row(
                                                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                            children: [
                                                              TextButton.icon(
                                                                onPressed: () {
                                                                  // TODO: Mark as Complete logic
                                                                  Navigator.of(ctx).pop();
                                                                },
                                                                icon: const Icon(Icons.check_circle, color: Color(0xFF22688E)),
                                                                label: const Text('Complete', style: TextStyle(color: Color(0xFF22688E), fontWeight: FontWeight.bold, fontSize: 16)),
                                                                style: TextButton.styleFrom(
                                                                  backgroundColor: const Color(0xFFE6F3FA),
                                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                                                                ),
                                                              ),
                                                              TextButton.icon(
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
                                                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
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
                                                                  onPressed: () {
                                                                    // TODO: Submit reason logic
                                                                    Navigator.of(ctx).pop();
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
                          // Full Add More Tasks dialog logic
                          final caregiverId = await _getCurrentCaregiverId(context);
                          List<Map<String, dynamic>> assignedElderly = await _getAssignedElderlyForCaregiver(caregiverId);
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (BuildContext ctx) {
                              String? selectedElderly;
                              String? selectedFrequency = 'Only once';
                              TimeOfDay? startTime;
                              TimeOfDay? endTime;
                              TextEditingController activityController = TextEditingController();
                              final List<String> frequencyList = ['Only once', 'Everyday', 'Custom'];
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
                                                      final List<String> daysOfWeek = [
                                                        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
                                                      ];
                                                      List<String> tempSelectedDays = List<String>.from(selectedDaysBox);
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
                                                                    children: daysOfWeek.map((day) {
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
                                                  if (selectedFrequency == 'Only once') {
                                                    valid = valid && selectedDate != null;
                                                    saveDate = selectedDate;
                                                  } else if (selectedFrequency == 'Custom') {
                                                    valid = valid && selectedDaysBox.isNotEmpty;
                                                    saveFrequency = selectedDaysBox;
                                                    saveDate = DateTime.now(); // Or let user pick a start date if needed
                                                  } else {
                                                    saveDate = DateTime.now();
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
                          'Add Tasks',
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
                      width: 160,
                      child: ElevatedButton(
                        onPressed: () {
                          // TODO: Delete Task logic here
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
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : hour == 0 ? 12 : hour;
    return '$hour12:$minute $ampm';
  }
