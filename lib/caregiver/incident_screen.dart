import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'incident_report_service.dart';
import 'caregiver_sidebar.dart';
import 'notifications.dart';

class IncidentScreen extends StatefulWidget {
  const IncidentScreen({super.key});

  @override
  State<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends State<IncidentScreen> {
  final IncidentReportService _service = IncidentReportService();
  final TextEditingController reportController = TextEditingController();

  bool isSidebarOpen = false;
  bool isLoading = true;
  bool isOnDuty = false;
  String? selectedElderlyId;
  String? selectedElderlyName;
  String? caregiverName;
  List<Map<String, dynamic>> elderlyList = [];

  void toggleSidebar() {
    setState(() {
      isSidebarOpen = !isSidebarOpen;
    });
  }

  @override
  void initState() {
    super.initState();
    loadInitialData();
  }

  Future<void> loadInitialData() async {
    // Load caregiver name
    caregiverName = await _service._loadCaregiverName();

    // Load elderly assignments
    final assignments = await _service._loadElderlyAssignments();
    isOnDuty = assignments['isOnDuty'] ?? false;
    elderlyList = List<Map<String, dynamic>>.from(assignments['elderlyList'] ?? []);

    setState(() {
      isLoading = false;
    });
  }

  void _checkShiftAndShowDialog(BuildContext context) async {
    await _service._checkShiftAndShowDialog((message) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Shift Warning"),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("OK"),
            )
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    Future<void> handleLogout() async {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/get_started',
        (route) => false,
      );
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
                  title: const Text(
                    'Incident Report',
                    style: TextStyle(
                      color: Color(0xFF00588e),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  centerTitle: true,
                  leading: IconButton(
                    icon: const Icon(Icons.menu, color: Color(0xFF00588e)),
                    onPressed: toggleSidebar,
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(
                        Icons.notifications,
                        color: Color(0xFF00588e),
                        size: 35,
                      ),
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
                          // Elderly Name Row
                          Row(
                            children: const [
                              Icon(Icons.person, color: Color(0xFF00588e)),
                              SizedBox(width: 8),
                              Text(
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
                                value: selectedElderlyId,
                                hint: Text(
                                  isLoading
                                      ? 'Loading...'
                                      : (isOnDuty ? 'Select Elderly' : 'Not your schedule today/shift'),
                                ),
                                isExpanded: true,
                                icon: const Icon(
                                  Icons.arrow_drop_down,
                                  color: Color(0xFF00588e),
                                ),
                                menuMaxHeight: 200,
                                items: elderlyList.map((elderly) {
                                  return DropdownMenuItem<String>(
                                    value: elderly['id'],
                                    child: Text(elderly['name']),
                                  );
                                }).toList(),
                                onChanged: isOnDuty
                                    ? (value) {
                                        setState(() {
                                          selectedElderlyId = value;
                                          selectedElderlyName = elderlyList
                                              .firstWhere((e) => e['id'] == value)['name'];
                                        });
                                      }
                                    : null,
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),
                          // Incident TextField
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6F3FA),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                              controller: reportController,
                              maxLines: 20,
                              enabled: isOnDuty,
                              decoration: const InputDecoration(
                                hintText: 'Write the incident report here.',
                                hintStyle: TextStyle(fontStyle: FontStyle.italic),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(5),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),
                          // Forward the Report Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: isOnDuty
                                  ? () async {
                                      final formattedDate = DateFormat('MM/dd/yy | h:mm a').format(DateTime.now());

                                      showDialog(
                                        context: context,
                                        barrierDismissible: true,
                                        builder: (BuildContext ctx) {
                                          bool acknowledged = false;
                                          return StatefulBuilder(
                                            builder: (context, setState) {
                                              return Dialog(
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                                                child: Container(
                                                  width: 380,
                                                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  child: SingleChildScrollView(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                                      children: [
                                                        // Close button
                                                        Row(
                                                          mainAxisAlignment: MainAxisAlignment.end,
                                                          children: [
                                                            IconButton(
                                                              padding: EdgeInsets.zero,
                                                              constraints: const BoxConstraints(),
                                                              icon: const Icon(Icons.close, size: 28, color: Color(0xFF00588e)),
                                                              onPressed: () => Navigator.of(context).pop(),
                                                            ),
                                                          ],
                                                        ),
                                                        // Header
                                                        const Center(
                                                          child: Text(
                                                            'Confirmation Form',
                                                            style: TextStyle(
                                                              fontSize: 24,
                                                              fontWeight: FontWeight.bold,
                                                              color: Color(0xFF00588e),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(height: 12),
                                                        const Divider(),
                                                        const SizedBox(height: 8),
                                                        const Text(
                                                          'Please review the following information before submitting:',
                                                          textAlign: TextAlign.justify,
                                                          style: TextStyle(fontSize: 15),
                                                        ),
                                                        const SizedBox(height: 12),
                                                        // Elderly Name
                                                        Row(
                                                          children: [
                                                            const Icon(Icons.person, color: Color(0xFF00588e)),
                                                            const SizedBox(width: 8),
                                                            const Text(
                                                              'Elderly Name:',
                                                              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00588e)),
                                                            ),
                                                            const SizedBox(width: 4),
                                                            Expanded(
                                                              child: Text(
                                                                selectedElderlyName ?? '',
                                                                style: const TextStyle(fontSize: 15),
                                                                overflow: TextOverflow.visible,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(height: 10),
                                                        // Date & Time
                                                        Row(
                                                          children: [
                                                            const Icon(Icons.access_time, color: Color(0xFF00588e)),
                                                            const SizedBox(width: 8),
                                                            const Text(
                                                              'Date & Time:',
                                                              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00588e)),
                                                            ),
                                                            const SizedBox(width: 4),
                                                            Expanded(
                                                              child: Text(
                                                                formattedDate,
                                                                style: const TextStyle(fontSize: 15),
                                                                overflow: TextOverflow.visible,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(height: 20),
                                                        // Incident Description
                                                        Row(
                                                          children: [
                                                            const Icon(Icons.warning, color: Color(0xFF00588e)),
                                                            const SizedBox(width: 8),
                                                            const Text(
                                                              'Incident Description:',
                                                              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00588e)),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(height: 10),
                                                        Container(
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFFE6F3FA),
                                                            boxShadow: [BoxShadow(color: Colors.black12)],
                                                          ),
                                                          padding: const EdgeInsets.all(10),
                                                          child: SizedBox(
                                                            height: 120,
                                                            child: Align(
                                                              alignment: Alignment.topLeft,
                                                              child: Text(
                                                                reportController.text,
                                                                style: const TextStyle(
                                                                  fontStyle: FontStyle.italic,
                                                                  fontSize: 15,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(height: 20),
                                                        // Caregiver
                                                        Row(
                                                          children: [
                                                            const Icon(Icons.person, color: Color(0xFF00588e)),
                                                            const SizedBox(width: 8),
                                                            const Text(
                                                              'Caregiver:',
                                                              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00588e)),
                                                            ),
                                                            const SizedBox(width: 4),
                                                            Expanded(
                                                              child: Text(
                                                                caregiverName ?? 'Loading...',
                                                                style: const TextStyle(fontSize: 15),
                                                                overflow: TextOverflow.visible,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(height: 16),
                                                        // Acknowledgement Checkbox
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
                                                            const Expanded(
                                                              child: Padding(
                                                                padding: EdgeInsets.only(right: 8.0),
                                                                child: Text(
                                                                  'I acknowledge that the information provided is accurate and complete. I accept full responsibility and understand that this submission is final and cannot be modified.',
                                                                  textAlign: TextAlign.justify,
                                                                  style: TextStyle(fontSize: 13),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(height: 20),
                                                        // Buttons
                                                        Row(
                                                          mainAxisAlignment: MainAxisAlignment.end,
                                                          children: [
                                                            SizedBox(
                                                              width: 120,
                                                              height: 44,
                                                              child: ElevatedButton(
                                                                onPressed: (acknowledged && selectedElderlyName != null && selectedElderlyName!.isNotEmpty && reportController.text.trim().isNotEmpty)
                                                                    ? () async {
                                                                        Navigator.of(ctx).pop();
                                                                        await _service.submitIncidentReport(
                                                                          selectedElderlyId: selectedElderlyId!,
                                                                          reportText: reportController.text,
                                                                        );
                                                                        reportController.clear();
                                                                        setState(() {
                                                                          selectedElderlyId = null;
                                                                          selectedElderlyName = null;
                                                                        });
                                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                                          const SnackBar(
                                                                            content: Text("Incident report submitted successfully."),
                                                                            behavior: SnackBarBehavior.floating,
                                                                            margin: EdgeInsets.fromLTRB(16, 50, 16, 0),
                                                                            backgroundColor: Color(0xFF00588e),
                                                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                                            duration: Duration(seconds: 3),
                                                                          ),
                                                                        );
                                                                      }
                                                                    : null,
                                                                style: ElevatedButton.styleFrom(
                                                                  backgroundColor: (acknowledged && selectedElderlyName != null && selectedElderlyName!.isNotEmpty && reportController.text.trim().isNotEmpty)
                                                                      ? const Color(0xFF00588e)
                                                                      : Colors.grey,
                                                                  shape: RoundedRectangleBorder(
                                                                    borderRadius: BorderRadius.circular(18),
                                                                  ),
                                                                ),
                                                                child: const Text(
                                                                  'Submit',
                                                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(width: 12),
                                                            SizedBox(
                                                              width: 120,
                                                              height: 44,
                                                              child: ElevatedButton(
                                                                onPressed: () => Navigator.of(ctx).pop(),
                                                                style: ElevatedButton.styleFrom(
                                                                  backgroundColor: const Color(0xFF900000),
                                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                                                ),
                                                                child: const Text(
                                                                  'Cancel',
                                                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                                ),
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
                                    }
                                  : () {
                                      _checkShiftAndShowDialog(context);
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00588e),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 4,
                              ),
                              child: const Text(
                                'Forward the Report',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
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
        // Sidebar
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
