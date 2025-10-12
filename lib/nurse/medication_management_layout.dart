// lib/nurse/medication_management_layout.dart
import 'package:flutter/material.dart';
import 'medication_upcoming.dart';
import 'medication_completed.dart';
import 'medication_missed.dart';
import 'nurse_sidebar.dart';

class MedicationManagementLayout extends StatefulWidget {
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
  final ScrollController tabScrollController;
  final void Function(int index, List<Map<String, dynamic>> houses)
  scrollToCenter;

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
    required this.tabScrollController,
    required this.scrollToCenter,
  });

  @override
  State<MedicationManagementLayout> createState() =>
      _MedicationManagementLayoutState();
}

class _MedicationManagementLayoutState
    extends State<MedicationManagementLayout> {
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
                        onPressed: widget.onBellPressed,
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: widget.fetchHouses(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final houses = snapshot.data!;
                      return DefaultTabController(
                        length: houses.length,
                        child: Column(
                          children: [
                            // 🩶 House Tabs — fixed divider + auto-scroll center
                            Stack(
                              children: [
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 1,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                                SingleChildScrollView(
                                  controller: widget.tabScrollController,
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  child: Transform.translate(
                                    offset: const Offset(-32, 0),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minWidth:
                                            MediaQuery.of(context).size.width +
                                            64, // extended right side
                                      ),
                                      child: Material(
                                        color: Colors.white,
                                        child: TabBar(
                                          isScrollable: true,
                                          labelColor: const Color(0xFF00588E),
                                          unselectedLabelColor: Colors.grey,
                                          indicator:
                                              const UnderlineTabIndicator(
                                                borderSide: BorderSide(
                                                  color: Color(0xFF00588E),
                                                  width: 3,
                                                ),
                                                insets: EdgeInsets.symmetric(
                                                  horizontal: -20,
                                                ),
                                              ),
                                          labelPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 20,
                                              ),
                                          physics:
                                              const BouncingScrollPhysics(),
                                          onTap: (index) {
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                                  widget.scrollToCenter(
                                                    index,
                                                    snapshot.data!,
                                                  );
                                                });
                                          },
                                          tabs: houses.map((house) {
                                            return Tab(
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    child: Image.asset(
                                                      'assets/images/${house['house_name']?.toString().replaceAll('St. ', '').replaceAll(' ', '')}_Logo.png',
                                                      width: 24,
                                                      height: 24,
                                                      errorBuilder:
                                                          (
                                                            context,
                                                            error,
                                                            stackTrace,
                                                          ) {
                                                            return const Icon(
                                                              Icons.home,
                                                            );
                                                          },
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    house['house_name'] ?? '',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
                                          indicatorColor: const Color(
                                            0xFF00588E,
                                          ),
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
                                                nurseName: widget.nurseName,
                                              ),
                                              CompletedMedicationsTab(
                                                houseId: house['house_id'],
                                                nurseName: widget.nurseName,
                                              ),
                                              MissedMedicationsTab(
                                                houseId: house['house_id'],
                                                nurseName: widget.nurseName,
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
          if (widget.isSidebarOpen)
            NurseSidebar(
              isSidebarOpen: widget.isSidebarOpen,
              toggleSidebar: widget.toggleSidebar,
              parentContext: context,
            ),
        ],
      ),
    );
  }
}
