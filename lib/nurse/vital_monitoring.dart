// lib/nurse/vital_monitoring.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'vital_upcoming.dart';
import 'vital_completed.dart';
import 'vital_missed.dart';
import 'activity_logs.dart';
import 'nurse_sidebar.dart';

/// =============================
/// Vital Monitoring Screen
/// =============================
class VitalMonitoringScreen extends StatefulWidget {
  const VitalMonitoringScreen({super.key});

  @override
  State<VitalMonitoringScreen> createState() => _VitalMonitoringScreenState();
}

class _VitalMonitoringScreenState extends State<VitalMonitoringScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final String _search = '';
  String? nurseName;
  bool isSidebarOpen = false;
  String? selectedHouseId; // track selected house

  // 🔹 Improved: Scroll controller for horizontal tab scroll
  final ScrollController _tabScrollController = ScrollController();

  // 🔹 Improved: Auto-scroll to center selected tab with dynamic tab width calculation
  void _scrollToCenter(int index, List<Map<String, dynamic>> houses) {
    if (!_tabScrollController.hasClients) return;

    // Calculate approximate tab width based on text length and icon
    double calculateTabWidth(String houseName) {
      // Base width for icon + padding
      double baseWidth = 24 + 8 + 20; // icon(24) + spacing(8) + padding(20)
      // Add text width (rough estimate: ~8-10px per character)
      double textWidth = houseName.length * 9.0;
      return baseWidth + textWidth + 40; // extra padding
    }

    // Calculate scroll position to center the selected tab
    double scrollPosition = 0.0;
    for (int i = 0; i < index; i++) {
      scrollPosition += calculateTabWidth(houses[i]['house_name'] ?? '');
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    final double selectedTabWidth = calculateTabWidth(
      houses[index]['house_name'] ?? '',
    );
    final double targetScroll =
        scrollPosition - (screenWidth / 2) + (selectedTabWidth / 2);

    // Ensure scroll position stays within bounds
    final double maxScroll = _tabScrollController.position.maxScrollExtent;
    final double clampedScroll = targetScroll.clamp(0.0, maxScroll);

    // Smooth animation with better curve and physics
    _tabScrollController
        .animateTo(
          clampedScroll,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
        )
        .then((_) {
          // Optional: Add a subtle bounce effect at the end for better UX
          if (clampedScroll > 0 && clampedScroll < maxScroll) {
            Future.delayed(const Duration(milliseconds: 50), () {
              if (_tabScrollController.hasClients) {
                _tabScrollController.animateTo(
                  clampedScroll,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.elasticOut,
                );
              }
            });
          }
        });
  }

  final Map<String, String> houseDescriptions = const {
    'St. Sebastian': 'Females with Psychological Needs',
    'St. Emmanuel': 'Females that are Bedridden',
    'St. Charbell': 'Males that are Bedridden',
    'St. Rose of Lima': 'Females that are Abled',
    'St. Gabriel': 'Males that are Abled',
  };

  @override
  void initState() {
    super.initState();
    _loadNurseData();
  }

  @override
  void dispose() {
    _tabScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadNurseData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final firstName = doc['user_fname'] ?? '';
          final lastName = doc['user_lname'] ?? '';
          setState(() => nurseName = '$firstName $lastName'.trim());

          if ((user.displayName ?? '').isEmpty) {
            await user.updateDisplayName(nurseName);
          }
        }
      }
    } catch (e) {
      print("❌ Error loading nurse data: $e");
    }
  }

  void toggleSidebar() => setState(() => isSidebarOpen = !isSidebarOpen);

  void _onBellPressed() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ActivityLogsScreen(
          houseId: selectedHouseId ?? 'H001',
          nurseName: nurseName,
        ),
      ),
    );
  }

  /// Fetch Houses
  Future<List<Map<String, dynamic>>> fetchHouses() async {
    final snap = await _firestore.collection('house').get();
    final list = snap.docs.map((d) => d.data()).toList();
    list.sort(
      (a, b) => (a['house_id'] ?? '').toString().compareTo(
        (b['house_id'] ?? '').toString(),
      ),
    );
    return list;
  }

  /// ✅ Fetch Elderly under a house
  Future<List<Map<String, dynamic>>> fetchElderlies(String houseId) async {
    final snap = await _firestore
        .collection('elderly')
        .where('house_id', isEqualTo: houseId)
        .where('elderly_status', isEqualTo: 'Alive')
        .get();

    final list = snap.docs.map((d) {
      final data = d.data();
      return {
        'elderly_id': d.id,
        'elderly_name':
            data['elderly_name'] ??
            "${data['elderly_fname'] ?? ''} ${data['elderly_lname'] ?? ''}"
                .trim(),
        'elderly_age': data['elderly_age'] ?? '',
      };
    }).toList();

    if (_search.isNotEmpty) {
      return list
          .where(
            (e) => (e['elderly_name'] ?? '').toString().toLowerCase().contains(
              _search.toLowerCase(),
            ),
          )
          .toList();
    }
    return list;
  }

  // Build the Upcoming tab with red circle count
  Widget _buildUpcomingTabWithCount(Map<String, dynamic> house) {
    return FutureBuilder<bool>(
      future: _isNurseAssignedToCurrentShift(),
      builder: (context, shiftSnapshot) {
        final isAssignedToShift =
            shiftSnapshot.data ?? true; // Default to true if loading

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Upcoming'),
            const SizedBox(width: 4),
            StreamBuilder<QuerySnapshot>(
              stream: _getUpcomingVitalsCountStream(house['house_id']),
              builder: (context, snapshot) {
                int count = 0;
                if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                  count = snapshot.data!.docs.length;
                }

                // Don't show red circle if nurse is not assigned to current shift
                if (count == 0 || !isAssignedToShift) {
                  return const SizedBox.shrink();
                }

                return Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    count.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  // Get stream for upcoming vitals count
  Stream<QuerySnapshot> _getUpcomingVitalsCountStream(String houseId) {
    // Get current shift and day
    final currentShift = _getCurrentShift();
    final today = _getTodayDateString();

    // Get nurse ID
    return Stream.fromFuture(_getNurseId()).asyncExpand((nurseId) {
      if (nurseId == null) {
        // Return empty stream
        return Stream<QuerySnapshot>.empty();
      }

      return _firestore
          .collection('vitals')
          .where('assigned_nurse_id', isEqualTo: nurseId)
          .where('house_id', isEqualTo: houseId)
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .where('status', isEqualTo: 'pending')
          .snapshots();
    });
  } // Get current shift

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

  // Get current day
  String _getCurrentDay() {
    final now = DateTime.now();
    final currentHour = now.hour;
    if (currentHour >= 0 && currentHour < 6) {
      final previousDay = now.subtract(Duration(days: 1));
      return DateFormat('EEEE').format(previousDay);
    }
    return DateFormat('EEEE').format(now);
  }

  // Get today date string
  String _getTodayDateString() {
    final now = DateTime.now();
    final currentHour = now.hour;
    if (currentHour >= 0 && currentHour < 6) {
      final previousDay = now.subtract(Duration(days: 1));
      return DateFormat('yyyy-MM-dd').format(previousDay);
    }
    return DateFormat('yyyy-MM-dd').format(now);
  }

  // Get nurse ID from name
  Future<String?> _getNurseId() async {
    if (nurseName == null) return null;

    final nameParts = nurseName!.split(' ');
    if (nameParts.length < 2) return null;

    final firstName = nameParts[0];
    final lastName = nameParts[1];

    final userQuery = await _firestore
        .collection('users')
        .where('user_fname', isEqualTo: firstName)
        .where('user_lname', isEqualTo: lastName)
        .where('user_type', isEqualTo: 'nurse')
        .get();

    if (userQuery.docs.isEmpty) return null;
    return userQuery.docs.first.id;
  }

  // Check if nurse is assigned to current shift
  Future<bool> _isNurseAssignedToCurrentShift() async {
    final nurseId = await _getNurseId();
    if (nurseId == null) return false;

    final currentShift = _getCurrentShift();
    final currentDay = _getCurrentDay();

    try {
      final shiftQuery = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .where('days_assigned', arrayContains: currentDay)
          .get();

      return shiftQuery.docs.isNotEmpty;
    } catch (e) {
      print('❌ Error checking shift assignment: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/background1.png',
              fit: BoxFit.cover,
            ),
          ),

          // Main Content
          SafeArea(
            child: Column(
              children: [
                // Header Row
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: toggleSidebar,
                        child: const Icon(
                          Icons.menu,
                          size: 30,
                          color: Color(0xFF00588E),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Vital Monitoring",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF00588E),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.notifications,
                          color: Color(0xFF00588E),
                        ),
                        iconSize: 30,
                        onPressed: _onBellPressed,
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: fetchHouses(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final houses = snapshot.data!;
                      return DefaultTabController(
                        length: houses.length,
                        child: Column(
                          children: [
                            // 🩶 House Tabs — fixed divider + auto-scroll center
                            Stack(
                              children: [
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 1,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                                SingleChildScrollView(
                                  controller: _tabScrollController,
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  child: Transform.translate(
                                    offset: const Offset(-32, 0),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minWidth:
                                            MediaQuery.of(context).size.width +
                                            64, // extended right side
                                      ),
                                      child: Material(
                                        color: Colors.white,
                                        child: TabBar(
                                          isScrollable: true,
                                          labelColor: const Color(0xFF00588E),
                                          unselectedLabelColor: Colors.grey,
                                          indicator:
                                              const UnderlineTabIndicator(
                                                borderSide: BorderSide(
                                                  color: Color(0xFF00588E),
                                                  width: 3,
                                                ),
                                                insets: EdgeInsets.symmetric(
                                                  horizontal: -20,
                                                ),
                                              ),
                                          labelPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 20,
                                              ),
                                          physics:
                                              const BouncingScrollPhysics(),
                                          onTap: (index) {
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                                  _scrollToCenter(
                                                    index,
                                                    houses,
                                                  );
                                                });
                                          },
                                          tabs: houses.map((house) {
                                            return Tab(
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    child: Image.asset(
                                                      'assets/images/${house['house_name']?.toString().replaceAll('St. ', '').replaceAll(' ', '')}_Logo.png',
                                                      width: 24,
                                                      height: 24,
                                                      errorBuilder:
                                                          (
                                                            context,
                                                            error,
                                                            stackTrace,
                                                          ) {
                                                            return const Icon(
                                                              Icons.home,
                                                            );
                                                          },
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    house['house_name'] ?? '',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // House Content
                            Expanded(
                              child: TabBarView(
                                children: houses.map((house) {
                                  return DefaultTabController(
                                    length: 3,
                                    child: Column(
                                      children: [
                                        TabBar(
                                          labelColor: const Color(0xFF00588E),
                                          unselectedLabelColor: Colors.grey,
                                          indicatorColor: const Color(
                                            0xFF00588E,
                                          ),
                                          tabs: [
                                            Tab(
                                              child: _buildUpcomingTabWithCount(
                                                house,
                                              ),
                                            ),
                                            Tab(text: 'Completed'),
                                            Tab(text: 'Missed'),
                                          ],
                                        ),
                                        Expanded(
                                          child: TabBarView(
                                            children: [
                                              Builder(
                                                builder: (context) {
                                                  return UpcomingVitalsTab(
                                                    houseId: house['house_id'],
                                                    nurseName: nurseName,
                                                  );
                                                },
                                              ),
                                              CompletedVitalsTab(
                                                houseId: house['house_id'],
                                                nurseName: nurseName,
                                              ),
                                              MissedVitalsTab(
                                                houseId: house['house_id'],
                                                nurseName: nurseName,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
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

          // Sidebar overlay
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
