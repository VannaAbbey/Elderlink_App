import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'vital_update_screen.dart';

class FollowUpVitalsSelectionScreen extends StatefulWidget {
  final String? nurseName;
  final String houseId;

  const FollowUpVitalsSelectionScreen({
    super.key,
    required this.nurseName,
    required this.houseId,
  });

  @override
  State<FollowUpVitalsSelectionScreen> createState() =>
      _FollowUpVitalsSelectionScreenState();
}

class _FollowUpVitalsSelectionScreenState
    extends State<FollowUpVitalsSelectionScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _assignedElderly = [];
  bool _isLoading = true;

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

  String _getTodayDateString() {
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  @override
  void initState() {
    super.initState();
    _loadAssignedElderly();
  }

  Future<String?> _getNurseId() async {
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
  }

  Future<void> _loadAssignedElderly() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final nurseId = await _getNurseId();
      if (nurseId == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final today = _getTodayDateString();
      final currentShift = _getCurrentShift();

      print('🔍 Loading elderly for follow-up...');
      print('Nurse: ${widget.nurseName} ($nurseId)');
      print('House: ${widget.houseId}');
      print('Date: $today');
      print('Current Shift: $currentShift');

      // Query vitals_daily for today in this house
      final vitalsQuery = await _firestore
          .collection('vitals_daily')
          .where('house_id', isEqualTo: widget.houseId)
          .where('assigned_date', isEqualTo: today)
          .get();

      print('📋 Found ${vitalsQuery.docs.length} vitals_daily documents');

      final elderlyList = <Map<String, dynamic>>[];

      for (final vitalDoc in vitalsQuery.docs) {
        final vitalData = vitalDoc.data();
        final elderlyId = vitalData['elderly_id'];
        final elderlyName = vitalData['elderly_name'] ?? 'Unknown';
        final shiftStatus =
            vitalData['shift_status'] as Map<String, dynamic>? ?? {};
        final vitalValues =
            vitalData['vital_values'] as Map<String, dynamic>? ?? {};

        // Check if ANY shift has been completed (has vital values)
        bool hasCompletedShift = false;
        String? completedShift;
        Map<String, dynamic>? completedShiftStatus;

        for (final shift in ['1st', '2nd', '3rd']) {
          final shiftData = shiftStatus[shift] as Map<String, dynamic>?;
          if (shiftData != null && shiftData['status'] == 'completed') {
            hasCompletedShift = true;
            completedShift = shift;
            completedShiftStatus = shiftData;
            break; // Take the first completed shift found
          }
        }

        // Can follow up if ANY shift has been completed
        final canFollowUp = hasCompletedShift;

        elderlyList.add({
          'elderly_id': elderlyId,
          'elderly_name': elderlyName,
          'vitals_id': vitalDoc.id,
          'assigned_date': today,
          'can_follow_up': canFollowUp,
          'completed_shift': completedShift ?? 'N/A',
          'completed_by_nurse':
              completedShiftStatus?['completed_by_nurse_name'] ?? 'None',
          'previous_vitals': canFollowUp ? vitalValues : null,
          'shift_status': shiftStatus,
        });
      }

      // Sort: completed vitals first (eligible for follow-up), then pending
      elderlyList.sort((a, b) {
        if (a['can_follow_up'] != b['can_follow_up']) {
          return a['can_follow_up'] ? -1 : 1;
        }
        return a['elderly_name'].compareTo(b['elderly_name']);
      });

      setState(() {
        _assignedElderly = elderlyList;
        _isLoading = false;
      });

      print('✅ Loaded ${elderlyList.length} elderly for follow-up');
    } catch (e) {
      print('❌ Error loading assigned elderly: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _recordFollowUpVitals(Map<String, dynamic> elderlyInfo) async {
    // Navigate to VitalUpdateScreen to record follow-up vitals
    // The vitals_daily document already exists, we're just updating it for current shift
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VitalUpdateScreen(
          vitalsId: elderlyInfo['vitals_id'],
          elderlyId: elderlyInfo['elderly_id'],
          elderlyName: elderlyInfo['elderly_name'],
          assignedDate: elderlyInfo['assigned_date'],
          houseId: widget.houseId,
        ),
      ),
    );

    if (result == true && mounted) {
      // Refresh the list
      _loadAssignedElderly();
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';

    DateTime dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    } else {
      return timestamp.toString();
    }

    return DateFormat('MMM dd, hh:mm a').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Follow-up Vitals Selection',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Color(0xFF00588E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _assignedElderly.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No assignments found',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No elderly vitals available for follow-up',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Header with instructions
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  margin: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Color(0xFFBBDEFB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Color(0xFF00588E)),
                          SizedBox(width: 8),
                          Text(
                            'Follow-up Vitals Recording',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00588E),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Select an elderly to record follow-up vitals. You can record follow-ups for elderly who have completed vitals in any previous shift.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF00588E),
                        ),
                      ),
                    ],
                  ),
                ),

                // List of assigned elderly
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _assignedElderly.length,
                    itemBuilder: (context, index) {
                      final elderlyInfo = _assignedElderly[index];
                      final canFollowUp = elderlyInfo['can_follow_up'] as bool;
                      final previousVitals =
                          elderlyInfo['previous_vitals']
                              as Map<String, dynamic>?;

                      return Card(
                        margin: EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: canFollowUp
                                        ? Color(0xFF00588E)
                                        : Colors.grey[400],
                                    radius: 24,
                                    child: Icon(
                                      Icons.person,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          elderlyInfo['elderly_name'],
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF2C3E50),
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: canFollowUp
                                                ? Color(0xFFE3F2FD)
                                                : Colors.grey[200],
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          child: Text(
                                            canFollowUp
                                                ? '✅ Completed by ${elderlyInfo['completed_by_nurse'] ?? 'Unknown'} (${elderlyInfo['completed_shift'] ?? 'Unknown'} shift)'
                                                : '⏳ Vitals Pending',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: canFollowUp
                                                  ? Color(0xFF00588E)
                                                  : Colors.grey[600],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              // Show previous vitals if completed
                              if (canFollowUp && previousVitals != null) ...[
                                SizedBox(height: 20),
                                Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey[200]!,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.monitor_heart,
                                            size: 16,
                                            color: Colors.grey[600],
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Previous Vitals',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 12),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (previousVitals['blood_pressure'] !=
                                              null)
                                            Text(
                                              'BP: ${previousVitals['blood_pressure']}',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          if (previousVitals['pulse_rate'] !=
                                              null)
                                            Text(
                                              'HR: ${previousVitals['pulse_rate']} bpm',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          if (previousVitals['temperature'] !=
                                              null)
                                            Text(
                                              'Temp: ${previousVitals['temperature']}°C',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          if (previousVitals['oxygen_saturation'] !=
                                              null)
                                            Text(
                                              'O2: ${previousVitals['oxygen_saturation']}%',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          if (previousVitals['respiratory_rate'] !=
                                              null)
                                            Text(
                                              'RR: ${previousVitals['respiratory_rate']} breaths/min',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              // Follow-up button at bottom
                              if (canFollowUp) ...[
                                SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  height: 45,
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _recordFollowUpVitals(elderlyInfo),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Color(0xFF00588E),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    icon: Icon(
                                      Icons.add_circle_outline,
                                      size: 20,
                                    ),
                                    label: Text(
                                      'Record Follow-up Vitals',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ] else ...[
                                SizedBox(height: 16),
                                Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Complete Initial Vitals First',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
