import 'package:flutter/material.dart';

// Helper function to show error modal
void _showErrorModal(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 60, color: Colors.red),
          const SizedBox(height: 12),
          const Text(
            "Can't send to Medical Services",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15),
          ),
        ],
      ),
      actions: [
        Center(
          child: TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Color(0xFF00588e),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "OK",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    ),
  );
}

Future<Map<String, dynamic>?> showEmergencyModal(
  BuildContext context, {
  required String defaultHouse,
  required String caregiverName, // ipapasa from handler
}) async {
  String? selectedHouse = defaultHouse;
  String? selectedEmergencyType; // new emergency type variable
  String emergencyDetails = '';
  bool acknowledged = false;

  final List<String> houses = [
    'St. Sebastian',
    'St. Emmanuel',
    'St. Charbell',
    'St. Rose',
    'St. Gabriel',
  ];

  final List<String> emergencyTypes = [
    'Elderly has slipped/fell down',
    'Elderly is having a stroke',
    'Elderly is having a heart attack',
    'Elderly is having a seizure',
    'Elderly is choking on something',
    'Elderly became unconscious',
    'Elderly is having an allergic reaction',
    'Elderly is missing/has wandered off',
    'Elderly is having a fever',
    'Others (please specify below)',
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
                              Transform.translate(
                                offset: const Offset(16, -3), // Move right and up
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(
                                    Icons.close,
                                    size: 28,
                                    color: Color(0xFF00588e),
                                  ),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
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

                      // Emergency Type
                      Row(
                        children: [
                          const Icon(Icons.warning, color: Color(0xFF00588e)),
                          const SizedBox(width: 8),
                          const Text(
                            'What is the Emergency?',
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
                            value: selectedEmergencyType,
                            isExpanded: true,
                            hint: const Text('Select emergency type'),
                            menuMaxHeight: 300, // Make dropdown scrollable
                            icon: const Icon(
                              Icons.arrow_drop_down,
                              color: Color(0xFF00588e),
                            ),
                            items: emergencyTypes.map((type) {
                              return DropdownMenuItem<String>(
                                value: type,
                                child: Text(type),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                selectedEmergencyType = value;
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
                            Icons.info_outline,
                            color: Color(0xFF00588e),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Other information',
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
                            hintText: 'Write here what happened... (optional)',
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
                                  selectedEmergencyType != null
                              ? () {
                                  // Check if "Others" is selected but text field is empty
                                  if (selectedEmergencyType == "Others (please specify below)" &&
                                      emergencyDetails.trim().isEmpty) {
                                    _showErrorModal(context, "Please fill in the field!");
                                    return;
                                  }
                                  
                                  Navigator.of(context).pop({
                                    "houseName": selectedHouse,
                                    "emergencyType": selectedEmergencyType,
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
