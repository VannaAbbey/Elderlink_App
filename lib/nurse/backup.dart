import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class UpcomingMedicationsTab extends StatefulWidget {
  final String houseId;
  final String? nurseName;

  const UpcomingMedicationsTab({
    super.key,
    required this.houseId,
    required this.nurseName,
  });

  @override
  State<UpcomingMedicationsTab> createState() => _UpcomingMedicationsTabState();
}

class _UpcomingMedicationsTabState extends State<UpcomingMedicationsTab>
    with AutomaticKeepAliveClientMixin<UpcomingMedicationsTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // In-memory cache to speed up UI when switching houses/tabs.
  // Keyed by: houseId|nurseName|shift|day to avoid cross-shift staleness.
  static final Map<String, List<Map<String, dynamic>>> _medsCache = {};
  static final Map<String, DateTime> _medsCacheTime = {};
  static const Duration _cacheDuration = Duration(minutes: 5);
  List<Map<String, String>> _elderlyList = [];
  String? _selectedElderly;
  bool _isLoading = false;
  List<Map<String, dynamic>> _upcomingMedications = [];
  Timer? _missedMedicationTimer;

  @override
  void initState() {
    super.initState();
    // Prewarm nurse id and load data (uses cache if available) to make
    // the first frame appear faster when switching tabs/houses.
    _prewarm();
    _startMissedMedicationTimer();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _prewarm() async {
    // Kick off assigned elderly and medications loading in background.
    // We intentionally don't await both sequentially to reduce perceived wait.
    _loadAssignedElderly();
    _loadUpcomingMedications();
  }

  @override
  void dispose() {
    _missedMedicationTimer?.cancel();
    super.dispose();
  }

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

  String _getCurrentDay() {
    final now = DateTime.now();
    final currentHour = now.hour;

    // For third shift (10pm-6am), if it's after midnight (0:00-5:59),
    // we need to look at the previous day's assignments
    if (currentHour >= 0 && currentHour < 6) {
      // It's after midnight during third shift, so get previous day
      final previousDay = now.subtract(Duration(days: 1));
      return DateFormat('EEEE').format(previousDay);
    }

    // For all other times, use current day
    return DateFormat('EEEE').format(now);
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

  Future<List<String>> _getNurseWorkingDays(String nurseId) async {
    try {
      final currentShift = _getCurrentShift();

      final shiftQuery = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .get();

      if (shiftQuery.docs.isNotEmpty) {
        final data = shiftQuery.docs.first.data();
        return List<String>.from(data['days_assigned'] ?? []);
      }
      return [];
    } catch (e) {
      print('Error getting nurse working days: $e');
      return [];
    }
  }

  Future<void> _saveMedicationToDatabase({
    required String elderlyId,
    required String medicationName,
    required String dosage,
    required String repeatInterval,
    required int numberOfIntakes,
    required List<TimeOfDay> intakeTimes,
  }) async {
    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) {
        throw Exception('Could not find nurse ID');
      }

      final workingDays = await _getNurseWorkingDays(nurseId);
      if (workingDays.isEmpty) {
        throw Exception('No working days found for nurse');
      }

      // Convert TimeOfDay to string format
      final intakeTimeStrings = intakeTimes
          .map(
            (time) =>
                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
          )
          .toList();

      // Create individual take statuses
      final List<Map<String, dynamic>> takeStatuses = [];
      for (int i = 0; i < numberOfIntakes; i++) {
        takeStatuses.add({
          'take_number': i + 1,
          'take_name': _getOrdinal(i + 1),
          'scheduled_time': intakeTimeStrings[i],
          'status': 'pending', // pending, complete, missed
          'completed_at': null,
          'completed_by': null,
        });
      }

      // Create medication document
      final medicationData = {
        'elderly_id': elderlyId,
        'house_id': widget.houseId,
        'created_nurse_id': nurseId, // Who created the medication
        'created_nurse_name': widget.nurseName,
        'medication_name': medicationName,
        'dosage': dosage,
        'repeat_interval': repeatInterval,
        'number_of_intakes': numberOfIntakes,
        'intake_times': intakeTimeStrings,
        'take_statuses': takeStatuses, // Individual take tracking
        'working_days': repeatInterval == 'Daily'
            ? [
                'Monday',
                'Tuesday',
                'Wednesday',
                'Thursday',
                'Friday',
                'Saturday',
                'Sunday',
              ]
            : workingDays, // All days for Daily, specific days for Once
        'shift': _getCurrentShift(),
        'status': 'upcoming',
        'created_at': FieldValue.serverTimestamp(),
        'created_by': nurseId,
      };

      final docRef = await _firestore
          .collection('medications')
          .add(medicationData);

      // Log the add medication activity
      await _logMedicationActivity(
        action: 'add_medication',
        medicationId: docRef.id,
        medicationData: medicationData,
        takeNumber: 0, // 0 for whole medication addition
        newData: medicationData,
      );

      print('Medication saved successfully');

      // Refresh the medications list
      await _loadUpcomingMedications();
    } catch (e) {
      print('Error saving medication: $e');
      rethrow;
    }
  }

  Future<void> _loadAssignedElderly() async {
    setState(() {
      _isLoading = true;
      _elderlyList = [];
    });

    try {
      final currentShift = _getCurrentShift();
      final currentDay = _getCurrentDay();

      print(
        'Fetching for nurse: ${widget.nurseName}, shift: $currentShift, day: $currentDay',
      );
      print('Filtering assignments for house: ${widget.houseId}');

      // First get the nurse's ID from users collection
      // Split the full name into first and last name
      final nameParts = widget.nurseName?.split(' ') ?? [];
      if (nameParts.length < 2) {
        print('Invalid nurse name format: ${widget.nurseName}');
        setState(() {
          _elderlyList = [];
          _isLoading = false;
        });
        return;
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
        setState(() {
          _elderlyList = [];
          _isLoading = false;
        });
        return;
      }

      final nurseId = userQuery.docs.first.id;
      print('Found nurse ID: $nurseId');

      // First check if nurse is assigned to work this shift on this day
      print('Checking shift assignment for nurseId: $nurseId');
      print('Looking for - Shift: $currentShift, Day: $currentDay');

      final shiftQuery = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .where('days_assigned', arrayContains: currentDay)
          .get();

      if (shiftQuery.docs.isEmpty) {
        print('Nurse is not assigned to this shift on this day');
        print('Query returned no results for house_shift_assignments');
        setState(() {
          _elderlyList = [];
          _isLoading = false;
        });
        return;
      }

      print('Found shift assignment: ${shiftQuery.docs.first.data()}');

      print('Checking elderly assignments...');
      print(
        'Params - nurseId: $nurseId, house: ${widget.houseId}, shift: $currentShift, day: $currentDay',
      );

      // Get nurse-elderly assignments for the current house and specific nurse
      final nurseElderlyQuery = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('house_id', arrayContains: widget.houseId)
          .where('shift', isEqualTo: currentShift)
          .where('day', isEqualTo: currentDay)
          .get();

      print(
        'Found ${nurseElderlyQuery.docs.length} matching nurse assignments',
      );

      if (nurseElderlyQuery.docs.isNotEmpty) {
        print('Assignment data: ${nurseElderlyQuery.docs.first.data()}');
      }

      if (nurseElderlyQuery.docs.isEmpty) {
        print('No assignments found for the current day and shift');
        setState(() {
          _elderlyList = [];
          _isLoading = false;
        });
        return;
      }

      // Get the assignment document
      final assignmentDoc = nurseElderlyQuery.docs.first;

      final data = assignmentDoc.data();
      print('Assignment data for house ${widget.houseId}: $data');

      // Get only the elderly IDs for this specific assignment
      final elderlyIds = List<String>.from(data['elderly_ids'] ?? []);
      print('Extracted elderly IDs for this house: $elderlyIds');

      print('Found ${elderlyIds.length} elderly IDs: $elderlyIds');

      if (elderlyIds.isEmpty) {
        setState(() {
          _elderlyList = [];
          _isLoading = false;
        });
        return;
      }

      // Process elderly IDs in chunks of 30 (Firestore limitation)
      final allElderly = <DocumentSnapshot>[];

      // Split the elderly IDs into chunks of 30
      for (var i = 0; i < elderlyIds.length; i += 30) {
        final end = (i + 30 < elderlyIds.length) ? i + 30 : elderlyIds.length;
        final chunk = elderlyIds.sublist(i, end);

        print('Processing chunk ${i ~/ 30 + 1} with ${chunk.length} IDs');

        final elderlyDetailsQuery = await _firestore
            .collection('elderly')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        allElderly.addAll(elderlyDetailsQuery.docs);
        print(
          'Retrieved ${elderlyDetailsQuery.docs.length} elderly for chunk ${i ~/ 30 + 1}',
        );
      }

      print('Total elderly documents retrieved: ${allElderly.length}');

      // Filter and process elderly for current house
      final filteredElderly = allElderly.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['house_id'] == widget.houseId;
      }).toList();

      print(
        'Filtered elderly for house ${widget.houseId}: ${filteredElderly.length}',
      );

      final newElderlyList = filteredElderly.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        print('Processing elderly document ${doc.id}');

        final firstName = data['elderly_fname'];
        final lastName = data['elderly_lname'];
        print('Raw data - firstName: $firstName, lastName: $lastName');

        final fullName = '${firstName ?? ''} ${lastName ?? ''}'.trim();
        print('Processed elderly: $fullName (ID: ${doc.id})');

        return {
          'id': doc.id,
          'name': fullName.isNotEmpty ? fullName : 'Unknown',
        };
      }).toList();

      // Sort alphabetically by name
      newElderlyList.sort((a, b) => a['name']!.compareTo(b['name']!));

      setState(() {
        _elderlyList = newElderlyList;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading assigned elderly: $e');
      setState(() {
        _elderlyList = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUpcomingMedications({bool forceRefresh = false}) async {
    final currentDay = _getCurrentDay();
    final currentShift = _getCurrentShift();
    final cacheKey =
        '${widget.houseId}|${widget.nurseName ?? ''}|$currentShift|$currentDay';

    try {
      // If cached and not forced to refresh, return cached data immediately
      final cached = _medsCache[cacheKey];
      final cacheTime = _medsCacheTime[cacheKey];
      if (!forceRefresh &&
          cached != null &&
          cacheTime != null &&
          DateTime.now().difference(cacheTime) < _cacheDuration) {
        setState(() {
          _upcomingMedications = List<Map<String, dynamic>>.from(cached);
          _isLoading = false;
        });

        // Schedule a background refresh after cache TTL to keep things fresh
        Future.delayed(
          _cacheDuration,
          () => _loadUpcomingMedications(forceRefresh: true),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      final nurseId = await _getNurseId();
      if (nurseId == null) {
        setState(() {
          _upcomingMedications = [];
          _isLoading = false;
        });
        return;
      }

      // Fetch nurse assignment and medications in parallel to reduce latency.
      final nurseAssignFuture = _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('house_id', arrayContains: widget.houseId)
          .where('shift', isEqualTo: currentShift)
          .where('day', isEqualTo: currentDay)
          .get();

      // Limit to current shift/day and upcoming status to reduce transferred data
      final medicationsFuture = _firestore
          .collection('medications')
          .where('house_id', isEqualTo: widget.houseId)
          .where('status', isEqualTo: 'upcoming')
          .get();

      final results = await Future.wait([nurseAssignFuture, medicationsFuture]);

      final nurseElderlyQuery = results[0] as QuerySnapshot;
      final medicationsQuery = results[1] as QuerySnapshot;

      if (nurseElderlyQuery.docs.isEmpty) {
        setState(() {
          _upcomingMedications = [];
          _isLoading = false;
        });
        return;
      }

      final assignData =
          nurseElderlyQuery.docs.first.data() as Map<String, dynamic>?;
      final assignedElderlyIds = List<String>.from(
        assignData?['elderly_ids'] ?? [],
      );

      if (assignedElderlyIds.isEmpty) {
        setState(() {
          _upcomingMedications = [];
          _isLoading = false;
        });
        return;
      }

      // Filter meds by assigned elderly, shift and working day, but don't fetch
      // elderly doc per-med; instead collect unique elderly IDs and fetch once in chunks.
      final medsToInclude = <Map<String, dynamic>>[];
      final elderlyIdsNeeded = <String>{};

      for (final doc in medicationsQuery.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final elderlyId = data['elderly_id'] as String?;
        if (elderlyId == null) continue;

        if (!assignedElderlyIds.contains(elderlyId)) continue;

        final medicationShift = data['shift'] as String?;
        final workingDays = data['working_days'] as List?;

        if (medicationShift == currentShift &&
            workingDays != null &&
            workingDays.contains(currentDay)) {
          medsToInclude.add({'id': doc.id, ...data});
          elderlyIdsNeeded.add(elderlyId);
        }
      }

      // Fetch elderly docs in chunks of 30 to build a lookup map
      final Map<String, String> elderlyNames = {};
      final elderlyIdList = elderlyIdsNeeded.toList();
      for (var i = 0; i < elderlyIdList.length; i += 30) {
        final end = (i + 30 < elderlyIdList.length)
            ? i + 30
            : elderlyIdList.length;
        final chunk = elderlyIdList.sublist(i, end);
        final elderlyQuery = await _firestore
            .collection('elderly')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final ed in elderlyQuery.docs) {
          final edata = ed.data();
          final name =
              '${edata['elderly_fname'] ?? ''} ${edata['elderly_lname'] ?? ''}'
                  .trim();
          elderlyNames[ed.id] = name.isNotEmpty ? name : 'Unknown';
        }
      }

      final medications = <Map<String, dynamic>>[];
      for (final m in medsToInclude) {
        final elderlyId = m['elderly_id'] as String;
        medications.add({
          'id': m['id'],
          'elderly_name': elderlyNames[elderlyId] ?? 'Unknown',
          ...m,
        });
      }

      // Update cache and state
      _medsCache[cacheKey] = List<Map<String, dynamic>>.from(medications);
      _medsCacheTime[cacheKey] = DateTime.now();

      setState(() {
        _upcomingMedications = medications;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading upcoming medications: $e');
      setState(() {
        _upcomingMedications = [];
        _isLoading = false;
      });
    }
  }

  void _showAddMedicationDialog() {
    String? selectedElderlyTemp = _selectedElderly;
    String? selectedMedicationTemp;
    String? selectedDosageTemp;
    String? selectedIntervalTemp;
    int? numberOfIntakesTemp;
    List<TimeOfDay?> intakeTimes = [];

    // Common medications for elderly
    final List<String> commonMedications = [
      'Lisinopril',
      'Metformin',
      'Atorvastatin',
      'Omeprazole',
      'Aspirin',
      'Levothyroxine',
    ];

    // Common dosages
    final List<String> commonDosages = [
      '5mg',
      '10mg',
      '25mg',
      '50mg',
      '100mg',
      '250mg',
      '500mg',
      '1g',
    ];

    // Repeat intervals
    final List<String> repeatIntervals = ['Once', 'Daily'];

    // Number of intakes options
    final List<int> intakeOptions = [1, 2, 3, 4, 5, 6];

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          contentPadding: EdgeInsets.all(20),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Add Medication'),
              SizedBox(height: 8),
              Text(
                'Total assigned elderly: ${_elderlyList.length}',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Elderly Selection
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.8,
                      child: DropdownMenu<String>(
                        width: MediaQuery.of(context).size.width * 0.8,
                        hintText: 'Select elderly',
                        enableSearch: true,
                        enableFilter: true,
                        requestFocusOnTap: true,
                        initialSelection: selectedElderlyTemp,
                        dropdownMenuEntries: _elderlyList.map((elderly) {
                          return DropdownMenuEntry<String>(
                            value: elderly['id']!,
                            label: elderly['name'] ?? '',
                          );
                        }).toList(),
                        onSelected: (String? value) {
                          setDialogState(() {
                            selectedElderlyTemp = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 16),

                    // Medication Name
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.8,
                      child: DropdownMenu<String>(
                        width: MediaQuery.of(context).size.width * 0.8,
                        hintText: 'Select medication',
                        enableSearch: true,
                        enableFilter: true,
                        requestFocusOnTap: true,
                        initialSelection: selectedMedicationTemp,
                        dropdownMenuEntries: commonMedications.map((
                          medication,
                        ) {
                          return DropdownMenuEntry<String>(
                            value: medication,
                            label: medication,
                          );
                        }).toList(),
                        onSelected: (String? value) {
                          setDialogState(() {
                            selectedMedicationTemp = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 16),

                    // Dosage
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.8,
                      child: DropdownMenu<String>(
                        width: MediaQuery.of(context).size.width * 0.8,
                        hintText: 'Select dosage',
                        enableSearch: true,
                        enableFilter: true,
                        requestFocusOnTap: true,
                        initialSelection: selectedDosageTemp,
                        dropdownMenuEntries: commonDosages.map((dosage) {
                          return DropdownMenuEntry<String>(
                            value: dosage,
                            label: dosage,
                          );
                        }).toList(),
                        onSelected: (String? value) {
                          setDialogState(() {
                            selectedDosageTemp = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 16),

                    // Repeat Interval
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.8,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: DropdownButton<String>(
                          value: selectedIntervalTemp,
                          isExpanded: true,
                          hint: Text('Select repeat interval'),
                          underline: Container(),
                          items: repeatIntervals.map((interval) {
                            return DropdownMenuItem<String>(
                              value: interval,
                              child: Text(interval),
                            );
                          }).toList(),
                          onChanged: (String? value) {
                            setDialogState(() {
                              selectedIntervalTemp = value;
                            });
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: 16),

                    // Number of Intakes
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.8,
                      child: DropdownMenu<int>(
                        width: MediaQuery.of(context).size.width * 0.8,
                        hintText: 'Number of medication intakes',
                        initialSelection: numberOfIntakesTemp,
                        dropdownMenuEntries: intakeOptions.map((intakeCount) {
                          return DropdownMenuEntry<int>(
                            value: intakeCount,
                            label:
                                '$intakeCount intake${intakeCount > 1 ? 's' : ''}',
                          );
                        }).toList(),
                        onSelected: (int? value) {
                          setDialogState(() {
                            numberOfIntakesTemp = value;
                            // Initialize intake times list
                            if (value != null) {
                              intakeTimes = List.filled(value, null);
                            } else {
                              intakeTimes = [];
                            }
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 16),

                    // Dynamic Intake Times
                    if (numberOfIntakesTemp != null && numberOfIntakesTemp! > 0)
                      ...List.generate(numberOfIntakesTemp!, (index) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${_getOrdinal(index + 1)} Take:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: GestureDetector(
                                  onTap: () async {
                                    final TimeOfDay? picked =
                                        await showTimePicker(
                                          context: context,
                                          initialTime:
                                              intakeTimes[index] ??
                                              TimeOfDay.now(),
                                        );
                                    if (picked != null) {
                                      setDialogState(() {
                                        intakeTimes[index] = picked;
                                      });
                                    }
                                  },
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          intakeTimes[index] != null
                                              ? intakeTimes[index]!.format(
                                                  context,
                                                )
                                              : 'Select time',
                                          style: TextStyle(
                                            color: intakeTimes[index] != null
                                                ? Colors.black
                                                : Colors.grey,
                                          ),
                                        ),
                                        Icon(
                                          Icons.access_time,
                                          color: Colors.grey,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                // Validate all fields are filled
                if (selectedElderlyTemp != null &&
                    selectedMedicationTemp != null &&
                    selectedDosageTemp != null &&
                    selectedIntervalTemp != null &&
                    numberOfIntakesTemp != null &&
                    intakeTimes.every((time) => time != null)) {
                  try {
                    // Show loading indicator
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) =>
                          Center(child: CircularProgressIndicator()),
                    );

                    // Save medication to database
                    await _saveMedicationToDatabase(
                      elderlyId: selectedElderlyTemp!,
                      medicationName: selectedMedicationTemp!,
                      dosage: selectedDosageTemp!,
                      repeatInterval: selectedIntervalTemp!,
                      numberOfIntakes: numberOfIntakesTemp!,
                      intakeTimes: intakeTimes.cast<TimeOfDay>(),
                    );

                    setState(() {
                      _selectedElderly = selectedElderlyTemp;
                    });

                    // Close loading dialog
                    Navigator.of(context).pop();

                    // Close medication dialog
                    Navigator.of(context).pop();

                    // Show success message
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Medication added successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    // Close loading dialog if it's open
                    Navigator.of(context).pop();

                    // Show error message
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Error adding medication: ${e.toString()}',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please fill in all fields'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: Text('Add'),
            ),
          ],
        );
      },
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

  void _startMissedMedicationTimer() {
    // Check for missed medications every 5 minutes
    _missedMedicationTimer = Timer.periodic(Duration(minutes: 5), (timer) {
      _checkForMissedMedications();
    });
    // Also check immediately
    _checkForMissedMedications();
  }

  Future<void> _checkForMissedMedications() async {
    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) return;

      final currentTime = DateTime.now();
      final currentDay = _getCurrentDay();
      final currentShift = _getCurrentShift();

      print(
        'Checking for missed medications at ${DateFormat('HH:mm').format(currentTime)}',
      );

      // Get nurse's assigned elderly for current day and shift
      final nurseElderlyQuery = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('house_id', arrayContains: widget.houseId)
          .where('shift', isEqualTo: currentShift)
          .where('day', isEqualTo: currentDay)
          .get();

      if (nurseElderlyQuery.docs.isEmpty) return;

      // Get assigned elderly IDs for this nurse
      final assignedElderlyIds = List<String>.from(
        nurseElderlyQuery.docs.first.data()['elderly_ids'] ?? [],
      );

      if (assignedElderlyIds.isEmpty) return;

      // Get all upcoming medications for current house and shift
      final medicationsQuery = await _firestore
          .collection('medications')
          .where('house_id', isEqualTo: widget.houseId)
          .where('status', isEqualTo: 'upcoming')
          .get();

      for (final doc in medicationsQuery.docs) {
        final data = doc.data();
        final elderlyId = data['elderly_id'] as String;

        // Only check medications for elderly assigned to this nurse
        if (!assignedElderlyIds.contains(elderlyId)) continue;

        final medicationShift = data['shift'] as String?;
        final workingDays = data['working_days'] as List?;

        // Only check medications for current shift and current day
        if (medicationShift == currentShift &&
            workingDays != null &&
            workingDays.contains(currentDay)) {
          final takeStatuses = data['take_statuses'] as List<dynamic>? ?? [];
          bool hasUpdates = false;

          for (int i = 0; i < takeStatuses.length; i++) {
            final take = takeStatuses[i] as Map<String, dynamic>;
            final status = take['status'] as String;
            final scheduledTimeStr = take['scheduled_time'] as String;

            // Only check pending medications
            if (status == 'pending') {
              // Parse scheduled time (assuming format is HH:mm)
              final timeParts = scheduledTimeStr.split(':');
              if (timeParts.length == 2) {
                final scheduledHour = int.tryParse(timeParts[0]) ?? 0;
                final scheduledMinute = int.tryParse(timeParts[1]) ?? 0;

                // Create scheduled DateTime for today
                final scheduledDateTime = DateTime(
                  currentTime.year,
                  currentTime.month,
                  currentTime.day,
                  scheduledHour,
                  scheduledMinute,
                );

                // Check if more than 1 hour has passed since scheduled time
                final timeDifference = currentTime.difference(
                  scheduledDateTime,
                );
                if (timeDifference.inHours >= 1) {
                  print(
                    'Marking take ${take['take_number']} as missed for medication ${data['medication_name']} (overdue by ${timeDifference.inMinutes} minutes)',
                  );

                  // Update status to missed
                  takeStatuses[i]['status'] = 'missed';
                  takeStatuses[i]['missed_at'] = currentTime;
                  takeStatuses[i]['missed_reason'] =
                      'Automatically marked as missed after 1 hour';
                  hasUpdates = true;
                }
              }
            }
          }

          // Update the document if there were changes
          if (hasUpdates) {
            await _firestore.collection('medications').doc(doc.id).update({
              'take_statuses': takeStatuses,
            });
            print(
              'Updated missed statuses for medication: ${data['medication_name']}',
            );
          }
        }
      }

      // Refresh the UI if there were any updates
      await _loadUpcomingMedications();
    } catch (e) {
      print('Error checking for missed medications: $e');
    }
  }

  // Removed _createCompletedMedicationIntake - using unified activity logs only

  // Removed methods that use separate collections - now using unified activity logs only

  Future<void> _logMedicationActivity({
    required String action,
    required String medicationId,
    required Map<String, dynamic> medicationData,
    required int takeNumber,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
    Map<String, dynamic>? takeData,
  }) async {
    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) return;

      final elderlyDoc = await _firestore
          .collection('elderly')
          .doc(medicationData['elderly_id'])
          .get();

      String elderlyName = 'Unknown';
      String elderlyTitle = 'Lola';
      if (elderlyDoc.exists) {
        final elderlyData = elderlyDoc.data() as Map<String, dynamic>;
        elderlyName =
            '${elderlyData['elderly_fname']} ${elderlyData['elderly_lname']}'
                .trim();
        elderlyTitle = elderlyData['elderly_title'] ?? 'Lola';
      }

      // Get scheduled time from takeData if provided, otherwise from medicationData
      String? scheduledTime;
      if (takeData != null && takeData['scheduled_time'] != null) {
        scheduledTime = takeData['scheduled_time'] as String;
      } else if (medicationData['intake_times'] != null && takeNumber > 0) {
        final intakeTimes = List<String>.from(medicationData['intake_times']);
        if (takeNumber <= intakeTimes.length) {
          scheduledTime = intakeTimes[takeNumber - 1];
        }
      }

      final activityData = {
        'action': action,
        'nurse_id': nurseId,
        'nurse_name': widget.nurseName,
        'medication_id': medicationId,
        'medication_name': medicationData['medication_name'],
        'dosage':
            medicationData['dosage'] ?? medicationData['medication_dosage'],
        'repeat_interval': medicationData['repeat_interval'],
        'elderly_id': medicationData['elderly_id'],
        'elderly_name': elderlyName,
        'elderly_title': elderlyTitle,
        'house_id': widget.houseId,
        'take_number': takeNumber,
        'take_ordinal': _getOrdinal(takeNumber),
        'scheduled_time': scheduledTime,
        'timestamp': FieldValue.serverTimestamp(),
        'shift': _getCurrentShift(),
        'day': _getCurrentDay(),
        if (oldData != null) 'old_data': oldData,
        if (newData != null) 'new_data': newData,
      };

      await _firestore.collection('medication_activity_logs').add(activityData);
      print('Medication activity logged: $action');
    } catch (e) {
      print('Error logging medication activity: $e');
    }
  }

  Future<void> _editMedication(
    String medicationId,
    Map<String, dynamic> medicationData,
  ) async {
    String? selectedMedicationTemp = medicationData['medication_name'];
    String? selectedDosageTemp = medicationData['dosage'];
    String? selectedIntervalTemp = medicationData['repeat_interval'];
    int? numberOfIntakesTemp = medicationData['number_of_intakes'];
    List<TimeOfDay?> intakeTimes = [];

    // Parse existing intake times
    final existingTimes = List<String>.from(
      medicationData['intake_times'] ?? [],
    );
    for (String timeStr in existingTimes) {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        intakeTimes.add(
          TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
        );
      }
    }

    // Fill remaining slots with null
    while (intakeTimes.length < 6) {
      intakeTimes.add(null);
    }

    final List<String> commonMedications = [
      'Lisinopril',
      'Metformin',
      'Atorvastatin',
      'Omeprazole',
      'Aspirin',
      'Levothyroxine',
    ];
    final List<String> commonDosages = [
      '5mg',
      '10mg',
      '25mg',
      '50mg',
      '100mg',
      '250mg',
      '500mg',
      '1g',
    ];
    final List<String> repeatIntervals = ['Once', 'Daily'];
    final List<int> intakeOptions = [1, 2, 3, 4, 5, 6];

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Edit Medication'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Medication Name
                    DropdownButtonFormField<String>(
                      value: selectedMedicationTemp,
                      decoration: InputDecoration(labelText: 'Medication Name'),
                      items: commonMedications.map((med) {
                        return DropdownMenuItem(value: med, child: Text(med));
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedMedicationTemp = value);
                      },
                    ),
                    SizedBox(height: 16),

                    // Dosage
                    DropdownButtonFormField<String>(
                      value: selectedDosageTemp,
                      decoration: InputDecoration(labelText: 'Dosage'),
                      items: commonDosages.map((dosage) {
                        return DropdownMenuItem(
                          value: dosage,
                          child: Text(dosage),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedDosageTemp = value);
                      },
                    ),
                    SizedBox(height: 16),

                    // Repeat Interval
                    DropdownButtonFormField<String>(
                      value: selectedIntervalTemp,
                      decoration: InputDecoration(labelText: 'Repeat'),
                      items: repeatIntervals.map((interval) {
                        return DropdownMenuItem(
                          value: interval,
                          child: Text(interval),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedIntervalTemp = value);
                      },
                    ),
                    SizedBox(height: 16),

                    // Number of Intakes
                    DropdownButtonFormField<int>(
                      value: numberOfIntakesTemp,
                      decoration: InputDecoration(
                        labelText: 'Number of Intakes',
                      ),
                      items: intakeOptions.map((count) {
                        return DropdownMenuItem(
                          value: count,
                          child: Text(count.toString()),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          numberOfIntakesTemp = value;
                          // Reset intake times when count changes
                          intakeTimes = List.generate(
                            6,
                            (index) => index < (value ?? 0)
                                ? (intakeTimes[index] ?? TimeOfDay.now())
                                : null,
                          );
                        });
                      },
                    ),
                    SizedBox(height: 16),

                    // Intake Times
                    if (numberOfIntakesTemp != null)
                      ...List.generate(numberOfIntakesTemp!, (index) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Text('${_getOrdinal(index + 1)} Intake:'),
                              SizedBox(width: 16),
                              Expanded(
                                child: TextButton(
                                  onPressed: () async {
                                    final time = await showTimePicker(
                                      context: context,
                                      initialTime:
                                          intakeTimes[index] ?? TimeOfDay.now(),
                                    );
                                    if (time != null) {
                                      setDialogState(
                                        () => intakeTimes[index] = time,
                                      );
                                    }
                                  },
                                  child: Text(
                                    intakeTimes[index]?.format(context) ??
                                        'Select Time',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (selectedMedicationTemp != null &&
                        selectedDosageTemp != null &&
                        selectedIntervalTemp != null &&
                        numberOfIntakesTemp != null) {
                      // Validate intake times
                      bool allTimesSelected = true;
                      for (int i = 0; i < numberOfIntakesTemp!; i++) {
                        if (intakeTimes[i] == null) {
                          allTimesSelected = false;
                          break;
                        }
                      }

                      if (!allTimesSelected) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Please select all intake times'),
                          ),
                        );
                        return;
                      }

                      try {
                        // Store old data for logging
                        final oldData = Map<String, dynamic>.from(
                          medicationData,
                        );

                        // Convert TimeOfDay to string format
                        final intakeTimeStrings = intakeTimes
                            .take(numberOfIntakesTemp!)
                            .map(
                              (time) =>
                                  '${time!.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                            )
                            .toList();

                        // Update take statuses to match new intake count
                        List<Map<String, dynamic>> updatedTakeStatuses = [];
                        final existingTakeStatuses =
                            List<Map<String, dynamic>>.from(
                              medicationData['take_statuses'] ?? [],
                            );

                        for (int i = 0; i < numberOfIntakesTemp!; i++) {
                          if (i < existingTakeStatuses.length) {
                            // Keep existing status but update scheduled time
                            updatedTakeStatuses.add({
                              ...existingTakeStatuses[i],
                              'scheduled_time': intakeTimeStrings[i],
                            });
                          } else {
                            // Add new take status
                            updatedTakeStatuses.add({
                              'take_number': i + 1,
                              'status': 'pending',
                              'scheduled_time': intakeTimeStrings[i],
                              'completed_at': null,
                              'completed_by': null,
                            });
                          }
                        }

                        final newData = {
                          'medication_name': selectedMedicationTemp,
                          'dosage': selectedDosageTemp,
                          'repeat_interval': selectedIntervalTemp,
                          'number_of_intakes': numberOfIntakesTemp,
                          'intake_times': intakeTimeStrings,
                          'take_statuses': updatedTakeStatuses,
                          'updated_at': FieldValue.serverTimestamp(),
                        };

                        // Update medication
                        await _firestore
                            .collection('medications')
                            .doc(medicationId)
                            .update(newData);

                        // Log the activity
                        await _logMedicationActivity(
                          action: 'edit_medication',
                          medicationId: medicationId,
                          medicationData: medicationData,
                          takeNumber: 0, // 0 for whole medication edit
                          oldData: oldData,
                          newData: newData,
                        );

                        Navigator.of(dialogContext).pop();
                        await _loadUpcomingMedications();

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Medication updated successfully'),
                          ),
                        );
                      } catch (e) {
                        print('Error updating medication: $e');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error updating medication')),
                        );
                      }
                    }
                  },
                  child: Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteIndividualTake(
    String medicationId,
    Map<String, dynamic> medicationData,
    int takeNumber,
  ) async {
    try {
      // Get current take statuses
      final takeStatuses = List<Map<String, dynamic>>.from(
        medicationData['take_statuses'] ?? [],
      );

      // Find the highest take number that still exists
      int highestTakeNumber = 0;
      for (var take in takeStatuses) {
        int currentTakeNumber = take['take_number'] as int;
        if (currentTakeNumber > highestTakeNumber) {
          highestTakeNumber = currentTakeNumber;
        }
      }

      // Validation: Can only delete from highest to lowest
      if (takeNumber < highestTakeNumber) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Hindi pwedeng burahin ang ${_getOrdinal(takeNumber)} take. '
              'Dapat muna burahin ang ${_getOrdinal(highestTakeNumber)} take.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      // Show confirmation dialog
      showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Text('Delete ${_getOrdinal(takeNumber)} Take'),
            content: Text(
              'Are you sure you want to delete the ${_getOrdinal(takeNumber)} take for ${medicationData['medication_name']}?\n\n'
              'This will remove this specific take and its schedule.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  try {
                    // Remove the specific take from take_statuses
                    takeStatuses.removeWhere(
                      (take) => take['take_number'] == takeNumber,
                    );

                    // Also remove from intake_times array
                    List<String> intakeTimes = List<String>.from(
                      medicationData['intake_times'] ?? [],
                    );
                    if (takeNumber <= intakeTimes.length) {
                      intakeTimes.removeAt(
                        takeNumber - 1,
                      ); // takeNumber is 1-based, array is 0-based
                    }

                    // Update number_of_intakes
                    int newIntakeCount = takeStatuses.length;

                    // Update the medication document
                    await _firestore
                        .collection('medications')
                        .doc(medicationId)
                        .update({
                          'take_statuses': takeStatuses,
                          'intake_times': intakeTimes,
                          'number_of_intakes': newIntakeCount,
                          'updated_at': FieldValue.serverTimestamp(),
                        });

                    // Using unified activity logs only - no separate collections to clean up

                    // Log the deletion activity
                    await _logMedicationActivity(
                      action: 'delete_individual_take',
                      medicationId: medicationId,
                      medicationData: medicationData,
                      takeNumber: takeNumber,
                      oldData: {
                        'take_number': takeNumber,
                        'take_statuses': medicationData['take_statuses'],
                      },
                    );

                    Navigator.of(dialogContext).pop();
                    await _loadUpcomingMedications();

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${_getOrdinal(takeNumber)} take deleted successfully',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    print('Error deleting individual take: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error deleting take'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: Text(
                  'Delete Take',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      );
    } catch (e) {
      print('Error in _deleteIndividualTake: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting take'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteMedication(
    String medicationId,
    Map<String, dynamic> medicationData,
  ) async {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Delete Entire Medication'),
          content: Text(
            'Are you sure you want to delete this entire medication: ${medicationData['medication_name']}?\n\n'
            'This action cannot be undone and will remove ALL takes and associated intake records.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                try {
                  // Log the deletion activity
                  await _logMedicationActivity(
                    action: 'delete_medication',
                    medicationId: medicationId,
                    medicationData: medicationData,
                    takeNumber: 0, // 0 for whole medication deletion
                    oldData: medicationData,
                  );

                  // Delete associated completed intake records
                  final completedIntakes = await _firestore
                      .collection('completed_medication_intakes')
                      .where('medication_id', isEqualTo: medicationId)
                      .get();

                  for (final doc in completedIntakes.docs) {
                    await doc.reference.delete();
                  }

                  // Delete associated missed intake records
                  final missedIntakes = await _firestore
                      .collection('missed_medication_intakes')
                      .where('medication_id', isEqualTo: medicationId)
                      .get();

                  for (final doc in missedIntakes.docs) {
                    await doc.reference.delete();
                  }

                  // Delete the medication itself
                  await _firestore
                      .collection('medications')
                      .doc(medicationId)
                      .delete();

                  Navigator.of(dialogContext).pop();
                  await _loadUpcomingMedications();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Medication deleted successfully')),
                  );
                } catch (e) {
                  print('Error deleting medication: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting medication')),
                  );
                }
              },
              child: Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  int _getTotalTakeCount() {
    int totalCount = 0;
    for (final medication in _upcomingMedications) {
      final takeStatuses = medication['take_statuses'] as List<dynamic>? ?? [];
      // Only count pending takes - exclude completed and missed
      final upcomingTakes = takeStatuses.where((take) {
        final status = take['status'] as String;
        return status == 'pending';
      }).toList();
      totalCount += upcomingTakes.length;
    }
    return totalCount;
  }

  Map<String, dynamic>? _getTakeInfoByIndex(int index) {
    int currentIndex = 0;

    for (final medication in _upcomingMedications) {
      final takeStatuses = medication['take_statuses'] as List<dynamic>? ?? [];

      // Sort take statuses by take_number
      takeStatuses.sort((a, b) {
        final aNum = a['take_number'] as int? ?? 0;
        final bNum = b['take_number'] as int? ?? 0;
        return aNum.compareTo(bNum);
      });

      // Only show pending takes - exclude completed and missed
      final upcomingTakes = takeStatuses.where((take) {
        final status = take['status'] as String;
        return status == 'pending';
      }).toList();

      for (final take in upcomingTakes) {
        if (currentIndex == index) {
          return {'medication': medication, 'take': take};
        }
        currentIndex++;
      }
    }
    return null;
  }

  Widget _buildIndividualTakeContainer(Map<String, dynamic> takeInfo) {
    final medication = takeInfo['medication'] as Map<String, dynamic>;
    final take = takeInfo['take'] as Map<String, dynamic>;

    final status = take['status'] as String;
    final takeNumber = take['take_number'] as int;
    final scheduledTime = take['scheduled_time'] as String;
    final takeOrdinal = _getOrdinal(takeNumber);

    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'complete':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'missed':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default: // pending
        statusColor = Colors.orange;
        statusIcon = Icons.schedule;
    }

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
                Icon(Icons.person, color: Color(0xFF00588E)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    medication['elderly_name'] ?? 'Unknown',
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
                Icon(Icons.medication, color: Colors.green),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${medication['medication_name']} - ${medication['dosage']}',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),

            // Frequency
            Row(
              children: [
                Icon(Icons.schedule, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Frequency: ${medication['repeat_interval']}',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
            SizedBox(height: 12),

            // Take Information Container
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: statusColor.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
                color: statusColor.withOpacity(0.1),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$takeOrdinal Take',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: statusColor,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Scheduled Time: $scheduledTime',
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
                      Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 4),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          size: 20,
                          color: statusColor,
                        ),
                        onSelected: (String newStatus) {
                          _updateTakeStatus(
                            medication['id'],
                            take['take_number'],
                            newStatus,
                          );
                        },
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<String>>[
                              PopupMenuItem<String>(
                                value: 'pending',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.schedule,
                                      color: Colors.orange,
                                      size: 16,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Pending'),
                                  ],
                                ),
                              ),
                              PopupMenuItem<String>(
                                value: 'complete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 16,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Complete'),
                                  ],
                                ),
                              ),
                              PopupMenuItem<String>(
                                value: 'missed',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.cancel,
                                      color: Colors.red,
                                      size: 16,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Missed'),
                                  ],
                                ),
                              ),
                            ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Created timestamp (smaller and at bottom)
            if (medication['created_at'] != null)
              Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Created: ${DateFormat('MMM dd, yyyy HH:mm').format((medication['created_at'] as Timestamp).toDate())}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ),

            // Action buttons section
            SizedBox(height: 12),

            // Individual Take Delete Button (only if this take is pending)
            if (status == 'pending')
              Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Center(
                  child: ElevatedButton.icon(
                    onPressed: () => _deleteIndividualTake(
                      medication['id'],
                      medication,
                      takeNumber,
                    ),
                    icon: Icon(Icons.remove_circle_outline, size: 16),
                    label: Text('Delete This ${_getOrdinal(takeNumber)} Take'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ),

            // Edit and Delete Entire Medication buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () =>
                      _editMedication(medication['id'], medication),
                  icon: Icon(Icons.edit, size: 16),
                  label: Text('Edit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () =>
                      _deleteMedication(medication['id'], medication),
                  icon: Icon(Icons.delete_forever, size: 16),
                  label: Text('Delete All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateTakeStatus(
    String medicationId,
    int takeNumber,
    String newStatus,
  ) async {
    try {
      final nurseId = await _getNurseId();

      // Get the medication document
      final medicationDoc = await _firestore
          .collection('medications')
          .doc(medicationId)
          .get();
      if (!medicationDoc.exists) return;

      final data = medicationDoc.data() as Map<String, dynamic>;
      final takeStatuses = List<Map<String, dynamic>>.from(
        data['take_statuses'] ?? [],
      );

      // Find and update the specific take
      Map<String, dynamic>? originalTake;
      final currentTime = DateTime.now();

      for (int i = 0; i < takeStatuses.length; i++) {
        if (takeStatuses[i]['take_number'] == takeNumber) {
          // Store original take data before modification
          originalTake = Map<String, dynamic>.from(takeStatuses[i]);

          takeStatuses[i]['status'] = newStatus;
          if (newStatus == 'complete') {
            takeStatuses[i]['completed_at'] = currentTime;
            takeStatuses[i]['completed_by'] = nurseId;
          } else {
            takeStatuses[i]['completed_at'] = null;
            takeStatuses[i]['completed_by'] = null;
          }
          break;
        }
      }

      // Handle activity logging
      if (originalTake != null) {
        final originalStatus = originalTake['status'] as String;
        print(
          'Status change: $originalStatus -> $newStatus for take $takeNumber',
        );

        // Log the activity based on the new status
        if (newStatus == 'complete' && originalStatus != 'complete') {
          await _logMedicationActivity(
            action: 'complete_take',
            medicationId: medicationId,
            medicationData: data,
            takeNumber: takeNumber,
            takeData: originalTake,
          );
        } else if (newStatus == 'missed' && originalStatus != 'missed') {
          await _logMedicationActivity(
            action: 'miss_take',
            medicationId: medicationId,
            medicationData: data,
            takeNumber: takeNumber,
            takeData: originalTake,
          );
        }
      }

      // Update the document
      await _firestore.collection('medications').doc(medicationId).update({
        'take_statuses': takeStatuses,
      });

      // Refresh the UI
      await _loadUpcomingMedications();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Take status updated to ${newStatus.toUpperCase()}'),
          backgroundColor: newStatus == 'complete'
              ? Colors.green
              : newStatus == 'missed'
              ? Colors.red
              : Colors.orange,
        ),
      );
    } catch (e) {
      print('Error updating take status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating status'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Activity logging is now handled directly in _updateTakeStatus method

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(
      children: [
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else
          // Medications List
          _upcomingMedications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.medication, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No upcoming medications',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.only(bottom: 80),
                  itemCount: _getTotalTakeCount(),
                  itemBuilder: (context, index) {
                    final takeInfo = _getTakeInfoByIndex(index);
                    if (takeInfo == null) return SizedBox.shrink();

                    return _buildIndividualTakeContainer(takeInfo);
                  },
                ),
        if (!_isLoading)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton.extended(
                onPressed: _showAddMedicationDialog,
                label: Text('Add Medication'),
                icon: Icon(Icons.add),
              ),
            ),
          ),
      ],
    );
  }
}
