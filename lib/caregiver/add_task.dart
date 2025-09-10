import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'caregiver_sidebar.dart';
import '../providers/auth_provider.dart';
import 'notifications.dart';

class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({super.key});
  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  Color _getCardColor(int tab) {
    switch (tab) {
      case 0: // Upcoming
      case 1: // Complete
        return const Color(0xFFE6F3FA); // Blue
      case 2: // Incomplete
        return const Color(0xFFE6FAF0); // Green
      case 3: // Missed
        return const Color(0xFFFDE6E6); // Red
      default:
        return Colors.white;
    }
  }

  Color _getTextColor(int tab) {
    switch (tab) {
      case 0:
      case 1:
        return const Color(0xFF00588e); // Blue text
      case 2:
        return const Color(0xFF1B7F5A); // Green text
      case 3:
        return const Color(0xFFD32F2F); // Red text
      default:
        return Colors.black;
    }
  }

  List<Map<String, String>> _getTasks(int tab) {
    // Placeholder data for each tab
    switch (tab) {
      case 0:
        return [
          {'name': 'Lolo Adam', 'task': 'Take a bath', 'time': '11:00 AM', 'image': 'elderly.png'},
          {'name': 'Lolo Mario', 'task': 'Serve a Dietary Lunch', 'time': '12:00 PM', 'image': 'elderly.png'},
          {'name': 'Lolo Sofronio', 'task': 'Do Walking Exercise', 'time': '3:00 PM', 'image': 'elderly.png'},
        ];
      case 1:
        return [
          {'name': 'Lolo Eloy', 'task': 'Do some stretching exercise', 'time': '1:00 PM', 'image': 'elderly.png'},
        ];
      case 2:
        return [
          {'name': 'Lolo Paul', 'task': 'Do Zumba', 'time': '2:30 PM', 'image': 'elderly.png'},
        ];
      case 3:
        return [
          {'name': 'Lolo Adam', 'task': 'Take a bath', 'time': '11:00 AM', 'image': 'elderly.png'},
        ];
      default:
        return [];
    }
  }

  Widget _buildTaskCard(Map<String, String> task, int tab) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _getCardColor(tab),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF00588e),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task['name'] ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: _getTextColor(tab),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  task['task'] ?? '',
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                task['time'] ?? '',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _getTextColor(tab),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  int _selectedTab = 0;
  final List<String> _tabs = ['Upcoming', 'Complete', 'Incomplete', 'Missed'];
  bool isSidebarOpen = false;
  void toggleSidebar() => setState(() => isSidebarOpen = !isSidebarOpen);

  @override
  Widget build(BuildContext context) {
    Future<void> handleLogout() async {
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

    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/background1.png',
            fit: BoxFit.cover,
          ),
        ),
        Column(
          children: [
            const SizedBox(height: 16), // Add space above AppBar
            Expanded(
              child: Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  title: const Text('List of Tasks',
                      style: TextStyle(
                          color: Color(0xFF00588e),
                          fontWeight: FontWeight.bold)),
                  centerTitle: true,
                  leading: IconButton(
                    icon: const Icon(Icons.menu, color: Color(0xFF00588e)),
                    onPressed: toggleSidebar,
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.notifications, color: Color(0xFF00588e), size: 35),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const NotificationsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                body: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      color: const Color(0xFFE6F3FA),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: IntrinsicWidth(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: List.generate(_tabs.length, (index) {
                              final bool selected = _selectedTab == index;
                              return Padding(
                                padding: const EdgeInsets.only(left: 3.0, right: 3.0),
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedTab = index;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    decoration: selected
                                        ? BoxDecoration(
                                            color: const Color(0xFF00588e),
                                            borderRadius: BorderRadius.circular(20),
                                          )
                                        : null,
                                    child: Text(
                                      _tabs[index],
                                      style: TextStyle(
                                        color: selected ? Colors.white : const Color(0xFF00588e),
                                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            itemCount: _getTasks(_selectedTab).length,
                            itemBuilder: (context, index) {
                              final task = _getTasks(_selectedTab)[index];
                              return _buildTaskCard(task, _selectedTab);
                            },
                          ),
                          if (_selectedTab == 0)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    SizedBox(
                                      width: 180,
                                      child: ElevatedButton(
                                        onPressed: () {
                                          // Show dialog to add task
                                          showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (BuildContext ctx) {
                                              String? selectedElderly;
                                              String? selectedFrequency = 'Once a day';
                                              TimeOfDay? startTime;
                                              TimeOfDay? endTime;
                                              TextEditingController activityController = TextEditingController();
                                              final List<String> elderlyList = ['Lolo Sandro', 'Lolo Adam', 'Lolo Mario', 'Lolo Sofronio']; // Placeholder data
                                              final List<String> frequencyList = ['Once a day', 'Everyday', 'Every other day', 'Once a week']; 
                                              return StatefulBuilder(
                                                builder: (context, setState) {
                                                  return Dialog(
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                                                    child: Container(
                                                      width: 350,
                                                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius: BorderRadius.circular(20),
                                                      ),
                                                      child: SingleChildScrollView(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                                          children: [
                                                            Row(
                                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                              children: [
                                                                const SizedBox(width: 8),
                                                                Expanded(
                                                                  child: Center(
                                                                    child: Text(
                                                                      'Add Task',
                                                                      style: const TextStyle(
                                                                        fontSize: 20,
                                                                        fontWeight: FontWeight.bold,
                                                                        color: Color(0xFF22688E),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                                IconButton(
                                                                  icon: const Icon(Icons.close, size: 25, color: Color(0xFF22688E)),
                                                                  onPressed: () => Navigator.of(ctx).pop(),
                                                                ),
                                                              ],
                                                            ),
                                                            const Divider(),
                                                            const SizedBox(height: 10),
                                                            Row(
                                                              children: [
                                                                const Icon(Icons.person, color: Color(0xFF22688E)),
                                                                const SizedBox(width: 8),
                                                                const Text('Name of the Elderly:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                              ],
                                                            ),
                                                            const SizedBox(height: 8),
                                                            Container(
                                                              height: 40,
                                                              decoration: BoxDecoration(
                                                                color: const Color(0xFFE6F3FA),
                                                                borderRadius: BorderRadius.circular(20),
                                                              ),
                                                              padding: const EdgeInsets.symmetric(horizontal: 16),
                                                              child: DropdownButtonHideUnderline(
                                                                // Select Elderly Dropdown box
                                                                child: DropdownButton<String>(
                                                                  value: selectedElderly,
                                                                  hint: const Text('Select Elderly'),
                                                                  isExpanded: false,
                                                                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF22688E)),
                                                                  items: elderlyList.map((elderly) { // Call placeholder elderly data
                                                                    return DropdownMenuItem<String>(
                                                                      value: elderly,
                                                                      child: Text(elderly),
                                                                    );
                                                                  }).toList(),
                                                                  onChanged: (value) {
                                                                    setState(() {
                                                                      selectedElderly = value;
                                                                    });
                                                                  },
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(height: 20),
                                                            Row(
                                                              children: [
                                                                const Icon(Icons.access_time, color: Color(0xFF22688E)),
                                                                const SizedBox(width: 8),
                                                                const Text('Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                              ],
                                                            ),
                                                            const SizedBox(height: 8),
                                                            Row(
                                                              children: [
                                                                Expanded(
                                                                  child: Column(
                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                    children: [
                                                                      const Text('Start', style: TextStyle(fontWeight: FontWeight.bold)),
                                                                      const SizedBox(height: 4),
                                                                      // Start time dropdown box
                                                                      Container(
                                                                        height: 40,
                                                                        decoration: BoxDecoration(
                                                                          color: const Color(0xFFE6F3FA),
                                                                          borderRadius: BorderRadius.circular(14),
                                                                        ),
                                                                        child: InkWell(
                                                                          onTap: () async {
                                                                            final picked = await showTimePicker(
                                                                              context: ctx,
                                                                              initialTime: startTime ?? TimeOfDay.now(),
                                                                            );
                                                                            if (picked != null) {
                                                                              setState(() {
                                                                                startTime = picked;
                                                                              });
                                                                            }
                                                                          },
                                                                          child: Padding(
                                                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                                            child: Row(
                                                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                                              children: [
                                                                                Text(
                                                                                  startTime != null ? startTime!.format(ctx) : 'Select',
                                                                                  style: const TextStyle(fontSize: 15),
                                                                                ),
                                                                                const Icon(Icons.arrow_drop_down, color: Color(0xFF22688E)),
                                                                              ],
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                                const SizedBox(width: 16),
                                                                Expanded(
                                                                  child: Column(
                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                    children: [
                                                                      const Text('End', style: TextStyle(fontWeight: FontWeight.bold)),
                                                                      const SizedBox(height: 4),
                                                                      // End time dropdown box
                                                                      Container(
                                                                        height: 40,
                                                                        decoration: BoxDecoration(
                                                                          color: const Color(0xFFE6F3FA),
                                                                          borderRadius: BorderRadius.circular(14),
                                                                        ),
                                                                        child: InkWell(
                                                                          onTap: () async {
                                                                            final picked = await showTimePicker(
                                                                              context: ctx,
                                                                              initialTime: endTime ?? TimeOfDay.now(),
                                                                            );
                                                                            if (picked != null) {
                                                                              setState(() {
                                                                                endTime = picked;
                                                                              });
                                                                            }
                                                                          },
                                                                          child: Padding(
                                                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                                            child: Row(
                                                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                                              children: [
                                                                                Text(
                                                                                  endTime != null ? endTime!.format(ctx) : 'Select',
                                                                                  style: const TextStyle(fontSize: 15),
                                                                                ),
                                                                                const Icon(Icons.arrow_drop_down, color: Color(0xFF22688E)),
                                                                              ],
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            const SizedBox(height: 20),
                                                            Row(
                                                              children: [
                                                                const Icon(Icons.date_range, color: Color(0xFF22688E)),
                                                                const SizedBox(width: 8),
                                                                const Text('Frequency', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                              ],
                                                            ),
                                                            const SizedBox(height: 8),
                                                            Container(
                                                              height: 40,
                                                              decoration: BoxDecoration(
                                                                color: const Color(0xFFE6F3FA),
                                                                borderRadius: BorderRadius.circular(20),
                                                              ),
                                                              padding: const EdgeInsets.symmetric(horizontal: 16),
                                                              child: DropdownButtonHideUnderline(
                                                                // Frequency dropdown box
                                                                child: DropdownButton<String>(
                                                                  value: selectedFrequency,
                                                                  isExpanded: false,
                                                                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF22688E)),
                                                                  items: frequencyList.map((freq) {
                                                                    return DropdownMenuItem<String>(
                                                                      value: freq,
                                                                      child: Text(freq),
                                                                    );
                                                                  }).toList(),
                                                                  onChanged: (value) {
                                                                    setState(() {
                                                                      selectedFrequency = value;
                                                                    });
                                                                  },
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(height: 20),
                                                            Row(
                                                              children: [
                                                                const Icon(Icons.emoji_people, color: Color(0xFF22688E)),
                                                                const SizedBox(width: 8),
                                                                const Text('What Activity?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF22688E))),
                                                              ],
                                                            ),
                                                            const SizedBox(height: 8),
                                                            Container(
                                                              decoration: BoxDecoration(
                                                                color: const Color(0xFFE6F3FA),
                                                                borderRadius: BorderRadius.circular(12),
                                                              ),
                                                              // Text field for activity
                                                              child: TextField(
                                                                controller: activityController,
                                                                maxLines: 3,
                                                                decoration: const InputDecoration(
                                                                  hintText: 'Type here',
                                                                  hintStyle: TextStyle(fontStyle: FontStyle.italic),
                                                                  border: InputBorder.none,
                                                                  contentPadding: EdgeInsets.all(8),
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(height: 20),
                                                            SizedBox(
                                                              width: double.infinity,
                                                              height: 48,
                                                              child: ElevatedButton(
                                                                onPressed: () {
                                                                  // TODO: Save task logic (placeholder)
                                                                  Navigator.of(ctx).pop();
                                                                },
                                                                style: ElevatedButton.styleFrom(
                                                                  backgroundColor: const Color(0xFF22688E),
                                                                  shape: RoundedRectangleBorder(
                                                                    borderRadius: BorderRadius.circular(32),
                                                                  ),
                                                                  elevation: 4,
                                                                ),
                                                                child: const Text(
                                                                  'Save Task',
                                                                  style: TextStyle(
                                                                    fontSize: 15,
                                                                    fontWeight: FontWeight.w600,
                                                                    color: Colors.white,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(height: 5),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              );
                                            },
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF00588e),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(30),
                                          ),
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          elevation: 4,
                                        ),
                                        child: const Text(
                                          'Add More Tasks',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    SizedBox(
                                      width: 180,
                                      child: ElevatedButton(
                                        onPressed: () {
                                          // TODO: Delete task logic
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFD32F2F),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(30),
                                          ),
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          elevation: 4,
                                        ),
                                        child: const Text(
                                          'Delete Task',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        CaregiverSidebar(
          onLogout: handleLogout,
          isSidebarOpen: isSidebarOpen,
          toggleSidebar: toggleSidebar,
          parentContext: context,
        ),
      ],
    );
  }
}
