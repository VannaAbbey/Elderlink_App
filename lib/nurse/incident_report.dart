import 'package:elderlink_app/nurse/leave_form.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'edit_profile.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class IncidentReportScreen extends StatefulWidget {
  const IncidentReportScreen({super.key});

  @override
  State<IncidentReportScreen> createState() => _IncidentReportScreenState();
}

class _IncidentReportScreenState extends State<IncidentReportScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _showCalendar = false;
  bool isSidebarOpen = false;

  String? nurseName;
  List<Map<String, dynamic>> emergencies = [];

  void _pickDate() async {
    setState(() => _showCalendar = true);
  }

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      _showCalendar = false;
      _loadIncidents();
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
    _loadIncidents();
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
            nurseName = doc['user_fname'];
          });
        }
      }
    } catch (e) {
      print("❌ Error loading nurse data: $e");
      setState(() => nurseName = null);
    }
  }

  Future<void> _loadIncidents() async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('incident_report')
        .where(
          'incident_date_time',
          isGreaterThanOrEqualTo: Timestamp.fromDate(
              DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day)),
        )
        .where(
          'incident_date_time',
          isLessThan: Timestamp.fromDate(
              DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day + 1)),
        )
        .get();

    List<Map<String, dynamic>> loaded = [];

    for (var doc in snapshot.docs) {
      // HOUSE NAME
      String houseName = "Unknown House";
      if (doc['house_id'] != null) {
        final houseQuery = await FirebaseFirestore.instance
            .collection('house')
            .where('house_id', isEqualTo: doc['house_id'])
            .limit(1)
            .get();
        if (houseQuery.docs.isNotEmpty) {
          houseName = houseQuery.docs.first['house_name'];
        }
      }

      // ELDERLY NAME
      String elderlyName = "Unknown Elderly";
      if (doc['elderly_id'] != null) {
        final elderlyDoc = await FirebaseFirestore.instance
            .collection('elderly')
            .doc(doc['elderly_id'])
            .get();
        if (elderlyDoc.exists) {
          elderlyName =
              "${elderlyDoc['elderly_fname']} ${elderlyDoc['elderly_lname']}";
        }
      }

      // CAREGIVER NAME
      String caregiverName = "Unknown Caregiver";
      if (doc['user_id_cg'] != null) {
        final caregiverDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(doc['user_id_cg'])
            .get();
        if (caregiverDoc.exists) {
          caregiverName =
              "${caregiverDoc['user_fname']} ${caregiverDoc['user_lname']}";
        }
      }

      loaded.add({
        'house': houseName,
        'elderly': elderlyName,
        'submitted_by': caregiverName,
        'time': DateFormat('h:mm a')
            .format((doc['incident_date_time'] as Timestamp).toDate()),
        'desc': doc['incident_desc'],
        'incident_id': doc.id,
        'user_id_nu': doc['user_id_nu'],
        'verified': doc['incident_verify'] ?? false,
        'timestamp': (doc['incident_date_time'] as Timestamp).toDate(),
      });
    }

    // Sort by timestamp descending (latest on top)
    loaded.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));

    setState(() => emergencies = loaded);
  } catch (e) {
    print("❌ Error loading incidents: $e");
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
                        onTap: toggleSidebar,
                        child: const Icon(
                          Icons.menu,
                          size: 30,
                          color: Color(0xFF00588E),
                        ),
                      ),
                      const Text(
                        'Incident Record',
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

                  // Date + Calendar
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
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
                                          em['house'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: Color(0xFF00588E),
                                          ),
                                        ),
                                        Text(
                                          em['elderly'],
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          "Submitted by: ${em['submitted_by']}",
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.black54,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'What happened?',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(em['desc']),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    em['time'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
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

          // Sidebar Overlay
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
                    style: const TextStyle(
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
                    title: const Text("Request Leave"),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LeaveForm(),
                        ),
                      );
                    },
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
                      onPressed: toggleSidebar,
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
