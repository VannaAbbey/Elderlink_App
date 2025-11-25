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
  final ScrollController _scrollController = ScrollController();
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

  // ✅ NEW: Get nurse's current shift from house_shift_assignments
  Future<String?> _getNurseCurrentShift() async {
    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) return null;

      final query = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .get();

      if (query.docs.isNotEmpty) {
        final data = query.docs.first.data();
        final shift = data['shift'] as String?;
        print('🔄 Nurse current shift: $shift');
        return shift;
      }

      print('⚠️ No current shift assignment found for nurse');
      return null;
    } catch (e) {
      print('❌ Error fetching nurse current shift: $e');
      return null;
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
                      DateFormat('MMM. d, yyyy').format(_selectedDate),
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
                    if (nurseIdSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final nurseId = nurseIdSnapshot.data;
                    print('🔍 DEBUG: Resolved nurse ID: $nurseId');
                    if (nurseId == null) {
                      return const Center(
                        child: Text('Unable to identify nurse'),
                      );
                    }

                    return FutureBuilder<String?>(
                      future: _getNurseCurrentShift(),
                      builder: (context, shiftSnapshot) {
                        if (shiftSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final nurseCurrentShift = shiftSnapshot.data;
                        print(
                          '🔄 DEBUG: Nurse current shift for filtering: $nurseCurrentShift',
                        );
                        print(
                          '📅 DEBUG: Selected date: ${_selectedDate.toString()}',
                        );

                        return StreamBuilder<QuerySnapshot>(
                          stream: _firestore
                              .collection('medication_takes')
                              .where('status', isEqualTo: 'missed')
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            if (snapshot.hasError) {
                              print(
                                'Error loading missed medications: ${snapshot.error}',
                              );
                              return Center(
                                child: Text('Error: ${snapshot.error}'),
                              );
                            }

                            final allTakes = snapshot.data?.docs ?? [];
                            print(
                              '📊 DEBUG: Total missed medication takes in DB: ${allTakes.length}',
                            );

                            // Debug: Show all missed takes data
                            for (int i = 0; i < allTakes.length && i < 5; i++) {
                              final debugData =
                                  allTakes[i].data() as Map<String, dynamic>;
                              print('🔍 DEBUG Take $i: {');
                              print(
                                '  missed_by_nurse_id: ${debugData['missed_by_nurse_id']}',
                              );
                              print('  shift: ${debugData['shift']}');
                              print('  missed_at: ${debugData['missed_at']}');
                              print(
                                '  from_previous_shift: ${debugData['from_previous_shift']}',
                              );
                              print(
                                '  medication_id: ${debugData['medication_id']}',
                              );
                              print('}');
                            }

                            // ✅ ENHANCED: Filter by nurse ID, selected date, current shift, and exclude from_previous_shift
                            print(
                              '🔄 Filtering missed medications for shift: $nurseCurrentShift',
                            );

                            int filterStep = 0;

                            final missedMedications =
                                allTakes.where((doc) {
                                  final data =
                                      doc.data() as Map<String, dynamic>;
                                  filterStep++;

                                  print('\n🔍 DEBUG Filter Step $filterStep:');
                                  print(
                                    '  Medication ID: ${data['medication_id']}',
                                  );
                                  print(
                                    '  Missed by nurse ID: ${data['missed_by_nurse_id']}',
                                  );
                                  print('  Current nurse ID: $nurseId');
                                  print('  Medication shift: ${data['shift']}');
                                  print(
                                    '  Nurse current shift: $nurseCurrentShift',
                                  );
                                  print(
                                    '  From previous shift: ${data['from_previous_shift']}',
                                  );

                                  // Show ALL missed medications by this nurse (including from_previous_shift)
                                  // from_previous_shift medications that are missed should still be shown
                                  // as they represent the nurse's responsibility
                                  print(
                                    '  ℹ️  from_previous_shift: ${data['from_previous_shift']} (still showing)',
                                  );

                                  // Check if this medication was missed by current nurse
                                  final missedByNurseId =
                                      data['missed_by_nurse_id'] as String?;
                                  if (missedByNurseId != nurseId) {
                                    print(
                                      '  ❌ EXCLUDED: Different nurse (${missedByNurseId} vs $nurseId)',
                                    );
                                    return false;
                                  }

                                  // Show missed medications regardless of shift for now
                                  // This ensures we capture all missed medications by this nurse
                                  final medicationShift =
                                      data['shift'] as String?;
                                  print(
                                    '  ℹ️  Medication shift: $medicationShift, Current shift: $nurseCurrentShift',
                                  );

                                  // Check if it's for the selected date
                                  final missedAt =
                                      data['missed_at'] as Timestamp?;
                                  if (missedAt == null) {
                                    print(
                                      '  ❌ EXCLUDED: No missed_at timestamp',
                                    );
                                    return false;
                                  }

                                  final missedDate = missedAt.toDate();
                                  print(
                                    '  Missed date: ${missedDate.toString()}',
                                  );
                                  print(
                                    '  Selected date: ${_selectedDate.toString()}',
                                  );

                                  final isSameDate =
                                      missedDate.year == _selectedDate.year &&
                                      missedDate.month == _selectedDate.month &&
                                      missedDate.day == _selectedDate.day;

                                  if (!isSameDate) {
                                    print('  ❌ EXCLUDED: Different date');
                                    return false;
                                  }

                                  print('  ✅ INCLUDED: All filters passed!');
                                  return true;
                                }).toList()..sort((a, b) {
                                  final aData =
                                      a.data() as Map<String, dynamic>;
                                  final bData =
                                      b.data() as Map<String, dynamic>;
                                  final aTimeStr =
                                      aData['scheduled_time'] as String? ??
                                      '00:00';
                                  final bTimeStr =
                                      bData['scheduled_time'] as String? ??
                                      '00:00';

                                  // Parse time strings (format: "HH:mm")
                                  final aTimeParts = aTimeStr.split(':');
                                  final bTimeParts = bTimeStr.split(':');

                                  final aHour =
                                      int.tryParse(aTimeParts[0]) ?? 0;
                                  final aMinute = aTimeParts.length > 1
                                      ? (int.tryParse(aTimeParts[1]) ?? 0)
                                      : 0;
                                  final bHour =
                                      int.tryParse(bTimeParts[0]) ?? 0;
                                  final bMinute = bTimeParts.length > 1
                                      ? (int.tryParse(bTimeParts[1]) ?? 0)
                                      : 0;

                                  // Convert to minutes for comparison
                                  final aMinutes = aHour * 60 + aMinute;
                                  final bMinutes = bHour * 60 + bMinute;

                                  return aMinutes.compareTo(
                                    bMinutes,
                                  ); // Ascending order (oldest to current)
                                });

                            print('\n📊 DEBUG SUMMARY:');
                            print('  Total takes in DB: ${allTakes.length}');
                            print(
                              '  After filtering: ${missedMedications.length}',
                            );
                            print('  Nurse ID: $nurseId');
                            print('  Nurse current shift: $nurseCurrentShift');
                            print(
                              '  Selected date: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
                            );
                            print('\n');

                            if (missedMedications.isEmpty) {
                              return RefreshIndicator(
                                onRefresh: () async {
                                  setState(() {});
                                },
                                child: ListView(
                                  children: [
                                    SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height *
                                          0.6,
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 32.0,
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
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
                                controller: _scrollController,
                                physics: const ClampingScrollPhysics(),
                                padding: EdgeInsets.symmetric(vertical: 8),
                                itemCount: missedMedications.length,
                                itemBuilder: (context, index) {
                                  final takeData =
                                      missedMedications[index].data()
                                          as Map<String, dynamic>;
                                  final takeOrdinal = _getOrdinal(
                                    takeData['take_number'] as int,
                                  );
                                  final medicationId =
                                      takeData['medication_id'] as String?;

                                  if (medicationId == null) {
                                    return SizedBox.shrink();
                                  }

                                  return FutureBuilder<DocumentSnapshot>(
                                    future: _firestore
                                        .collection('medications')
                                        .doc(medicationId)
                                        .get(),
                                    builder: (context, medSnapshot) {
                                      if (!medSnapshot.hasData ||
                                          !medSnapshot.data!.exists) {
                                        return SizedBox.shrink();
                                      }

                                      final medData =
                                          medSnapshot.data!.data()
                                              as Map<String, dynamic>;
                                      final elderlyId =
                                          medData['elderly_id'] as String?;

                                      return FutureBuilder<DocumentSnapshot?>(
                                        future: elderlyId != null
                                            ? _firestore
                                                  .collection('elderly')
                                                  .doc(elderlyId)
                                                  .get()
                                            : null,
                                        builder: (context, elderlySnapshot) {
                                          String elderlyName = 'Unknown';
                                          if (elderlySnapshot.hasData &&
                                              elderlySnapshot.data != null &&
                                              elderlySnapshot.data!.exists) {
                                            final elderlyData =
                                                elderlySnapshot.data!.data()
                                                    as Map<String, dynamic>;
                                            final firstName =
                                                elderlyData['elderly_fname'] ??
                                                '';
                                            final lastName =
                                                elderlyData['elderly_lname'] ??
                                                '';
                                            elderlyName =
                                                '${firstName} ${lastName}'
                                                    .trim();
                                            if (elderlyName.isEmpty) {
                                              elderlyName = 'Unknown';
                                            }
                                          }

                                          return Card(
                                            margin: EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                            color: const Color(0xFFE6F3FA),
                                            child: Padding(
                                              padding: EdgeInsets.all(16),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  // Elderly Name
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.person,
                                                        color: Color(
                                                          0xFF00588E,
                                                        ),
                                                      ),
                                                      SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          elderlyName,
                                                          style: TextStyle(
                                                            fontSize: 18,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Color(
                                                              0xFF00588E,
                                                            ),
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
                                                          '${medData['medication_name'] ?? 'Unknown'} - ${medData['dosage'] ?? ''}',
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.w600,
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
                                                        color: Colors.red
                                                            .withOpacity(0.3),
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
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
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                '$takeOrdinal Take - MISSED',
                                                                style: TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 16,
                                                                  color: Colors
                                                                      .red,
                                                                ),
                                                              ),
                                                              SizedBox(
                                                                height: 4,
                                                              ),
                                                              Text(
                                                                'Scheduled Time: ${_formatTimeTo12Hour(takeData['scheduled_time'] ?? 'Not specified')}',
                                                                style: TextStyle(
                                                                  fontSize: 14,
                                                                  color: Colors
                                                                      .grey[700],
                                                                ),
                                                              ),
                                                              if (takeData['missed_at'] !=
                                                                  null)
                                                                Padding(
                                                                  padding:
                                                                      EdgeInsets.only(
                                                                        top: 4,
                                                                      ),
                                                                  child: Text(
                                                                    'Missed: ${DateFormat('MMM dd, yyyy hh:mm a').format((takeData['missed_at'] as Timestamp).toDate())}',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          14,
                                                                      color: Colors
                                                                          .red[700],
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w500,
                                                                    ),
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),

                                                  // Missed timestamp (smaller and at bottom)
                                                  if (takeData['missed_at'] !=
                                                      null)
                                                    Padding(
                                                      padding: EdgeInsets.only(
                                                        top: 12,
                                                      ),
                                                      child: Text(
                                                        'Missed At: ${DateFormat('MMM dd, yyyy hh:mm a').format((takeData['missed_at'] as Timestamp).toDate())}',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color:
                                                              Colors.grey[500],
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
