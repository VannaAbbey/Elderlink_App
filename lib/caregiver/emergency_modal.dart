import 'package:flutter/material.dart';

Future<Map<String, dynamic>?> showEmergencyModal(
  BuildContext context, {
  required String defaultHouse,
  required String caregiverName, // ipapasa from handler
}) async {
  String? selectedHouse = defaultHouse;
  String selectedType = "Medical"; // default
  String emergencyDetails = '';
  bool acknowledged = false;

  final List<String> houses = [
    'St. Sebastian',
    'St. Emmanuel',
    'St. Charbell',
    'St. Rose',
    'St. Gabriel',
  ];

  final TextEditingController detailsController = TextEditingController();

  return await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            padding: const EdgeInsets.fromLTRB(
              20,
              2,
              20,
              20,
            ), // top padding reduced from 20 -> 8
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: StatefulBuilder(
              builder: (context, setState) {
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Replace your current Row with this Stack
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // First row: Exit icon at top-right
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(
                                  Icons.close,
                                  size: 28,
                                  color: Color(0xFF00588e),
                                ),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),

                          // Second row: Header text centered
                          Center(
                            child: Text(
                              'Emergency Details',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588e),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 16),

                      // House
                      Row(
                        children: [
                          const Icon(Icons.home, color: Color(0xFF00588e)),
                          const SizedBox(width: 8),
                          const Text(
                            'Name of House?',
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
                            value: selectedHouse,
                            isExpanded: true,
                            icon: const Icon(
                              Icons.arrow_drop_down,
                              color: Color(0xFF00588e),
                            ),
                            items: houses.map((house) {
                              return DropdownMenuItem<String>(
                                value: house,
                                child: Text(house),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                selectedHouse = value;
                              });
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Details
                      Row(
                        children: [
                          const Icon(
                            Icons.medical_services,
                            color: Color(0xFF00588e),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'What is the emergency?',
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
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: detailsController,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            hintText: 'Write here what happened...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(12),
                          ),
                          onChanged: (val) {
                            emergencyDetails = val;
                          },
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 🔹 Reporting Caregiver
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.person, color: Color(0xFF00588e)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Reporting Caregiver: $caregiverName',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                              softWrap: true,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Checkbox
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
                      const SizedBox(height: 18),

                      // Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              acknowledged &&
                                  selectedHouse != null &&
                                  emergencyDetails.isNotEmpty
                              ? () {
                                  Navigator.of(context).pop({
                                    "houseName": selectedHouse,
                                    "type": selectedType,
                                    "description": emergencyDetails,
                                    "caregiverName": caregiverName,
                                  });
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00588e),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            elevation: 4,
                          ),
                          child: const Text(
                            'Send Alert to Medical Services',
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
                );
              },
            ),
          ),
        ),
      );
    },
  );
}
