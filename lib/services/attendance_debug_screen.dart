import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'attendance_check_service.dart';

/// 🐛 DEBUG SCREEN FOR ATTENDANCE SYSTEM
/// ====================================
///
/// This screen helps administrators test and debug the attendance system.
/// Features:
/// - Manually trigger background check
/// - View today's attendance records
/// - View scheduled users
/// - Test attendance marking
///
/// **To access:** Add this screen to your admin menu or debug menu

class AttendanceDebugScreen extends StatefulWidget {
  const AttendanceDebugScreen({super.key});

  @override
  State<AttendanceDebugScreen> createState() => _AttendanceDebugScreenState();
}

class _AttendanceDebugScreenState extends State<AttendanceDebugScreen> {
  bool _isLoading = false;
  String _resultMessage = '';
  List<Map<String, dynamic>> _todaysAttendance = [];
  List<Map<String, dynamic>> _scheduledUsers = [];

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _loadTodaysAttendance();
    await _loadScheduledUsers();
  }

  Future<void> _loadTodaysAttendance() async {
    try {
      final now = DateTime.now();
      final dateString =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final snapshot = await _firestore
          .collection('attendance')
          .where('date', isEqualTo: dateString)
          .get();

      final List<Map<String, dynamic>> records = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        // Get user name
        try {
          final userDoc = await _firestore
              .collection('users')
              .doc(data['user_id'])
              .get();
          data['user_name'] = userDoc.data()?['name'] ?? 'Unknown';
        } catch (e) {
          data['user_name'] = 'Unknown';
        }
        records.add(data);
      }

      setState(() {
        _todaysAttendance = records;
      });
    } catch (e) {
      print('Error loading attendance: $e');
    }
  }

  Future<void> _loadScheduledUsers() async {
    try {
      final currentShift = AttendanceCheckService.getCurrentShift();
      final startTime = AttendanceCheckService.getShiftStartTime(currentShift);

      final snapshot = await _firestore
          .collection('house_shift_assignments')
          .where('is_current', isEqualTo: true)
          .where('start_time', isEqualTo: startTime)
          .get();

      final List<Map<String, dynamic>> users = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        // Get user name
        try {
          final userDoc = await _firestore
              .collection('users')
              .doc(data['user_id'])
              .get();
          data['user_name'] = userDoc.data()?['name'] ?? 'Unknown';
        } catch (e) {
          data['user_name'] = 'Unknown';
        }
        users.add(data);
      }

      setState(() {
        _scheduledUsers = users;
      });
    } catch (e) {
      print('Error loading scheduled users: $e');
    }
  }

  Future<void> _triggerBackgroundCheck() async {
    setState(() {
      _isLoading = true;
      _resultMessage = 'Running attendance check...';
    });

    try {
      // Trigger the attendance check directly
      await AttendanceCheckService.startPeriodicAttendanceCheck(context, () {
        // Callback when attendance is checked
        print('Attendance checked from debug screen');
      });

      // Wait a bit for the check to complete
      await Future.delayed(const Duration(seconds: 2));

      // Reload data
      await _loadData();

      setState(() {
        _resultMessage = '✅ Attendance check completed successfully!';
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attendance check completed!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _resultMessage = '❌ Error: $e';
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentShift = AttendanceCheckService.getCurrentShift();
    final shiftStart = AttendanceCheckService.getShiftStartTime(currentShift);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Debug'),
        backgroundColor: const Color(0xFF00588E),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current Time Info
            _buildInfoCard(
              title: 'Current Time',
              children: [
                _buildInfoRow(
                  'Time',
                  '${now.hour}:${now.minute.toString().padLeft(2, '0')}',
                ),
                _buildInfoRow('Date', '${now.year}-${now.month}-${now.day}'),
                _buildInfoRow('Current Shift', '$currentShift Shift'),
                _buildInfoRow('Shift Start', shiftStart),
              ],
            ),
            const SizedBox(height: 16),

            // Manual Trigger Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _triggerBackgroundCheck,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh),
                label: Text(
                  _isLoading ? 'Running...' : 'Trigger Background Check',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00588E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),

            if (_resultMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _resultMessage.startsWith('✅')
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _resultMessage.startsWith('✅')
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
                child: Text(
                  _resultMessage,
                  style: TextStyle(
                    color: _resultMessage.startsWith('✅')
                        ? Colors.green.shade900
                        : Colors.red.shade900,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Scheduled Users
            _buildInfoCard(
              title: 'Scheduled for Current Shift (${_scheduledUsers.length})',
              children: _scheduledUsers.isEmpty
                  ? [
                      const Text(
                        'No users scheduled',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ]
                  : _scheduledUsers.map((user) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.person,
                              size: 16,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(user['user_name'] ?? 'Unknown'),
                            ),
                            Text(
                              user['user_type'] ?? '',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
            ),

            const SizedBox(height: 16),

            // Today's Attendance
            _buildInfoCard(
              title:
                  'Today\'s Attendance Records (${_todaysAttendance.length})',
              children: _todaysAttendance.isEmpty
                  ? [
                      const Text(
                        'No attendance records today',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ]
                  : _todaysAttendance.map((record) {
                      final isPresent = record['is_present'] ?? false;
                      final markedBy = record['marked_by'] ?? 'unknown';
                      final shift = record['shift'] ?? '';

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isPresent
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isPresent ? Colors.green : Colors.red,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isPresent ? Icons.check_circle : Icons.cancel,
                                  color: isPresent ? Colors.green : Colors.red,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    record['user_name'] ?? 'Unknown',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isPresent
                                        ? Colors.green
                                        : Colors.red,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    isPresent ? 'PRESENT' : 'ABSENT',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Shift: $shift | Marked by: $markedBy',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            if (record['reason'] != null &&
                                record['reason'].toString().isNotEmpty)
                              Text(
                                'Reason: ${record['reason']}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
            ),

            const SizedBox(height: 24),

            // Instructions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Testing Instructions',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '1. Check "Scheduled for Current Shift" to see who should be working\n'
                    '2. Click "Trigger Background Check" to manually run the absent marking\n'
                    '3. Check "Today\'s Attendance Records" to see results\n'
                    '4. Users marked by "system_background" were auto-marked as absent\n'
                    '5. Background service runs automatically every 15 minutes',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00588E),
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
