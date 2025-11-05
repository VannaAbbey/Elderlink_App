import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'nurse_sidebar.dart';
import 'notification_service.dart';
import '../providers/auth_provider.dart' as my_auth;
import 'activity_logs.dart';

class IncidentReportScreen extends StatefulWidget {
  const IncidentReportScreen({super.key});

  @override
  State<IncidentReportScreen> createState() => _IncidentReportScreenState();
}

class _IncidentReportScreenState extends State<IncidentReportScreen> {
  DateTime _selectedDate = DateTime.now();
  bool isSidebarOpen = false;
  bool _mounted = true;

  String? nurseName;
  String? nurseId;
  final Map<String, bool> _shownIncidentNotifications = {};
  int _refreshKey = 0; // Key to force stream rebuild on refresh

  void _pickDate() async {
    if (_mounted) {
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
    _loadNurseId();
  }

  @override
  void dispose() {
    _mounted = false;
    super.dispose();
  }

  Future<void> _refreshIncidents() async {
    // Force rebuild of StreamBuilder by updating key
    setState(() {
      _refreshKey++;
    });
    // Small delay to show the refresh indicator
    await Future.delayed(const Duration(milliseconds: 500));
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

  Future<void> _loadNurseId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && _mounted) {
      setState(() => nurseId = user.uid);
    }
  }

  Future<Map<String, Map<String, String>>> _fetchRelatedData(
    Set<String> houseIds,
    Set<String> elderlyIds,
    Set<String> caregiverIds,
  ) async {
    Map<String, String> houseNames = {};
    Map<String, String> elderlyNames = {};
    Map<String, String> caregiverNames = {};

    final futures = <Future>[];

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
      futures.add(
        FirebaseFirestore.instance
            .collection('elderly')
            .where(FieldPath.documentId, whereIn: elderlyIds.toList())
            .get()
            .then((snapshot) {
              for (var doc in snapshot.docs) {
                elderlyNames[doc.id] =
                    "${doc['elderly_fname']} ${doc['elderly_lname']}";
              }
            }),
      );
    }

    // Fetch caregiver names
    if (caregiverIds.isNotEmpty) {
      futures.add(
        FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: caregiverIds.toList())
            .get()
            .then((snapshot) {
              for (var doc in snapshot.docs) {
                caregiverNames[doc.id] =
                    "${doc['user_fname']} ${doc['user_lname']}";
              }
            }),
      );
    }

    await Future.wait(futures);

    return {
      'houses': houseNames,
      'elderly': elderlyNames,
      'caregivers': caregiverNames,
    };
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
                          size: 30,
                          color: Color(0xFF00588E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Date + Calendar
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

                  // Incident Cards with Real-time Stream
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _refreshIncidents,
                      child: StreamBuilder<QuerySnapshot>(
                        key: ValueKey(_refreshKey), // Force rebuild on refresh
                        stream: FirebaseFirestore.instance
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
                                          Icons.report_outlined,
                                          size: 64,
                                          color: Colors.grey[400],
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          "No incident report yet.",
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

                          final incidents = snapshot.data!.docs;

                          // Collect unique IDs for batch fetching
                          final Set<String> houseIds = {};
                          final Set<String> elderlyIds = {};
                          final Set<String> caregiverIds = {};

                          for (final doc in incidents) {
                            final data = doc.data() as Map<String, dynamic>;
                            if (data['house_id'] != null) {
                              List<String> houseIdList = [];
                              if (data['house_id'] is List) {
                                houseIdList = List<String>.from(
                                  data['house_id'],
                                );
                              } else if (data['house_id'] is String) {
                                houseIdList = [data['house_id']];
                              }
                              houseIds.addAll(houseIdList);
                            }
                            if (data['elderly_id'] != null) {
                              elderlyIds.add(data['elderly_id'].toString());
                            }
                            if (data['user_id_cg'] != null) {
                              caregiverIds.add(data['user_id_cg'].toString());
                            }
                          }

                          // Fetch all related data in batch
                          return FutureBuilder<
                            Map<String, Map<String, String>>
                          >(
                            future: _fetchRelatedData(
                              houseIds,
                              elderlyIds,
                              caregiverIds,
                            ),
                            builder: (context, relatedDataSnapshot) {
                              if (relatedDataSnapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final relatedData =
                                  relatedDataSnapshot.data ??
                                  {
                                    'houses': {},
                                    'elderly': {},
                                    'caregivers': {},
                                  };

                              return ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: incidents.length,
                                itemBuilder: (context, index) {
                                  final data =
                                      incidents[index].data()
                                          as Map<String, dynamic>;
                                  final incidentId = incidents[index].id;

                                  // Handle house_id as string or array
                                  List<String> houseIdList = [];
                                  if (data['house_id'] is List) {
                                    houseIdList = List<String>.from(
                                      data['house_id'],
                                    );
                                  } else if (data['house_id'] is String) {
                                    houseIdList = [data['house_id']];
                                  }
                                  final houseId = houseIdList.isNotEmpty
                                      ? houseIdList[0]
                                      : '';
                                  final houseName =
                                      relatedData['houses']?[houseId] ??
                                      "Unknown House";

                                  final elderlyName =
                                      relatedData['elderly']?[data['elderly_id']
                                          ?.toString()] ??
                                      "Unknown Elderly";
                                  final caregiverName =
                                      relatedData['caregivers']?[data['user_id_cg']
                                          ?.toString()] ??
                                      "Unknown Caregiver";

                                  final timestamp =
                                      (data['incident_date_time'] as Timestamp)
                                          .toDate();
                                  final time = DateFormat(
                                    'h:mm a',
                                  ).format(timestamp);

                                  // Send notification for new incidents (only recent ones)
                                  if (nurseId != null) {
                                    final assignedNurses = data['user_id_nu'];
                                    final now = DateTime.now();
                                    if (assignedNurses is List &&
                                        assignedNurses.contains(nurseId) &&
                                        !_shownIncidentNotifications
                                            .containsKey(incidentId) &&
                                        timestamp.isAfter(
                                          now.subtract(
                                            const Duration(seconds: 10),
                                          ),
                                        )) {
                                      NotificationService.scheduleTaskNotification(
                                        id: incidentId.hashCode,
                                        title: 'Incident Report',
                                        body:
                                            'Incident: ${data['incident_type'] ?? ''} - ${data['additional_info'] ?? ''}',
                                        dateTime: DateTime.now().add(
                                          const Duration(seconds: 1),
                                        ),
                                      );
                                      _shownIncidentNotifications[incidentId] =
                                          true;
                                    }
                                  }

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color.fromARGB(
                                        255,
                                        220,
                                        247,
                                        220,
                                      ), // Green background
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color.fromARGB(
                                          255,
                                          180,
                                          246,
                                          182,
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
                                        // Top row with incident icon, house name, time
                                        Row(
                                          children: [
                                            Container(
                                              width: 50,
                                              height: 50,
                                              decoration: BoxDecoration(
                                                color: Colors.green,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                Icons.report,
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
                                                  color: Colors.green,
                                                ),
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  time,
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
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        // Elderly and caregiver info
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                              Icons.person,
                                              size: 18,
                                              color: Colors.green,
                                            ),
                                            const SizedBox(width: 6),
                                            const Text(
                                              "Elderly: ",
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                elderlyName,
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                              Icons.person_outline,
                                              size: 18,
                                              color: Colors.green,
                                            ),
                                            const SizedBox(width: 6),
                                            const Text(
                                              "Submitted by: ",
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
                                              color: Colors.green,
                                            ),
                                            const SizedBox(width: 6),
                                            const Text(
                                              "What happened?",
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        // Description box
                                        Center(
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.green[50],
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // Incident Type
                                                Text(
                                                  (data['incident_type'] ?? '')
                                                          .isNotEmpty
                                                      ? data['incident_type']
                                                      : 'No incident type specified',
                                                  textAlign: TextAlign.justify,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                                // Additional Info
                                                if ((data['additional_info'] ??
                                                        '')
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
                                                    data['additional_info'],
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

          // Sidebar Overlay
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
