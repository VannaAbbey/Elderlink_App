import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'nurse_sidebar.dart';
import 'package:intl/intl.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  bool isSidebarOpen = false;
  String? nurseName;
  bool _showCalendar = false;
  DateTime _selectedDate = DateTime.now();

  void toggleSidebar() {
    setState(() {
      isSidebarOpen = !isSidebarOpen;
    });
  }

  void _pickDate() {
    setState(() => _showCalendar = true);
  }

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      _showCalendar = false;
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
            nurseName = doc['user_fname'];
          });
        }
      }
    } catch (e) {
      print(' Error loading nurse data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final startOfDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final endOfDay = startOfDay.add(const Duration(days: 1));

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
              padding: const EdgeInsets.all(16),
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
                        'Emergency Record',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00588E),
                        ),
                      ),
                      IconButton(
                        onPressed: _pickDate,
                        icon: const Icon(
                          Icons.notifications,
                          color: Color(0xFF00588E),
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Date display
                  // Date + Calendar row
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
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Emergency cards
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('emergency_alert')
                          .where(
                            'alert_timestamp',
                            isGreaterThanOrEqualTo: startOfDay,
                          )
                          .where('alert_timestamp', isLessThan: endOfDay)
                          .orderBy('alert_timestamp', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No emergency alerts yet.',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final alerts = snapshot.data!.docs;

                        return ListView.builder(
                          itemCount: alerts.length,
                          itemBuilder: (context, index) {
                            final data =
                                alerts[index].data() as Map<String, dynamic>;
                            final emergencyType = data['emergency_type'] ?? '';
                            final additionalInfo =
                                data['additional_info'] ?? '';
                            final houseName = data['house_name'] ?? '';
                            final caregiverName =
                                data['caregiver_name'] ?? 'Unknown Caregiver';
                            final timestamp =
                                (data['alert_timestamp'] as Timestamp).toDate();

                            // Caregiver name is now directly available in the alert data
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(255, 247, 220, 220),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Top row with house icon, name, time
                                  Row(
                                    children: [
                                      Container(
                                        width: 50,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.home,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          houseName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 20,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        DateFormat('hh:mm a').format(timestamp),
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
                                    ],
                                  ),

                                  const SizedBox(height: 8),
                                  // Reporting caregiver label & value in same row with wrap
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Reporting Caregiver: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          caregiverName,
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
                                    'What happened?',
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
                                        color: Colors.red[50],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Emergency Type (Main description)
                                          Text(
                                            emergencyType.isNotEmpty
                                                ? emergencyType
                                                : 'No emergency type specified',
                                            textAlign: TextAlign.justify,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          // Additional Info (Optional)
                                          if (additionalInfo.isNotEmpty) ...[
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
                                              additionalInfo,
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
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Calendar overlay
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
          // Sidebar
          if (isSidebarOpen)
            NurseSidebar(
              isSidebarOpen: isSidebarOpen,
              toggleSidebar: toggleSidebar,
              parentContext: context,
            ),
        ],
      ),
    );
  }
}
