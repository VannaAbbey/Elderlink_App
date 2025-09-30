// lib/nurse/medication_management_layout.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'medication_detail_screen.dart';
import 'medication_activity_logs.dart';

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
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Medication Management"),
        actions: [
          // Activity Log button instead of Logout
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: "Activity Logs",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MedicationActivityLogsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Nurse greeting
          if (nurseName != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                "Welcome, $nurseName",
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search...',
              ),
              onChanged: onSearchChanged,
            ),
          ),

          const SizedBox(height: 10),

          // Show houses OR elderlies depending on selection
          Expanded(
            child: selectedHouseId == null
                ? _buildHouseList()
                : _buildElderlyList(selectedHouseId!),
          ),
        ],
      ),
    );
  }

  /// -------------------------------
  /// Build House List
  /// -------------------------------
  Widget _buildHouseList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fetchHouses(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("No houses found"));
        }

        final houses = snapshot.data!;
        return ListView.builder(
          itemCount: houses.length,
          itemBuilder: (context, index) {
            final house = houses[index];
            final houseName = house['house_name'] ?? 'Unknown House';
            final desc = houseDescriptions[houseName] ?? '';

            return Card(
              child: ListTile(
                title: Text(
                  houseName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(desc),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => onHouseSelected(house['house_id'].toString()),
              ),
            );
          },
        );
      },
    );
  }

  /// -------------------------------
/// Build Elderly List filtered by nurse shift
/// -------------------------------
Widget _buildElderlyList(String houseId) {
  return FutureBuilder<List<Map<String, dynamic>>>(
    future: () async {
      // 1. Fetch all elderlies for the house
      final allElderlies = await fetchElderlies(houseId);

      // 2. Get current user (nurse) and today's day
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return <Map<String, dynamic>>[];

      final now = DateTime.now();
      final dayOfWeek = [
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
        "Sunday"
      ][now.weekday - 1];

      // 3. Fetch nurse_elderly_assign for today
      final assignSnap = await FirebaseFirestore.instance
          .collection("nurse_elderly_assign")
          .where("nurse_id", isEqualTo: currentUser.uid)
          .where("day", isEqualTo: dayOfWeek)
          .get();

      if (assignSnap.docs.isEmpty) return <Map<String, dynamic>>[];

      final assignedIds =
          assignSnap.docs.first.data()["elderly_ids"] as List<dynamic>? ?? [];

      if (assignedIds.isEmpty) return <Map<String, dynamic>>[];

      // 4. Filter elderlies to only include assigned ones
      final filteredElderlies = allElderlies
          .where((e) => assignedIds.contains(e["elderly_id"]))
          .toList();

      return filteredElderlies;
    }(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (!snapshot.hasData || snapshot.data!.isEmpty) {
        return const Center(
          child: Text("It is not your shift today or no assigned elderlies."),
        );
      }

      final elderlies = snapshot.data!;
      return Column(
        children: [
          // Back button to house list
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => onHouseSelected(null),
              icon: const Icon(Icons.arrow_back),
              label: const Text("Back to Houses"),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: elderlies.length,
              itemBuilder: (context, index) {
                final elderly = elderlies[index];
                final name = elderly['elderly_name'] ?? 'Unnamed Elderly';
                final age = elderly['elderly_age']?.toString() ?? 'N/A';
                final gender = elderly['elderly_gender'] ?? '';

                return Card(
                  child: ListTile(
                    title: Text(name),
                    subtitle: Text("Age: $age  Gender: $gender"),
                    trailing: const Icon(Icons.medical_services),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MedicationDetailScreen(
                            elderlyId: elderly['elderly_id'].toString(),
                            elderlyName: name,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      );
    },
  );
}
}
