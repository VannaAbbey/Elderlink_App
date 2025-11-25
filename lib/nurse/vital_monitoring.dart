// lib/nurse/vital_monitoring.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'vital_upcoming.dart';
import 'vital_completed.dart';
import 'vital_missed.dart';
import 'nurse_sidebar.dart';
import '../services/daily_reset_service.dart';
import '../widgets/nurse_widgets/nurse_notification_icon_button.dart';

/// =============================
/// Vital Monitoring Screen
/// =============================
class VitalMonitoringScreen extends StatefulWidget {
  const VitalMonitoringScreen({super.key});

  @override
  State<VitalMonitoringScreen> createState() => _VitalMonitoringScreenState();
}

class _VitalMonitoringScreenState extends State<VitalMonitoringScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final String _search = '';
  String? nurseName;
  bool isSidebarOpen = false;
  String? selectedHouseId; // track selected house

  // 🔹 Improved: Scroll controller for horizontal tab scroll
  final ScrollController _tabScrollController = ScrollController();

  // 🔹 Vital tabs state management
  late TabController _vitalTabController;
  int _selectedVitalTabIndex = 0;

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
    _vitalTabController = TabController(length: 3, vsync: this);
    _vitalTabController.addListener(() {
      if (!_vitalTabController.indexIsChanging) {
        setState(() {
          _selectedVitalTabIndex = _vitalTabController.index;
        });
      }
    });
    _loadNurseData();

    // 🆕 FEATURE 4: Initialize comprehensive vital monitoring system
    _initializeVitalSystem();
  }

  // 🆕 FEATURE 4: Initialize comprehensive vital monitoring system with real-time sync
  Future<void> _initializeVitalSystem() async {
    try {
      await DailyResetService.startComprehensiveMonitoring();
      print(
        '✅ Comprehensive vital monitoring with real-time schedule sync initialized',
      );
    } catch (e) {
      print('❌ Error initializing vital monitoring system: $e');
    }
  }

  @override
  void dispose() {
    _vitalTabController.dispose();
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
        .where('elderly_status', isEqualTo: 'Alive')
        .get();

    final list = snap.docs.map((d) {
      final data = d.data();
      return {
        'elderly_id': d.id,
        'elderly_name':
            data['elderly_name'] ??
            "${data['elderly_fname'] ?? ''} ${data['elderly_lname'] ?? ''}"
                .trim(),
        'elderly_age': data['elderly_age'] ?? '',
      };
    }).toList();

    if (_search.isNotEmpty) {
      return list
          .where(
            (e) => (e['elderly_name'] ?? '').toString().toLowerCase().contains(
              _search.toLowerCase(),
            ),
          )
          .toList();
    }
    return list;
  }

  // Build the Upcoming tab with red circle count
  Widget _buildUpcomingTabWithCount(Map<String, dynamic> house, bool selected) {
    // 🔴 FIXED: Use cached count as initial data to prevent badge disappearing
    final cachedCount = _getCachedBadgeCount(house['house_id']);

    return StreamBuilder<int>(
      stream: _getUpcomingVitalsCountStream(house['house_id']),
      initialData: cachedCount, // Use cached count so badge appears immediately
      builder: (context, snapshot) {
        int count = snapshot.data ?? 0;

        // Debug output
        if (snapshot.hasData) {
          print(
            '🔴 Badge displaying count for house ${house['house_id']}: $count',
          );
        } else {
          print(
            '⚪ Badge waiting for data. ConnectionState: ${snapshot.connectionState}',
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Upcoming',
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF00588e),
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 11.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (count > 0) ...[
              const SizedBox(width: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(9),
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Center(
                  child: Text(
                    count.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  // 🔴 CACHED: Store badge counts to survive tab switches
  static final Map<String, int> _badgeCache = {};
  static final Map<String, DateTime> _badgeCacheTime = {};

  // Get cached badge count (instant, survives tab switches)
  int _getCachedBadgeCount(String houseId) {
    final currentShift = _getCurrentShift();
    final today = _getTodayDateString();
    final cacheKey = '${houseId}_${currentShift}_$today';

    final cachedCount = _badgeCache[cacheKey];
    final cacheTime = _badgeCacheTime[cacheKey];

    // Return cached count if it's less than 10 seconds old
    if (cachedCount != null && cacheTime != null) {
      final age = DateTime.now().difference(cacheTime).inSeconds;
      if (age < 10) {
        print(
          '🔴 Badge CACHE HIT: Returning cached count $cachedCount for $cacheKey',
        );
        return cachedCount;
      }
    }

    return 0; // Default if no valid cache
  }

  // Get stream for upcoming vitals count (reactive to schedule changes)
  Stream<int> _getUpcomingVitalsCountStream(String houseId) {
    // Get current shift and day
    final currentShift = _getCurrentShift();
    final currentDay = _getCurrentDay();
    final today = _getTodayDateString();

    // Get nurse ID directly from Firebase Auth
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Stream.value(0);
    }

    print(
      '🔴 Badge Stream: Setting up for house $houseId, shift $currentShift, day $currentDay, date $today',
    );

    // Create stream that emits cached value first, then real-time updates
    return Stream.periodic(
      const Duration(seconds: 3), // Slightly faster for responsiveness
      (_) => DateTime.now(),
    ).asyncMap((_) async {
      print(
        '🔄 Badge: Checking for updates (schedule changes, vital completions)',
      );

      // Fetch current vitals
      final vitalsSnapshot = await _firestore
          .collection('vitals')
          .where('house_id', isEqualTo: houseId)
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .get();
      print(
        '🔄 Badge: Processing ${vitalsSnapshot.docs.length} vitals, checking assignments',
      );

      // 🆕 UPDATED: Get current nurse assignments (supports both old and new collection structure)
      var assignmentQuery = await _firestore
          .collection('assignments')
          .where('nurse_id', isEqualTo: user.uid)
          .where('house_id', isEqualTo: houseId)
          .where('shift', isEqualTo: currentShift)
          .get();

      // Fallback to old structure if new one is empty
      if (assignmentQuery.docs.isEmpty) {
        assignmentQuery = await _firestore
            .collection('elderly_assignments')
            .where('user_type', isEqualTo: 'nurse')
            .where('user_id', isEqualTo: user.uid)
            .where('is_current', isEqualTo: true)
            .where('house_id', arrayContains: houseId)
            .where('shift', isEqualTo: currentShift)
            .where('day', isEqualTo: currentDay)
            .get();
      }

      if (assignmentQuery.docs.isEmpty) {
        print('🔴 Badge Stream: No assignments found for nurse');
        return 0;
      }

      // Collect all elderly IDs assigned to this nurse in this house
      final assignedElderlyIds = <String>[];
      for (final doc in assignmentQuery.docs) {
        final elderlyIds = List<String>.from(doc.data()['elderly_ids'] ?? []);
        assignedElderlyIds.addAll(elderlyIds);
      }

      if (assignedElderlyIds.isEmpty) {
        print('🔴 Badge Stream: No elderly assigned to nurse');
        return 0;
      }

      print(
        '🔴 Badge Stream: Nurse assigned to ${assignedElderlyIds.length} elderly: $assignedElderlyIds',
      );

      // 🔴 EXACT UPCOMING TAB LOGIC: Filter elderly by actual house location first
      // Get elderly documents to check which ones are actually in current house
      final elderlyDocs = await Future.wait(
        assignedElderlyIds.map(
          (id) => _firestore.collection('elderly').doc(id).get(),
        ),
      );

      // Filter elderly that belong to the specific house (same as upcoming tab)
      final elderlyInCurrentHouse = <String>[];
      for (final elderlyDoc in elderlyDocs) {
        if (elderlyDoc.exists) {
          final elderlyHouseId = elderlyDoc.data()?['house_id'];
          if (elderlyHouseId == houseId) {
            elderlyInCurrentHouse.add(elderlyDoc.id);
          }
        }
      }

      print(
        '🔴 Badge: ${elderlyInCurrentHouse.length} elderly in current house out of ${assignedElderlyIds.length} assigned',
      );

      // Check completed vitals for elderly in current house (same as upcoming tab)
      final completedTodayElderlyIds = <String>{};
      final completedTodayQuery = await _firestore
          .collection('vitals')
          .where('house_id', isEqualTo: houseId)
          .where('assigned_date', isEqualTo: today)
          .where('status', isEqualTo: 'completed')
          .where('elderly_id', whereIn: elderlyInCurrentHouse.take(30).toList())
          .get();

      for (final doc in completedTodayQuery.docs) {
        final data = doc.data();
        final elderlyId = data['elderly_id'] as String?;
        if (elderlyId != null) {
          completedTodayElderlyIds.add(elderlyId);
        }
      }

      // Badge Count = Elderly in house - Already completed (exact upcoming tab logic)
      final elderlyNeedingVitals = elderlyInCurrentHouse
          .where((elderlyId) => !completedTodayElderlyIds.contains(elderlyId))
          .toList();

      final badgeCount = elderlyNeedingVitals.length;

      // 🔴 CACHE: Store badge count to survive tab switches
      final cacheKey = '${houseId}_${currentShift}_$today';
      _badgeCache[cacheKey] = badgeCount;
      _badgeCacheTime[cacheKey] = DateTime.now();

      print(
        '🔴 Badge EXACT MATCH: ${elderlyInCurrentHouse.length} in house - ${completedTodayElderlyIds.length} completed = $badgeCount badge count',
      );
      print('🔴 Badge completed today: $completedTodayElderlyIds');
      print('🔴 Badge needing vitals: $elderlyNeedingVitals');
      print('🔴 Badge CACHED: Stored count $badgeCount for key $cacheKey');
      return badgeCount;
    });
  }

  // Get current shift

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

  // Get current day
  String _getCurrentDay() {
    final now = DateTime.now();
    final currentHour = now.hour;
    if (currentHour >= 0 && currentHour < 6) {
      final previousDay = now.subtract(Duration(days: 1));
      return DateFormat('EEEE').format(previousDay);
    }
    return DateFormat('EEEE').format(now);
  }

  // Get today date string
  String _getTodayDateString() {
    final now = DateTime.now();
    final currentHour = now.hour;
    if (currentHour >= 0 && currentHour < 6) {
      final previousDay = now.subtract(Duration(days: 1));
      return DateFormat('yyyy-MM-dd').format(previousDay);
    }
    return DateFormat('yyyy-MM-dd').format(now);
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
                          "Vital Monitoring",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF00588E),
                          ),
                        ),
                      ),
                      // 🔧 DEBUG: Manual trigger button for missed vitals check
                      IconButton(
                        icon: const Icon(
                          Icons.refresh,
                          color: Colors.orange,
                          size: 24,
                        ),
                        onPressed: () async {
                          print(
                            '🔄 Manual trigger: Checking for missed vitals...',
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Checking for missed vitals...'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                          await DailyResetService.forceCheckMissedVitals();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Check completed! Pull down to refresh.',
                              ),
                              duration: Duration(seconds: 2),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                        tooltip: 'Check for missed vitals',
                      ),
                      // Nurse Notification Bell Icon for Leave Requests
                      const NurseNotificationIconButton(),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
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
                                  controller: _tabScrollController,
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
                                                  _scrollToCenter(
                                                    index,
                                                    houses,
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
                                                      'assets/houses_img/${house['house_name']}.png',
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
                                                      fontSize: 15,
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
                                  return Column(
                                    children: [
                                      // Vitals Status Tabs - Match medication management layout
                                      Container(
                                        width: double.infinity,
                                        color: const Color(0xFFE6F3FA),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: 16,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceEvenly,
                                          children: List.generate(3, (index) {
                                            final bool selected =
                                                _selectedVitalTabIndex == index;
                                            final List<String> tabLabels = [
                                              'Upcoming',
                                              'Completed',
                                              'Missed',
                                            ];
                                            return Expanded(
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 2.0,
                                                    ),
                                                child: GestureDetector(
                                                  onTap: () {
                                                    setState(() {
                                                      _selectedVitalTabIndex =
                                                          index;
                                                    });
                                                    _vitalTabController
                                                        .animateTo(
                                                          index,
                                                          duration:
                                                              Duration.zero,
                                                        );
                                                  },
                                                  child: Container(
                                                    clipBehavior: Clip
                                                        .none, // CRITICAL: Don't clip the badge!
                                                    // Remove fixed width constraint to let content expand
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 8,
                                                        ),
                                                    decoration: selected
                                                        ? BoxDecoration(
                                                            color: const Color(
                                                              0xFF00588e,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  20,
                                                                ),
                                                          )
                                                        : null,
                                                    child: index == 0
                                                        ? _buildUpcomingTabWithCount(
                                                            house,
                                                            selected,
                                                          )
                                                        : Text(
                                                            tabLabels[index],
                                                            textAlign: TextAlign
                                                                .center,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              color: selected
                                                                  ? Colors.white
                                                                  : const Color(
                                                                      0xFF00588e,
                                                                    ),
                                                              fontWeight:
                                                                  selected
                                                                  ? FontWeight
                                                                        .bold
                                                                  : FontWeight
                                                                        .normal,
                                                              fontSize: 14,
                                                            ),
                                                          ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
                                        ),
                                      ),
                                      // Vitals Content
                                      Expanded(
                                        child: TabBarView(
                                          controller: _vitalTabController,
                                          physics: const PageScrollPhysics(),
                                          children: [
                                            Builder(
                                              builder: (context) {
                                                return UpcomingVitalsTab(
                                                  houseId: house['house_id'],
                                                  nurseName: nurseName,
                                                );
                                              },
                                            ),
                                            CompletedVitalsTab(
                                              houseId: house['house_id'],
                                              nurseName: nurseName,
                                            ),
                                            MissedVitalsTab(
                                              houseId: house['house_id'],
                                              nurseName: nurseName,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
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
          if (isSidebarOpen)
            NurseSidebar(
              isSidebarOpen: isSidebarOpen,
              toggleSidebar: toggleSidebar,
              parentContext: context,
            ),
        ],
      ),
    );
  }
}
