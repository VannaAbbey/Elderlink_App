import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import '../providers/auth_provider.dart';
import 'elderly_list.dart';
import 'medication_management.dart';
import 'vital_monitoring.dart';
import 'emergency.dart';
import 'nurse_bottom_navbar.dart';
import 'incident_report.dart';
import 'nurse_sidebar.dart';
import 'notification_service.dart';
import 'activity_logs.dart';

class NurseHomeScreen extends StatefulWidget {
  const NurseHomeScreen({super.key});

  @override
  State<NurseHomeScreen> createState() => _NurseHomeScreenState();
}

class _NurseHomeScreenState extends State<NurseHomeScreen> {
  bool isSidebarOpen = false;
  int selectedIndex = 0;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _houses = [];
  bool _isLoadingHouses = true;

  final AudioPlayer _taskAudioPlayer = AudioPlayer();
  final Map<String, bool> _shownTaskDialogs =
      {}; // track which tasks have been shown

  // Common task description options keyed by task title
  final Map<String, List<String>> _commonTaskDescriptions = {
    'Vitals': [
      'Do the vitals of all elderly',
      'Check BP/HR for all elderly',
      'Record temperature for all elderly',
      'Check respiration for all elderly',
      'Spot-check random elderly vitals',
      'Other',
    ],
    'Medication': [
      'Administer morning medications',
      'Prepare medications for distribution',
      'Verify medication list for each elderly',
      'Check medication stock',
      'Other',
    ],
    'Assessment': [
      'Cognitive assessment (MMSE)',
      'Mobility/ambulation check for all elderly',
      'ADL (Activities of Daily Living) assessment',
      'Pain assessment for residents',
      'Other',
    ],
    // Add a helpful example option for generic/other tasks
    'Other': [
      'Do the vitals of all elderly',
      'Get the vitals of all elderly',
      'Do a headcount of residents',
      'Check all room doors are secured',
      'Other',
    ],
    'Custom': ['Other'],
  };

  @override
  void initState() {
    super.initState();
    _loadHouses();
    NotificationService.init(); // initialize notification service
    // After first frame we can access context safely and generate medication tasks
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateMedicationTasksForToday();
    });
  }

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

  String _getCurrentDay() {
    final now = DateTime.now();
    final currentHour = now.hour;
    if (currentHour >= 0 && currentHour < 6) {
      final previousDay = now.subtract(Duration(days: 1));
      return DateFormat('EEEE').format(previousDay);
    }
    return DateFormat('EEEE').format(now);
  }

  Future<String?> _getNurseIdFromAuth() async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final first = auth.userFirstName;
      final last = auth.userLastName;
      if (first.isEmpty || last.isEmpty) return null;

      final q = await _firestore
          .collection('users')
          .where('user_fname', isEqualTo: first)
          .where('user_lname', isEqualTo: last)
          .where('user_type', isEqualTo: 'nurse')
          .get();
      if (q.docs.isEmpty) return null;
      return q.docs.first.id;
    } catch (e) {
      debugPrint('Error getting nurse id: $e');
      return null;
    }
  }

  // Generate medical_tasks entries for today's medication schedule for this nurse
  Future<void> _generateMedicationTasksForToday() async {
    try {
      final nurseId = await _getNurseIdFromAuth();
      if (nurseId == null) return;

      final currentShift = _getCurrentShift();
      final currentDay = _getCurrentDay();

      // Get nurse_elderly_assign for this nurse for today's shift/day
      final assignQuery = await _firestore
          .collection('nurse_elderly_assign')
          .where('nurse_id', isEqualTo: nurseId)
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .where('day', isEqualTo: currentDay)
          .get();
      if (assignQuery.docs.isEmpty) return;

      // Collect all elderly IDs across assignments
      final Set<String> elderlyIds = {};
      for (final doc in assignQuery.docs) {
        final data = doc.data();
        final ids = List<String>.from(data['elderly_ids'] ?? []);
        elderlyIds.addAll(ids);
      }
      if (elderlyIds.isEmpty) return;

      // Fetch elderly names in chunks
      final Map<String, String> elderlyNames = {};
      final elderlyList = elderlyIds.toList();
      for (var i = 0; i < elderlyList.length; i += 30) {
        final end = (i + 30 < elderlyList.length) ? i + 30 : elderlyList.length;
        final chunk = elderlyList.sublist(i, end);
        final q = await _firestore
            .collection('elderly')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final ed in q.docs) {
          final edata = ed.data();
          final name =
              '${edata['elderly_fname'] ?? ''} ${edata['elderly_lname'] ?? ''}'
                  .trim();
          elderlyNames[ed.id] = name.isNotEmpty ? name : 'Unknown';
        }
      }

      // Query medications for these elderly in chunks and create tasks for pending takes
      final now = DateTime.now();
      for (var i = 0; i < elderlyList.length; i += 30) {
        final end = (i + 30 < elderlyList.length) ? i + 30 : elderlyList.length;
        final chunk = elderlyList.sublist(i, end);

        final medsQuery = await _firestore
            .collection('medications')
            .where('elderly_id', whereIn: chunk)
            .where('status', isEqualTo: 'upcoming')
            .where('shift', isEqualTo: currentShift)
            .get();

        for (final mdoc in medsQuery.docs) {
          final mdata = mdoc.data();
          final medicationId = mdoc.id;
          final medName = mdata['medication_name'] ?? 'Medication';
          final dosage = mdata['dosage'] ?? '';
          final elderlyId = mdata['elderly_id'] as String?;
          if (elderlyId == null) continue;
          final elderlyName = elderlyNames[elderlyId] ?? 'Unknown';

          final intakeTimes = List<String>.from(mdata['intake_times'] ?? []);
          final takeStatuses = List<Map<String, dynamic>>.from(
            mdata['take_statuses'] ?? [],
          );

          for (int t = 0; t < intakeTimes.length; t++) {
            final scheduled = intakeTimes[t];
            // scheduled expected as 'HH:mm'
            final parts = scheduled.split(':');
            if (parts.length != 2) continue;
            final hour = int.tryParse(parts[0]) ?? 0;
            final minute = int.tryParse(parts[1]) ?? 0;

            // build today's DateTime for the scheduled time
            final taskStart = DateTime(
              now.year,
              now.month,
              now.day,
              hour,
              minute,
            );

            // skip past takes
            if (taskStart.isBefore(now)) continue;

            // only create task if status is pending
            final status =
                (t < takeStatuses.length && takeStatuses[t]['status'] != null)
                ? takeStatuses[t]['status'] as String
                : 'pending';
            if (status != 'pending') continue;

            // avoid duplicates: check for existing medical_tasks with same medication_id and take index and same start
            final existing = await _firestore
                .collection('medical_tasks')
                .where('task_source', isEqualTo: 'medication')
                .where('medication_id', isEqualTo: medicationId)
                .where('take_index', isEqualTo: t)
                .where('task_start', isEqualTo: Timestamp.fromDate(taskStart))
                .get();
            if (existing.docs.isNotEmpty) continue;

            // create task
            final taskTitle =
                '$medName ${dosage.isNotEmpty ? '- $dosage' : ''} for $elderlyName';
            final taskDesc =
                'Medication scheduled for $elderlyName at $scheduled';

            await _firestore.collection('medical_tasks').add({
              'task_title': taskTitle,
              'task_description': taskDesc,
              'task_category': 'Medication',
              'task_start': taskStart,
              'task_end_date': null,
              'task_frequency': 'Once',
              'task_status': 'Pending',
              // metadata to avoid duplicates and allow tracing
              'task_source': 'medication',
              'medication_id': medicationId,
              'take_index': t,
              'elderly_id': elderlyId,
              'created_at': FieldValue.serverTimestamp(),
            });

            // schedule notification 5 minutes before
            final notifyTime = taskStart.subtract(Duration(minutes: 5));
            if (notifyTime.isAfter(DateTime.now())) {
              NotificationService.scheduleTaskNotification(
                id: ('${medicationId}_$t').hashCode,
                title: 'Medication Reminder',
                body: '$medName for $elderlyName in 5 minutes',
                dateTime: notifyTime,
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error generating medication tasks: $e');
    }
  }

  Future<void> _loadHouses() async {
    try {
      QuerySnapshot snapshot = await _firestore.collection('house').get();
      setState(() {
        _houses = snapshot.docs
            .map((doc) => doc.data() as Map<String, dynamic>)
            .toList();
        _houses.sort((a, b) {
          String idA = a['house_id'] ?? '';
          String idB = b['house_id'] ?? '';
          return idA.compareTo(idB);
        });
        _isLoadingHouses = false;
      });
    } catch (e) {
      debugPrint("Error fetching houses: $e");
      setState(() => _isLoadingHouses = false);
    }
  }

  void toggleSidebar() {
    setState(() {
      isSidebarOpen = !isSidebarOpen;
    });
  }

  final List<Widget> _screens = [
    const Center(child: Text("Nurse Dashboard")),
    const IncidentReportScreen(),
    EmergencyScreen(),
    MedicationManagementScreen(),
    VitalMonitoringScreen(),
  ];

  void onNavTap(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (isSidebarOpen) setState(() => isSidebarOpen = false);
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
                      child: ListView(
                        children: [
                          _headerSection(),
                          const SizedBox(height: 40),
                          _medicalTasksSection(),
                          const SizedBox(height: 30),
                          _housesSection(),
                        ],
                      ),
                    ),
                  ),
                  if (isSidebarOpen)
                    NurseSidebar(
                      isSidebarOpen: isSidebarOpen,
                      toggleSidebar: toggleSidebar,
                      parentContext: context,
                    ),
                ],
              )
            : _screens[selectedIndex],
        bottomNavigationBar: NurseBottomNavBar(
          selectedIndex: selectedIndex,
          onNavTap: onNavTap,
        ),
      ),
    );
  }

  Widget _headerSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: toggleSidebar,
              child: Consumer<AuthProvider>(
                builder: (context, authProvider, child) {
                  final profilePic = authProvider.userData?['user_profilePic'];
                  return CircleAvatar(
                    radius: 24,
                    backgroundImage:
                        (profilePic != null && profilePic.isNotEmpty)
                        ? NetworkImage(profilePic)
                        : const AssetImage('assets/images/people_icon.png')
                              as ImageProvider,
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Consumer<AuthProvider>(
                  builder: (context, authProvider, child) {
                    final firstName = authProvider.userFirstName;
                    final displayName =
                        (firstName.isEmpty || firstName == 'User')
                        ? ''
                        : firstName;

                    return Text(
                      displayName.isEmpty
                          ? 'Hello Nurse,'
                          : 'Hello Nurse $displayName,',
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
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ActivityLogsScreen(
                  houseId: 'H001', // Default house
                  nurseName:
                      '${Provider.of<AuthProvider>(context, listen: false).userFirstName} ${Provider.of<AuthProvider>(context, listen: false).userLastName}',
                ),
              ),
            );
          },
          child: const Icon(
            Icons.notifications,
            color: Color(0XFF1D66A0),
            size: 35,
          ),
        ),
      ],
    );
  }

  // ---------------------- MEDICAL TASKS SECTION ----------------------
  Widget _medicalTasksSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(183, 221, 245, 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.medical_services, color: Color(0xFF1D66A0), size: 45),
              SizedBox(width: 6),
              Text(
                "Medical Tasks",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1D66A0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _showAddTaskDialog,
                icon: const Icon(Icons.add),
                label: const Text(
                  "Add Task",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D66A0),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Inner container for tasks
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 232, 244, 248),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: const Color.fromARGB(255, 70, 179, 247).withOpacity(0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('medical_tasks')
                  .orderBy('task_start')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        "No tasks available.",
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }

                final tasks = snapshot.data!.docs.map((doc) {
                  final task = doc.data() as Map<String, dynamic>;
                  task['task_id'] = doc.id; // assign doc ID
                  return task;
                }).toList();

                return ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    final title = task['task_title'] ?? '';
                    final description = task['task_description'] ?? '';
                    final start = task['task_start'] != null
                        ? (task['task_start'] as Timestamp).toDate()
                        : DateTime.now();
                    final formattedTime = TimeOfDay.fromDateTime(
                      start,
                    ).format(context);

                    // Schedule notification and dialog if not already shown
                    final taskId = task['task_id'];
                    if (!_shownTaskDialogs.containsKey(taskId) &&
                        start.isAfter(DateTime.now())) {
                      _shownTaskDialogs[taskId] = true;

                      NotificationService.scheduleTaskNotification(
                        id: taskId.hashCode,
                        title: title,
                        body: description,
                        dateTime: start,
                      );

                      Future.delayed(
                        start.difference(DateTime.now()),
                        () async {
                          if (mounted) {
                            await _showTaskDialog(taskId, title, description);
                          }
                        },
                      );
                    }

                    // Color based on category
                    final category = task['task_category'] ?? 'Other';
                    Color bgColor;
                    switch (category) {
                      case 'Vitals':
                        bgColor = Colors.orange[200]!;
                        break;
                      case 'Medication':
                        bgColor = Colors.yellow[200]!;
                        break;
                      case 'Assessment':
                        bgColor = Colors.blue[200]!;
                        break;
                      default:
                        bgColor = Colors.grey[200]!;
                    }

                    return _medicalTaskCard(
                      title,
                      description,
                      formattedTime,
                      bgColor,
                      taskId: taskId,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------- SHOW ADD TASK DIALOG ----------------------
  void _showAddTaskDialog() {
    TimeOfDay taskTime = TimeOfDay.now();
    DateTime? taskEndDate;
    String taskTitle = '';
    String taskDescription = '';
    String taskCategory = 'Vitals';
    String taskFrequency = 'Once';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              contentPadding: const EdgeInsets.all(16),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.medical_services,
                          color: Color(0xFF00588E),
                          size: 28,
                        ),
                        SizedBox(width: 10),
                        Text(
                          "Add Task",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00588E),
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Task Title (combo box with editable custom option)
                    DropdownButtonFormField<String>(
                      value: taskTitle.isEmpty ? 'Vitals' : taskTitle,
                      decoration: const InputDecoration(
                        labelText: 'Task Title',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Vitals',
                          child: Text('Vitals'),
                        ),
                        DropdownMenuItem(
                          value: 'Medication',
                          child: Text('Medication'),
                        ),
                        DropdownMenuItem(
                          value: 'Assessment',
                          child: Text('Assessment'),
                        ),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                        DropdownMenuItem(
                          value: 'Custom',
                          child: Text('Custom'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            taskTitle = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    // If custom selected, allow typing an exact title
                    if (taskTitle == 'Custom')
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Custom Task Title',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => taskTitle = value,
                      ),
                    const SizedBox(height: 12),
                    const SizedBox(height: 12),

                    // Task Description (predefined choices per type, with custom fallback)
                    Builder(
                      builder: (context) {
                        final options =
                            _commonTaskDescriptions[taskTitle] ?? ['Other'];
                        final initial =
                            options.contains(taskDescription) &&
                                taskDescription.isNotEmpty
                            ? taskDescription
                            : options.first;

                        return Column(
                          children: [
                            DropdownButtonFormField<String>(
                              value: initial,
                              decoration: const InputDecoration(
                                labelText: 'Task Description',
                                border: OutlineInputBorder(),
                              ),
                              items: options
                                  .map(
                                    (o) => DropdownMenuItem(
                                      value: o,
                                      child: Text(o),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => taskDescription = value);
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            if (taskDescription == 'Other')
                              TextField(
                                decoration: const InputDecoration(
                                  labelText: 'Custom Description',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) => taskDescription = value,
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // Note: removed separate Category field; category will be derived from Task Title

                    // Repeat Interval
                    DropdownButtonFormField<String>(
                      value: taskFrequency,
                      decoration: const InputDecoration(
                        labelText: 'Repeat Interval',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Once', child: Text('Once')),
                        DropdownMenuItem(
                          value: 'Everyday',
                          child: Text('Everyday'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => taskFrequency = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Task Time
                    TextField(
                      readOnly: true,
                      controller: TextEditingController(
                        text: taskTime.format(context),
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Time',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(
                          Icons.access_time,
                          color: Color(0xFF00588E),
                        ),
                      ),
                      onTap: () async {
                        TimeOfDay? picked = await showTimePicker(
                          context: context,
                          initialTime: taskTime,
                        );
                        if (picked != null) setState(() => taskTime = picked);
                      },
                    ),
                    const SizedBox(height: 12),

                    const SizedBox(height: 20),

                    // Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Cancel
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        // Submit
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00588E),
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () async {
                            // Construct task start DateTime from selected time
                            final now = DateTime.now();
                            DateTime taskStart = DateTime(
                              now.year,
                              now.month,
                              now.day,
                              taskTime.hour,
                              taskTime.minute,
                            );

                            // Save task to Firestore
                            final docRef = await FirebaseFirestore.instance
                                .collection('medical_tasks')
                                .add({
                                  'task_title': taskTitle,
                                  'task_description': taskDescription,
                                  'task_category': taskCategory,
                                  'task_start': taskStart,
                                  'task_end_date': taskEndDate,
                                  'task_frequency': taskFrequency,
                                  'task_status': 'Pending',
                                });

                            // Schedule notification
                            NotificationService.scheduleTaskNotification(
                              id: docRef.id.hashCode,
                              title: taskTitle,
                              body: taskDescription,
                              dateTime: taskStart,
                            );

                            Navigator.of(context).pop();
                          },
                          child: const Text('Submit'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------- TASK DIALOG ----------------------
  Future<void> _showTaskDialog(
    String taskId,
    String title,
    String description,
  ) async {
    try {
      await _taskAudioPlayer.setReleaseMode(ReleaseMode.loop);
      await _taskAudioPlayer.play(AssetSource('sounds/alarm.mp3'));

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
          contentPadding: const EdgeInsets.all(16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon + Header
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.medical_services,
                    color: Color(0xFF00588E),
                    size: 28,
                  ),
                  SizedBox(width: 8),
                  Text(
                    "Task Reminder",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00588E),
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Centered task title
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),

              // Centered description
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Cancel
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      await _taskAudioPlayer.stop();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Cancel'),
                  ),

                  // OK
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00588E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      await _taskAudioPlayer.stop();
                      Navigator.of(context).pop();

                      // Remove task from Firestore
                      await _firestore
                          .collection('medical_tasks')
                          .doc(taskId)
                          .delete();
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      print('❌ Task dialog error: $e');
    }
  }

  Widget _medicalTaskCard(
    String title,
    String description,
    String time,
    Color bgColor, {
    String? taskId,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.medical_services,
            size: 40,
            color: Color(0xFF00588E),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                // Title: keep single line and ellipsize if too long
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // Description: allow wrapping to next rows (max 3 lines) then ellipsize
                Text(
                  description,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                  softWrap: true,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(time, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          if (taskId != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete Task'),
                    content: const Text(
                      'Are you sure you want to delete this task?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  try {
                    // Attempt to read the task doc to see if it has medication metadata
                    final doc = await FirebaseFirestore.instance
                        .collection('medical_tasks')
                        .doc(taskId)
                        .get();
                    final data = doc.data();
                    if (data != null) {
                      // If this task was generated from a medication, cancel the deterministic notification id too
                      final medId = data['medication_id'] as String?;
                      final takeIndex = data['take_index'];
                      if (medId != null && takeIndex != null) {
                        try {
                          NotificationService.cancelNotification(
                            ('${medId}_$takeIndex').hashCode,
                          );
                        } catch (e) {
                          debugPrint(
                            'Error cancelling deterministic notification for $medId:$takeIndex -> $e',
                          );
                        }
                      }
                    }

                    await FirebaseFirestore.instance
                        .collection('medical_tasks')
                        .doc(taskId)
                        .delete();
                  } catch (e) {
                    debugPrint('Error deleting task $taskId: $e');
                  }

                  // Always attempt to cancel the doc-based notification id as well
                  try {
                    NotificationService.cancelNotification(taskId.hashCode);
                  } catch (e) {
                    debugPrint('Error cancelling notification for $taskId: $e');
                  }
                }
              },
            ),
        ],
      ),
    );
  }

  // ---------------------- HOUSES SECTION ----------------------
  Widget _housesSection() {
    if (_isLoadingHouses) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_houses.isEmpty) return const Text("No houses available.");

    List<String> houseImages = [
      'assets/images/Sebastian_Logo.png',
      'assets/images/Emmanuel_Logo.png',
      'assets/images/Charbell_Logo.png',
      'assets/images/Rose_Logo.png',
      'assets/images/Gabriel_Logo.png',
    ];
    List<String> houseDescriptions = [
      'Females with Psychological Needs',
      'Females that are Bedridden',
      'Males that are Bedridden',
      'Females that are Abled',
      'Males that are Abled',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.home, color: Color(0xFF00588E), size: 45),
            SizedBox(width: 8),
            Text(
              "Elderly Houses",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: _houses.length,
          itemBuilder: (context, index) {
            final house = _houses[index];
            final houseName = house['house_name'] ?? '';
            String imagePath = index < houseImages.length
                ? houseImages[index]
                : 'assets/images/people_icon.png';
            String description = index < houseDescriptions.length
                ? houseDescriptions[index]
                : 'Elderly Care Facility';

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ElderlyListScreen(
                      houseId: house['house_id'],
                      houseName: houseName,
                    ),
                  ),
                );
              },
              child: Card(
                color: const Color(0XFFE7EFFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Image.asset(imagePath, width: 80, height: 80),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              "House of $houseName",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588E),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF00588E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
