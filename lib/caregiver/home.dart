import 'package:flutter/material.dart';

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
  bool isSidebarOpen = false;
  int selectedIndex = 0;

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
                                  'assets/profile.jpg',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Hello Caregiver Lorna,',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text('Hope you are doing well'),
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
                      child: Container(
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
                        color: Color.fromRGBO(183, 221, 245, 0.25),
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
                          _taskCard(
                            'Lola Celia',
                            '15 minutes Walking Exercise',
                            '10:00 AM',
                            Color(0xFFFFB0A5),
                          ),
                          _taskCard(
                            'Lolo Adam',
                            'Serve a Dietary Lunch',
                            '11:00 AM',
                            Color(0xFFB7DDF5),
                          ),
                          _taskCard(
                            'Lola Andrea',
                            'Take a Bath',
                            '1:00 PM',
                            Color(0xFFB7DDF5),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),
                    Row(
                      children: const [
                        Icon(Icons.home, color: Color(0xFF00588E), size: 45),
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
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Color(0XFFE7EFFF),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.home, size: 40, color: Colors.blue),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'House of St. Sebastian',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text('Females with Psychological Needs'),
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
                          child: Text(
                            'Caregiver Lorna',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                              fontFamily: 'Poppins',
                            ),
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
                                horizontal: 60, // Adjusted to fit sidebar width
                              ),
                            ),
                            onPressed: () {
                              // TODO: Add logout logic
                            },
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
        // Replace your existing 'bottomNavigationBar' with this:
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0XFFA5D4DC),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
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

  Widget _taskCard(String name, String task, String time, Color bgColor) {
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
            offset: const Offset(0, 3), // subtle shadow below the card
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
      leading: Icon(icon, color: Color(0xFF00588e)),
      title: Text(title),
      onTap: () {
        setState(() => isSidebarOpen = false);
      },
    );
  }
}
