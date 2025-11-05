import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MissedMedicationsTab extends StatefulWidget {
  final String houseId;
  final String? nurseName;
  final DateTime? selectedDate;

  const MissedMedicationsTab({
    super.key,
    required this.houseId,
    required this.nurseName,
    this.selectedDate,
  });

  @override
  State<MissedMedicationsTab> createState() => _MissedMedicationsTabState();
}

class _MissedMedicationsTabState extends State<MissedMedicationsTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late DateTime _selectedDate;
  List<String> _nurseWorkingDays = [];

  @override
  void initState() {
    super.initState();
    final base = widget.selectedDate ?? DateTime.now();
    _selectedDate = DateTime(base.year, base.month, base.day);
    _fetchNurseWorkingDays().then((days) {
      if (mounted) setState(() => _nurseWorkingDays = days);
    });
  }

  void _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      selectableDayPredicate: (date) {
        if (_nurseWorkingDays.isEmpty) return true;
        final weekday = DateFormat('EEEE').format(date);
        return _nurseWorkingDays.contains(weekday);
      },
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF00588E)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final normalized = DateTime(picked.year, picked.month, picked.day);
      if (normalized != _selectedDate) {
        setState(() => _selectedDate = normalized);
      }
    }
  }

  Future<List<String>> _fetchNurseWorkingDays() async {
    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) return [];
      final query = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .get();
      final days = <String>{};
      for (var doc in query.docs) {
        final data = doc.data();
        final assigned = List<String>.from(data['days_assigned'] ?? []);
        for (var d in assigned) {
          days.add(d);
        }
      }
      return days.toList();
    } catch (e) {
      print('Error fetching nurse working days: $e');
      return [];
    }
  }

  Future<String?> _getNurseId() async {
    try {
      final nameParts = widget.nurseName?.split(' ') ?? [];
      if (nameParts.length >= 2) {
        final firstName = nameParts[0];
        final lastName = nameParts[1];
        final userQuery = await _firestore
            .collection('users')
            .where('user_fname', isEqualTo: firstName)
            .where('user_lname', isEqualTo: lastName)
            .where('user_type', isEqualTo: 'nurse')
            .get();
        if (userQuery.docs.isNotEmpty) return userQuery.docs.first.id;
      }

      // Fallback to currently authenticated user id
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null) return currentUid;
      return null;
    } catch (e) {
      print('Error getting nurse ID: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _getMissedMedications() async {
    try {
      // Get missed medications from activity logs where nurse_name matches current nurse
      final missedLogsQuery = await _firestore
          .collection('medication_activity_logs')
          .where('house_id', isEqualTo: widget.houseId)
          .where('action', isEqualTo: 'take_missed')
          .where('nurse_name', isEqualTo: widget.nurseName)
          .get();

      final missedMedications = <Map<String, dynamic>>[];

      for (final logDoc in missedLogsQuery.docs) {
        final logData = logDoc.data();

        missedMedications.add({
          'id': logData['medication_id'],
          'elderly_id': logData['elderly_id'],
          'elderly_name': logData['elderly_name'],
          'medication_name': logData['medication_name'],
          'dosage': logData['dosage'],
          'take_number': logData['take_number'],
          'scheduled_time': logData['scheduled_time'],
          'repeat_interval': logData['repeat_interval'],
          'created_at': logData['timestamp'],
          'created_nurse_name': logData['nurse_name'],
          'house_id': logData['house_id'],
          'shift': logData['shift'],
          'missed_at': logData['timestamp'], // When it was marked as missed
        });
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
    return Column(
      children: [
        const SizedBox(height: 16),
        Expanded(
          child: Column(
            children: [
              // Date Picker Row
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: Colors.white,
                child: Row(
                  children: [
                    const Text(
                      'Date: ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF00588E),
                      ),
                    ),
                    Text(
                      DateFormat('MMM dd, yyyy').format(_selectedDate),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.calendar_today,
                        color: Color(0xFF00588E),
                      ),
                      onPressed: () => _selectDate(context),
                    ),
                  ],
                ),
              ),
              // Main Content
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('medication_activity_logs')
                      .where('house_id', isEqualTo: widget.houseId)
                      .where('action', isEqualTo: 'take_missed')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      print(
                        'Error loading missed medications: ${snapshot.error}',
                      );
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    return FutureBuilder<List<Map<String, dynamic>>>(
                      future: _getMissedMedications(),
                      builder: (context, futureSnapshot) {
                        if (futureSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final allMissedMedications = futureSnapshot.data ?? [];
                        print(
                          'Found ${allMissedMedications.length} missed medications',
                        );

                        // Filter by selected date
                        final missedMedications = allMissedMedications.where((
                          medication,
                        ) {
                          final missedDate = medication['missed_at'] != null
                              ? (medication['missed_at'] as Timestamp).toDate()
                              : (medication['created_at'] as Timestamp)
                                    .toDate();
                          final isSameDate =
                              missedDate.year == _selectedDate.year &&
                              missedDate.month == _selectedDate.month &&
                              missedDate.day == _selectedDate.day;
                          return isSameDate;
                        }).toList();

                        print(
                          'Filtered missed medications for selected date: ${missedMedications.length}',
                        );

                        if (missedMedications.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32.0,
                              ),
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
                                    'No missed medications for selected date',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
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
                                        Icon(
                                          Icons.person,
                                          color: Color(0xFF00588E),
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            medication['elderly_name'] ??
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

                                    // Medication Name and Dosage
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.medication,
                                          color: Colors.green,
                                        ),
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
                                        color: Colors.white,
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
                                                  '$takeOrdinal Take - MISSED',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                    color: Colors.red,
                                                  ),
                                                ),
                                                SizedBox(height: 4),
                                                Text(
                                                  'Scheduled Time: ${_formatTimeTo12Hour(medication['scheduled_time'] ?? 'Not specified')}',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.grey[700],
                                                  ),
                                                ),
                                                if (medication['missed_at'] !=
                                                    null)
                                                  Padding(
                                                    padding: EdgeInsets.only(
                                                      top: 4,
                                                    ),
                                                    child: Text(
                                                      'Missed: ${DateFormat('MMM dd, yyyy hh:mm a').format((medication['missed_at'] as Timestamp).toDate())}',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: Colors.red[700],
                                                        fontWeight:
                                                            FontWeight.w500,
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
                                          'Created: ${DateFormat('MMM dd, yyyy hh:mm a').format((medication['created_at'] as Timestamp).toDate())}',
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
                ),
              ),
            ],
          ),
        ),
      ],
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

  String _formatTimeTo12Hour(String timeString) {
    try {
      final timeParts = timeString.split(':');
      if (timeParts.length < 2) return timeString;

      final hour = int.tryParse(timeParts[0]) ?? 0;
      final minute = int.tryParse(timeParts[1]) ?? 0;

      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);

      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return timeString; // Return original if parsing fails
    }
  }
}
