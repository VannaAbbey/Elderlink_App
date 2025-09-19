import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'edit_profile.dart';
import 'settings.dart' as app_settings;
import 'help_support.dart';
import 'add_task.dart';
import 'emergency_modal.dart';
import 'incident.dart';
import 'shift.dart';
import 'notifications.dart';
import 'caregiver_bottom_navbar.dart';
import 'houses.dart';
import 'services/house_service.dart';

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CaregiverHomeScreen(),
    ),
  );
}

class CaregiverHomeScreen extends StatefulWidget {
  const CaregiverHomeScreen({super.key});

  @override
  State<CaregiverHomeScreen> createState() => _CaregiverHomeScreenState();
}

class _CaregiverHomeScreenState extends State<CaregiverHomeScreen> {
  // Get assigned house for caregiver
  Future<Map<String, dynamic>?> getAssignedHouse() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final caregiverId = authProvider.currentUser?.uid;
    if (caregiverId == null) return null;
    final houseService = HouseService();
    return await houseService.getAssignedHouseForCaregiver(caregiverId);
  }
  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12
        ? hour - 12
        : hour == 0
        ? 12
        : hour;
    return '$hour12:$minute $ampm';
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.refreshUserData();
    });
  }

  // Helper to get upcoming tasks from AddTaskScreen logic with elderly profile pictures
  Stream<List<Map<String, dynamic>>> getUpcomingTasksStream() {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    final caregiverId = user?.uid;
    return FirebaseFirestore.instance
        .collection('care_tasks')
        .where('task_status', arrayContains: 'Upcoming')
        .where('caregiver_id', isEqualTo: caregiverId)
        .snapshots()
        .asyncMap((snapshot) async {
          final now = DateTime.now();
          List<Map<String, dynamic>> tasks = [];
          
          for (var doc in snapshot.docs) {
            final data = doc.data();
            final elderlyId = data['elderly_id'];
            
            // Fetch elderly profile picture
            String profilePicUrl = '';
            if (elderlyId != null) {
              try {
                final elderlyDoc = await FirebaseFirestore.instance
                    .collection('elderly')
                    .doc(elderlyId)
                    .get();
                if (elderlyDoc.exists) {
                  final elderlyData = elderlyDoc.data();
                  profilePicUrl = elderlyData?['elderly_profilePic'] ?? elderlyData?['profile_pic'] ?? '';
                  print('DEBUG: Found profile pic for ${data['elderly_fname']}: $profilePicUrl');
                }
              } catch (e) {
                print('DEBUG: Error fetching elderly profile pic: $e');
              }
            }
            
            tasks.add({
              'elderly_fname': data['elderly_fname'] ?? '',
              'task_description': data['task_description'] ?? '',
              'task_start': (data['task_start'] is Timestamp)
                  ? (data['task_start'] as Timestamp).toDate()
                  : data['task_start'],
              'task_date': (data['task_date'] is Timestamp)
                  ? (data['task_date'] as Timestamp).toDate()
                  : data['task_date'],
              'profile_pic': profilePicUrl,
            });
          }
          
          // Sort by task_start closest to now
          tasks.sort((a, b) {
            final aStart = a['task_start'] as DateTime? ?? now;
            final bStart = b['task_start'] as DateTime? ?? now;
            return aStart.compareTo(bStart);
          });
          return tasks;
        });
  }

  bool isSidebarOpen = false;
  int selectedIndex = 0;

  // Add the list of screens for navigation
  final List<Widget> _screens = [
    SizedBox.shrink(), // Home
    const AddTaskScreen(),
    // Emergency is now a modal, not a screen
    const IncidentScreen(),
    const ShiftScreen(),
  ];

  void toggleSidebar() {
    setState(() {
      isSidebarOpen = !isSidebarOpen;
    });
  }

  void onNavTap(int index) {
    if (index == 2) {
      // Emergency button pressed, show modal
      showEmergencyModal(context);
      return;
    }
    setState(() {
      selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (isSidebarOpen) {
          setState(() => isSidebarOpen = false);
        }
      },
      child: Scaffold(
        body: selectedIndex == 0
            ? Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/background1.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ListView(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Consumer<AuthProvider>(
                                    builder: (context, authProvider, child) {
                                      final profilePicUrl =
                                          authProvider.userProfilePic;
                                      return GestureDetector(
                                        onTap: toggleSidebar,
                                        child: CircleAvatar(
                                          radius: 24,
                                          backgroundColor: Colors.grey[200],
                                          child: ClipOval(
                                            child: profilePicUrl.isNotEmpty
                                                ? CachedNetworkImage(
                                                    imageUrl: profilePicUrl,
                                                    width: 48,
                                                    height: 48,
                                                    fit: BoxFit.cover,
                                                    placeholder: (context, url) =>
                                                        const CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                    errorWidget:
                                                        (
                                                          context,
                                                          url,
                                                          error,
                                                        ) => Image.asset(
                                                          'assets/images/people_icon.png',
                                                          width: 48,
                                                          height: 48,
                                                          fit: BoxFit.cover,
                                                        ),
                                                  )
                                                : Image.asset(
                                                    'assets/images/people_icon.png',
                                                    width: 48,
                                                    height: 48,
                                                    fit: BoxFit.cover,
                                                  ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Consumer<AuthProvider>(
                                        builder: (context, authProvider, child) {
                                          // Wait for user data to be loaded
                                          if (authProvider.userData == null) {
                                            return const Text(
                                              'Hello Caregiver,',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            );
                                          }

                                          final firstName =
                                              authProvider.userFirstName;
                                          // Ensure firstName is not empty or default
                                          final displayName =
                                              (firstName.isEmpty ||
                                                  firstName == 'User')
                                              ? ''
                                              : firstName;

                                          return Text(
                                            displayName.isEmpty
                                                ? 'Hello Caregiver,'
                                                : 'Hello Caregiver $displayName,',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          );
                                        },
                                      ),
                                      const Text('Hope you are doing well'),
                                    ],
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.notifications,
                                  color: Color(0XFF1D66A0),
                                  size: 35,
                                ),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const NotificationsScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width * 0.85,
                              child: TextField(
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    color: Colors.grey,
                                  ),
                                  hintText: "Search",
                                  hintStyle: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 15,
                                  ),
                                  filled: true,
                                  fillColor: Color(0xFFD8F4FF),
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
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ✅ MODIFIED: Light blue background for "Today's Tasks"
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Color(0x3EB7DDF5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: const [
                                        Icon(
                                          Icons.task,
                                          color: Color(0xFF00588E),
                                          size: 45,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          "Today's Tasks",
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          selectedIndex =
                                              1; // 1 is the index for AddTaskScreen (Upcoming Tasks tab)
                                        });
                                      },
                                      child: const Text(
                                        "See All",
                                        style: TextStyle(
                                          color: Colors.blue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // Show first 3 upcoming tasks as cards
                                StreamBuilder<List<Map<String, dynamic>>>(
                                  stream: getUpcomingTasksStream(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    }
                                    final tasks = snapshot.data ?? [];
                                    if (tasks.isEmpty) {
                                      return const Center(
                                        child: Text('No upcoming tasks.'),
                                      );
                                    }
                                    return Column(
                                      children: tasks
                                          .take(3)
                                          .map(
                                            (task) => _taskCard(
                                              task['elderly_fname'] ?? '',
                                              task['task_description'] ?? '',
                                              task['task_start'] != null
                                                  ? (task['task_start']
                                                            is DateTime
                                                        ? _formatTime(
                                                            task['task_start'],
                                                          )
                                                        : task['task_start']
                                                              .toString())
                                                  : '',
                                              Color(0xFFB7DDF5),
                                              task['profile_pic'] ?? '',
                                            ),
                                          )
                                          .toList(),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 30),
                          Row(
                            children: const [
                              Icon(
                                Icons.home,
                                color: Color(0xFF00588E),
                                size: 45,
                              ),
                              SizedBox(width: 8),
                              Text(
                                "Elderly Houses",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),
                          FutureBuilder<Map<String, dynamic>?>(
                            future: getAssignedHouse(),
                            builder: (context, snapshot) {
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => HousesScreen(),
                                    ),
                                  );
                                },
                                child: snapshot.connectionState == ConnectionState.waiting
                                    ? const Card(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.all(Radius.circular(16)),
                                        ),
                                        color: Color(0xFFE6F3FA),
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                                          child: Center(child: CircularProgressIndicator()),
                                        ),
                                      )
                                    : (snapshot.data == null
                                        ? Card(
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            color: const Color(0xFFE6F3FA),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                                              child: Row(
                                                children: const [
                                                  Icon(
                                                    Icons.home,
                                                    size: 50,
                                                    color: Color(0xFF00588E),
                                                  ),
                                                  SizedBox(width: 12),
                                                  Expanded(
                                                    child: Text(
                                                      'No house assigned',
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFF00588e),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                        : Card(
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            color: const Color(0xFFE6F3FA),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                                              child: Row(
                                                children: [
                                                  SizedBox(
                                                    width: 50,
                                                    height: 50,
                                                    child: Image.asset(
                                                      'assets/houses_img/${snapshot.data!['house_name'] ?? 'Unknown'}.png',
                                                      fit: BoxFit.contain,
                                                      errorBuilder: (context, error, stackTrace) => const Icon(
                                                        Icons.home,
                                                        size: 50,
                                                        color: Color(0xFF00588E),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          'House of ${snapshot.data!['house_name'] ?? 'Unknown'}',
                                                          style: const TextStyle(
                                                            fontSize: 16,
                                                            fontWeight: FontWeight.bold,
                                                            color: Color(0xFF00588e),
                                                          ),
                                                        ),
                                                        if (snapshot.data!['house_desc'] != null)
                                                          Padding(
                                                            padding: const EdgeInsets.only(top: 4),
                                                            child: Text(
                                                              snapshot.data!['house_desc'],
                                                              style: const TextStyle(
                                                                fontSize: 14,
                                                                color: Color(0xFF00588e),
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                      ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  CaregiverSidebar(
                    onLogout: () async {
                      final authProvider = Provider.of<AuthProvider>(
                        context,
                        listen: false,
                      );
                      await authProvider.signOut();
                      if (mounted) {
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/get_started',
                          (route) => false,
                        );
                      }
                    },
                    isSidebarOpen: isSidebarOpen,
                    toggleSidebar: toggleSidebar,
                    parentContext: context,
                  ),
                ],
              )
            : _screens[selectedIndex > 2 ? selectedIndex - 1 : selectedIndex],
        bottomNavigationBar: CaregiverBottomNavBar(
          selectedIndex: selectedIndex,
          onNavTap: onNavTap,
        ),
      ),
    );
  }

  Widget _taskCard(String name, String task, String time, Color bgColor, String profilePicUrl) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: Colors.grey[200],
            child: ClipOval(
              child: profilePicUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: profilePicUrl,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 50,
                        height: 50,
                        color: Colors.grey[300],
                        child: const Icon(
                          Icons.person,
                          color: Colors.grey,
                          size: 25,
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/people_icon.png',
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    )
                  : Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,  
                        color: Colors.white,
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/people_icon.png',
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(task),
              ],
            ),
          ),
          Text(time, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// Move CaregiverSidebar to top-level
class CaregiverSidebar extends StatelessWidget {
  final VoidCallback onLogout;
  final bool isSidebarOpen;
  final VoidCallback toggleSidebar;
  final BuildContext parentContext;

  const CaregiverSidebar({
    required this.onLogout,
    required this.isSidebarOpen,
    required this.toggleSidebar,
    required this.parentContext,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!isSidebarOpen) return SizedBox.shrink();
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
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 50),
                  Center(
                    child: Consumer<AuthProvider>(
                      builder: (context, authProvider, child) {
                        if (authProvider.userData == null) {
                          return const Text(
                            'Caregiver',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                              fontFamily: 'Poppins',
                            ),
                          );
                        }
                        final firstName = authProvider.userFirstName;
                        final displayName =
                            (firstName.isEmpty || firstName == 'User')
                            ? ''
                            : firstName;
                        return Text(
                          displayName.isEmpty
                              ? 'Caregiver'
                              : 'Caregiver $displayName',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            fontFamily: 'Poppins',
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(Icons.edit, color: Color(0xFF00588e)),
                    title: Text('Edit Profile'),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(
                        parentContext,
                        MaterialPageRoute(
                          builder: (context) => const EditProfile(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.settings, color: Color(0xFF00588e)),
                    title: Text('Settings'),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(
                        parentContext,
                        MaterialPageRoute(
                          builder: (context) => const app_settings.Settings(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.help, color: Color(0xFF00588e)),
                    title: Text('Help & Support'),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(
                        parentContext,
                        MaterialPageRoute(
                          builder: (context) => const HelpSupport(),
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
                      onPressed: onLogout,
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
