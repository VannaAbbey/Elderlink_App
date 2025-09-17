import 'package:elderlink_app/nurse/incident_report.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';
import 'elderly_list.dart';
import 'edit_profile.dart';
import 'medication_management.dart';
import 'vital_monitoring.dart';
import 'emergency.dart';
import 'nurse_bottom_navbar.dart';

class NurseHomeScreen extends StatefulWidget {
  const NurseHomeScreen({super.key});

  @override
  State<NurseHomeScreen> createState() => _NurseHomeScreenState();
}

class _NurseHomeScreenState extends State<NurseHomeScreen> {
  bool isSidebarOpen = false;
  int selectedIndex = 0;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _houses = [];
  bool _isLoadingHouses = true;

  @override
  void initState() {
    super.initState();
    _loadHouses();
  }

  Future<void> _loadHouses() async {
    try {
      QuerySnapshot snapshot = await _firestore.collection('house').get();
      setState(() {
        _houses = snapshot.docs
            .map((doc) => doc.data() as Map<String, dynamic>)
            .toList();
        _houses.sort((a, b) {
          String idA = a['house_id'] ?? '';
          String idB = b['house_id'] ?? '';
          return idA.compareTo(idB);
        });
        _isLoadingHouses = false;
      });
    } catch (e) {
      debugPrint("Error fetching houses: $e");
      setState(() => _isLoadingHouses = false);
    }
  }

  Future<List<Map<String, dynamic>>> fetchHouses() async {
    QuerySnapshot snapshot = await _firestore.collection('house').get();
    return snapshot.docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .toList();
  }

  Future<void> _handleLogout() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/get_started',
        (route) => false,
      );
    }
  }

  void toggleSidebar() {
    setState(() {
      isSidebarOpen = !isSidebarOpen;
    });
  }

  /// ✅ Modified to navigate to Medication Management when index == 3
  // List of screens for the nurse (index 0 = dashboard, others map to pages)
  final List<Widget> _screens = [
    const Center(child: Text("Nurse Dashboard")),
    IncidentReportScreen(),
    EmergencyScreen(),
    MedicationManagementScreen(),
    VitalMonitoringScreen(),
  ];

  void onNavTap(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (isSidebarOpen) {
          setState(() => isSidebarOpen = false);
        }
      },
      child: Scaffold(
        body: selectedIndex == 0
            ? Stack(
                // Nurse Dashboard
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
                      child: ListView(
                        children: [
                          _headerSection(),
                          const SizedBox(height: 20),
                          _searchBar(),
                          const SizedBox(height: 20),
                          _medicalTasksSection(),
                          const SizedBox(height: 30),
                          _housesSection(),
                        ],
                      ),
                    ),
                  ),
                  if (isSidebarOpen) _buildSidebarOverlay(),
                ],
              )
            : _screens[selectedIndex], // other tabs
        bottomNavigationBar: NurseBottomNavBar(
          selectedIndex: selectedIndex,
          onNavTap: onNavTap,
        ),
      ),
    );
  }

  Widget _headerSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: toggleSidebar,
              child: Consumer<AuthProvider>(
                builder: (context, authProvider, child) {
                  final profilePic = authProvider.userData?['user_profilePic'];

                  return CircleAvatar(
                    radius: 24,
                    backgroundImage:
                        (profilePic != null && profilePic.isNotEmpty)
                        ? NetworkImage(profilePic)
                        : const AssetImage('assets/images/people_icon.png')
                              as ImageProvider,
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Consumer<AuthProvider>(
                  builder: (context, authProvider, child) {
                    if (authProvider.userData == null) {
                      return const Text(
                        'Hello Nurse,',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      );
                    }
                    final firstName = authProvider.userFirstName;
                    final displayName =
                        (firstName.isEmpty || firstName == 'User')
                        ? ''
                        : firstName;

                    return Text(
                      displayName.isEmpty
                          ? 'Hello Nurse,'
                          : 'Hello Nurse $displayName,',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    );
                  },
                ),
                const Text('Hope you are doing well'),
              ],
            ),
          ],
        ),
        const Icon(Icons.notifications, color: Color(0XFF1D66A0), size: 35),
      ],
    );
  }

  Widget _searchBar() {
    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        child: TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            hintText: "Search",
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 15),
            filled: true,
            fillColor: const Color(0xFFD8F4FF),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 9,
              horizontal: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Color(0xFF00588E),
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF00588E), width: 2),
            ),
          ),
          style: const TextStyle(fontSize: 18, color: Colors.black),
        ),
      ),
    );
  }

  Widget _medicalTasksSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(183, 221, 245, 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(
                    Icons.medical_services,
                    color: Color(0xFF00588E),
                    size: 45,
                  ),
                  SizedBox(width: 6),
                  Text(
                    "Medical Tasks",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const Text(
                "See All",
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _medicalTaskCard(
            'Lola Celia',
            'Blood Pressure Check',
            '9:00 AM',
            const Color(0xFFFFB0A5),
          ),
          _medicalTaskCard(
            'Lolo Adam',
            'Medication Administration',
            '11:00 AM',
            const Color(0xFFB7DDF5),
          ),
          _medicalTaskCard(
            'Lola Andrea',
            'Health Assessment',
            '2:00 PM',
            const Color(0xFFB7DDF5),
          ),
        ],
      ),
    );
  }

 Widget _housesSection() {
  if (_isLoadingHouses) {
    return const Center(child: CircularProgressIndicator());
  }

  if (_houses.isEmpty) {
    return const Text("No houses available.");
  }

  // Scrollable list ng houses
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: const [
          Icon(Icons.home, color: Color(0xFF00588E), size: 45),
          SizedBox(width: 8),
          Text(
            "Elderly Houses",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      const SizedBox(height: 10),
      ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _houses.length,
        itemBuilder: (context, index) {
          final house = _houses[index];
          final houseName = house['house_name'] ?? '';
          
          List<String> houseImages = [
            'assets/images/Sebastian.png',
            'assets/images/Emmanuel.png',
            'assets/images/Charbell.png',
            'assets/images/Rose_of_Lima.png',
            'assets/images/Gabriel.png',
          ];

          List<String> houseDescriptions = [
            'Females with Psychological Needs',
            'Females that are Bedridden',
            'Males that are Bedridden',
            'Females that are Abled',
            'Males that are Abled',
          ];

          String imagePath = index < houseImages.length
              ? houseImages[index]
              : 'assets/images/people_icon.png';

          String description = index < houseDescriptions.length
              ? houseDescriptions[index]
              : 'Elderly Care Facility';

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ElderlyListScreen(
                    houseId: house['house_id'],
                    houseName: houseName,
                  ),
                ),
              );
            },
            child: Card(
              color: const Color(0XFFE7EFFF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Image.asset(imagePath, width: 80, height: 80),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            "House of $houseName",
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00588E),
                              fontFamily: 'Poppins',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF00588E),
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ],
  );
}




  Widget _navIcon(String assetPath, int index) {
    return GestureDetector(
      onTap: () => onNavTap(index),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selectedIndex == index
              ? const Color.fromARGB(255, 255, 255, 255)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Image.asset(
          assetPath,
          height: 38,
          width: 38,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _medicalTaskCard(
    String name,
    String task,
    String time,
    Color bgColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 25,
            backgroundImage: AssetImage('assets/people_icon.png'),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(task),
              ],
            ),
          ),
          Text(time, style: const TextStyle(fontWeight: FontWeight.bold)),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 50),
                  Center(
                    child: Consumer<AuthProvider>(
                      builder: (context, authProvider, child) {
                        if (authProvider.userData == null) {
                          return const Text(
                            'Nurse',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                              fontFamily: 'Poppins',
                            ),
                          );
                        }

                        final firstName = authProvider.userFirstName;
                        final displayName =
                            (firstName.isEmpty || firstName == 'User')
                            ? ''
                            : firstName;

                        return Text(
                          displayName.isEmpty ? 'Nurse' : 'Nurse $displayName',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            fontFamily: 'Poppins',
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.edit, color: Color(0xFF00588e)),
                    title: const Text('Edit Profile'),
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
                  _sidebarItem(Icons.settings, 'Settings'),
                  _sidebarItem(Icons.help, 'Help & Support'),
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
                      onPressed: _handleLogout,
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

  Widget _sidebarItem(IconData icon, String title) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF00588e)),
      title: Text(title),
      onTap: () {
        setState(() => isSidebarOpen = false);
      },
    );
  }
}
