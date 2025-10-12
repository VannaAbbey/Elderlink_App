import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'medication_management_layout.dart';
import 'activity_logs.dart';

/// =============================
/// Medication Management Screen
/// =============================
class MedicationManagementScreen extends StatefulWidget {
  const MedicationManagementScreen({super.key});

  @override
  State<MedicationManagementScreen> createState() =>
      _MedicationManagementScreenState();
}

class _MedicationManagementScreenState
    extends State<MedicationManagementScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _search = '';
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

  /// ✅ Fetch Elderly under a house (assigned only for this nurse + today + current shift)
  Future<List<Map<String, dynamic>>> fetchElderlies(String houseId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return [];

    // 🔹 Step 1: Load nurse profile to get the correct nurse_id (doc ID)
    final userDoc = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .get();
    if (!userDoc.exists) return [];
    final nurseId = userDoc.id; // ✅ Firestore doc ID is nurse_id

    // 🔹 Step 2: Determine today's day string
    final days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final today = days[DateTime.now().weekday - 1];

    // 🔹 Step 3: Get current shift assignment
    final shiftSnap = await _firestore
        .collection('house_shift_assignments')
        .where('user_id', isEqualTo: nurseId)
        .where('user_type', isEqualTo: 'nurse')
        .where('is_current', isEqualTo: true)
        .where('days_assigned', arrayContains: today)
        .get();

    if (shiftSnap.docs.isEmpty) return []; // No shift assigned today

    final currentShift = shiftSnap.docs.first.data()['shift'] as String?;
    if (currentShift == null) return [];

    // 🔹 Step 4: Get elderly assignments for this nurse + today + shift
    final assignSnap = await _firestore
        .collection('elderly_assignments')
        .where('user_id', isEqualTo: nurseId)
        .where('user_type', isEqualTo: 'nurse')
        .where('is_current', isEqualTo: true)
        .where('day', isEqualTo: today)
        .where('shift', isEqualTo: currentShift)
        .get();

    if (assignSnap.docs.isEmpty) return [];

    // 🔹 Step 4: Collect elderly IDs assigned to this nurse
    final Set<String> assignedIds = {};
    for (var doc in assignSnap.docs) {
      final data = doc.data();
      final ids = (data['elderly_ids'] as List?) ?? [];
      for (var e in ids) {
        assignedIds.add(e.toString());
      }
    }

    if (assignedIds.isEmpty) return [];

    // 🔹 Step 5: Query all elderly first to debug
    List<Map<String, dynamic>> results = [];
    final allIds = assignedIds.toList();
    print('🔍 DEBUG: Total assigned elderly IDs: ${allIds.length}');
    print('🔍 DEBUG: House ID being filtered: $houseId');

    for (var i = 0; i < allIds.length; i += 10) {
      final batchIds = allIds.skip(i).take(10).toList();
      print(
        '🔍 DEBUG: Processing batch ${i ~/ 10 + 1} with ${batchIds.length} IDs',
      );

      // First get all elderly without house filter
      final snap = await _firestore
          .collection('elderly')
          .where(FieldPath.documentId, whereIn: batchIds)
          .get();

      print('🔍 DEBUG: Found ${snap.docs.length} elderly in this batch');

      // Process and filter by house
      for (var doc in snap.docs) {
        final data = doc.data();
        final elderlyHouseId = data['house_id'];
        print('🔍 DEBUG: Elderly ${doc.id} is in house $elderlyHouseId');

        if (elderlyHouseId == houseId) {
          results.add({
            'elderly_id': doc.id,
            'elderly_name':
                "${data['elderly_fname'] ?? ''} ${data['elderly_lname'] ?? ''}"
                    .trim(),
            'elderly_age': data['elderly_age'] ?? '',
            'house_id': elderlyHouseId,
          });
        }
      }
    }

    // 🔹 Step 6: Apply search filter
    if (_search.isNotEmpty) {
      results = results
          .where(
            (e) => (e['elderly_name'] ?? '').toString().toLowerCase().contains(
              _search.toLowerCase(),
            ),
          )
          .toList();
    }

    return results;
  }

  @override
  Widget build(BuildContext context) {
    return MedicationManagementLayout(
      search: _search,
      onSearchChanged: (v) => setState(() => _search = v),
      toggleSidebar: toggleSidebar,
      isSidebarOpen: isSidebarOpen,
      nurseName: nurseName,
      houseDescriptions: houseDescriptions,
      fetchHouses: fetchHouses,
      fetchElderlies: fetchElderlies, // 👈 fixed with day + house filter
      selectedHouseId: selectedHouseId,
      onHouseSelected: (houseId) {
        setState(() => selectedHouseId = houseId);
      },
      onBellPressed: _onBellPressed,
      tabScrollController: _tabScrollController,
      scrollToCenter: _scrollToCenter,
    );
  }
}
