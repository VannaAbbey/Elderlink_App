import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import '../providers/auth_provider.dart';
import 'elderly_list.dart';
import 'medication_management.dart';
import 'vital_monitoring.dart';
import 'emergency.dart';
import 'nurse_bottom_navbar.dart';
import 'incident_report.dart';
import 'edit_profile.dart';
import 'leave_form.dart';
import 'notification_service.dart';

class NurseHomeScreen extends StatefulWidget {
  const NurseHomeScreen({super.key});

  @override
  State<NurseHomeScreen> createState() => _NurseHomeScreenState();
}

class _NurseHomeScreenState extends State<NurseHomeScreen> {
  bool isSidebarOpen = false;
  int selectedIndex = 0;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

   // Controllers & variables for search
  final TextEditingController _searchController = TextEditingController();
  final List<Map<String, dynamic>> _searchResults = [];
  final bool _isSearching = false;

  List<Map<String, dynamic>> _houses = [];
  bool _isLoadingHouses = true;

  final AudioPlayer _taskAudioPlayer = AudioPlayer();
  final Map<String, bool> _shownTaskDialogs = {}; // track which tasks have been shown

  @override
  void initState() {
    super.initState();
    _loadHouses();
    NotificationService.init(); // initialize notification service
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

  Future<void> _handleLogout() async {
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
                          const SizedBox(height: 20),
                          _searchBar(),
                          const SizedBox(height: 20),
                          _medicalTasksSection(),
                          const SizedBox(height: 30),
                          _housesSection(),
                        ],
                      ),
                    ),
                  ),
                  if (isSidebarOpen) _buildSidebarOverlay(),
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
                            : const AssetImage(
                                'assets/images/people_icon.png') as ImageProvider,
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
                        (firstName.isEmpty || firstName == 'User') ? '' : firstName;

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
        const Icon(Icons.notifications, color: Color(0XFF1D66A0), size: 35),
      ],
    );
  }

  Widget _searchBar() {
    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        child: TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            hintText: "Search",
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 15),
            filled: true,
            fillColor: const Color(0xFFD8F4FF),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF00588E), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF00588E), width: 2),
            ),
          ),
          style: const TextStyle(fontSize: 18, color: Colors.black),
        ),
      ),
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
            mainAxisAlignment: MainAxisAlignment.end,
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
          StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('medical_tasks')
                .orderBy('task_start')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Text("No tasks available.");
              }

              final tasks = snapshot.data!.docs
                  .map((doc) {
                    final task = doc.data() as Map<String, dynamic>;
                    task['task_id'] = doc.id; // assign doc ID
                    return task;
                  })
                  .toList();

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
                  final formattedTime =
                      TimeOfDay.fromDateTime(start).format(context);

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
                        start.difference(DateTime.now()), () async {
                      if (mounted) {
                        await _showTaskDialog(taskId, title, description);
                      }
                    });
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

                  return _medicalTaskCard(title, description, formattedTime, bgColor);
                },
              );
            },
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
                      Icon(Icons.medical_services, color: Color(0xFF00588E), size: 28),
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

                  // Task Title
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Task Title',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => taskTitle = value,
                  ),
                  const SizedBox(height: 12),

                  // Task Description
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Task Description',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => taskDescription = value,
                  ),
                  const SizedBox(height: 12),

                  // Task Category
                  DropdownButtonFormField<String>(
                    value: taskCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Vitals', child: Text('Vitals')),
                      DropdownMenuItem(value: 'Medication', child: Text('Medication')),
                      DropdownMenuItem(value: 'Assessment', child: Text('Assessment')),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => taskCategory = value);
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
                      suffixIcon: Icon(Icons.access_time, color: Color(0xFF00588E)),
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

                  // Frequency
                  DropdownButtonFormField<String>(
                    value: taskFrequency,
                    decoration: const InputDecoration(
                      labelText: 'Frequency',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Once', child: Text('Once')),
                      DropdownMenuItem(value: 'Daily', child: Text('Daily')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => taskFrequency = value);
                    },
                  ),
                  const SizedBox(height: 12),

                  // Optional End Date if repeating
                  if (taskFrequency != 'Once')
                    TextField(
                      readOnly: true,
                      controller: TextEditingController(
                        text: taskEndDate != null
                            ? taskEndDate!.toLocal().toString().split(' ')[0]
                            : '',
                      ),
                      decoration: const InputDecoration(
                        labelText: 'End Date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today, color: Color(0xFF00588E)),
                      ),
                      onTap: () async {
                        DateTime? pickedDate = await showDatePicker(
                          context: context,
                          initialDate: taskEndDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );
                        if (pickedDate != null) setState(() => taskEndDate = pickedDate);
                      },
                    ),
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
                          textStyle: const TextStyle(fontWeight: FontWeight.bold),
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
                          textStyle: const TextStyle(fontWeight: FontWeight.bold),
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
  Future<void> _showTaskDialog(String taskId, String title, String description) async {
  try {
    await _taskAudioPlayer.setReleaseMode(ReleaseMode.loop);
    await _taskAudioPlayer.play(AssetSource('sounds/alarm.mp3'));

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.all(16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon + Header
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.medical_services, color: Color(0xFF00588E), size: 28),
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
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () async {
                    await _taskAudioPlayer.stop();
                    Navigator.of(context).pop();

                    // Remove task from Firestore
                    await _firestore.collection('medical_tasks').doc(taskId).delete();
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

  Widget _medicalTaskCard(String title, String description, String time, Color bgColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6)],
      ),
      child: Row(
        children: [
          const Icon(Icons.medical_services, size: 40, color: Color(0xFF00588E)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(fontSize: 14, color: Colors.black87)),
              ],
            ),
          ),
          Text(time, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ---------------------- HOUSES SECTION ----------------------
  Widget _housesSection() {
    if (_isLoadingHouses) return const Center(child: CircularProgressIndicator());
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
            String imagePath = index < houseImages.length ? houseImages[index] : 'assets/images/people_icon.png';
            String description = index < houseDescriptions.length ? houseDescriptions[index] : 'Elderly Care Facility';

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
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00588E)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14, color: Color(0xFF00588E)),
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

  // ---------------------- SIDEBAR ----------------------
  Widget _buildSidebarOverlay() {
    return Stack(
      children: [
        GestureDetector(
          onTap: toggleSidebar,
          child: Container(color: Colors.black54),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          child: Material(
            elevation: 5,
            child: Container(
              width: 250,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Colors.white),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 50),
                  Center(
                    child: Consumer<AuthProvider>(
                      builder: (context, authProvider, child) {
                        final firstName = authProvider.userFirstName;
                        final displayName = (firstName.isEmpty || firstName == 'User') ? '' : firstName;
                        return Text(
                          displayName.isEmpty ? 'Nurse' : 'Nurse $displayName',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.edit, color: Color(0xFF00588E)),
                    title: const Text("Edit Profile"),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const EditProfile()));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings, color: Color(0xFF00588E)),
                    title: const Text("Request Leave"),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const LeaveForm()));
                    },
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D5B78),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 60),
                      ),
                      onPressed: _handleLogout,
                      child: const Text('LOGOUT', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
