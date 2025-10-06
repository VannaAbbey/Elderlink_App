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

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

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
      final currentShift = _getCurrentShift();

      // Get nurse's assigned elderly for current day and shift
      final nurseElderlyQuery = await _firestore
          .collection('nurse_elderly_assign')
          .where('nurse_id', isEqualTo: nurseId)
          .where('is_current', isEqualTo: true)
          .where('house_ids', arrayContains: widget.houseId)
          .where('shift', isEqualTo: currentShift)
          .where('day', isEqualTo: currentDay)
          .get();

      if (nurseElderlyQuery.docs.isEmpty) return [];

      // Get assigned elderly IDs for this nurse
      final assignedElderlyIds = List<String>.from(
        nurseElderlyQuery.docs.first.data()['elderly_ids'] ?? [],
      );

      if (assignedElderlyIds.isEmpty) return [];

      // Get medications for assigned elderly
      final medicationsQuery = await _firestore
          .collection('medications')
          .where('house_id', isEqualTo: widget.houseId)
          .where('status', isEqualTo: 'upcoming')
          .get();

      final missedMedications = <Map<String, dynamic>>[];

      for (final medicationDoc in medicationsQuery.docs) {
        final medicationData = medicationDoc.data();
        final elderlyId = medicationData['elderly_id'] as String;

        // Only include medications for elderly assigned to this nurse
        if (!assignedElderlyIds.contains(elderlyId)) continue;

        // Filter by shift and working days
        final medicationShift = medicationData['shift'] as String?;
        final workingDays = medicationData['working_days'] as List?;

        // Only include medications for current shift and current day
        if (medicationShift == currentShift &&
            workingDays != null &&
            workingDays.contains(currentDay)) {
          final takeStatuses =
              medicationData['take_statuses'] as List<dynamic>? ?? [];

          // Get elderly name
          final elderlyDoc = await _firestore
              .collection('elderly')
              .doc(elderlyId)
              .get();

          String elderlyName = 'Unknown';
          if (elderlyDoc.exists) {
            final elderlyData = elderlyDoc.data() as Map<String, dynamic>;
            elderlyName =
                '${elderlyData['elderly_fname'] ?? ''} ${elderlyData['elderly_lname'] ?? ''}'
                    .trim();
          }

          for (final take in takeStatuses) {
            final takeData = take as Map<String, dynamic>;
            final status = takeData['status'] as String;

            if (status == 'missed') {
              missedMedications.add({
                'id': medicationDoc.id,
                'elderly_id': elderlyId,
                'elderly_name': elderlyName,
                'medication_name': medicationData['medication_name'],
                'dosage': medicationData['dosage'],
                'take_number': takeData['take_number'],
                'scheduled_time': takeData['scheduled_time'],
                'repeat_interval': medicationData['repeat_interval'],
                'created_at': medicationData['created_at'],
                'created_nurse_name': medicationData['created_nurse_name'],
                'house_id': medicationData['house_id'],
                'shift': medicationData['shift'],
                'missed_at': takeData['missed_at'], // If available
              });
            }
          }
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
          .collection('medications')
          .where('house_id', isEqualTo: widget.houseId)
          .where('status', isEqualTo: 'upcoming')
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
                                      'Scheduled Time: ${medication['scheduled_time']}',
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
