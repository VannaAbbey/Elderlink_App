import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VitalMissed extends StatefulWidget {
  final String houseId;

  const VitalMissed({super.key, required this.houseId});

  @override
  State<VitalMissed> createState() => _VitalMissedState();
}

class _VitalMissedState extends State<VitalMissed> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _getCurrentShift() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 14) return '1st';
    if (hour >= 14 && hour < 22) return '2nd';
    return '3rd';
  }

  // For early-morning hours consider previous day's assigned_date
  String _getTodayDateString() {
    final now = DateTime.now();
    final currentHour = now.hour;
    if (currentHour >= 0 && currentHour < 6) {
      final previousDay = now.subtract(const Duration(days: 1));
      return DateFormat('yyyy-MM-dd').format(previousDay);
    }
    return DateFormat('yyyy-MM-dd').format(now);
  }

  Future<Set<String>> _getAssignedElderlyIds(
    String nurseId,
    String shift,
  ) async {
    final day = DateFormat('EEEE').format(DateTime.now());
    final Set<String> elderlyIds = {};
    try {
      final assignmentsSnapshot = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('day', isEqualTo: day)
          .where('shift', isEqualTo: shift)
          .get();

      for (final doc in assignmentsSnapshot.docs) {
        final data = doc.data();
        final ids = List<String>.from(data['elderly_ids'] ?? []);
        elderlyIds.addAll(ids);
      }
    } catch (e) {
      // keep app running; return empty set on error
      print(' [_getAssignedElderlyIds] Error: $e');
    }
    return elderlyIds;
  }

  Stream<List<Map<String, dynamic>>> _getMissedVitalsStream() async* {
    final currentShift = _getCurrentShift();
    final today = _getTodayDateString();

    final user = FirebaseAuth.instance.currentUser;
    final nurseId = user?.uid;
    if (nurseId == null) {
      yield <Map<String, dynamic>>[];
      return;
    }

    await for (final snapshot
        in _firestore
            .collection('vitals_daily')
            .where('house_id', isEqualTo: widget.houseId)
            .where('assigned_date', isEqualTo: today)
            .where('any_missed', isEqualTo: true)
            .snapshots()) {
      final assignedElderly = await _getAssignedElderlyIds(
        nurseId,
        currentShift,
      );

      final List<Map<String, dynamic>> missedVitals = [];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final elderlyId = data['elderly_id'] as String?;
        if (elderlyId == null || !assignedElderly.contains(elderlyId)) continue;

        final shiftStatus = data['shift_status'] as Map<String, dynamic>?;
        if (shiftStatus == null || shiftStatus[currentShift] == null) continue;

        final currentShiftData =
            shiftStatus[currentShift] as Map<String, dynamic>;
        if (currentShiftData['status'] == 'missed') {
          missedVitals.add({
            'vitals_id': doc.id,
            'elderly_id': elderlyId,
            'elderly_name': data['elderly_name'],
            'house_id': data['house_id'],
            'assigned_date': data['assigned_date'],
            'shift': currentShift,
            'missed_reason':
                currentShiftData['missed_reason'] ?? 'No reason provided',
            'marked_at': currentShiftData['marked_at'],
          });
        }
      }

      missedVitals.sort((a, b) {
        final aTime = a['marked_at'] != null
            ? (a['marked_at'] as Timestamp).toDate()
            : DateTime.now();
        final bTime = b['marked_at'] != null
            ? (b['marked_at'] as Timestamp).toDate()
            : DateTime.now();
        return bTime.compareTo(aTime);
      });

      yield missedVitals;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getMissedVitalsStream(),
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
                Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No missed vitals for ${_getCurrentShift()} shift',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: missedVitals.length,
          padding: const EdgeInsets.all(8),
          itemBuilder: (context, index) {
            final vital = missedVitals[index];
            return _buildMissedCard(vital);
          },
        );
      },
    );
  }

  Widget _buildMissedCard(Map<String, dynamic> vital) {
    final markedTime = vital['marked_at'] != null
        ? DateFormat(
            'MMM dd, yyyy hh:mm a',
          ).format((vital['marked_at'] as Timestamp).toDate())
        : 'Unknown';

    // Match Upcoming/Completed visuals: same bg color, elderly name color,
    // show only formatted date (remove Shift label) and increase vertical size
    String dateText = vital['assigned_date'] ?? '';
    try {
      if (vital['assigned_date'] != null) {
        final parsed = DateFormat('yyyy-MM-dd').parse(vital['assigned_date']);
        dateText = DateFormat('MMM. d, yyyy').format(parsed);
      }
    } catch (e) {
      // leave raw
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      color: const Color(0xFFD8F4FF),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          vertical: 18,
          horizontal: 16,
        ),
        leading: const CircleAvatar(
          backgroundColor: Colors.red,
          child: Icon(Icons.close, color: Colors.white),
        ),
        title: Text(
          vital['elderly_name'] ?? 'Unknown',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF00588E), // elderly name blue
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Text(
              'Date: $dateText',
              style: const TextStyle(color: Colors.black),
            ),
            const SizedBox(height: 6),
            Text(
              'Marked as missed: $markedTime',
              style: TextStyle(color: Colors.grey[800]),
            ),
            if (vital['missed_reason'] != null &&
                vital['missed_reason'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Text(
                  'Reason: ${vital['missed_reason']}',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
        isThreeLine: true,
        onTap: () => _showMissedDetailsDialog(vital),
      ),
    );
  }

  void _showMissedDetailsDialog(Map<String, dynamic> vital) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Missed Vital - ${vital['elderly_name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Elderly ID', vital['elderly_id']),
            _buildDetailRow('Shift', vital['shift']),
            _buildDetailRow('Date', vital['assigned_date']),
            _buildDetailRow(
              'Marked At',
              vital['marked_at'] != null
                  ? DateFormat(
                      'MMM dd, yyyy hh:mm a',
                    ).format((vital['marked_at'] as Timestamp).toDate())
                  : 'Unknown',
            ),
            const Divider(),
            const Text(
              'Reason:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(vital['missed_reason'] ?? 'No reason provided'),
            const SizedBox(height: 16),
            const Text(
              'This vital can still be completed in the Upcoming tab during subsequent shifts.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value?.toString() ?? 'N/A')),
        ],
      ),
    );
  }
}
