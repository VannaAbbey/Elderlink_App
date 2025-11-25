import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return '1st';
    if (currentHour >= 14 && currentHour < 22) return '2nd';
    return '3rd';
  }

  Stream<List<Map<String, dynamic>>> _getCompletedVitalsStream() {
    final today = _getTodayDateString();
    final currentShift = _getCurrentShift();
    final String? nurseId = FirebaseAuth.instance.currentUser?.uid;

    return _firestore
        .collection('vitals_daily')
        .where('house_id', isEqualTo: widget.houseId)
        .where('assigned_date', isEqualTo: today)
        .where('any_completed', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final List<Map<String, dynamic>> completedVitals = [];

          for (final doc in snapshot.docs) {
            final data = doc.data();
            final shiftStatus = data['shift_status'] as Map<String, dynamic>?;

            if (shiftStatus != null && shiftStatus[currentShift] != null) {
              final currentShiftData =
                  shiftStatus[currentShift] as Map<String, dynamic>;

              // Only include completed vitals that were completed by the current nurse
              if (currentShiftData['status'] == 'completed' &&
                  (nurseId != null &&
                      currentShiftData['completed_by'] == nurseId)) {
                final vitalValues =
                    data['vital_values'] as Map<String, dynamic>? ?? {};

                completedVitals.add({
                  'vitals_id': doc.id,
                  'elderly_id': data['elderly_id'],
                  'elderly_name': data['elderly_name'],
                  'house_id': data['house_id'],
                  'assigned_date': data['assigned_date'],
                  'shift': currentShift,
                  'blood_pressure': vitalValues['blood_pressure'] ?? 'N/A',
                  'pulse_rate': vitalValues['pulse_rate'] ?? 'N/A',
                  'oxygen_saturation':
                      vitalValues['oxygen_saturation'] ?? 'N/A',
                  'temperature': vitalValues['temperature'] ?? 'N/A',
                  'respiratory_rate': vitalValues['respiratory_rate'] ?? 'N/A',
                  'notes': vitalValues['notes'] ?? '',
                  'completed_by': currentShiftData['completed_by'],
                  'completed_at': currentShiftData['completed_at'],
                });
              }
            }
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

          return completedVitals;
        });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getCompletedVitalsStream(),
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
                Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No completed vitals for ${_getCurrentShift()} shift',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: completedVitals.length,
          itemBuilder: (context, index) {
            final vital = completedVitals[index];
            return _buildCompletedCard(vital);
          },
        );
      },
    );
  }

  Widget _buildCompletedCard(Map<String, dynamic> vital) {
    final completedAt = vital['completed_at'] != null
        ? (vital['completed_at'] as Timestamp).toDate()
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade100,
          child: Icon(Icons.check_circle, color: Colors.green.shade700),
        ),
        title: Text(
          vital['elderly_name'] ?? 'Unknown',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if (completedAt != null)
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Completed: ${DateFormat('h:mm a').format(completedAt)}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildVitalRow('Blood Pressure', vital['blood_pressure']),
                _buildVitalRow('Pulse Rate', vital['pulse_rate']),
                _buildVitalRow('O₂ Saturation', vital['oxygen_saturation']),
                _buildVitalRow('Temperature', vital['temperature']),
                _buildVitalRow('Respiratory Rate', vital['respiratory_rate']),
                if (vital['notes'] != null &&
                    vital['notes'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Notes:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(vital['notes'].toString()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVitalRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(
            value?.toString() ?? 'N/A',
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }
}
