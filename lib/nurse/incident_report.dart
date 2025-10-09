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
  bool _mounted = true;

  String? nurseName;
  List<Map<String, dynamic>> emergencies = [];

  void _pickDate() async {
    if (_mounted) {
      setState(() => _showCalendar = true);
    }
  }

  void _onDateSelected(DateTime date) {
    if (_mounted) {
      setState(() {
        _selectedDate = date;
        _showCalendar = false;
        _loadIncidents();
      });
    }
  }

  void toggleSidebar() {
    if (_mounted) {
      setState(() {
        isSidebarOpen = !isSidebarOpen;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadNurseData();
    _loadIncidents();
  }

  @override
  void dispose() {
    _mounted = false;
    super.dispose();
  }

  Future<void> _loadNurseData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists && _mounted) {
          setState(() {
            nurseName = doc['user_fname'];
          });
        }
      }
    } catch (e) {
      print("❌ Error loading nurse data: $e");
      if (_mounted) {
        setState(() => nurseName = null);
      }
    }
  }

  Future<void> _loadIncidents() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('incident_report')
          .where(
            'incident_date_time',
            isGreaterThanOrEqualTo: Timestamp.fromDate(
              DateTime(
                _selectedDate.year,
                _selectedDate.month,
                _selectedDate.day,
              ),
            ),
          )
          .where(
            'incident_date_time',
            isLessThan: Timestamp.fromDate(
              DateTime(
                _selectedDate.year,
                _selectedDate.month,
                _selectedDate.day + 1,
              ),
            ),
          )
          .orderBy('incident_date_time', descending: true)
          .get();

      if (snapshot.docs.isEmpty) {
        if (_mounted) {
          setState(() => emergencies = []);
        }
        return;
      }

      // Collect all unique IDs for batch fetching
      Set<String> houseIds = {};
      Set<String> elderlyIds = {};
      Set<String> caregiverIds = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['house_id'] != null) houseIds.add(data['house_id'].toString());
        if (data['elderly_id'] != null) {
          elderlyIds.add(data['elderly_id'].toString());
        }
        if (data['user_id_cg'] != null) {
          caregiverIds.add(data['user_id_cg'].toString());
        }
      }

      // Batch fetch all data concurrently
      final futures = <Future>[];
      Map<String, String> houseNames = {};
      Map<String, String> elderlyNames = {};
      Map<String, String> caregiverNames = {};

      // Fetch house names
      if (houseIds.isNotEmpty) {
        futures.add(
          FirebaseFirestore.instance
              .collection('house')
              .where('house_id', whereIn: houseIds.toList())
              .get()
              .then((snapshot) {
                for (var doc in snapshot.docs) {
                  houseNames[doc['house_id'].toString()] =
                      doc['house_name'] ?? 'Unknown House';
                }
              }),
        );
      }

      // Fetch elderly names
      if (elderlyIds.isNotEmpty) {
        for (String elderlyId in elderlyIds) {
          futures.add(
            FirebaseFirestore.instance
                .collection('elderly')
                .doc(elderlyId)
                .get()
                .then((doc) {
                  if (doc.exists) {
                    elderlyNames[elderlyId] =
                        "${doc['elderly_fname']} ${doc['elderly_lname']}";
                  }
                }),
          );
        }
      }

      // Fetch caregiver names
      if (caregiverIds.isNotEmpty) {
        for (String caregiverId in caregiverIds) {
          futures.add(
            FirebaseFirestore.instance
                .collection('users')
                .doc(caregiverId)
                .get()
                .then((doc) {
                  if (doc.exists) {
                    caregiverNames[caregiverId] =
                        "${doc['user_fname']} ${doc['user_lname']}";
                  }
                }),
          );
        }
      }

      // Wait for all fetches to complete
      await Future.wait(futures);

      // Build the final list
      List<Map<String, dynamic>> loaded = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();

        final houseName =
            houseNames[data['house_id']?.toString()] ?? "Unknown House";
        final elderlyName =
            elderlyNames[data['elderly_id']?.toString()] ?? "Unknown Elderly";
        final caregiverName =
            caregiverNames[data['user_id_cg']?.toString()] ??
            "Unknown Caregiver";

        loaded.add({
          'house': houseName,
          'elderly': elderlyName,
          'submitted_by': caregiverName,
          'time': DateFormat(
            'h:mm a',
          ).format((data['incident_date_time'] as Timestamp).toDate()),
          'incident_type': data['incident_type'] ?? '',
          'additional_info': data['additional_info'] ?? '',
          'incident_id': doc.id,
          'user_id_nu': data['user_id_nu'],
          'verified': data['incident_verify'] ?? false,
          'timestamp': (data['incident_date_time'] as Timestamp).toDate(),
        });
      }

      if (_mounted) {
        setState(() => emergencies = loaded);
      }
    } catch (e) {
      print("❌ Error loading incidents: $e");
      if (_mounted) {
        setState(() => emergencies = []);
      }
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
                            color: em['verified']
                                ? const Color.fromARGB(255, 220, 247, 220)
                                : const Color.fromARGB(255, 255, 248, 220),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top row with incident icon, house name, time
                              Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: em['verified']
                                          ? Colors.green
                                          : Colors.orange,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      em['verified']
                                          ? Icons.verified
                                          : Icons.report_problem,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      em['house'],
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                        color: em['verified']
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        em['time'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color.fromARGB(
                                            255,
                                            82,
                                            81,
                                            81,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        em['verified'] ? 'Verified' : 'Pending',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: em['verified']
                                              ? Colors.green
                                              : Colors.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              const SizedBox(height: 8),
                              // Elderly and caregiver info in separate rows
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Elderly: ",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      em['elderly'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.normal,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Submitted by: ",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      em['submitted_by'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.normal,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // What happened label
                              const Text(
                                "What happened?",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Centered description box
                              Center(
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: em['verified']
                                        ? Colors.green[50]
                                        : Colors.orange[50],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Incident Type (Main description)
                                      Text(
                                        em['incident_type'].isNotEmpty
                                            ? em['incident_type']
                                            : 'No incident type specified',
                                        textAlign: TextAlign.justify,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      // Additional Info (Optional)
                                      if (em['additional_info'].isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        const Text(
                                          'Additional Information:',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black54,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          em['additional_info'],
                                          textAlign: TextAlign.justify,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.normal,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
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
              onTap: () {
                if (_mounted) {
                  setState(() => _showCalendar = false);
                }
              },
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
