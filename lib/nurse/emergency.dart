import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'home.dart';
import 'medication_management.dart';
import 'bottom_navbar.dart';
import 'incident_report.dart';
import 'vital_monitoring.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _showCalendar = false;

  // Dummy emergency data
  final List<Map<String, String>> emergencies = [
    {
      'house': 'St. Gabriel',
      'time': '7:30 AM',
      'desc': 'Lolo Garin slipped and broke his ankle',
    },
    {
      'house': 'St. Sebastian',
      'time': '9:00 AM',
      'desc': 'Lola Marian was cut by a broken glass',
    },
  ];

  void _pickDate() async {
    setState(() => _showCalendar = true);
  }

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      _showCalendar = false;
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
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(
                        Icons.menu,
                        size: 30,
                        color: Color(0xFF00588E),
                      ),
                      const Text(
                        'Emergency Record',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00588E),
                        ),
                      ),
                      const Icon(
                        Icons.notifications,
                        size: 30,
                        color: Color(0xFF00588E),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Date + Calendar icon
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('MMMM dd, yyyy').format(_selectedDate),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      IconButton(
                        onPressed: _pickDate,
                        icon: const Icon(
                          Icons.calendar_today,
                          color: Color(0xFF00588E),
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Emergency Cards
                  Expanded(
                    child: ListView.builder(
                      itemCount: emergencies.length,
                      itemBuilder: (context, index) {
                        final em = emergencies[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.lightBlue[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00588E),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.home,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      em['house']!,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Color(0xFF00588E),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'What happened?',
                                      style: TextStyle(
                                        color: Colors.grey[800],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(em['desc']!),
                                  ],
                                ),
                              ),
                              Text(
                                em['time']!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black54,
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
          ),

          // Calendar Overlay
          if (_showCalendar)
            GestureDetector(
              onTap: () => setState(() => _showCalendar = false),
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CalendarDatePicker(
                      initialDate: _selectedDate,
                      firstDate: DateTime(_selectedDate.year - 1),
                      lastDate: DateTime(_selectedDate.year + 1),
                      onDateChanged: _onDateSelected,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),

      // Bottom navbar
      bottomNavigationBar: BottomNavbar(
        selectedIndex: 2, // Incident report is index 1
        onTap: (index) {
          switch (index) {
            case 0:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const NurseHomeScreen()),
              );
              break;
            case 1:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const IncidentReportScreen()),
              );
              break;
            case 2:
              break;
            case 3:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const MedicationManagementScreen(),
                ),
              );
              break;
            case 4:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const VitalMonitoringScreen(),
                ),
              );
              break;
          }
        },
      ),
    );
  }

  Widget _navIcon(String assetPath) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: Image.asset(assetPath, height: 38, width: 38, fit: BoxFit.contain),
    );
  }
}
