// lib/nurse/vitals_monitoring_layout.dart
import 'package:flutter/material.dart';
import 'vital_monitoring_details.dart';
import 'activity_logs.dart';
import 'nurse_sidebar.dart';

class VitalMonitoringLayout extends StatefulWidget {
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

  const VitalMonitoringLayout({
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
  State<VitalMonitoringLayout> createState() => _VitalMonitoringLayoutState();
}

class _VitalMonitoringLayoutState extends State<VitalMonitoringLayout> {
  String _sortOrder = "A-Z";

  void _sortElderlies(List<Map<String, dynamic>> elderlies) {
    elderlies.sort((a, b) {
      final nameA = (a['elderly_name'] ?? '').toString().toLowerCase();
      final nameB = (b['elderly_name'] ?? '').toString().toLowerCase();
      return _sortOrder == "A-Z"
          ? nameA.compareTo(nameB)
          : nameB.compareTo(nameA);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/background1.png',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(
                left: 0,
                right: 8,
                top: 16,
                bottom: 16,
              ),
              child: Column(
                children: [
                  // Header Row
                  Row(
                    children: [
                      GestureDetector(
                        onTap: widget.toggleSidebar,
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
                        tooltip: "Activity Logs",
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ActivityLogsScreen(
                                houseId:
                                    widget.selectedHouseId ??
                                    'H001', // Default to first house if none selected
                                nurseName: widget.nurseName,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  // Search bar
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      hintText: widget.selectedHouseId == null
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
                    onChanged: (value) => widget.onSearchChanged(value),
                  ),
                  const SizedBox(height: 16),
                  // Houses / Elderly
                  Expanded(
                    child: widget.selectedHouseId == null
                        ? _buildHouseList(context)
                        : Column(
                            children: [
                              // Back + Sort row
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () =>
                                          widget.onHouseSelected(null),
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
                                        setState(() {
                                          _sortOrder = value;
                                        });
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: "A-Z",
                                          child: Text(
                                            "A-Z",
                                            style: TextStyle(
                                              color: Color(0xFF00588E),
                                            ),
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: "Z-A",
                                          child: Text(
                                            "Z-A",
                                            style: TextStyle(
                                              color: Color(0xFF00588E),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: _buildElderlyList(
                                  widget.selectedHouseId!,
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
          // Sidebar overlay - positioned to cover entire screen
          if (widget.isSidebarOpen)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              child: NurseSidebar(
                isSidebarOpen: widget.isSidebarOpen,
                toggleSidebar: widget.toggleSidebar,
                parentContext: context,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHouseList(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: widget.fetchHouses(),
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
                widget.search.toLowerCase(),
              ),
            )
            .toList();

        return ListView(
          padding: EdgeInsets.zero,
          children: houses.map((house) {
            final houseName = house['house_name'] ?? 'Unknown House';
            final desc = widget.houseDescriptions[houseName] ?? '';
            final imageName = houseName
                .replaceAll('St. ', '')
                .replaceAll(' ', '');
            final imagePath = 'assets/images/${imageName}_Logo.png';

            return GestureDetector(
              onTap: () => widget.onHouseSelected(house['house_id'].toString()),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12, left: 0),
                padding: const EdgeInsets.only(
                  left: 0,
                  right: 16,
                  top: 16,
                  bottom: 16,
                ),
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

  Widget _buildElderlyList(String houseId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: widget.fetchElderlies(houseId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("No elderlies found"));
        }

        var elderlies = snapshot.data!;
        // Apply search filter
        elderlies = elderlies
            .where(
              (e) => (e['elderly_name'] ?? '')
                  .toString()
                  .toLowerCase()
                  .contains(widget.search.toLowerCase()),
            )
            .toList();

        // Apply sort
        _sortElderlies(elderlies);

        return ListView.builder(
          itemCount: elderlies.length,
          itemBuilder: (context, index) {
            final elderly = elderlies[index];
            final name = elderly['elderly_name'] ?? 'Unnamed Elderly';
            final profilePic = elderly['elderly_profilePic'] ?? '';
            final elderlyId = elderly['elderly_id'].toString();

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFFE7EFFF),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF00588E),
                  child: ClipOval(
                    child: profilePic.isNotEmpty
                        ? Image.network(profilePic, fit: BoxFit.cover)
                        : Image.asset(
                            'assets/images/people_icon.png',
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                title: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00588E),
                  ),
                ),
                trailing: const Icon(
                  Icons.monitor_heart,
                  color: Color(0xFF00588E),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VitalDetailScreen(
                        elderlyId: elderlyId,
                        elderlyName: name,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
