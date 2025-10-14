import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CompletedMedicationsTab extends StatefulWidget {
  final String houseId;
  final String? nurseName;
  final DateTime? selectedDate;

  const CompletedMedicationsTab({
    super.key,
    required this.houseId,
    required this.nurseName,
    this.selectedDate,
  });

  @override
  State<CompletedMedicationsTab> createState() =>
      _CompletedMedicationsTabState();
}

class _CompletedMedicationsTabState extends State<CompletedMedicationsTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.selectedDate ?? DateTime.now();
  }

  void _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF00588E)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

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
    return Column(
      children: [
        // Date Picker Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          child: FutureBuilder<String?>(
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
                    .where('action', isEqualTo: 'take_completed')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    print(
                      'Error loading completed medications: ${snapshot.error}',
                    );
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // Filter by nurse ID in code and sort by completion date
                  final allLogs = snapshot.data?.docs ?? [];
                  print(
                    'Total completed medication logs in DB: ${allLogs.length}',
                  );

                  final completedLogs =
                      allLogs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final isCompletedByCurrentNurse =
                            data['nurse_id'] == nurseId;
                        final completedDate = (data['timestamp'] as Timestamp)
                            .toDate();
                        final isSameDate =
                            completedDate.year == _selectedDate.year &&
                            completedDate.month == _selectedDate.month &&
                            completedDate.day == _selectedDate.day;
                        if (isCompletedByCurrentNurse && isSameDate) {
                          print(
                            'Found completed medication: ${data['medication_name']} for ${data['elderly_name']}',
                          );
                        }
                        return isCompletedByCurrentNurse && isSameDate;
                      }).toList()..sort((a, b) {
                        final aData = a.data() as Map<String, dynamic>;
                        final bData = b.data() as Map<String, dynamic>;
                        final aTime = (aData['timestamp'] as Timestamp)
                            .toDate();
                        final bTime = (bData['timestamp'] as Timestamp)
                            .toDate();
                        return bTime.compareTo(
                          aTime,
                        ); // Descending order (newest first)
                      });

                  print(
                    'Filtered completed medications for this nurse and date: ${completedLogs.length}',
                  );

                  if (completedLogs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32.0),
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
                              'No completed medications for selected date',
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
                    itemCount: completedLogs.length,
                    itemBuilder: (context, index) {
                      final log =
                          completedLogs[index].data() as Map<String, dynamic>;
                      final takeOrdinal = _getOrdinal(
                        log['take_number'] as int,
                      );

                      return FutureBuilder<Map<String, dynamic>?>(
                        future: _getTakeCompletionData(
                          log['medication_id'] as String,
                          log['take_number'] as int,
                        ),
                        builder: (context, takeSnapshot) {
                          final takeData = takeSnapshot.data;
                          final completedAt = takeData?['completed_at'] != null
                              ? (takeData!['completed_at'] as Timestamp)
                                    .toDate()
                              : (log['timestamp'] as Timestamp).toDate();
                          final completedByName =
                              takeData?['completed_by_name'] as String? ??
                              'Unknown';

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
                                      Icon(
                                        Icons.person,
                                        color: Color(0xFF00588E),
                                      ),
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
                                      Icon(
                                        Icons.medication,
                                        color: Colors.green,
                                      ),
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
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
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
                                              SizedBox(height: 4),
                                              Text(
                                                'Completed by: $completedByName',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey[700],
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
                                        'Logged: ${DateFormat('MMM dd, yyyy HH:mm').format((log['timestamp'] as Timestamp).toDate())}',
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
            },
          ),
        ),
      ],
    );
  }

  Future<Map<String, dynamic>?> _getTakeCompletionData(
    String medicationId,
    int takeNumber,
  ) async {
    try {
      // Find the specific take document
      final takeQuery = await _firestore
          .collection('medication_takes')
          .where('medication_id', isEqualTo: medicationId)
          .where('take_number', isEqualTo: takeNumber)
          .get();

      if (takeQuery.docs.isEmpty) return null;

      final takeData = takeQuery.docs.first.data();
      final completedBy = takeData['completed_by'] as String?;
      String? completedByName;

      if (completedBy != null) {
        // Fetch nurse name from users collection
        final userDoc = await _firestore
            .collection('users')
            .doc(completedBy)
            .get();
        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          completedByName =
              '${userData['user_fname'] ?? ''} ${userData['user_lname'] ?? ''}'
                  .trim();
          if (completedByName.isEmpty) completedByName = 'Unknown';
        }
      }

      return {
        'completed_at': takeData['completed_at'],
        'completed_by_name': completedByName ?? 'Unknown',
      };
    } catch (e) {
      print('Error fetching take completion data: $e');
      return null;
    }
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
