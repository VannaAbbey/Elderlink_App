import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'nurse_sidebar.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart' as my_auth;
import 'activity_logs.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  bool isSidebarOpen = false;
  String? nurseName;
  DateTime _selectedDate = DateTime.now();
  int _refreshKey = 0; // Key to force stream rebuild on refresh

  void toggleSidebar() {
    setState(() {
      isSidebarOpen = !isSidebarOpen;
    });
  }

  Future<void> _refreshEmergencies() async {
    // Force rebuild of StreamBuilder by updating key
    setState(() {
      _refreshKey++;
    });
    // Small delay to show the refresh indicator
    await Future.delayed(const Duration(milliseconds: 500));
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(_selectedDate.year - 1),
      lastDate: DateTime(_selectedDate.year + 1),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF00588E)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _refreshKey++; // Force stream rebuild when date changes
      });
    }
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
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ActivityLogsScreen(
                                houseId: 'H001', // Default house
                                nurseName:
                                    '${Provider.of<my_auth.AuthProvider>(context, listen: false).userFirstName} ${Provider.of<my_auth.AuthProvider>(context, listen: false).userLastName}',
                              ),
                            ),
                          );
                        },
                        child: const Icon(
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
                        DateFormat('MMMM d, yyyy').format(_selectedDate),
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
                  // Emergency cards
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _refreshEmergencies,
                      child: StreamBuilder<QuerySnapshot>(
                        key: ValueKey(_refreshKey), // Force rebuild on refresh
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
                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.6,
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
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
                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          final alerts = snapshot.data!.docs;

                          // Collect unique caregiver IDs
                          final Set<String> caregiverIds = {};
                          for (final doc in alerts) {
                            final data = doc.data() as Map<String, dynamic>;
                            final userIdCg = data['user_id_cg'] ?? '';
                            if (userIdCg.isNotEmpty) {
                              caregiverIds.add(userIdCg);
                            }
                          }

                          // Fetch all caregiver names in batch
                          return FutureBuilder<Map<String, String>>(
                            future: caregiverIds.isNotEmpty
                                ? FirebaseFirestore.instance
                                      .collection('users')
                                      .where(
                                        FieldPath.documentId,
                                        whereIn: caregiverIds.toList(),
                                      )
                                      .get()
                                      .then((querySnapshot) {
                                        final Map<String, String>
                                        caregiverNames = {};
                                        for (final doc in querySnapshot.docs) {
                                          final userData = doc.data();
                                          final firstName =
                                              userData['user_fname'] ?? '';
                                          final lastName =
                                              userData['user_lname'] ?? '';
                                          final fullName =
                                              '$firstName $lastName'.trim();
                                          caregiverNames[doc.id] =
                                              fullName.isNotEmpty
                                              ? fullName
                                              : 'Unknown Caregiver';
                                        }
                                        return caregiverNames;
                                      })
                                : Future.value({}),
                            builder: (context, caregiverNamesSnapshot) {
                              if (caregiverNamesSnapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final caregiverNames =
                                  caregiverNamesSnapshot.data ?? {};

                              return ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: alerts.length,
                                itemBuilder: (context, index) {
                                  final data =
                                      alerts[index].data()
                                          as Map<String, dynamic>;
                                  final emergencyType =
                                      data['emergency_type'] ?? '';
                                  final additionalInfo =
                                      data['additional_info'] ?? '';
                                  final houseName = data['house_name'] ?? '';
                                  final userIdCg = data['user_id_cg'] ?? '';
                                  final timestamp =
                                      (data['alert_timestamp'] as Timestamp)
                                          .toDate();

                                  final caregiverName =
                                      caregiverNames[userIdCg] ??
                                      'Unknown Caregiver';

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color.fromARGB(
                                        255,
                                        247,
                                        220,
                                        220,
                                      ), // Red/pink background
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color.fromARGB(
                                          255,
                                          253,
                                          193,
                                          189,
                                        ),
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 2,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Top row with house icon, name, time
                                        Row(
                                          children: [
                                            Container(
                                              width: 50,
                                              height: 50,
                                              decoration: BoxDecoration(
                                                color: Colors.red,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                Icons
                                                    .warning_amber_rounded, // Emergency icon
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
                                              DateFormat(
                                                'hh:mm a',
                                              ).format(timestamp),
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
                                            const Icon(
                                              Icons.person_outline,
                                              size: 18,
                                              color: Colors.red,
                                            ),
                                            const SizedBox(width: 6),
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
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.info_outline,
                                              size: 18,
                                              color: Colors.red,
                                            ),
                                            const SizedBox(width: 6),
                                            const Text(
                                              'What happened?',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        // Centered description box
                                        Center(
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.red[50],
                                              borderRadius:
                                                  BorderRadius.circular(12),
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
                                                if (additionalInfo
                                                    .isNotEmpty) ...[
                                                  const SizedBox(height: 12),
                                                  const Text(
                                                    'Additional Information:',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    additionalInfo,
                                                    textAlign:
                                                        TextAlign.justify,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.normal,
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
                          );
                        },
                      ),
                    ),
                  ),
                ],
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
