// lib/nurse/medication_management_layout.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'medication_detail_screen.dart';
import 'medication_activity_logs.dart';
import 'edit_profile.dart';
import 'leave_form.dart';

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
              child: Column(
                children: [
                  // Header Row
                  Row(
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
                          "Medication Management",
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
                        tooltip: "Activity Logs",
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const MedicationActivityLogsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),

                  // Search bar
                  // Search bar
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      hintText: selectedHouseId == null
                          ? "Search house..."
                          : "Search elderly...",
                      hintStyle: const TextStyle(
                        color: Colors.grey,
                        fontSize: 15,
                      ),
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
                        borderSide: const BorderSide(
                          color: Color(0xFF00588E),
                          width: 2,
                        ),
                      ),
                    ),
                    style: const TextStyle(fontSize: 18, color: Colors.black),
                    onChanged: (value) {
                      if (selectedHouseId == null) {
                        onSearchChanged(value); // Filter houses
                      } else {
                        // Filter elderlies
                        // We just call setState from parent if needed to update search for elderlies
                        onSearchChanged(value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Houses / Elderly
                  Expanded(
                    child: selectedHouseId == null
                        ? _buildHouseList(context)
                        : _buildElderlyListScreen(selectedHouseId!),
                  ),
                ],
              ),
            ),
          ),

          // Sidebar overlay
          if (isSidebarOpen) _buildSidebarOverlay(context),
        ],
      ),
    );
  }

  /// -------------------------------
  /// House List with styled cards + images
  /// -------------------------------
  Widget _buildHouseList(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fetchHouses(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("No houses found"));
        }

        final houses = snapshot.data!
            .where(
              (h) => (h['house_name'] ?? '').toString().toLowerCase().contains(
                search.toLowerCase(),
              ),
            )
            .toList();

        return ListView(
          children: houses.map((house) {
            final houseName = house['house_name'] ?? 'Unknown House';
            final desc = houseDescriptions[houseName] ?? '';
            final imageName = houseName
                .replaceAll('St. ', '')
                .replaceAll(' ', '');
            final imagePath = 'assets/images/${imageName}_Logo.png';

            return GestureDetector(
              onTap: () => onHouseSelected(house['house_id'].toString()),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFFE7EFFF),
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
                              fontFamily: 'Poppins',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            desc,
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
            );
          }).toList(),
        );
      },
    );
  }

  /// -------------------------------
  /// Separate "screen" for Elderly List
  /// -------------------------------
  Widget _buildElderlyListScreen(String houseId) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _buildElderlyList(houseId), // <-- keeps the same function exactly
    );
  }

  /// -------------------------------
  /// Build Elderly List filtered by nurse shift
  /// -------------------------------
 Widget _buildElderlyList(String houseId) {
  // Stream to refresh the list every 30 seconds for real-time highlight
  Stream<DateTime> timeStream() async* {
    while (true) {
      await Future.delayed(const Duration(seconds: 30));
      yield DateTime.now();
    }
  }

  return StreamBuilder<DateTime>(
    stream: timeStream(),
    builder: (context, timeSnapshot) {
      final now = timeSnapshot.data ?? DateTime.now();

      return FutureBuilder<List<Map<String, dynamic>>>(
        future: () async {
          final allElderlies = await fetchElderlies(houseId);
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser == null) return <Map<String, dynamic>>[];

          final dayOfWeek = [
            "Monday",
            "Tuesday",
            "Wednesday",
            "Thursday",
            "Friday",
            "Saturday",
            "Sunday",
          ][now.weekday - 1];

          final assignSnap = await FirebaseFirestore.instance
              .collection("nurse_elderly_assign")
              .where("nurse_id", isEqualTo: currentUser.uid)
              .where("day", isEqualTo: dayOfWeek)
              .get();

          if (assignSnap.docs.isEmpty) return <Map<String, dynamic>>[];

          final assignedIds =
              assignSnap.docs.first.data()["elderly_ids"] as List<dynamic>? ?? [];

          if (assignedIds.isEmpty) return <Map<String, dynamic>>[];

          final filteredElderlies = allElderlies
              .where((e) => assignedIds.contains(e["elderly_id"]))
              .toList();

          filteredElderlies.sort((a, b) {
            final nameA = (a['elderly_name'] ?? '').toString().toLowerCase();
            final nameB = (b['elderly_name'] ?? '').toString().toLowerCase();
            return nameA.compareTo(nameB);
          });

          return filteredElderlies;
        }(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text("It is not your shift today or no assigned set of elderly."),
            );
          }

          final elderlies = snapshot.data!;
          return Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () => onHouseSelected(null),
                      icon: const Icon(
                        Icons.arrow_back,
                        size: 30,
                        color: Color(0xFF00588E),
                      ),
                      label: const Text("Back to Houses"),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.sort,
                        color: Color(0xFF00588E),
                        size: 30,
                      ),
                      tooltip: "Sort Elderly",
                      onSelected: (value) {
                        if (value == "A-Z") {
                          elderlies.sort((a, b) {
                            final nameA = (a['elderly_name'] ?? '').toString().toLowerCase();
                            final nameB = (b['elderly_name'] ?? '').toString().toLowerCase();
                            return nameA.compareTo(nameB);
                          });
                        } else if (value == "Z-A") {
                          elderlies.sort((a, b) {
                            final nameA = (a['elderly_name'] ?? '').toString().toLowerCase();
                            final nameB = (b['elderly_name'] ?? '').toString().toLowerCase();
                            return nameB.compareTo(nameA);
                          });
                        }
                        (context as Element).markNeedsBuild();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                            value: "A-Z",
                            child: Text("A-Z", style: TextStyle(color: Color(0xFF00588E)))),
                        PopupMenuItem(
                            value: "Z-A",
                            child: Text("Z-A", style: TextStyle(color: Color(0xFF00588E)))),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: elderlies.length,
                  itemBuilder: (context, index) {
                    final elderly = elderlies[index];
                    final name = elderly['elderly_name'] ?? 'Unnamed Elderly';
                    final profilePic = elderly['elderly_profilePic'] ?? '';
                    final elderlyId = elderly['elderly_id'].toString();

                    // StreamBuilder for medications to update highlight in real-time
                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection("medications")
                          .where("elderly_id", isEqualTo: elderlyId)
                          .snapshots(),
                      builder: (context, medsSnapshot) {
                        bool isTimeToTakeMedicine = false;
                        List<String> medTimes = [];

                        if (medsSnapshot.hasData) {
                          for (var doc in medsSnapshot.data!.docs) {
                            final timeStr = doc['time'] as String? ?? '';
                            if (timeStr.isEmpty) continue;

                            final parts = timeStr.split(":");
                            if (parts.length != 2) continue;

                            final medTime = DateTime(
                              now.year,
                              now.month,
                              now.day,
                              int.parse(parts[0]),
                              int.parse(parts[1]),
                            );

                            medTimes.add(timeStr);

                            if (now.isAfter(medTime.subtract(const Duration(minutes: 2))) &&
                                now.isBefore(medTime.add(const Duration(minutes: 2)))) {
                              isTimeToTakeMedicine = true;
                            }
                          }
                        }

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isTimeToTakeMedicine ? Colors.red[400] : const Color(0xFFE7EFFF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => MedicationDetailScreen(
                                    elderlyId: elderlyId,
                                    elderlyName: name,
                                  ),
                                ),
                              );
                            },
                            leading: Container(
                              width: 50,
                              height: 50,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF00588E),
                              ),
                              child: ClipOval(
                                child: profilePic.isNotEmpty
                                    ? Image.network(profilePic, fit: BoxFit.cover)
                                    : Image.asset(
                                        'assets/images/people_icon.png',
                                        fit: BoxFit.cover,
                                      ),
                              ),
                            ),
                            title: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF00588E),
                                  ),
                                ),
                                if (isTimeToTakeMedicine)
                                  Text(
                                    "Time to take medicine: ${medTimes.join(', ')}",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: const Icon(
                              Icons.medical_services,
                              color: Color(0xFF00588E),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    },
  );
}



  /// -------------------------------
  /// Sidebar overlay
  /// -------------------------------
  Widget _buildSidebarOverlay(BuildContext context) {
    void handleLogout() async {
      await FirebaseAuth.instance.signOut();
      Navigator.pushReplacementNamed(context, '/login');
    }

    Widget sidebarItem(IconData icon, String title) {
      return ListTile(
        leading: Icon(icon, color: const Color(0xFF00588E)),
        title: Text(title),
        onTap: () {
          // Handle item tap here
          print('$title tapped');
        },
      );
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
                  const SizedBox(height: 50),
                  Text(
                    nurseName != null && nurseName!.isNotEmpty
                        ? 'Nurse ${nurseName!.split(' ').first}' // take only the first name
                        : 'No name found',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.edit, color: Color(0xFF00588E)),
                    title: const Text("Edit Profile"),
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
                  ListTile(
                    leading: const Icon(
                      Icons.settings,
                      color: Color(0xFF00588E),
                    ),
                    title: const Text("Request Leave"),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LeaveForm(),
                        ),
                      );
                    },
                  ),
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
                      onPressed: handleLogout,
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
}
