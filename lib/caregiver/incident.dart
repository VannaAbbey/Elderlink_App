import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'caregiver_sidebar.dart';
import '../providers/auth_provider.dart';
import 'notifications.dart';

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
            const SizedBox(height: 16),
            Expanded(
              child: Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  backgroundColor: const Color(0x00FFFFFF),
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
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const NotificationsScreen(),
                          ),
                        );
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

                                // Show confirmation dialog modal
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (BuildContext ctx) {
                                    bool acknowledged = false;
                                    return StatefulBuilder(
                                      builder: (context, setState) {
                                        return Dialog(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                                          child: Container(
                                            width: 380,
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
                                                            'Confirmation Form',
                                                            style: const TextStyle(
                                                              fontSize: 20,
                                                              fontWeight: FontWeight.bold,
                                                              color: Color(0xFF22688E),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(Icons.close, size: 28, color: Color(0xFF00588E)),
                                                        onPressed: () => Navigator.of(ctx).pop(),
                                                      ),
                                                    ],
                                                  ),
                                                  const Divider(),
                                                  const SizedBox(height: 8),
                                                  const Text(
                                                    'Please review the following information before submitting:',
                                                    style: TextStyle(fontSize: 15),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.person, color: Colors.black),
                                                      const SizedBox(width: 8),
                                                      const Text('Elderly Name:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          selectedElderly ?? '',
                                                          style: const TextStyle(fontSize: 15),
                                                          overflow: TextOverflow.visible,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 10),
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.access_time, color: Colors.black),
                                                      const SizedBox(width: 8),
                                                      const Text('Date & Time:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          '06/15/25 | 5PM', // Placeholder
                                                          style: const TextStyle(fontSize: 15),
                                                          overflow: TextOverflow.visible,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 20),
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.warning, color: Colors.black),
                                                      const SizedBox(width: 8),
                                                      const Text('Incident Description:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 10),
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: Color(0xFFE6F3FA),
                                                      boxShadow: [BoxShadow(color: Colors.black12)],
                                                    ),
                                                    padding: const EdgeInsets.all(10),
                                                    child: SizedBox(
                                                      height: 120,
                                                      child: Align(
                                                        alignment: Alignment.topLeft,
                                                        child: Text(
                                                          reportController.text,
                                                          style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 15),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 20),
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.person, color: Colors.black),
                                                      const SizedBox(width: 8),
                                                      const Text('Caregiver:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          'Matthew Sandoval II', // Placeholder
                                                          style: const TextStyle(fontSize: 15),
                                                          overflow: TextOverflow.visible,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Checkbox(
                                                        value: acknowledged,
                                                        activeColor: const Color(0xFF00588e),
                                                        onChanged: (val) {
                                                          setState(() {
                                                            acknowledged = val ?? false;
                                                          });
                                                        },
                                                      ),
                                                      Expanded(
                                                        child: const Text(
                                                          'I acknowledge that the information provided is accurate and complete. I accept full responsibility and understand that this submission is final and cannot be modified.',
                                                          style: TextStyle(fontSize: 13),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 20),
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                    children: [
                                                      SizedBox(
                                                        width: 120,
                                                        height: 44,
                                                        child: ElevatedButton(
                                                          onPressed: acknowledged ? () {
                                                            // TODO: Submit logic
                                                            Navigator.of(ctx).pop();
                                                          } : null,
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor: const Color(0xFF00588e),
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius: BorderRadius.circular(18),
                                                            ),
                                                          ),
                                                          child: const Text('Submit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 120,
                                                        height: 44,
                                                        child: ElevatedButton(
                                                          onPressed: () {
                                                            Navigator.of(ctx).pop();
                                                          },
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor: Colors.red,
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius: BorderRadius.circular(18),
                                                            ),
                                                          ),
                                                          child: const Text('Cancel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
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
          onLogout: handleLogout,
          isSidebarOpen: isSidebarOpen,
          toggleSidebar: toggleSidebar,
          parentContext: context,
        ),
      ],
    );
  }
}
