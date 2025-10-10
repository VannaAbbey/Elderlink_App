// lib/nurse/vital_monitoring.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  String _search = '';
  String? nurseName;
  bool isSidebarOpen = false;
  String? selectedHouseId; // track selected house

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
          houseId: selectedHouseId ?? 'H001', // Use selected house or default
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
        .where('elderly_status', isEqualTo: 'Alive') // optional filter
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

    // Apply search filter
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
                            // House Tabs
                            Material(
                              color: Colors.white,
                              child: TabBar(
                                isScrollable: true,
                                labelColor: const Color(0xFF00588E),
                                unselectedLabelColor: Colors.grey,
                                indicatorColor: const Color(0xFF00588E),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 0,
                                ),
                                  tabs: houses.map((house) {
                                    print(
                                      '🏠 Creating tab for house: ${house['house_name']} with ID: ${house['house_id']}',
                                    );
                                    return Tab(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: Image.asset(
                                              'assets/images/${house['house_name']?.toString().replaceAll('St. ', '').replaceAll(' ', '')}_Logo.png',
                                              width: 24,
                                              height: 24,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                    return const Icon(
                                                      Icons.home,
                                                    );
                                                  },
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(house['house_name'] ?? ''),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),

                            // House Content
                            Expanded(
                              child: TabBarView(
                                children: houses.map((house) {
                                  return DefaultTabController(
                                    length: 3,
                                    child: Column(
                                      children: [
                                        // Vital Status Tabs
                                        TabBar(
                                          labelColor: const Color(0xFF00588E),
                                          unselectedLabelColor: Colors.grey,
                                          indicatorColor: const Color(
                                            0xFF00588E,
                                          ),
                                          tabs: const [
                                            Tab(text: 'Upcoming'),
                                            Tab(text: 'Completed'),
                                            Tab(text: 'Missed'),
                                          ],
                                        ),

                                        // Vital Content
                                        Expanded(
                                          child: TabBarView(
                                            children: [
                                              Builder(
                                                builder: (context) {
                                                  print(
                                                    '🔄 Creating UpcomingVitalsTab for house: ${house['house_name']} with ID: ${house['house_id']}',
                                                  );
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
