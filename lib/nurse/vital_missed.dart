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
      // STEP 1: Get current nurse ID
      final nurseId = await _getNurseId();
      if (nurseId == null) {
        print('Could not find nurse ID for ${widget.nurseName}');
        return [];
      }

      // STEP 2: Get missed vitals from activity logs (with stored elderly names)
      final now = DateTime.now();
      final cutoffTime = now.subtract(Duration(hours: 72)); // Last 3 days
      final cutoffTimestamp = Timestamp.fromDate(cutoffTime);

      print('🔍 Getting missed vitals for ${widget.nurseName}...');
      print('🔍 Nurse ID: $nurseId');
      print('🔍 House ID: ${widget.houseId}');
      print('🔍 Cutoff timestamp: $cutoffTimestamp');

      // Query activity logs for missed vitals (has stored elderly names)
      // 🎯 ONLY show vitals that were originally PENDING (not already completed/missed)
      final missedLogsQuery = await _firestore
          .collection('vital_activity_logs')
          .where('house_id', isEqualTo: widget.houseId)
          .where('nurse_id', isEqualTo: nurseId)
          .where('action_type', isEqualTo: 'vital_missed')
          .where('timestamp', isGreaterThanOrEqualTo: cutoffTimestamp)
          .orderBy('timestamp', descending: true)
          .get();

      print(
        '🔍 Filtering missed logs to ONLY show originally PENDING vitals...',
      );

      print(
        '🔍 Found ${missedLogsQuery.docs.length} missed vital logs for this nurse',
      );

      final missedVitals = <Map<String, dynamic>>[];

      for (final logDoc in missedLogsQuery.docs) {
        final logData = logDoc.data();

        // 🎯 CRITICAL: Only include vitals that were originally PENDING
        final oldValue = logData['old_value'] as Map<String, dynamic>?;
        final originalStatus = oldValue?['status'] as String?;

        if (originalStatus != 'pending') {
          print(
            '⏭️ Skipping vital - was not originally PENDING (was: $originalStatus)',
          );
          continue;
        }

        // Use stored elderly name from activity log (no more "Unknown"!)
        final elderlyName =
            logData['elderly_name'] as String? ?? 'Unknown Elderly';
        final elderlyId = logData['elderly_id'] as String?;
        final vitalId = logData['vital_id'] as String?;

        print(
          '🏥 ✅ Found ORIGINALLY PENDING missed vital: $elderlyName (ID: $elderlyId)',
        );

        missedVitals.add({
          'assignment_id': vitalId,
          'elderly_id': elderlyId,
          'elderly_name': elderlyName, // ✅ Uses stored name from activity log
          'elderly_profilePic': '',
          'house_id': logData['house_id'],
          'last_vital': null,
          'status': 'missed',
          'missed_date': logData['assigned_date'],
          'missed_at': logData['timestamp'],
          'shift': logData['shift'],
          'nurse_name': widget.nurseName,
          'missed_reason': logData['remarks'] ?? 'Missed vital',
        });
      }

      print('🔍 Found ${missedVitals.length} missed vitals for this nurse');

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
    return Column(
      children: [
        // Main Content
        Expanded(
          child: Stack(
            children: [
              FutureBuilder<List<Map<String, dynamic>>>(
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
                                    Icons.check_circle_outline,
                                    size: 64,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'No missed vitals today',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Missed assignments from previous shifts will appear in your upcoming vitals',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                    textAlign: TextAlign.center,
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
                      itemCount: missedVitals.length,
                      itemBuilder: (context, index) {
                        final elderlyInfo = missedVitals[index];
                        final lastVital =
                            elderlyInfo['last_vital'] as Map<String, dynamic>?;

                        return Card(
                          margin: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
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
                                          elderlyInfo['elderly_profilePic']
                                                  ?.isNotEmpty ==
                                              true
                                          ? ClipOval(
                                              child: Image.network(
                                                elderlyInfo['elderly_profilePic'],
                                                fit: BoxFit.cover,
                                              ),
                                            )
                                          : Icon(
                                              Icons.person,
                                              color: Colors.white,
                                            ),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        elderlyInfo['elderly_name'] ??
                                            'Unknown',
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
                                    border: Border.all(
                                      color: Colors.red.withOpacity(0.3),
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.red.withOpacity(0.1),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.cancel,
                                        color: Colors.red,
                                        size: 24,
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                            onPressed: () =>
                                                _markAsCompleted(elderlyInfo),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                        if (lastVital['vital_record_at'] !=
                                            null)
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
