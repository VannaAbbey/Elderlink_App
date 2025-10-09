import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class MissedMedicationsTab extends StatefulWidget {
  final String houseId;
  final String? nurseName;

  const MissedMedicationsTab({
    super.key,
    required this.houseId,
    required this.nurseName,
  });

  @override
  State<MissedMedicationsTab> createState() => _MissedMedicationsTabState();
}

class _MissedMedicationsTabState extends State<MissedMedicationsTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _getCurrentDay() {
    return DateFormat('EEEE').format(DateTime.now());
  }

  Future<String?> _getNurseId() async {
    try {
      final nameParts = widget.nurseName?.split(' ') ?? [];
      if (nameParts.length < 2) return null;

      final firstName = nameParts[0];
      final lastName = nameParts[1];

      final userQuery = await _firestore
          .collection('users')
          .where('user_fname', isEqualTo: firstName)
          .where('user_lname', isEqualTo: lastName)
          .where('user_type', isEqualTo: 'nurse')
          .get();

      return userQuery.docs.isNotEmpty ? userQuery.docs.first.id : null;
    } catch (e) {
      print('Error getting nurse ID: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _getMissedMedications() async {
    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) return [];

      final currentDay = _getCurrentDay();

      // Get nurse's assigned elderly for current day (ALL shifts)
      final nurseElderlyQuery = await _firestore
          .collection('nurse_elderly_assign')
          .where('nurse_id', isEqualTo: nurseId)
          .where('is_current', isEqualTo: true)
          .where('house_ids', arrayContains: widget.houseId)
          .where('day', isEqualTo: currentDay)
          .get();

      if (nurseElderlyQuery.docs.isEmpty) return [];

      // Get assigned elderly IDs from ALL shifts for this nurse today
      final assignedElderlyIds = <String>[];
      for (final doc in nurseElderlyQuery.docs) {
        final elderlyIds = List<String>.from(doc.data()['elderly_ids'] ?? []);
        assignedElderlyIds.addAll(elderlyIds);
      }

      // Remove duplicates
      final uniqueElderlyIds = assignedElderlyIds.toSet().toList();

      if (uniqueElderlyIds.isEmpty) return [];

      // Get missed medications from activity logs
      final missedLogsQuery = await _firestore
          .collection('medication_activity_logs')
          .where('house_id', isEqualTo: widget.houseId)
          .where('action', isEqualTo: 'miss_take')
          .get();

      final missedMedications = <Map<String, dynamic>>[];

      for (final logDoc in missedLogsQuery.docs) {
        final logData = logDoc.data();
        final elderlyId = logData['elderly_id'] as String;

        // Only include medications for elderly assigned to this nurse
        if (!uniqueElderlyIds.contains(elderlyId)) continue;

        // Filter by current day only (all shifts)
        final logDay = logData['day'] as String?;

        // Include logs for current day (any shift where you were assigned)
        if (logDay == currentDay) {
          missedMedications.add({
            'id': logData['medication_id'],
            'elderly_id': elderlyId,
            'elderly_name': logData['elderly_name'],
            'medication_name': logData['medication_name'],
            'dosage': logData['dosage'],
            'take_number': logData['take_number'],
            'scheduled_time': logData['scheduled_time'],
            'repeat_interval': logData['repeat_interval'],
            'created_at': logData['timestamp'],
            'created_nurse_name': logData['nurse_name'],
            'house_id': logData['house_id'],
            'shift': logData['shift'],
            'missed_at': logData['timestamp'], // When it was marked as missed
          });
        }
      }

      // Sort by scheduled time (most recent first)
      missedMedications.sort((a, b) {
        try {
          final aTime = TimeOfDay(
            hour: int.parse(a['scheduled_time'].split(':')[0]),
            minute: int.parse(a['scheduled_time'].split(':')[1]),
          );
          final bTime = TimeOfDay(
            hour: int.parse(b['scheduled_time'].split(':')[0]),
            minute: int.parse(b['scheduled_time'].split(':')[1]),
          );

          final aMinutes = aTime.hour * 60 + aTime.minute;
          final bMinutes = bTime.hour * 60 + bTime.minute;

          return bMinutes.compareTo(aMinutes);
        } catch (e) {
          return 0;
        }
      });

      return missedMedications;
    } catch (e) {
      print('Error getting missed medications: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('medication_activity_logs')
          .where('house_id', isEqualTo: widget.houseId)
          .where('action', isEqualTo: 'miss_take')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          print('Error loading missed medications: ${snapshot.error}');
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _getMissedMedications(),
          builder: (context, futureSnapshot) {
            if (futureSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final missedMedications = futureSnapshot.data ?? [];
            print('Found ${missedMedications.length} missed medications');

            if (missedMedications.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No missed medications',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: EdgeInsets.symmetric(vertical: 8),
              itemCount: missedMedications.length,
              itemBuilder: (context, index) {
                final medication = missedMedications[index];
                final takeOrdinal = _getOrdinal(
                  medication['take_number'] as int,
                );

                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Elderly Name
                        Row(
                          children: [
                            Icon(Icons.person, color: Color(0xFF00588E)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                medication['elderly_name'] ?? 'Unknown',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF00588E),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),

                        // Medication Name and Dosage
                        Row(
                          children: [
                            Icon(Icons.medication, color: Colors.orange),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${medication['medication_name']} - ${medication['dosage']}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),

                        // Missed Take Information
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.red.withOpacity(0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.red.withOpacity(0.1),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.cancel, color: Colors.red, size: 24),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$takeOrdinal Take - MISSED',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.red,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Scheduled Time: ${medication['scheduled_time'] ?? 'Not specified'}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    if (medication['missed_at'] != null)
                                      Padding(
                                        padding: EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Missed: ${DateFormat('MMM dd, yyyy HH:mm').format((medication['missed_at'] as Timestamp).toDate())}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.red[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Created timestamp (smaller and at bottom)
                        if (medication['created_at'] != null)
                          Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              'Created: ${DateFormat('MMM dd, yyyy HH:mm').format((medication['created_at'] as Timestamp).toDate())}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _getOrdinal(int number) {
    if (number >= 11 && number <= 13) {
      return '${number}th';
    }
    switch (number % 10) {
      case 1:
        return '${number}st';
      case 2:
        return '${number}nd';
      case 3:
        return '${number}rd';
      default:
        return '${number}th';
    }
  }
}
