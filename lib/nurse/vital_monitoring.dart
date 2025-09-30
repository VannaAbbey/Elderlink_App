import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../auth/login.dart';
import 'vital_monitoring_layout.dart';

/// =============================
/// Medication Management Screen
/// =============================
class VitalMonitoringScreen extends StatefulWidget {
  const VitalMonitoringScreen({super.key});

  @override
  State<VitalMonitoringScreen> createState() =>
      _VitalMonitoringScreenState();
}

class _VitalMonitoringScreenState
    extends State<VitalMonitoringScreen> {
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
        'elderly_name': data['elderly_name'] ??
            "${data['elderly_fname'] ?? ''} ${data['elderly_lname'] ?? ''}".trim(),
        'elderly_age': data['elderly_age'] ?? '',
      };
    }).toList();

    // Apply search filter
    if (_search.isNotEmpty) {
      return list
          .where((e) =>
              (e['elderly_name'] ?? '')
                  .toString()
                  .toLowerCase()
                  .contains(_search.toLowerCase()))
          .toList();
    }
    return list;
  }

  Future<void> _handleLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return VitalMonitoringLayout(
      search: _search,
      onSearchChanged: (v) => setState(() => _search = v),
      toggleSidebar: toggleSidebar,
      isSidebarOpen: isSidebarOpen,
      nurseName: nurseName,
      houseDescriptions: houseDescriptions,
      fetchHouses: fetchHouses,
      fetchElderlies: fetchElderlies, // 👈 now correctly implemented
      selectedHouseId: selectedHouseId,
      onHouseSelected: (houseId) {
        setState(() => selectedHouseId = houseId);
      },
     
    );
  }
}
