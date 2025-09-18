import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'caregiver_sidebar.dart';
import 'notifications.dart';
import 'package:intl/intl.dart';

class IncidentScreen extends StatefulWidget {
  const IncidentScreen({super.key});
  @override
  State<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends State<IncidentScreen> {
  bool isSidebarOpen = false;
  bool isOnDuty = false;
  void toggleSidebar() => setState(() => isSidebarOpen = !isSidebarOpen);

  String? selectedElderly;
  final TextEditingController reportController = TextEditingController();
  List<Map<String, dynamic>> elderlyList = []; // Will contain elderly data
  String caregiverName = '';

  @override
  void initState() {
    super.initState();
    _loadAssignedElderly();
    _loadCaregiverName();
  }

  Future<void> _loadAssignedElderly() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return; // Not logged in

    // Step 0: Get caregiver document ID from users collection
    final caregiverSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('user_email', isEqualTo: currentUser.email)
        .where('user_type', isEqualTo: 'caregiver')
        .get();

    if (caregiverSnapshot.docs.isEmpty) return;
    final caregiverId = caregiverSnapshot.docs.first.id;

    final today = DateTime.now();
    final dayOfWeek = DateFormat('EEEE').format(today); // Monday, Tuesday, etc.
    final currentTime = DateFormat('HH:mm').format(today);

    // Step 1: Get current house assignments for this caregiver
    final assignSnapshot = await FirebaseFirestore.instance
        .collection('cg_house_assign')
        .where('caregiver_id', isEqualTo: caregiverId)
        .where('is_current', isEqualTo: true)
        .get();

    List<String> eligibleHouseIds = [];
    for (var doc in assignSnapshot.docs) {
      final data = doc.data();
      final daysAssigned = List<String>.from(data['days_assigned'] ?? []);
      final timeRange = Map<String, dynamic>.from(data['time_range'] ?? {});
      final shiftStart = timeRange['start'] ?? '00:00';
      final shiftEnd = timeRange['end'] ?? '23:59';
      final houseId = data['house_id'];

      // Check if today is in assigned days and current time is in range
      if (daysAssigned.contains(dayOfWeek) &&
          _isTimeInRange(currentTime, shiftStart, shiftEnd)) {
        eligibleHouseIds.add(houseId);
        isOnDuty = true; // ✅ Caregiver is currently on shift
      }
    }

    if (eligibleHouseIds.isEmpty) return;

    // Step 2: Get elderly assigned to this caregiver
    final elderlyAssignSnapshot = await FirebaseFirestore.instance
        .collection('elderly_caregiver_assign')
        .where('caregiver_id', isEqualTo: caregiverId)
        .where('status', isEqualTo: 'active')
        .get();

    List<String> eligibleElderlyIds = elderlyAssignSnapshot.docs
        .map((doc) => doc['elderly_id'] as String)
        .toList();

    if (eligibleElderlyIds.isEmpty) return;

    // Step 3: Fetch elderly details and filter by house
    final elderlySnapshot = await FirebaseFirestore.instance
        .collection('elderly')
        .where(FieldPath.documentId, whereIn: eligibleElderlyIds)
        .get();

    final filteredElderly = elderlySnapshot.docs
        .where((doc) => eligibleHouseIds.contains(doc['house_id']))
        .map(
          (doc) => {
            'id': doc.id,
            'name': '${doc['elderly_fname']} ${doc['elderly_lname']}',
          },
        )
        .toList();

    // Safe, case-insensitive alphabetical sort
    filteredElderly.sort((a, b) {
      final nameA = (a['name'] ?? '');
      final nameB = (b['name'] ?? '');
      return nameA.toLowerCase().compareTo(nameB.toLowerCase());
    });

    setState(() {
      elderlyList = filteredElderly;
    });
  }

  Future<void> _loadCaregiverName() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    print("🔎 Current user email: ${currentUser.email}");

    final caregiverSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('user_email', isEqualTo: currentUser.email)
        .where('user_type', isEqualTo: 'caregiver')
        .get();

    print("📌 Docs found: ${caregiverSnapshot.docs.length}");

    if (caregiverSnapshot.docs.isNotEmpty) {
      final data = caregiverSnapshot.docs.first.data();
      print("✅ Caregiver data: $data");

      setState(() {
        caregiverName = "${data['user_fname']} ${data['user_lname']}";
      });
    } else {
      setState(() {
        caregiverName = "No caregiver found";
      });
    }
  }

  bool _isTimeInRange(String current, String start, String end) {
    final fmt = DateFormat('HH:mm');
    final now = fmt.parse(current);
    final startTime = fmt.parse(start);
    final endTime = fmt.parse(end);

    // Handle overnight shifts (e.g., 22:00-06:00)
    if (endTime.isBefore(startTime)) {
      return now.isAfter(startTime) || now.isBefore(endTime);
    } else {
      return now.isAfter(startTime) && now.isBefore(endTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    Future<void> handleLogout() async {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/get_started',
          (route) => false,
        );
      }
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/background1.png',
            fit: BoxFit.cover,
          ),
        ),
        Column(
          children: [
            const SizedBox(height: 16),
            Expanded(
              child: Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  backgroundColor: const Color(0x00FFFFFF),
                  title: const Text(
                    'Incident Report',
                    style: TextStyle(
                      color: Color(0xFF00588e),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  centerTitle: true,
                  leading: IconButton(
                    icon: const Icon(Icons.menu, color: Color(0xFF00588e)),
                    onPressed: toggleSidebar,
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(
                        Icons.notifications,
                        color: Color(0xFF00588e),
                        size: 35,
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const NotificationsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                body: Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.person,
                                color: Color(0xFF00588e),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Name of the Elderly:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF00588e),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6F3FA),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedElderly,
                                hint: const Text('Select Elderly'),
                                isExpanded: true,
                                icon: const Icon(
                                  Icons.arrow_drop_down,
                                  color: Color(0xFF00588e),
                                ),
                                menuMaxHeight: 200,
                                items: elderlyList.map((elderly) {
                                  return DropdownMenuItem<String>(
                                    value: '${elderly['name']}', // name lang
                                    child: Text('${elderly['name']}'),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    selectedElderly = value; // name lang
                                  });
                                },
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6F3FA),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                              controller: reportController,
                              maxLines: 20,
                              enabled: isOnDuty,
                              decoration: const InputDecoration(
                                hintText: 'Write the incident report here.',
                                hintStyle: TextStyle(
                                  fontStyle: FontStyle.italic,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                if (!isOnDuty) {
                                  // ❌ Not on schedule → show warning
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize
                                            .min, // 🔹 Sakto lang sa content width
                                        children: const [
                                          Icon(
                                            Icons.warning_amber_rounded,
                                            color: Colors.orange,
                                            size: 28,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            "Not Your Schedule",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 22,
                                            ),
                                          ),
                                        ],
                                      ),
                                      content: const Text(
                                        "You are not scheduled for this time. You can only forward a report during your assigned shift.",
                                        textAlign:
                                            TextAlign.justify, // 🔹 Justified
                                        style: TextStyle(fontSize: 15),
                                      ),
                                      actions: [
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Color(
                                              0xFF00588E,
                                            ), // 🔹 Blue background
                                            foregroundColor:
                                                Colors.white, // 🔹 White text
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 30,
                                              vertical: 14,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    30,
                                                  ), // 🔹 Capsule style
                                            ),
                                            elevation:
                                                3, // optional: shadow effect
                                          ),
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text(
                                            "OK",
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  return;
                                }
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (BuildContext ctx) {
                                    bool acknowledged = false;
                                    return StatefulBuilder(
                                      builder: (context, setState) {
                                        return Dialog(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          insetPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 24,
                                                vertical: 40,
                                              ),
                                          child: Container(
                                            width: 380,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 16,
                                              horizontal: 18,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: SingleChildScrollView(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Center(
                                                          child: Text(
                                                            'Confirmation Form',
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 20,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: Color(
                                                                    0xFF22688E,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(
                                                          Icons.close,
                                                          size: 28,
                                                          color: Color(
                                                            0xFF00588E,
                                                          ),
                                                        ),
                                                        onPressed: () =>
                                                            Navigator.of(
                                                              ctx,
                                                            ).pop(),
                                                      ),
                                                    ],
                                                  ),
                                                  const Divider(),
                                                  const SizedBox(height: 8),
                                                  const Text(
                                                    'Please review the following information before submitting:',
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.person,
                                                        color: Color(
                                                          0xFF00588e,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      const Text(
                                                        'Elderly Name:',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Color(
                                                            0xFF00588e,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          selectedElderly ?? '',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 15,
                                                              ),
                                                          overflow: TextOverflow
                                                              .visible,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 10),
                                                  Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.access_time,
                                                        color: Color(
                                                          0xFF00588e,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      const Text(
                                                        'Date & Time:',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Color(
                                                            0xFF00588e,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          DateFormat(
                                                            'MM/dd/yy | h:mm a',
                                                          ).format(
                                                            DateTime.now(),
                                                          ), // current time
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 15,
                                                              ),
                                                          overflow: TextOverflow
                                                              .visible,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 20),
                                                  Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.warning,
                                                        color: Color(
                                                          0xFF00588e,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      const Text(
                                                        'Incident Description:',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Color(
                                                            0xFF00588e,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 10),
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: Color(0xFFE6F3FA),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black12,
                                                        ),
                                                      ],
                                                    ),
                                                    padding:
                                                        const EdgeInsets.all(
                                                          10,
                                                        ),
                                                    child: SizedBox(
                                                      height: 120,
                                                      child: Align(
                                                        alignment:
                                                            Alignment.topLeft,
                                                        child: Text(
                                                          reportController.text,
                                                          style:
                                                              const TextStyle(
                                                                fontStyle:
                                                                    FontStyle
                                                                        .italic,
                                                                fontSize: 15,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 20),
                                                  Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.person,
                                                        color: Color(
                                                          0xFF00588e,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      const Text(
                                                        'Caregiver:',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Color(
                                                            0xFF00588e,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          caregiverName, // Placeholder
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 15,
                                                              ),
                                                          overflow: TextOverflow
                                                              .visible,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Checkbox(
                                                        value: acknowledged,
                                                        activeColor:
                                                            const Color(
                                                              0xFF00588e,
                                                            ),
                                                        onChanged: (val) {
                                                          setState(() {
                                                            acknowledged =
                                                                val ?? false;
                                                          });
                                                        },
                                                      ),
                                                      Expanded(
                                                        child: const Text(
                                                          'I acknowledge that the information provided is accurate and complete. I accept full responsibility and understand that this submission is final and cannot be modified.',
                                                          textAlign:
                                                              TextAlign.justify,
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 20),
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceEvenly,
                                                    children: [
                                                      SizedBox(
                                                        width: 120,
                                                        height: 44,
                                                        child: ElevatedButton(
                                                          onPressed:
                                                              acknowledged
                                                              ? () {
                                                                  // TODO: Submit logic
                                                                  Navigator.of(
                                                                    ctx,
                                                                  ).pop();
                                                                }
                                                              : null,
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                const Color(
                                                                  0xFF00588e,
                                                                ),
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    18,
                                                                  ),
                                                            ),
                                                          ),
                                                          child: const Text(
                                                            'Submit',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 120,
                                                        height: 44,
                                                        child: ElevatedButton(
                                                          onPressed: () {
                                                            Navigator.of(
                                                              ctx,
                                                            ).pop();
                                                          },
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                Colors.red,
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    18,
                                                                  ),
                                                            ),
                                                          ),
                                                          child: const Text(
                                                            'Cancel',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
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
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isOnDuty
                                    ? const Color(
                                        0xFF00588e,
                                      ) // 🔹 Blue if on schedule
                                    : const Color.fromARGB(
                                        255,
                                        215,
                                        215,
                                        215,
                                      ), // 🔹 Gray if not schedule
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                elevation: 4,
                              ),
                              child: const Text(
                                'Forward the Report',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        CaregiverSidebar(
          onLogout: handleLogout,
          isSidebarOpen: isSidebarOpen,
          toggleSidebar: toggleSidebar,
          parentContext: context,
        ),
      ],
    );
  }
}
