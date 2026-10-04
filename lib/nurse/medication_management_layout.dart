// lib/nurse/medication_management_layout.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'medication_upcoming.dart';
import 'medication_completed.dart';
import 'medication_missed.dart';

class MedicationManagementLayout extends StatelessWidget {
  final String search;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback toggleSidebar;
  final bool isSidebarOpen;
  final String? nurseName;
  final Map<String, String> houseDescriptions;
  final Future<List<Map<String, dynamic>>> Function() fetchHouses;
  final Future<List<Map<String, dynamic>>> Function(String houseId)
  fetchElderlies;
  final String? selectedHouseId;
  final ValueChanged<String?> onHouseSelected;
  final VoidCallback? onBellPressed;

  const MedicationManagementLayout({
    super.key,
    required this.search,
    required this.onSearchChanged,
    required this.toggleSidebar,
    required this.isSidebarOpen,
    required this.nurseName,
    required this.houseDescriptions,
    required this.fetchHouses,
    required this.fetchElderlies,
    required this.selectedHouseId,
    required this.onHouseSelected,
    this.onBellPressed,
  });
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF00588E),
        title: const Text(
          'Medication Management',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: toggleSidebar,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications, color: Colors.white),
            onPressed: onBellPressed,
          ),
        ],
      ),
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
          FutureBuilder<List<Map<String, dynamic>>>(
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
                        tabs: houses.map((house) {
                          return Tab(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.asset(
                                    'assets/images/${house['house_name']?.toString().replaceAll('St. ', '').replaceAll(' ', '')}_Logo.png',
                                    width: 24,
                                    height: 24,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Icon(Icons.home);
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

                    // House Content
                    Expanded(
                      child: TabBarView(
                        children: houses.map((house) {
                          return DefaultTabController(
                            length: 3,
                            child: Column(
                              children: [
                                // Medication Status Tabs
                                TabBar(
                                  labelColor: const Color(0xFF00588E),
                                  unselectedLabelColor: Colors.grey,
                                  indicatorColor: const Color(0xFF00588E),
                                  tabs: const [
                                    Tab(text: 'Upcoming'),
                                    Tab(text: 'Completed'),
                                    Tab(text: 'Missed'),
                                  ],
                                ),

                                // Medication Content
                                Expanded(
                                  child: TabBarView(
                                    children: [
                                      UpcomingMedicationsTab(
                                        houseId: house['house_id'],
                                        nurseName: nurseName,
                                      ),
                                      CompletedMedicationsTab(
                                        houseId: house['house_id'],
                                        nurseName: nurseName,
                                      ),
                                      MissedMedicationsTab(
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

          // Sidebar overlay
          if (isSidebarOpen) _buildSidebarOverlay(context),
        ],
      ),
    );
  }

  Widget _buildSidebarOverlay(BuildContext context) {
    void handleLogout() async {
      await FirebaseAuth.instance.signOut();
      Navigator.pushReplacementNamed(context, '/login');
    }

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
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: const Color(0xFF00588E),
                    child: Text(
                      nurseName?.substring(0, 1).toUpperCase() ?? 'N',
                      style: const TextStyle(fontSize: 32, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    nurseName ?? 'Nurse',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ListTile(
                    leading: const Icon(
                      Icons.person_outline,
                      color: Color(0xFF00588E),
                    ),
                    title: const Text('Profile'),
                    onTap: () => Navigator.pushNamed(context, '/profile'),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.calendar_today,
                      color: Color(0xFF00588E),
                    ),
                    title: const Text('Leave Form'),
                    onTap: () => Navigator.pushNamed(context, '/leave-form'),
                  ),
                  const Spacer(),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text(
                      'Logout',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: handleLogout,
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
