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
        final doc =
            await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          setState(() {
            nurseName = doc['user_fname'] ?? '';
          });
        }
      }
    } catch (e) {
      print('❌ Error loading nurse data: $e');
      setState(() => nurseName = null);
    }
  }

  Future<List<Map<String, dynamic>>> fetchHouses() async {
    final snap = await _firestore.collection('house').get();
    final list = snap.docs.map((d) => d.data()).toList();
    list.sort((a, b) =>
        (a['house_id'] ?? '').toString().compareTo((b['house_id'] ?? '').toString()));
    return list;
  }

  void toggleSidebar() => setState(() => isSidebarOpen = !isSidebarOpen);

  Future<void> _handleLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pop();
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
          // Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/background1.png',
              fit: BoxFit.cover,
            ),
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
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF00588E),
                          ),
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

                  // Houses header
                  Row(
                    children: const [
                      Icon(Icons.home, color: Color(0xFF00588E), size: 45),
                      SizedBox(width: 8),
                      Text(
                        'Elderly Houses',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Houses list
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: fetchHouses(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snap.hasData || snap.data!.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text('No houses available.'),
                        );
                      }

                      final houses = snap.data!.where((h) {
                        final name = (h['house_name'] ?? '').toString().toLowerCase();
                        return _search.isEmpty || name.contains(_search);
                      }).toList();

                      if (houses.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text('No matching houses.'),
                        );
                      }

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
                                  builder: (_) => ElderlyVitalsListScreen(
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
                                    errorBuilder: (context, error, stackTrace) {
                                      return Image.asset(
                                        'assets/images/Rose_Logo.png',
                                        width: 80,
                                        height: 80,
                                      );
                                    },
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
                  ListTile(
                    leading: const Icon(Icons.edit, color: Color(0xFF00588E)),
                    title: const Text("Edit Profile"),
                    onTap: () {},
                  ),
                  const Divider(),
                  ElevatedButton(
                    onPressed: _handleLogout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1D5B78),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding:
                          const EdgeInsets.symmetric(vertical: 10, horizontal: 60),
                    ),
                    child: const Text(
                      'LOGOUT',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
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
}

/// --- Elderly List per House ---
class ElderlyVitalsListScreen extends StatefulWidget {
  final String houseId;
  final String houseName;

  const ElderlyVitalsListScreen({
    super.key,
    required this.houseId,
    required this.houseName,
  });

  @override
  State<ElderlyVitalsListScreen> createState() =>
      _ElderlyVitalsListScreenState();
}

class _ElderlyVitalsListScreenState extends State<ElderlyVitalsListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> allElderly = [];
  List<Map<String, dynamic>> filteredElderly = [];
  String searchQuery = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchElderly();
  }

  Future<void> fetchElderly() async {
    try {
      final snapshot = await _firestore
          .collection('elderly')
          .where('house_id', isEqualTo: widget.houseId)
          .where('elderly_status', isEqualTo: 'Alive')
          .get();

      allElderly = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'elderly_id': doc.id,
          'elderly_fname': data['elderly_fname'] ?? '',
          'elderly_lname': data['elderly_lname'] ?? '',
          'elderly_profilePic': data['elderly_profilePic'] ?? '',
        };
      }).toList();

      filterElderly();
    } catch (e) {
      print('❌ Error fetching elderly: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void filterElderly() {
    List<Map<String, dynamic>> filtered = List.from(allElderly);

    if (searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (e) => ('${e['elderly_fname']} ${e['elderly_lname']}')
                .toLowerCase()
                .contains(searchQuery.toLowerCase()),
          )
          .toList();
    }

    setState(() => filteredElderly = filtered);
  }

  @override
  Widget build(BuildContext context) {
    String logoImage =
        'assets/images/${widget.houseName.replaceAll('St. ', '').trim()}_Logo.png';

    return Scaffold(
      appBar: AppBar(
        title: Text('House of ${widget.houseName}'),
        backgroundColor: const Color(0xFF00588E),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredElderly.isEmpty
              ? const Center(child: Text('No elderly found'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredElderly.length,
                  itemBuilder: (context, index) {
                    final elderly = filteredElderly[index];
                    final fullName =
                        '${elderly['elderly_fname']} ${elderly['elderly_lname']}';
                    final imageUrl =
                        elderly['elderly_profilePic'] as String? ?? '';

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ElderlyVitalDetailsScreen(
                              elderlyId: elderly['elderly_id'],
                              elderlyName: fullName,
                            ),
                          ),
                        );
                      },
                      child: Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: ListTile(
                          leading: ClipOval(
                            child: imageUrl.isNotEmpty
                                ? Image.network(imageUrl, fit: BoxFit.cover)
                                : Image.asset('assets/images/people_icon.png'),
                          ),
                          title: Text(fullName),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

/// --- Elderly Vital Details ---
class ElderlyVitalDetailsScreen extends StatefulWidget {
  final String elderlyId;
  final String elderlyName;

  const ElderlyVitalDetailsScreen({
    super.key,
    required this.elderlyId,
    required this.elderlyName,
  });

  @override
  State<ElderlyVitalDetailsScreen> createState() =>
      _ElderlyVitalDetailsScreenState();
}

class _ElderlyVitalDetailsScreenState extends State<ElderlyVitalDetailsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loading = true;
  Map<String, dynamic> _latestVital = {};

  @override
  void initState() {
    super.initState();
    _loadLatestVital();
  }

  Future<void> _loadLatestVital() async {
  try {
    final snap = await _firestore
        .collection('vitals')
        .where('elderly_id', isEqualTo: widget.elderlyId)
        .get();

    if (snap.docs.isNotEmpty) {
      setState(() {
        _latestVital = snap.docs.first.data();
      });
    } else {
      setState(() {
        _latestVital = {};
      });
    }
  } catch (e) {
    print('❌ Error fetching vitals: $e');
    setState(() => _latestVital = {});
  } finally {
    setState(() => _loading = false);
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Vitals of ${widget.elderlyName}'),
        backgroundColor: const Color(0xFF00588E),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _latestVital.isEmpty
              ? const Center(child: Text('No vitals found'))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Blood Pressure: ${_latestVital['blood_pressure'] ?? '-'}'),
                      const SizedBox(height: 8),
                      Text('Pulse Rate: ${_latestVital['pulse_rate'] ?? '-'}'),
                      const SizedBox(height: 8),
                      Text('O₂ Saturation: ${_latestVital['o2_sat'] ?? '-'}'),
                      const SizedBox(height: 8),
                      Text('Respiratory Rate: ${_latestVital['respiratory_rate'] ?? '-'}'),
                      const SizedBox(height: 8),
                      Text('Temperature: ${_latestVital['temperature'] ?? '-'}'),
                      const SizedBox(height: 8),
                      Text('Recorded At: ${_latestVital['vital_record_at'] != null ? (_latestVital['vital_record_at'] as Timestamp).toDate().toString() : '-'}'),
                    ],
                  ),
                ),
    );
  }
}
