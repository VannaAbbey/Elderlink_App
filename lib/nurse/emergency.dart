import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'edit_profile.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _showCalendar = false;
  bool isSidebarOpen = false; // 🔹 added for sidebar state

  String? nurseName;

  // Dummy emergency data
  final List<Map<String, String>> emergencies = [
    {
      'house': 'St. Gabriel',
      'time': '7:30 AM',
      'desc': 'Lolo Garin slipped and broke his ankle',
    },
    {
      'house': 'St. Sebastian',
      'time': '9:00 AM',
      'desc': 'Lola Marian was cut by a broken glass',
    },
  ];

  void _pickDate() async {
    setState(() => _showCalendar = true);
  }

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      _showCalendar = false;
    });
  }

  void toggleSidebar() {
    setState(() {
      isSidebarOpen = !isSidebarOpen;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadNurseData();
  }

  Future<void> _loadNurseData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists) {
          setState(() {
            nurseName = "${doc['user_fname']}";
          });
        } else {
          setState(() {
            nurseName = null; // para lumabas "No name found"
          });
        }
      }
    } catch (e) {
      print("❌ Error loading nurse data: $e");
      setState(() {
        nurseName = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
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
              child: Column(
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: toggleSidebar, // 🔹 open/close sidebar
                        child: const Icon(
                          Icons.menu,
                          size: 30,
                          color: Color(0xFF00588E),
                        ),
                      ),
                      const Text(
                        'Emergency Record',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00588E),
                        ),
                      ),
                      const Icon(
                        Icons.notifications,
                        size: 30,
                        color: Color(0xFF00588E),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Date + Calendar icon
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('MMMM dd, yyyy').format(_selectedDate),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      IconButton(
                        onPressed: _pickDate,
                        icon: const Icon(
                          Icons.calendar_today,
                          color: Color(0xFF00588E),
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Emergency Cards
                  Expanded(
                    child: ListView.builder(
                      itemCount: emergencies.length,
                      itemBuilder: (context, index) {
                        final em = emergencies[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.lightBlue[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00588E),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.home,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      em['house']!,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Color(0xFF00588E),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'What happened?',
                                      style: TextStyle(
                                        color: Colors.grey[800],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(em['desc']!),
                                  ],
                                ),
                              ),
                              Text(
                                em['time']!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Calendar Overlay
          if (_showCalendar)
            GestureDetector(
              onTap: () => setState(() => _showCalendar = false),
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CalendarDatePicker(
                      initialDate: _selectedDate,
                      firstDate: DateTime(_selectedDate.year - 1),
                      lastDate: DateTime(_selectedDate.year + 1),
                      onDateChanged: _onDateSelected,
                    ),
                  ),
                ),
              ),
            ),

          // Sidebar Overlay (correctly inside Stack)
          if (isSidebarOpen) _buildSidebarOverlay(),
        ],
      ),
    );
  }

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
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(10),
              bottomRight: Radius.circular(10),
            ),
            child: Container(
              width: 250,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Colors.white),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 50),
                  Text(
                    nurseName != null ? "Nurse $nurseName" : "No name found",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.edit, color: Color(0xFF00588E)),
                    title: const Text("Edit Profile"),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const EditProfile(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.settings,
                      color: Color(0xFF00588E),
                    ),
                    title: const Text("Settings"),
                    onTap: toggleSidebar,
                  ),
                  ListTile(
                    leading: const Icon(Icons.help, color: Color(0xFF00588E)),
                    title: const Text("Help & Support"),
                    onTap: toggleSidebar,
                  ),
                  const Divider(),
                  const SizedBox(height: 20),
                  Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D5B78),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 60,
                        ),
                      ),
                      onPressed: () {
                        // TODO: hook into AuthProvider kung gusto logout
                        toggleSidebar();
                      },
                      child: const Text(
                        'LOGOUT',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
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
