import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart' as main; // For EmergencyService

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
    return WillPopScope(
      onWillPop: () async => false, // Prevent back button dismissal
      child: AlertDialog(
        backgroundColor: Colors.white,
        contentPadding: EdgeInsets.zero,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical:
              100, // NEVER HIDE BOTTOM NAV - 100px space at top and bottom
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 48),
            SizedBox(height: 8),
            Text(
              'Emergency Alert',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF00588e),
                fontSize: 22,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // House Name
                _InfoRow(icon: Icons.home, label: 'House', value: houseName),
                const SizedBox(height: 8),

                // Date & Time
                _InfoRow(
                  icon: Icons.access_time,
                  label: 'Date & Time',
                  value: alertTimestamp,
                ),
                const SizedBox(height: 8),

                // Reporting Caregiver
                _InfoRow(
                  icon: Icons.person,
                  label: 'Caregiver',
                  value: caregiverName,
                ),
                const SizedBox(height: 12),

                // Description Section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 205, 227, 246),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Emergency Type
                      Row(
                        children: const [
                          Icon(
                            Icons.warning,
                            color: Color(0xFF00588e),
                            size: 20,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Emergency Type:',
                            style: TextStyle(
                              color: Color(0xFF00588e),
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
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

                      // Additional Information (only if exists)
                      if (alertDescription.isNotEmpty &&
                          alertDescription != 'No description' &&
                          alertDescription != 'Emergency alert received') ...[
                        const SizedBox(height: 10),
                        Row(
                          children: const [
                            Icon(
                              Icons.info_outline,
                              color: Color(0xFF00588e),
                              size: 20,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Additional Info:',
                              style: TextStyle(
                                color: Color(0xFF00588e),
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          alertDescription,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00588e),
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 12,
                ),
              ),
              onPressed: () async {
                try {
                  await FirebaseFirestore.instance
                      .collection('emergency_alert')
                      .doc(alertId)
                      .update({'alert_viewed': true});
                  print('✅ Alert marked as viewed');
                } catch (e) {
                  print('❌ Failed to update alert: $e');
                }
                main.EmergencyService.stopAlarm();
                Navigator.of(context).pop();
              },
              child: const Text(
                'Mark as Viewed',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
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
