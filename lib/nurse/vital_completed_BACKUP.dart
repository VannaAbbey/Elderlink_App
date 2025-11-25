import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  String _getTodayDateString() {
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  Future<String?> _getCurrentNurseId() async {
    // Use the authenticated user's UID directly for reliable nurse identification
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('No authenticated user found');
      return null;
    }
    return user.uid;
  }

  Future<List<Map<String, dynamic>>> _getCompletedVitals() async {
    try {
      final today = _getTodayDateString();

      // Get nurse ID using Firebase Auth UID (same as upcoming vitals)
      final nurseId = await _getCurrentNurseId();
      if (nurseId == null) {
        print('Could not get current nurse ID');
        return [];
      }

      print('🔍 Getting completed vitals recorded by: $nurseId');
      print('🏠 House: ${widget.houseId}, Date: $today');

      // Query completed vitals by the current nurse for the house
      // Note: We can't filter by completion date in Firestore query due to timestamp limitations
      // So we'll get all completed vitals and filter by date in code
      final completedVitalsQuery = await _firestore
          .collection('vitals')
          .where('house_id', isEqualTo: widget.houseId)
          .where('status', isEqualTo: 'completed')
          .where('recorded_by', isEqualTo: nurseId)
          .get();

      print(
        '✅ Found ${completedVitalsQuery.docs.length} completed vitals total',
      );

      // Filter by completion date in code
      final filteredDocs = completedVitalsQuery.docs.where((doc) {
        final data = doc.data();
        final completedAt = data['completed_at'] as Timestamp?;
        if (completedAt == null) return false;

        final completedDate = DateFormat(
          'yyyy-MM-dd',
        ).format(completedAt.toDate());
        return completedDate == today;
      }).toList();

      print('✅ Found ${filteredDocs.length} completed vitals for today');

      // Build a list of completed vitals and collect elderly IDs
      final completedVitals = <Map<String, dynamic>>[];
      final elderlyIdSet = <String>{};
      for (final vitalDoc in filteredDocs) {
        final vitalData = vitalDoc.data();
        final elderlyId = vitalData['elderly_id'] ?? '';
        elderlyIdSet.add(elderlyId);
        completedVitals.add({
          'vital_id': vitalDoc.id,
          'assignment_id': vitalDoc.id,
          'elderly_id': elderlyId,
          'blood_pressure': vitalData['blood_pressure'] ?? 'N/A',
          'pulse_rate': vitalData['pulse_rate'] ?? 'N/A',
          'oxygen_saturation': vitalData['oxygen_saturation'] ?? 'N/A',
          'temperature': vitalData['temperature'] ?? 'N/A',
          'respiratory_rate': vitalData['respiratory_rate'] ?? 'N/A',
          'remarks': vitalData['remarks'] ?? '',
          'completed_at': vitalData['completed_at'],
          'created_at': vitalData['created_at'],
          'recorded_by': vitalData['recorded_by'] ?? nurseId,
          'recorded_by_name': vitalData['recorded_by_name'] ?? 'Unknown Nurse',
          'status': 'completed',
          'shift': vitalData['shift'] ?? 'Unknown',
          'assigned_date': vitalData['assigned_date'] ?? '',
          'inherited_from': vitalData['inherited_from'],
        });
      }

      // Fetch elderly names in batches (Firestore whereIn limit is 10)
      final elderlyNames = <String, String>{};
      final elderlyIds = elderlyIdSet.where((id) => id.isNotEmpty).toList();
      for (var i = 0; i < elderlyIds.length; i += 10) {
        final chunk = elderlyIds.sublist(
          i,
          i + 10 > elderlyIds.length ? elderlyIds.length : i + 10,
        );
        final elderlyQuery = await _firestore
            .collection('elderly')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in elderlyQuery.docs) {
          final data = doc.data();
          final fname = data['elderly_fname']?.toString().trim();
          final lname = data['elderly_lname']?.toString().trim();
          String elderlyName = '';
          if (fname != null &&
              fname.isNotEmpty &&
              lname != null &&
              lname.isNotEmpty) {
            elderlyName = '$fname $lname';
          } else if (fname != null && fname.isNotEmpty) {
            elderlyName = fname;
          } else if (lname != null && lname.isNotEmpty) {
            elderlyName = lname;
          } else {
            elderlyName = 'Unnamed Elderly';
          }
          elderlyNames[doc.id] = elderlyName;
        }
      }

      // Attach elderly name to each completed vital
      for (final vital in completedVitals) {
        final elderlyId = vital['elderly_id'] ?? '';
        vital['elderly_name'] = elderlyNames[elderlyId] ?? 'Unnamed Elderly';
      }

      // Sort by completion time (most recent first)
      completedVitals.sort((a, b) {
        final aTime = a['completed_at'] != null
            ? (a['completed_at'] as Timestamp).toDate()
            : DateTime.now();
        final bTime = b['completed_at'] != null
            ? (b['completed_at'] as Timestamp).toDate()
            : DateTime.now();
        return bTime.compareTo(aTime);
      });

      print(
        '🏁 Returning ${completedVitals.length} completed vitals for display',
      );
      return completedVitals;
    } catch (e) {
      print('Error getting completed vitals: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Main Content
        Expanded(
          child: Stack(
            children: [
              FutureBuilder<List<Map<String, dynamic>>>(
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
                    return RefreshIndicator(
                      onRefresh: () async {
                        setState(() {});
                      },
                      child: ListView(
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height - 200,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.assignment_turned_in,
                                    size: 64,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'No completed vitals today',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      setState(() {});
                    },
                    child: ListView.builder(
                      padding: EdgeInsets.only(bottom: 80),
                      itemCount: completedVitals.length,
                      itemBuilder: (context, index) {
                        final vital = completedVitals[index];

                        return Card(
                          margin: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          color: const Color(0xFFE6F3FA),
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
                                      child: Icon(
                                        Icons.person,
                                        color: Colors.white,
                                      ),
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
                                    color: Colors.white,
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    'COMPLETE',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                              'Recorded by: ${vital['recorded_by_name'] ?? 'Unknown'}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[700],
                                              ),
                                            ),
                                            if (vital['completed_at'] != null)
                                              Text(
                                                'Completed: ${DateFormat('MMM dd, yyyy h:mm a').format((vital['completed_at'] as Timestamp).toDate())}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                            // 🆕 ENHANCED: Show shift information
                                            Text(
                                              'Shift: ${vital['shift'] ?? 'Unknown'}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                                fontWeight: FontWeight.w500,
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
                                    border: Border.all(
                                      color: Colors.blue.withOpacity(0.3),
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.white,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Blood Pressure:',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Text(
                                                  '${vital['blood_pressure'] ?? 'N/A'}',
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Pulse Rate:',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Text(
                                                  '${vital['pulse_rate'] ?? 'N/A'} bpm',
                                                ),
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
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'O₂ Saturation:',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Text(
                                                  '${vital['oxygen_saturation'] ?? 'N/A'}%',
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Temperature:',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Text(
                                                  '${vital['temperature'] ?? 'N/A'}°C',
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 8),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Respiratory Rate:',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            '${vital['respiratory_rate'] ?? 'N/A'} breaths/min',
                                          ),
                                        ],
                                      ),
                                      if (vital['remarks']?.isNotEmpty ==
                                          true) ...[
                                        SizedBox(height: 8),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Remarks:',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text('${vital['remarks']}'),
                                          ],
                                        ),
                                      ],

                                      // ✅ Show inheritance info if applicable
                                      if (vital['inherited_from']?.isNotEmpty ==
                                          true) ...[
                                        SizedBox(height: 8),
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withOpacity(
                                              0.1,
                                            ),
                                            border: Border.all(
                                              color: Colors.orange.withOpacity(
                                                0.3,
                                              ),
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.transfer_within_a_station,
                                                size: 16,
                                                color: Colors.orange,
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                'Inherited from: ${vital['inherited_from']}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.orange[700],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
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
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
