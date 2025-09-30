import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'caregiver_sidebar.dart';
import 'notifications.dart';

class IncidentScreen extends StatefulWidget {
  const IncidentScreen({super.key});

  @override
  State<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends State<IncidentScreen> {
  bool isSidebarOpen = false;
  void toggleSidebar() => setState(() => isSidebarOpen = !isSidebarOpen);

  String? selectedElderlyId;
  String? selectedElderlyName;
  final TextEditingController reportController = TextEditingController();
  bool isLoading = true;
  bool isOnDuty = false;
  List<Map<String, dynamic>> elderlyList = [];

  // caregiver name
  String? caregiverName;

  // Shift state
  DateTime shiftStart = DateTime.now();
  DateTime shiftEnd = DateTime.now();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadElderlyAssignments();
    _loadCaregiverName();
  }

  Future<void> _loadCaregiverName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        setState(() {
          caregiverName = "${doc['user_fname']} ${doc['user_lname']}";
        });
      }
    }
  }

  Future<void> _loadElderlyAssignments() async {
    setState(() => isLoading = true);

    final now = DateTime.now();
    final dayName = DateFormat('EEEE').format(now);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          elderlyList = [];
          isOnDuty = false;
          isLoading = false;
        });
        return;
      }

      final caregiverId = user.uid;

      final houseSnapshot = await _firestore
          .collection('cg_house_assign')
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('is_current', isEqualTo: true)
          .where('is_absent', isEqualTo: false)
          .limit(1)
          .get();

      if (houseSnapshot.docs.isEmpty) {
        setState(() {
          elderlyList = [];
          isOnDuty = false;
          isLoading = false;
        });
        return;
      }

      final houseData = houseSnapshot.docs.first.data();
      final daysAssigned = List<String>.from(houseData['days_assigned'] ?? []);
      final houseId = houseData['house_id'] as String;
      final startDate = (houseData['start_date'] as Timestamp).toDate();
      final endDate = (houseData['end_date'] as Timestamp).toDate();

      if (now.isBefore(startDate) || now.isAfter(endDate)) {
        setState(() {
          elderlyList = [];
          isOnDuty = false;
          isLoading = false;
        });
        return;
      }

      if (!daysAssigned.contains(dayName)) {
        setState(() {
          elderlyList = [];
          isOnDuty = false;
          isLoading = false;
        });
        return;
      }

      final timeRange = Map<String, dynamic>.from(
        houseData['time_range'] ?? {},
      );
      int startHour = 6, startMinute = 0, endHour = 14, endMinute = 0;
      if (timeRange.isNotEmpty) {
        final startParts = (timeRange['start'] as String).split(':');
        final endParts = (timeRange['end'] as String).split(':');
        startHour = int.parse(startParts[0]);
        startMinute = int.parse(startParts[1]);
        endHour = int.parse(endParts[0]);
        endMinute = int.parse(endParts[1]);
      }

      DateTime calculatedShiftStart = DateTime(
        now.year,
        now.month,
        now.day,
        startHour,
        startMinute,
      );
      DateTime calculatedShiftEnd = DateTime(
        now.year,
        now.month,
        now.day,
        endHour,
        endMinute,
      );

      if (calculatedShiftEnd.isBefore(calculatedShiftStart)) {
        if (now.isBefore(calculatedShiftEnd)) {
          calculatedShiftStart = calculatedShiftStart.subtract(
            const Duration(days: 1),
          );
        } else {
          calculatedShiftEnd = calculatedShiftEnd.add(const Duration(days: 1));
        }
      }

      final isWithinShift =
          !(now.isBefore(calculatedShiftStart) ||
              now.isAfter(calculatedShiftEnd));

      if (!isWithinShift) {
        setState(() {
          elderlyList = [];
          isOnDuty = false;
          isLoading = false;
        });
        return;
      }

      final assignSnapshot = await _firestore
          .collection('elderly_caregiver_assign')
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('day', isEqualTo: dayName)
          .get();

      List<Map<String, dynamic>> elderlyDetails = [];

      if (assignSnapshot.docs.isNotEmpty) {
        final elderlyIds = assignSnapshot.docs
            .map((doc) => doc.data()['elderly_id'] as String)
            .toSet()
            .toList();

        for (int i = 0; i < elderlyIds.length; i += 30) {
          final chunk = elderlyIds.skip(i).take(30).toList();
          final chunkSnapshot = await _firestore
              .collection('elderly')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();

          for (var doc in chunkSnapshot.docs) {
            final data = doc.data();
            if (data['house_id'] == houseId) {
              elderlyDetails.add({
                'id': doc.id,
                'name':
                    '${data['elderly_fname'] ?? ''} ${data['elderly_lname'] ?? ''}',
              });
            }
          }
        }

        elderlyDetails.sort(
          (a, b) => (a['name'] as String).compareTo(b['name'] as String),
        );
      }

      setState(() {
        elderlyList = elderlyDetails;
        isOnDuty = true;
        isLoading = false;
        selectedElderlyId = null;
        selectedElderlyName = null;
        shiftStart = calculatedShiftStart;
        shiftEnd = calculatedShiftEnd;
      });
    } catch (e) {
      setState(() {
        elderlyList = [];
        isOnDuty = false;
        isLoading = false;
        selectedElderlyId = null;
        selectedElderlyName = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    Future<void> handleLogout() async {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/get_started',
        (route) => false,
      );
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
                            children: const [
                              Icon(Icons.person, color: Color(0xFF00588e)),
                              SizedBox(width: 8),
                              Text(
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
                              color: Color(0xFFE6F3FA),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedElderlyId,
                                hint: Text(
                                  isLoading
                                      ? 'Loading...'
                                      : (isOnDuty
                                            ? 'Select Elderly'
                                            : 'Not your schedule today/shift'),
                                ),
                                isExpanded: true,
                                icon: const Icon(
                                  Icons.arrow_drop_down,
                                  color: Color(0xFF00588e),
                                ),
                                menuMaxHeight: 200,
                                items: elderlyList.map((elderly) {
                                  return DropdownMenuItem<String>(
                                    value: elderly['id'],
                                    child: Text(elderly['name']),
                                  );
                                }).toList(),
                                onChanged: isOnDuty
                                    ? (value) {
                                        setState(() {
                                          selectedElderlyId = value;
                                          selectedElderlyName = elderlyList
                                              .firstWhere(
                                                (e) => e['id'] == value,
                                              )['name'];
                                        });
                                      }
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            decoration: BoxDecoration(
                              color: Color(0xFFE6F3FA),
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
                                final formattedDate = DateFormat(
                                  'MM/dd/yy | h:mm a',
                                ).format(DateTime.now());

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
                                                        color: Colors.black,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      const Text(
                                                        'Elderly Name:',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          selectedElderlyName ??
                                                              '',
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
                                                        color: Colors.black,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      const Text(
                                                        'Date & Time:',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          formattedDate,
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
                                                        color: Colors.black,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      const Text(
                                                        'Incident Description:',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
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
                                                        color: Colors.black,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      const Text(
                                                        'Caregiver:',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          caregiverName ??
                                                              'Loading...',
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
                                                      const Expanded(
                                                        child: Text(
                                                          'I acknowledge that the information provided is accurate and complete. I accept full responsibility and understand that this submission is final and cannot be modified.',
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
                                                        MainAxisAlignment.end,
                                                    children: [
                                                      // ✅ Submit Button (left side)
                                                      SizedBox(
                                                        width: 120,
                                                        height: 44,
                                                        child: ElevatedButton(
                                                          onPressed:
                                                              (acknowledged &&
                                                                  selectedElderlyName !=
                                                                      null &&
                                                                  selectedElderlyName!
                                                                      .isNotEmpty &&
                                                                  reportController
                                                                      .text
                                                                      .trim()
                                                                      .isNotEmpty)
                                                              ? () {
                                                                  // VALIDATION PASSED
                                                                  Navigator.of(
                                                                    ctx,
                                                                  ).pop();
                                                                  // TODO: Firestore save logic here
                                                                }
                                                              : null, // ❌ Disabled kapag kulang
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                (acknowledged &&
                                                                    selectedElderlyName !=
                                                                        null &&
                                                                    selectedElderlyName!
                                                                        .isNotEmpty &&
                                                                    reportController
                                                                        .text
                                                                        .trim()
                                                                        .isNotEmpty)
                                                                ? const Color(
                                                                    0xFF00588e,
                                                                  ) // Blue kapag enabled
                                                                : Colors
                                                                      .grey, // Grey kapag disabled
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
                                                      const SizedBox(width: 12),

                                                      // ❌ Cancel Button (right side)
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
                                                                const Color(
                                                                  0xFF900000,
                                                                ),
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
                                backgroundColor: const Color(0xFF00588e),
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
