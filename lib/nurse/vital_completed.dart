import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CompletedVitalsTab extends StatefulWidget {
  final String houseId;
  final String? nurseName;

  const CompletedVitalsTab({
    super.key,
    required this.houseId,
    required this.nurseName,
  });

  @override
  State<CompletedVitalsTab> createState() => _CompletedVitalsTabState();
}

class _CompletedVitalsTabState extends State<CompletedVitalsTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

  String _getTodayDateString() {
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  Future<List<Map<String, dynamic>>> _getCompletedVitals() async {
    try {
      final currentShift = _getCurrentShift();

      // Get nurse ID using same logic as upcoming vitals
      final nameParts = widget.nurseName?.split(' ') ?? [];
      if (nameParts.length < 2) {
        print('Invalid nurse name format: ${widget.nurseName}');
        return [];
      }

      final firstName = nameParts[0];
      final lastName = nameParts[1];

      final userQuery = await _firestore
          .collection('users')
          .where('user_fname', isEqualTo: firstName)
          .where('user_lname', isEqualTo: lastName)
          .where('user_type', isEqualTo: 'nurse')
          .get();

      if (userQuery.docs.isEmpty) {
        print('No nurse found with name: $firstName $lastName');
        return [];
      }

      final nurseId = userQuery.docs.first.id;
      final today = _getTodayDateString();

      print(
        'Getting completed vitals for nurse: $nurseId, date: $today, shift: $currentShift',
      );

      // Debug: Check ALL assignments first
      final allAssignmentsQuery = await _firestore
          .collection('daily_vital_assignments')
          .where('house_id', isEqualTo: widget.houseId)
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .where('assigned_nurse_id', isEqualTo: nurseId)
          .get();

      print('🔍 DEBUG: All assignments for house ${widget.houseId}:');
      for (final doc in allAssignmentsQuery.docs) {
        final data = doc.data();
        print('   - ${data['elderly_name']} → Status: ${data['status']}');
      }

      // Get completed vital assignments for today
      final completedAssignments = await _firestore
          .collection('daily_vital_assignments')
          .where('house_id', isEqualTo: widget.houseId)
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .where('assigned_nurse_id', isEqualTo: nurseId)
          .where('status', isEqualTo: 'completed')
          .get();

      print(
        'Found ${completedAssignments.docs.length} completed assignments out of ${allAssignmentsQuery.docs.length} total',
      );

      // Debug: Print completed assignments details
      print('🟢 DEBUG: Completed assignments found:');
      for (final doc in completedAssignments.docs) {
        final data = doc.data();
        print('   - Assignment ID: ${doc.id}');
        print('   - Elderly: ${data['elderly_name']}');
        print('   - Status: ${data['status']}');
        print('   - Completed At: ${data['completed_at']}');
      }

      final completedVitals = <Map<String, dynamic>>[];

      for (final assignmentDoc in completedAssignments.docs) {
        final assignmentData = assignmentDoc.data();

        print(
          '🔍 Checking completed assignment: ${assignmentData['elderly_name']}',
        );
        print('   - Assignment ID: ${assignmentDoc.id}');
        print('   - Elderly ID: ${assignmentData['elderly_id']}');

        // Get vital record using assignment_id to connect the collections properly
        final vitalQuery = await _firestore
            .collection('vitals')
            .where('assignment_id', isEqualTo: assignmentDoc.id)
            .limit(1)
            .get();

        print(
          '   - Found ${vitalQuery.docs.length} vital records for this assignment',
        );

        if (vitalQuery.docs.isNotEmpty) {
          final vitalData = vitalQuery.docs.first.data();
          print('   ✅ Found vital data with proper assignment_id connection');

          // Add vital record with actual data
          completedVitals.add({
            'assignment_id': assignmentDoc.id,
            'elderly_id': assignmentData['elderly_id'],
            'elderly_name': assignmentData['elderly_name'],
            'elderly_profilePic': assignmentData['elderly_profilePic'] ?? '',
            'blood_pressure': vitalData['blood_pressure'] ?? 'N/A',
            'pulse_rate': vitalData['pulse_rate'] ?? 'N/A',
            'o2_sat': vitalData['o2_sat'] ?? 'N/A',
            'temperature': vitalData['temperature'] ?? 'N/A',
            'respiratory_rate': vitalData['respiratory_rate'] ?? 'N/A',
            'vital_remarks': vitalData['vital_remarks'] ?? '',
            'updated_at': assignmentData['updated_at'],
            'updated_by_nurse':
                vitalData['updated_by_nurse_name'] ??
                assignmentData['assigned_nurse_name'],
            'updated_by_nurse_id':
                vitalData['updated_by_nurse_id'] ??
                assignmentData['assigned_nurse_id'],
            'vital_record_at': vitalData['vital_record_at'],
            'status': 'completed',
          });
        } else {
          print(
            '   ❌ No vital record found for assignment: ${assignmentDoc.id}',
          );
          print(
            '   📊 Assignment marked as completed but no vital data exists yet',
          );

          // Still add to completed list but with placeholder data
          completedVitals.add({
            'assignment_id': assignmentDoc.id,
            'elderly_id': assignmentData['elderly_id'],
            'elderly_name': assignmentData['elderly_name'],
            'elderly_profilePic': assignmentData['elderly_profilePic'] ?? '',
            'blood_pressure': 'Pending',
            'pulse_rate': 'Pending',
            'o2_sat': 'Pending',
            'temperature': 'Pending',
            'respiratory_rate': 'Pending',
            'vital_remarks': 'Data entry in progress',
            'updated_at': assignmentData['updated_at'],
            'updated_by_nurse': assignmentData['assigned_nurse_name'],
            'updated_by_nurse_id': assignmentData['assigned_nurse_id'],
            'vital_record_at':
                assignmentData['completed_at'] ?? assignmentData['updated_at'],
            'status': 'completed',
          });
        }
      }

      // Sort by record time (most recent first)
      completedVitals.sort((a, b) {
        final aTime = a['vital_record_at'] != null
            ? (a['vital_record_at'] as Timestamp).toDate()
            : DateTime.now();
        final bTime = b['vital_record_at'] != null
            ? (b['vital_record_at'] as Timestamp).toDate()
            : DateTime.now();
        return bTime.compareTo(aTime);
      });

      return completedVitals;
    } catch (e) {
      print('Error getting completed vitals: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getCompletedVitals(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final completedVitals = snapshot.data ?? [];

        if (completedVitals.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_turned_in, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No completed vitals today',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.symmetric(vertical: 8),
          itemCount: completedVitals.length,
          itemBuilder: (context, index) {
            final vital = completedVitals[index];

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
                          child: vital['elderly_profilePic']?.isNotEmpty == true
                              ? ClipOval(
                                  child: Image.network(
                                    vital['elderly_profilePic'],
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Icon(Icons.person, color: Colors.white),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            vital['elderly_name'] ?? 'Unknown',
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

                    // Completed Status
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
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'COMPLETE',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Updated Today',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Updated by: ${vital['updated_by_nurse'] ?? 'Unknown'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                if (vital['vital_record_at'] != null)
                                  Text(
                                    'Completed: ${DateFormat('MMM dd, yyyy HH:mm').format((vital['vital_record_at'] as Timestamp).toDate())}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 12),

                    // Vital Signs Details
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.blue.withOpacity(0.1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vital Signs',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF00588E),
                            ),
                          ),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Blood Pressure:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text('${vital['blood_pressure'] ?? 'N/A'}'),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Pulse Rate:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text('${vital['pulse_rate'] ?? 'N/A'} bpm'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'O₂ Saturation:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text('${vital['o2_sat'] ?? 'N/A'}%'),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Temperature:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text('${vital['temperature'] ?? 'N/A'}°C'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Respiratory Rate:',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${vital['respiratory_rate'] ?? 'N/A'} breaths/min',
                              ),
                            ],
                          ),
                          if (vital['vital_remarks']?.isNotEmpty == true) ...[
                            SizedBox(height: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Remarks:',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text('${vital['vital_remarks']}'),
                              ],
                            ),
                          ],
                        ],
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
  }
}
