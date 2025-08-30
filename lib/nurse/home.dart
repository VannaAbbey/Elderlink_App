import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class NurseHomeScreen extends StatefulWidget {
  const NurseHomeScreen({super.key});

  @override
  State<NurseHomeScreen> createState() => _NurseHomeScreenState();
}

class _NurseHomeScreenState extends State<NurseHomeScreen> {
  bool isSidebarOpen = false;
  int selectedIndex = 0;

  Future<void> _handleLogout() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/get_started',
        (route) => false,
      );
    }
  }

  void toggleSidebar() {
    setState(() {
      isSidebarOpen = !isSidebarOpen;
    });
  }

  void onNavTap(int index) {
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
                padding: const EdgeInsets.all(16.0),
                child: ListView(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: toggleSidebar,
                              child: const CircleAvatar(
                                radius: 24,
                                backgroundImage: AssetImage(
                                  'assets/profile.jpg', // Placeholder
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Consumer<AuthProvider>(
                                  builder: (context, authProvider, child) {
                                    // Wait for user data to be loaded
                                    if (authProvider.userData == null) {
                                      return const Text(
                                        'Hello Nurse,',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      );
                                    }
                                    
                                    final firstName = authProvider.userFirstName;
                                    // Ensure firstName is not empty or default
                                    final displayName = (firstName.isEmpty || firstName == 'User') 
                                        ? '' 
                                        : firstName;
                                    
                                    return Text(
                                      displayName.isEmpty 
                                          ? 'Hello Nurse,'
                                          : 'Hello Nurse $displayName,',
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
                        const Icon(
                          Icons.notifications,
                          color: Color(0XFF1D66A0),
                          size: 35,
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
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Nurse-specific content
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(183, 221, 245, 0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: const [
                                  Icon(
                                    Icons.medical_services,
                                    color: Color(0xFF00588E),
                                    size: 45,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    "Today's Medical Tasks",
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const Text(
                                "See All",
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _medicalTaskCard(
                            'Lola Celia',
                            'Blood Pressure Check',
                            '9:00 AM',
                            const Color(0xFFFFB0A5),
                          ),
                          _medicalTaskCard(
                            'Lolo Adam',
                            'Medication Administration',
                            '11:00 AM',
                            const Color(0xFFB7DDF5),
                          ),
                          _medicalTaskCard(
                            'Lola Andrea',
                            'Health Assessment',
                            '2:00 PM',
                            const Color(0xFFB7DDF5),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),
                    Row(
                      children: const [
                        Icon(Icons.local_hospital, color: Color(0xFF00588E), size: 45),
                        SizedBox(width: 8),
                        Text(
                          "Medical Centers",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0XFFE7EFFF),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.local_hospital, size: 40, color: Colors.blue),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'St. Sebastian Medical Center',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text('Specialized Elderly Care'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (isSidebarOpen) ...[
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
                              // Wait for user data to be loaded
                              if (authProvider.userData == null) {
                                return const Text(
                                  'Nurse',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                    fontFamily: 'Poppins',
                                  ),
                                );
                              }
                              
                              final firstName = authProvider.userFirstName;
                              // Ensure firstName is not empty or default
                              final displayName = (firstName.isEmpty || firstName == 'User') 
                                  ? '' 
                                  : firstName;
                              
                              return Text(
                                displayName.isEmpty 
                                    ? 'Nurse'
                                    : 'Nurse $displayName',
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
                        _sidebarItem(Icons.edit, 'Edit Profile'),
                        _sidebarItem(Icons.settings, 'Settings'),
                        _sidebarItem(Icons.help, 'Help & Support'),
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
                            onPressed: _handleLogout,
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
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0XFFA5D4DC),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _navIcon('assets/images/homeIcon.png', 0),
                _navIcon('assets/images/addTaskIcon.png', 1),
                _navIcon('assets/images/emerIcon.png', 2),
                _navIcon('assets/images/incidentIcon.png', 3),
                _navIcon('assets/images/shiftIcon.png', 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navIcon(String assetPath, int index) {
    return GestureDetector(
      onTap: () => onNavTap(index),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selectedIndex == index
              ? const Color.fromARGB(255, 255, 255, 255)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Image.asset(
          assetPath,
          height: 38,
          width: 38,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _medicalTaskCard(String name, String task, String time, Color bgColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 25,
            backgroundImage: AssetImage('assets/profile.jpg'),
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

  Widget _sidebarItem(IconData icon, String title) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF00588e)),
      title: Text(title),
      onTap: () {
        setState(() => isSidebarOpen = false);
      },
    );
  }
}
