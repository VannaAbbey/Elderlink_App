import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CompletedMedicationsTab extends StatefulWidget {
  final String houseId;
  final String? nurseName;

  const CompletedMedicationsTab({
    super.key,
    required this.houseId,
    required this.nurseName,
  });

  @override
  State<CompletedMedicationsTab> createState() =>
      _CompletedMedicationsTabState();
}

class _CompletedMedicationsTabState extends State<CompletedMedicationsTab> {
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _getNurseId(),
      builder: (context, nurseIdSnapshot) {
        if (nurseIdSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final nurseId = nurseIdSnapshot.data;
        if (nurseId == null) {
          return const Center(child: Text('Unable to identify nurse'));
        }

        return StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('medication_activity_logs')
              .where('house_id', isEqualTo: widget.houseId)
              .where('action', isEqualTo: 'complete_take')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              print('Error loading completed medications: ${snapshot.error}');
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // Filter by nurse ID in code and sort by completion date
            final allLogs = snapshot.data?.docs ?? [];
            print('Total completed medication logs in DB: ${allLogs.length}');

            final completedLogs =
                allLogs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final isCompletedByCurrentNurse = data['nurse_id'] == nurseId;
                  if (isCompletedByCurrentNurse) {
                    print(
                      'Found completed medication: ${data['medication_name']} for ${data['elderly_name']}',
                    );
                  }
                  return isCompletedByCurrentNurse;
                }).toList()..sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aTime = (aData['timestamp'] as Timestamp).toDate();
                  final bTime = (bData['timestamp'] as Timestamp).toDate();
                  return bTime.compareTo(
                    aTime,
                  ); // Descending order (newest first)
                });

            print(
              'Filtered completed medications for this nurse: ${completedLogs.length}',
            );

            if (completedLogs.isEmpty) {
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
                      'No completed medications',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: EdgeInsets.symmetric(vertical: 8),
              itemCount: completedLogs.length,
              itemBuilder: (context, index) {
                final log = completedLogs[index].data() as Map<String, dynamic>;
                final completedAt = (log['timestamp'] as Timestamp).toDate();
                final takeOrdinal = _getOrdinal(log['take_number'] as int);

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
                                log['elderly_name'] ?? 'Unknown',
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
                            Icon(Icons.medication, color: Colors.green),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${log['medication_name']} - ${log['dosage']}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),

                        // Completed Take Information
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.green.withOpacity(0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.green.withOpacity(0.1),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 24,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$takeOrdinal Take - COMPLETED',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.green,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Scheduled Time: ${log['scheduled_time'] ?? 'Not specified'}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Completed: ${DateFormat('MMM dd, yyyy HH:mm').format(completedAt)}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Created timestamp (smaller and at bottom)
                        if (log['timestamp'] != null)
                          Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              'Created: ${DateFormat('MMM dd, yyyy HH:mm').format((log['timestamp'] as Timestamp).toDate())}',
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
