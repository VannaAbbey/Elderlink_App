import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'caregiver_sidebar.dart';
import '../providers/auth_provider.dart';

class IncidentScreen extends StatefulWidget {
  const IncidentScreen({super.key});
  @override
  State<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends State<IncidentScreen> {
  bool isSidebarOpen = false;
  void toggleSidebar() => setState(() => isSidebarOpen = !isSidebarOpen);

  String? selectedElderly;
  final List<String> elderlyList = ['Lolo Sandro', 'Lolo Adam', 'Lolo Mario']; // Placeholders
  final TextEditingController reportController = TextEditingController();

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: 16),
            Expanded(
              child: Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  title: const Text('Incident Report',
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
                        // TODO: Implement notification logic
                      },
                    ),
                  ],
                ),
                body: Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person, color: Color(0xFF00588e)),
                              const SizedBox(width: 8),
                              const Text(
                                'Name of the Elderly:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF00588e),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6F3FA),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedElderly,
                                hint: const Text('Select Elderly'),
                                isExpanded: true,
                                icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF00588e)),
                                items: elderlyList.map((elderly) {
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
                          const SizedBox(height: 18),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6F3FA),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                              controller: reportController,
                              maxLines: 20,
                              decoration: const InputDecoration(
                                hintText: 'Write the incident report here.',
                                hintStyle: TextStyle(fontStyle: FontStyle.italic),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                // TODO: Forward the report logic
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00588e),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 4,
                              ),
                              child: const Text(
                                'Forward the Report',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        CaregiverSidebar(
          onLogout: _handleLogout,
          isSidebarOpen: isSidebarOpen,
          toggleSidebar: toggleSidebar,
          parentContext: context,
        ),
      ],
    );
  }
}
