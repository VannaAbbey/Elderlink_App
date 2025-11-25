import 'package:flutter/material.dart';
import 'houses_grids.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/cg_providers/absence_provider.dart';
import '../services/cg_services/house_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HousesScreen extends StatefulWidget {
  const HousesScreen({super.key});

  @override
  State<HousesScreen> createState() => _HousesScreenState();
}

class _HousesScreenState extends State<HousesScreen> {
  List<String> caregiverAssignedDays = [];
  String selectedDay = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeDays();
  }

  Future<void> _initializeDays() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final caregiverId = authProvider.currentUser?.uid;
    if (caregiverId == null) return;

    try {
      // Fetch caregiver's assigned days
      final assignSnap = await FirebaseFirestore.instance
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .get();
      
      if (assignSnap.docs.isNotEmpty) {
        final assignData = assignSnap.docs.first.data();
        caregiverAssignedDays = List<String>.from(assignData['days_assigned'] ?? []);
      }

      // Set selectedDay - prefer current day if assigned, otherwise first assigned day
      final now = DateTime.now();
      final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      final currentDay = weekdays[now.weekday - 1];
      
      selectedDay = caregiverAssignedDays.contains(currentDay)
          ? currentDay
          : (caregiverAssignedDays.isNotEmpty ? caregiverAssignedDays.first : 'Monday');

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      print('Error initializing days: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> getAssignedHouse(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final caregiverId = authProvider.currentUser?.uid;
    if (caregiverId == null) return null;
    final houseService = HouseService();
    return await houseService.getAssignedHouseForCaregiver(caregiverId);
  }

  Future<List<Map<String, dynamic>>> getAssignedElderlyForSelectedDay(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final caregiverId = authProvider.currentUser?.uid;
    if (caregiverId == null) return [];
    
    try {
      final houseService = HouseService();
      print('DEBUG houses.dart: Getting elderly including temporary assignments for $selectedDay');
      
      // Use the new method that includes temporary assignments from absent caregivers
      final assignedElderly = await houseService.getAssignedElderlyIncludingTemporary(
        caregiverId, 
        selectedDay
      );
      
      print('DEBUG houses.dart: House service returned ${assignedElderly.length} total elderly for $selectedDay');
      
      // Count temporary assignments for logging
      final tempCount = assignedElderly.where((e) => e['is_temporary_assignment'] == true).length;
      if (tempCount > 0) {
        print('DEBUG houses.dart: ✨ Including $tempCount temporary elderly from absent caregivers');
      }
      
      return assignedElderly;
    } catch (e) {
      print('DEBUG houses.dart: Error in getAssignedElderlyForSelectedDay: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getDeceasedElderlyInHouse(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final caregiverId = authProvider.currentUser?.uid;
    if (caregiverId == null) return [];
    
    try {
      final houseService = HouseService();
      print('DEBUG houses.dart: Getting all deceased elderly in house');
      final deceasedElderly = await houseService.getDeceasedElderlyInHouse(caregiverId);
      print('DEBUG houses.dart: Found ${deceasedElderly.length} deceased elderly in house');
      
      return deceasedElderly;
    } catch (e) {
      print('DEBUG houses.dart: Error getting deceased elderly: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Check if caregiver is absent today
    return Consumer<AbsenceProvider>(
      builder: (context, absenceProvider, child) {
        if (absenceProvider.isAbsentToday) {
          // Show redistribution message for absent caregivers
          return Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/background1.png',
                  fit: BoxFit.cover,
                ),
              ),
              Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  backgroundColor: Colors.white,
                  elevation: 0,
                  centerTitle: true,
                  surfaceTintColor: Colors.white,
                  scrolledUnderElevation: 0,
                  title: const Text(
                    'Elderly Houses',
                    style: TextStyle(
                      color: Color(0xFF00588e),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF00588e)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                body: SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          margin: const EdgeInsets.all(32),
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 80,
                                color: Colors.orange.withOpacity(0.8),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                absenceProvider.absenceType == 'leave'
                                    ? 'On Leave Today'
                                    : 'Marked Absent Today',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Elderly assigned for you today was redistributed.\nCome back soon!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.black87,
                                  height: 1.4,
                                ),
                              ),
                            ],
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

        // Normal houses display for non-absent caregivers
        return _buildHousesContent(context);
      },
    );
  }

  Widget _buildHousesContent(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/background1.png',
            fit: BoxFit.cover,
          ),
        ),
        FutureBuilder<Map<String, dynamic>?>(
          future: getAssignedHouse(context),
          builder: (context, houseSnapshot) {
            if (houseSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!houseSnapshot.hasData || houseSnapshot.data?['house_name'] == null) {
              return Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  backgroundColor: Colors.white,
                  elevation: 0,
                  centerTitle: true,
                  surfaceTintColor: Colors.white,
                  scrolledUnderElevation: 0,
                  title: const Text(
                    '',
                    style: TextStyle(
                      color: Color(0xFF00588e),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF00588e)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                body: SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.home_outlined,
                                size: 80,
                                color: Color(0xFF00588e).withOpacity(0.6),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No House Assigned',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF00588e),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'You have not been assigned to any house yet.\nPlease contact your administrator.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                  height: 1.4,
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
            }
            final houseName = houseSnapshot.data!['house_name'];
            return FutureBuilder<List<Map<String, dynamic>>>(
              future: getAssignedElderlyForSelectedDay(context),
              builder: (context, aliveElderlySnapshot) {
                if (aliveElderlySnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (aliveElderlySnapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error, size: 64, color: Colors.red),
                        SizedBox(height: 16),
                        Text('Error loading alive elderly data'),
                      ],
                    ),
                  );
                }

                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: getDeceasedElderlyInHouse(context),
                  builder: (context, deceasedElderlySnapshot) {
                    if (deceasedElderlySnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    if (deceasedElderlySnapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error, size: 64, color: Colors.red),
                            SizedBox(height: 16),
                            Text('Error loading deceased elderly data'),
                          ],
                        ),
                      );
                    }

                    final aliveElderlyList = aliveElderlySnapshot.data ?? [];
                    final deceasedElderlyList = deceasedElderlySnapshot.data ?? [];
                    
                    print('DEBUG houses.dart: Processing ${aliveElderlyList.length} alive elderly records');
                    print('DEBUG houses.dart: Processing ${deceasedElderlyList.length} deceased elderly records');
                    
                    // Debug: Check temporary flags before mapping
                    for (var elderly in aliveElderlyList) {
                      if (elderly['is_temporary_assignment'] == true) {
                        print('DEBUG houses.dart: BEFORE mapping - ${elderly['name']} has is_temporary_assignment: ${elderly['is_temporary_assignment']}');
                      }
                    }
                    
                    final aliveProfiles = aliveElderlyList
                        .where((e) {
                          final status = e['elderly_status'];
                          final isAlive = status == 'Alive' || status == 'alive';
                          return isAlive;
                        })
                        .map((e) => {
                              'elderly_id': e['elderly_id'],
                              'name': (e['elderly_sex'] == 'Female' ? 'Lola ' : 'Lolo ') + (e['elderly_fname'] ?? ''),
                              'full_name': '${e['elderly_fname'] ?? ''} ${e['elderly_lname'] ?? ''}',
                              'profile_pic': e['elderly_profilePic'] ?? e['profile_pic'] ?? '',
                              'birthdate': e['elderly_birthdate'],
                              'sex': e['elderly_sex'] ?? '',
                              'days_assigned': e['days_assigned'] ?? [],
                              'status': e['elderly_status'],
                              // Required fields for alive elderly
                              'elderly_fname': e['elderly_fname'],
                              'elderly_lname': e['elderly_lname'],
                              'elderly_bday': e['elderly_bday'],
                              'elderly_age': e['elderly_age'],
                              'elderly_sex': e['elderly_sex'],
                              'house_name': e['house_name'],
                              'elderly_mobilityStatus': e['elderly_mobilityStatus'],
                              'elderly_dietNotes': e['elderly_dietNotes'],
                              'elderly_condition': e['elderly_condition'],
                              // ⭐ IMPORTANT: Include temporary assignment and emergency coverage flags
                              'is_temporary_assignment': e['is_temporary_assignment'] ?? false,
                              'is_emergency_coverage': e['is_emergency_coverage'] ?? false,
                              'temporary_assignment_note': e['temporary_assignment_note'],
                            })
                        .toList();
                    
                    // Debug: Check temporary flags after mapping
                    for (var profile in aliveProfiles) {
                      if (profile['is_temporary_assignment'] == true) {
                        print('DEBUG houses.dart: AFTER mapping - ${profile['name']} has is_temporary_assignment: ${profile['is_temporary_assignment']}');
                      }
                    }
                    
                    print('DEBUG houses.dart: Passing ${aliveProfiles.length} alive profiles to grid');
                        
                    final deceasedProfiles = deceasedElderlyList
                        .map((e) => {
                              'elderly_id': e['elderly_id'],
                              'name': (e['elderly_sex'] == 'Female' ? 'Lola ' : 'Lolo ') + (e['elderly_fname'] ?? ''),
                              'full_name': '${e['elderly_fname'] ?? ''} ${e['elderly_lname'] ?? ''}',
                              'profile_pic': e['elderly_profilePic'] ?? e['profile_pic'] ?? '',
                              'birthdate': e['elderly_birthdate'],
                              'sex': e['elderly_sex'] ?? '',
                              'days_assigned': [], // Not relevant for deceased
                              'status': e['elderly_status'],
                              // Required fields for deceased elderly
                              'elderly_fname': e['elderly_fname'],
                              'elderly_lname': e['elderly_lname'],
                              'elderly_bday': e['elderly_bday'],
                              'elderly_sex': e['elderly_sex'],
                              'house_name': e['house_name'],
                              'elderly_condition': e['elderly_condition'],
                              'elderly_causeDeath': e['elderly_causeDeath'],
                              'elderly_deathDate': e['elderly_deathDate'],
                            })
                        .toList();

                    print('DEBUG houses.dart: Passing ${aliveProfiles.length} alive profiles to grid');
                    print('DEBUG houses.dart: Passing ${deceasedProfiles.length} deceased profiles to grid');
                    
                    return _HousesTabScaffold(
                      aliveProfiles: aliveProfiles,
                      deceasedProfiles: deceasedProfiles,
                      houseName: houseName,
                      selectedDay: selectedDay,
                      caregiverAssignedDays: caregiverAssignedDays,
                      onDayChanged: (newDay) async {
                        setState(() {
                          selectedDay = newDay;
                        });
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }
}


class _HousesTabScaffold extends StatefulWidget {
  final List<Map<String, dynamic>> aliveProfiles;
  final List<Map<String, dynamic>> deceasedProfiles;
  final String houseName;
  final String selectedDay;
  final List<String> caregiverAssignedDays;
  final Function(String) onDayChanged;
  
  const _HousesTabScaffold({
    required this.aliveProfiles,
    required this.deceasedProfiles,
    required this.houseName,
    required this.selectedDay,
    required this.caregiverAssignedDays,
    required this.onDayChanged,
  });

  @override
  State<_HousesTabScaffold> createState() => _HousesTabScaffoldState();
}

class _HousesTabScaffoldState extends State<_HousesTabScaffold> {
  int selectedTab = 0; // 0 = Alive, 1 = Deceased
  bool isSortedAscending = true; // true = A-Z, false = Z-A
  bool isSorted = true; // Track if data is currently sorted - initialize to true for alphabetical order
  
  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSort() {
    setState(() {
      if (isSorted && isSortedAscending) {
        // First click: sort Z-A (currently A-Z)
        isSortedAscending = false;
      } else if (isSorted && !isSortedAscending) {
        // Second click: return to original order (currently Z-A)
        isSorted = false;
        isSortedAscending = true;
      } else {
        // Third click: sort A-Z (currently original order)
        isSorted = true;
        isSortedAscending = true;
      }
    });
  }

  List<Map<String, dynamic>> _getFilteredAndSortedProfiles(List<Map<String, dynamic>> profiles) {
    // First apply search filter
    List<Map<String, dynamic>> filteredProfiles = profiles;
    
    if (_searchQuery.isNotEmpty) {
      filteredProfiles = profiles.where((profile) {
        final fullName = (profile['full_name'] as String? ?? '').toLowerCase();
        final firstName = (profile['elderly_fname'] as String? ?? '').toLowerCase();
        final lastName = (profile['elderly_lname'] as String? ?? '').toLowerCase();
        final displayName = (profile['name'] as String? ?? '').toLowerCase();
        final condition = (profile['elderly_condition'] as String? ?? '').toLowerCase();
        final mobilityStatus = (profile['elderly_mobilityStatus'] as String? ?? '').toLowerCase();
        
        // Search in multiple fields including name, condition, and mobility status
        return fullName.contains(_searchQuery) ||
               firstName.contains(_searchQuery) ||
               lastName.contains(_searchQuery) ||
               displayName.contains(_searchQuery) ||
               condition.contains(_searchQuery) ||
               mobilityStatus.contains(_searchQuery);
      }).toList();
    }
    
    // Then apply sorting if enabled
    if (!isSorted) {
      return filteredProfiles; // Return filtered list in original order
    }
    
    // Create a copy and sort by full_name
    final sortedList = List<Map<String, dynamic>>.from(filteredProfiles);
    sortedList.sort((a, b) {
      final nameA = (a['full_name'] as String? ?? '').toLowerCase();
      final nameB = (b['full_name'] as String? ?? '').toLowerCase();
      
      return isSortedAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
    });
    
    return sortedList;
  }

  Widget _buildProfileGrid() {
    final profiles = selectedTab == 0 
        ? _getFilteredAndSortedProfiles(widget.aliveProfiles)
        : _getFilteredAndSortedProfiles(widget.deceasedProfiles);
    
    // Show "No results found" message when search returns empty results
    if (profiles.isEmpty && _searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: Colors.grey.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No elderly found for "$_searchQuery"',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching with a different name, condition, or mobility status',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    // Show appropriate grid based on selected tab
    return selectedTab == 0
        ? AliveProfilesGrid(profiles: profiles)
        : DeceasedProfilesGrid(profiles: profiles);
  }

  String _buildResultsCountText() {
    final profiles = selectedTab == 0 
        ? _getFilteredAndSortedProfiles(widget.aliveProfiles)
        : _getFilteredAndSortedProfiles(widget.deceasedProfiles);
    
    final count = profiles.length;
    final tabName = selectedTab == 0 ? 'alive' : 'deceased';
    
    if (count == 0) {
      return 'No $tabName elderly found for "$_searchQuery"';
    } else if (count == 1) {
      return 'Found 1 $tabName elderly for "$_searchQuery"';
    } else {
      return 'Found $count $tabName elderly for "$_searchQuery"';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 90,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: Image.asset(
                'assets/houses_img/${widget.houseName}.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.home,
                  size: 40,
                  color: Color(0xFF00588E),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'House of',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00588e),
                  ),
                ),
                Text(
                  widget.houseName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00588e),
                  ),
                ),
              ],
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF00588e)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Color(0xFFD8F4FF), // Light blue background for tab row
                      borderRadius: BorderRadius.circular(32),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedTab = 0;
                                // Clear search when switching tabs for better UX
                                _searchController.clear();
                              });
                            },
                            child: Container(
                              height: 28, // reduced from 38
                              decoration: BoxDecoration(
                                color: selectedTab == 0
                                    ? Color(0xFF2368A2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(32),
                              ),
                              child: Center(
                                child: Text(
                                  'Alive',
                                  style: TextStyle(
                                    color: selectedTab == 0
                                        ? Colors.white
                                        : Color(0xFF2368A2),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15, // reduced from 18
                                    decoration: TextDecoration.none,
                                    decorationColor: Colors.white,
                                    decorationThickness: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedTab = 1;
                                // Clear search when switching tabs for better UX
                                _searchController.clear();
                              });
                            },
                            child: Container(
                              height: 28, // increased from 25 for consistency
                              decoration: BoxDecoration(
                                color: selectedTab == 1
                                    ? Color(0xFF2368A2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(32),
                              ),
                              child: Center(
                                child: Text(
                                  'Deceased',
                                  style: TextStyle(
                                    color: selectedTab == 1
                                        ? Colors.white
                                        : Colors.black,
                                    fontWeight: FontWeight.normal,
                                    fontSize: 15, // reduced from 18
                                    decoration: TextDecoration.none,
                                    decorationColor: Colors.white,
                                    decorationThickness: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      hintText: 'Search by name, condition, or mobility...',
                      hintStyle: const TextStyle(
                        color: Colors.grey,
                          fontSize: 13, // reduced from 15
                      ),
                      filled: true,
                      fillColor: Color(0xFFD8F4FF),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 5, // reduced from 9
                          horizontal: 12, // reduced from 14
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
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                          : null,
                    ),
                      style: const TextStyle(fontSize: 15, color: Colors.black),
                  ),
                  const SizedBox(height: 8),
                  // Results counter
                  if (_searchQuery.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        _buildResultsCountText(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Assigned Day Dropdown on the left - only show for Alive tab
                      if (selectedTab == 0) // Only show for Alive tab
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Icon(Icons.calendar_today, color: Color(0xFF22688E), size: 18),
                            const SizedBox(width: 6),
                            const Text(
                              'Day:',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 15,
                                color: Color(0xFF22688E),
                              ),
                            ),
                            const SizedBox(width: 6),
                            DropdownButton<String>(
                              value: widget.selectedDay,
                              underline: const SizedBox(),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF22688E),
                              ),
                              items: (() {
                                const weekdayOrder = [
                                  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
                                ];
                                List<String> sortedDays = List<String>.from(widget.caregiverAssignedDays);
                                sortedDays.sort((a, b) => weekdayOrder.indexOf(a).compareTo(weekdayOrder.indexOf(b)));
                                return sortedDays.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList();
                              })(),
                              onChanged: (val) async {
                                if (val != null) {
                                  widget.onDayChanged(val);
                                }
                              },
                            ),
                          ],
                        )
                      else // For Deceased tab, add invisible placeholder to maintain height
                        const SizedBox(height: 48), // Match the approximate height of the dropdown row
                      // Add spacer to push sort button to the right
                      const Spacer(),
                      // Sort button on the right
                      GestureDetector(
                        onTap: _toggleSort,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              isSorted 
                                ? (isSortedAscending ? 'Sorted A-Z' : 'Sorted Z-A')
                                : 'Click to Sort',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 15,
                                color: isSorted ? Color(0xFF2368A2) : Color(0xFF00588e),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              isSorted 
                                ? (isSortedAscending ? Icons.arrow_upward : Icons.arrow_downward)
                                : Icons.sort, 
                              size: 18,
                              color: isSorted ? Color(0xFF2368A2) : Color(0xFF00588e),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildProfileGrid(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}