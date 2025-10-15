import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart'; // For EmergencyService

class EmergencyScreenModal extends StatelessWidget {
  final String alertId;
  final String alertDescription;
  final String alertTimestamp;
  final String houseName;
  final String caregiverName;
  final String emergencyType;

  const EmergencyScreenModal({
    super.key,
    required this.alertId,
    required this.alertDescription,
    required this.alertTimestamp,
    required this.houseName,
    required this.caregiverName,
    required this.emergencyType,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white, // light red
      title: Column(
        children: const [
          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 50),
          SizedBox(height: 5),
          Text(
            'Emergency Alert',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF00588e),
              fontSize: 25,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),

          // House Name
          _InfoRow(icon: Icons.home, label: 'House', value: houseName),
          const SizedBox(height: 5),

          // Date & Time
          _InfoRow(
            icon: Icons.access_time,
            label: 'Date & Time',
            value: alertTimestamp,
          ),
          const SizedBox(height: 5),

          // Reporting Caregiver
          _InfoRow(
            icon: Icons.person,
            label: 'Reporting Caregiver',
            value: caregiverName,
          ),
          const SizedBox(height: 10),

          // Description with blue container
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: const [
                  Icon(Icons.description, color: Color(0xFF00588e), size: 25),
                  SizedBox(width: 8),
                  Text(
                    'Description:',
                    style: TextStyle(
                      color: Color(0xFF00588e),
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 205, 227, 246),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Emergency Type as first line
                    Text(
                      emergencyType.isNotEmpty
                          ? emergencyType
                          : 'Emergency Alert',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Additional Information label
                    const Text(
                      'Additional Information:',
                      style: TextStyle(
                        color: Color(0xFF00588e),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Additional Information value
                    Text(
                      alertDescription.isNotEmpty &&
                              alertDescription != 'No description'
                          ? alertDescription
                          : 'No additional information provided',
                      style: const TextStyle(color: Colors.black, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00588e),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
          ),
          onPressed: () async {
            try {
              // Update Firestore to mark alert as viewed
              await FirebaseFirestore.instance
                  .collection('emergency_alert')
                  .doc(alertId)
                  .update({'alert_viewed': true});

              print('✅ Alert marked as viewed in DB');
            } catch (e) {
              print('❌ Failed to update alert_viewed: $e');
            }

            // Stop the alarm & close modal
            EmergencyService.stopAlarm();
            Navigator.of(context).pop();
          },
          child: const Text(
            'Mark as Viewed',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

// Custom widget for House / Date / Caregiver rows
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center, // icon aligned with text
      children: [
        Icon(icon, color: const Color(0xFF00588e), size: 28),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(
                    color: Color(0xFF00588e),
                    fontWeight: FontWeight.bold, // bold like description
                    fontSize: 16,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(color: Colors.black, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
