import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'home.dart';
import 'medication_management.dart';
import 'bottom_navbar.dart';
import 'vital_monitoring.dart';
import 'emergency.dart';

class IncidentReportScreen extends StatefulWidget {
  const IncidentReportScreen({super.key});

  @override
  State<IncidentReportScreen> createState() => _IncidentReportScreenState();
}

class _IncidentReportScreenState extends State<IncidentReportScreen> {
  String _search = '';
  DateTime? _selectedDate;

  // Dummy incident data
  final List<Map<String, String>> incidents = [
    {
      'name': 'Lola Celia',
      'house': 'Sebastian',
      'submittedBy': 'Caregiver Debbie',
      'time': '1:30 PM',
      'desc': 'Fell into the floor',
      'image': 'assets/images/elder1.png',
    },
    {
      'name': 'Lola Marites',
      'house': 'St. Rose',
      'submittedBy': 'Caregiver Debbie',
      'time': '1:30 PM',
      'desc': 'Scratched her body',
      'image': 'assets/images/elder2.png',
    },
  ];

  void _pickDate() async {
    final now = DateTime.now();
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final filteredIncidents = incidents.where((i) {
      final name = i['name']!.toLowerCase();
      final search = _search.toLowerCase();
      return search.isEmpty || name.contains(search);
    }).toList();

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
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Incident Report',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.notifications),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Search & Calendar row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'Search an Elderly...',
                            filled: true,
                            fillColor: Colors.blue[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (v) => setState(() => _search = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _pickDate,
                        icon: const Icon(
                          Icons.calendar_today,
                          size: 30,
                          color: Color(0xFF00588E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Selected date
                  if (_selectedDate != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        DateFormat('MMMM dd, yyyy').format(_selectedDate!),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  const SizedBox(height: 8),

                  // Incident cards
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredIncidents.length,
                      itemBuilder: (context, index) {
                        final inc = filteredIncidents[index];
                        return Card(
                          color: Colors.blue[50],
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundImage: AssetImage(
                                        inc['image']!,
                                      ),
                                      radius: 25,
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          inc['name']!,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text('Name of House: ${inc['house']}'),
                                        Text(
                                          'Submitted by: ${inc['submittedBy']}',
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Text(
                                      inc['time']!,
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(inc['desc']!),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      // Bottom navbar
      bottomNavigationBar: BottomNavbar(
        selectedIndex: 1, // Incident report
        onTap: (index) {
          switch (index) {
            case 0:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const NurseHomeScreen()),
              );
              break;
            case 1:
              break;
            case 2:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const EmergencyScreen()),
              );
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
}
