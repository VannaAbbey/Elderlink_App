import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'vital_update_screen.dart';

class MissedVitalsTab extends StatefulWidget {
  final String houseId;
  final String? nurseName;

  const MissedVitalsTab({
    super.key,
    required this.houseId,
    required this.nurseName,
  });

  @override
  State<MissedVitalsTab> createState() => _MissedVitalsTabState();
}

class _MissedVitalsTabState extends State<MissedVitalsTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

  Future<List<Map<String, dynamic>>> _getMissedVitals() async {
    try {
      // Get missed vitals from activity logs where nurse_name matches current nurse
      final missedLogsQuery = await _firestore
          .collection('vital_activity_logs')
          .where('house_id', isEqualTo: widget.houseId)
          .where('action_type', isEqualTo: 'vital_missed')
          .where('nurse_name', isEqualTo: widget.nurseName)
          .get();

      final missedVitals = <Map<String, dynamic>>[];

      for (final logDoc in missedLogsQuery.docs) {
        final logData = logDoc.data();

        missedVitals.add({
          'assignment_id': logData['vital_id'],
          'elderly_id': logData['elderly_id'],
          'elderly_name': logData['elderly_name'],
          'elderly_profilePic': '',
          'house_id': logData['house_id'],
          'last_vital': null, // Could be fetched if needed
          'status': 'missed',
          'missed_date': DateFormat(
            'yyyy-MM-dd',
          ).format((logData['timestamp'] as Timestamp).toDate()),
          'missed_at': logData['timestamp'],
          'shift': logData['shift'],
          'nurse_name': logData['nurse_name'],
        });
      }

      // Sort by timestamp (most recent first)
      missedVitals.sort((a, b) {
        final aTimestamp = a['missed_at'] as Timestamp?;
        final bTimestamp = b['missed_at'] as Timestamp?;

        if (aTimestamp == null && bTimestamp == null) return 0;
        if (aTimestamp == null) return 1;
        if (bTimestamp == null) return -1;

        return bTimestamp.compareTo(aTimestamp); // Descending order
      });

      return missedVitals;
    } catch (e) {
      print('Error getting missed vitals: $e');
      return [];
    }
  }

  Future<void> _markAsCompleted(Map<String, dynamic> elderlyInfo) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VitalUpdateScreen(
          assignmentId: elderlyInfo['assignment_id'],
          elderlyId: elderlyInfo['elderly_id'],
          elderlyName: elderlyInfo['elderly_name'],
          nurseName: widget.nurseName,
          houseId: widget.houseId,
        ),
      ),
    );

    // Refresh the list if vitals were updated
    if (result == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getMissedVitals(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final missedVitals = snapshot.data ?? [];

        if (missedVitals.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No missed vitals today',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text(
                  'Missed assignments from previous shifts will appear in your upcoming vitals',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.symmetric(vertical: 8),
          itemCount: missedVitals.length,
          itemBuilder: (context, index) {
            final elderlyInfo = missedVitals[index];
            final lastVital =
                elderlyInfo['last_vital'] as Map<String, dynamic>?;

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
                        CircleAvatar(
                          backgroundColor: const Color(0xFF00588E),
                          child:
                              elderlyInfo['elderly_profilePic']?.isNotEmpty ==
                                  true
                              ? ClipOval(
                                  child: Image.network(
                                    elderlyInfo['elderly_profilePic'],
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Icon(Icons.person, color: Colors.white),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            elderlyInfo['elderly_name'] ?? 'Unknown',
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

                    // Missed Status
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
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
                                  'VITALS MISSED',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.red,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'No vitals recorded today',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                Text(
                                  'Assigned to: ${elderlyInfo['assigned_nurse_id'] ?? 'Unknown'}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            children: [
                              ElevatedButton(
                                onPressed: () => _markAsCompleted(elderlyInfo),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                child: Text(
                                  'Update Now',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Last vital info if available
                    if (lastVital != null) ...[
                      SizedBox(height: 12),
                      Text(
                        'Last recorded vitals:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.3),
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.withOpacity(0.1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'BP: ${lastVital['blood_pressure'] ?? 'N/A'}',
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'Pulse: ${lastVital['pulse_rate'] ?? 'N/A'}',
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'O₂: ${lastVital['o2_sat'] ?? 'N/A'}%',
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'Temp: ${lastVital['temperature'] ?? 'N/A'}°C',
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Text(
                              'RR: ${lastVital['respiratory_rate'] ?? 'N/A'}',
                            ),
                            if (lastVital['vital_record_at'] != null)
                              Text(
                                'Recorded: ${DateFormat('MMM dd, yyyy HH:mm').format((lastVital['vital_record_at'] as Timestamp).toDate())}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
