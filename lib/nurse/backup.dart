import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
          setState(() {
            nurseName = doc['user_fname'] ?? '';
          });
        } else {
          setState(() => nurseName = null);
        }
      }
    } catch (e) {
      print("❌ Error loading nurse data: $e");
      setState(() => nurseName = null);
    }
  }

  void toggleSidebar() => setState(() => isSidebarOpen = !isSidebarOpen);

  final Map<String, String> houseDescriptions = const {
    'St. Sebastian': 'Females with Psychological Needs',
    'St. Emmanuel': 'Females that are Bedridden',
    'St. Charbell': 'Males that are Bedridden',
    'St. Rose of Lima': 'Females that are Abled',
    'St. Gabriel': 'Males that are Abled',
  };

  Future<List<Map<String, dynamic>>> fetchHouses() async {
    final snap = await _firestore.collection('house').get();
    final list = snap.docs.map((d) => d.data()).toList();
    list.sort((a, b) => (a['house_id'] ?? '')
        .toString()
        .compareTo((b['house_id'] ?? '').toString()));
    return list;
  }

  Future<void> _handleLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/background1.png', fit: BoxFit.cover),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  // Header
                  Row(
                    children: [
                      GestureDetector(
                        onTap: toggleSidebar,
                        child: const Icon(Icons.menu, size: 30, color: Color(0xFF00588E)),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Vital Monitoring',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF00588E)),
                        ),
                      ),
                      const Icon(Icons.notifications, size: 30, color: Color(0xFF00588E)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Search bar
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      hintText: "Search house...",
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 15),
                      filled: true,
                      fillColor: const Color(0xFFD8F4FF),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF00588E), width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF00588E), width: 2),
                      ),
                    ),
                    style: const TextStyle(fontSize: 18, color: Colors.black),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 24),

                  // Houses list
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: fetchHouses(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snap.hasData || snap.data!.isEmpty) {
                        return const Center(child: Text('No houses available.'));
                      }

                      final houses = snap.data!
                          .where((h) =>
                              _search.isEmpty ||
                              ((h['house_name'] ?? '').toString().toLowerCase())
                                  .contains(_search.toLowerCase()))
                          .toList();

                      return Column(
                        children: houses.map((house) {
                          final houseName = (house['house_name'] ?? '').toString();
                          final imageName =
                              houseName.replaceAll('St. ', '').replaceAll(' ', '');
                          final imagePath = 'assets/images/${imageName}_Logo.png';
                          final desc = houseDescriptions[houseName] ?? 'Elderly Care Facility';

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ElderlyVitalsScreen(
                                    houseId: (house['house_id'] ?? '').toString(),
                                    houseName: houseName,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: const Color(0XFFE7EFFF),
                              ),
                              child: Row(
                                children: [
                                  Image.asset(
                                    imagePath,
                                    width: 80,
                                    height: 80,
                                    errorBuilder: (context, error, stackTrace) =>
                                        Image.asset('assets/images/Rose_Logo.png',
                                            width: 80, height: 80),
                                  ),
                                  const SizedBox(width: 15),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          houseName,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF00588E),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          desc,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          if (isSidebarOpen) _buildSidebarOverlay(),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String title, {VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF00588e)),
      title: Text(title),
      onTap: onTap ?? () {},
    );
  }

  Widget _buildSidebarOverlay() {
    return Stack(
      children: [
        GestureDetector(onTap: toggleSidebar, child: Container(color: Colors.black54)),
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
                    nurseName != null && nurseName!.isNotEmpty
                        ? 'Nurse $nurseName'
                        : 'No name found',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  _sidebarItem(Icons.logout, "Logout", onTap: _handleLogout),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Screen showing all elderly in a house along with their vital details
class ElderlyVitalsScreen extends StatefulWidget {
  final String houseId;
  final String houseName;

  const ElderlyVitalsScreen({super.key, required this.houseId, required this.houseName});

  @override
  State<ElderlyVitalsScreen> createState() => _ElderlyVitalsScreenState();
}

class _ElderlyVitalsScreenState extends State<ElderlyVitalsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> elderlyList = [];
  bool isLoading = true;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchElderly();
  }

  Future<void> _fetchElderly() async {
    try {
      final snapshot = await _firestore
          .collection('elderly')
          .where('house_id', isEqualTo: widget.houseId)
          .where('elderly_status', isEqualTo: 'Alive')
          .get();

      elderlyList = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'elderly_id': doc.id,
          'elderly_fname': data['elderly_fname'] ?? '',
          'elderly_lname': data['elderly_lname'] ?? '',
          'elderly_profilePic': data['elderly_profilePic'] ?? '',
          'elderly_age': data['elderly_age'] ?? '',
          'elderly_sex': data['elderly_sex'] ?? '',
          'elderly_mobilityStatus': data['elderly_mobilityStatus'] ?? '',
          'elderly_condition': data['elderly_condition'] ?? '',
          'elderly_dietNotes': data['elderly_dietNotes'] ?? '',
        };
      }).toList();
    } catch (e) {
      print('Error fetching elderly: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = elderlyList
        .where((e) =>
            ('${e['elderly_fname']} ${e['elderly_lname']}')
                .toLowerCase()
                .contains(searchQuery.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Vitals of ${widget.houseName}'),
        backgroundColor: const Color(0xFF00588E),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search elderly...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => searchQuery = v),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredList.isEmpty
                      ? const Center(child: Text('No elderly found'))
                      : ListView.builder(
                          itemCount: filteredList.length,
                          itemBuilder: (context, index) {
                            final elderly = filteredList[index];
                            final fullName =
                                '${elderly['elderly_fname']} ${elderly['elderly_lname']}';
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: elderly['elderly_profilePic'] != ''
                                      ? NetworkImage(elderly['elderly_profilePic'])
                                      : const AssetImage('assets/images/profile.png')
                                          as ImageProvider,
                                ),
                                title: Text(fullName),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Age: ${elderly['elderly_age']}'),
                                    Text('Sex: ${elderly['elderly_sex']}'),
                                    Text('Mobility: ${elderly['elderly_mobilityStatus']}'),
                                    Text('Condition: ${elderly['elderly_condition']}'),
                                    Text('Diet Notes: ${elderly['elderly_dietNotes']}'),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
