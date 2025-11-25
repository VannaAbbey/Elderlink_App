import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'activity_report.dart';

class ActivityLogsScreen extends StatefulWidget {
  final String houseId;
  final String? nurseName;

  const ActivityLogsScreen({
    super.key,
    required this.houseId,
    required this.nurseName,
  });

  @override
  State<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

class _ActivityLogsScreenState extends State<ActivityLogsScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Tab Controller
  late TabController _tabController;

  // Medication Activities
  List<Map<String, dynamic>> _medicationLogs = [];
  bool _isMedicationLoading = false;
  String? _selectedElderlyMed;
  DateTime _selectedDateMed = DateTime.now();

  // Vitals Activities
  List<Map<String, dynamic>> _vitalsLogs = [];
  bool _isVitalsLoading = false;
  String? _selectedElderlyVitals;
  DateTime _selectedDateVitals = DateTime.now();

  // Common
  List<Map<String, String>> _elderlyList = [];

  // 🗑️ Cache removed - using direct Firestore queries for real-time comprehensive activity logs

  // 🆕 NEW: Shift summary data
  Map<String, dynamic> _shiftSummary = {};
  bool _isLoadingShiftSummary = false;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // Updated to 3 tabs
    _loadAssignedElderly();
    _loadMedicationLogs();
    _loadVitalsLogs();
    _loadShiftSummary(); // Load shift summary
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

  // 🆕 NEW: Get previous shift based on current shift
  String _getPreviousShift() {
    final currentShift = _getCurrentShift();
    switch (currentShift) {
      case '1st':
        return '3rd'; // 1st shift sees 3rd shift logs
      case '2nd':
        return '1st'; // 2nd shift sees 1st shift logs
      case '3rd':
        return '2nd'; // 3rd shift sees 2nd shift logs
      default:
        return '1st';
    }
  }

  // 🆕 NEW: Get day name for date
  String _getDayName(DateTime date) {
    return DateFormat('EEEE').format(date);
  }

  Future<void> _loadAssignedElderly() async {
    try {
      // Load all elderly for the specified house
      final elderlyQuery = await _firestore
          .collection('elderly')
          .where('house_id', isEqualTo: widget.houseId)
          .get();

      if (elderlyQuery.docs.isEmpty) return;

      final newElderlyList = elderlyQuery.docs.map((doc) {
        final data = doc.data();
        final firstName = data['elderly_fname'];
        final lastName = data['elderly_lname'];
        final fullName = '${firstName ?? ''} ${lastName ?? ''}'.trim();

        return {
          'id': doc.id,
          'name': fullName.isNotEmpty ? fullName : 'Unknown',
        };
      }).toList();

      // Sort alphabetically by name
      newElderlyList.sort((a, b) => a['name']!.compareTo(b['name']!));

      setState(() {
        _elderlyList = newElderlyList;
      });
    } catch (e) {
      print('Error loading elderly for house: $e');
    }
  }

  // 🆕 NEW: Load shift summary from previous shift
  Future<void> _loadShiftSummary() async {
    setState(() {
      _isLoadingShiftSummary = true;
    });

    try {
      final previousShift = _getPreviousShift();
      final dayName = _getDayName(_selectedDate);

      print(
        '🔄 Loading shift summary for previous shift: $previousShift on $dayName',
      );

      // Get nurses from previous shift in the same house
      final previousShiftNurseQuery = await _firestore
          .collection('house_shift_assignments')
          .where('house_id', isEqualTo: widget.houseId)
          .where('shift', isEqualTo: previousShift)
          .where('user_type', isEqualTo: 'nurse')
          .get();

      final previousShiftNurseIds = <String>[];

      // Filter nurses by who was scheduled to work on the selected day
      for (var doc in previousShiftNurseQuery.docs) {
        final data = doc.data();
        final nurseId = data['user_id'] as String?;
        final daysAssigned = data['days_assigned'] as List<dynamic>? ?? [];

        if (nurseId != null && daysAssigned.contains(dayName)) {
          previousShiftNurseIds.add(nurseId);
        }
      }

      print(
        '🏥 Found ${previousShiftNurseIds.length} nurses from previous shift',
      );

      if (previousShiftNurseIds.isEmpty) {
        setState(() {
          _shiftSummary = {
            'totalCompleted': 0,
            'totalMissed': 0,
            'medicationCompleted': 0,
            'medicationMissed': 0,
            'vitalsCompleted': 0,
            'vitalsMissed': 0,
            'previousShift': previousShift,
          };
          _isLoadingShiftSummary = false;
        });
        return;
      }

      // Get completed and missed tasks from previous shift
      final startOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final endOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        23,
        59,
        59,
      );

      // Count medication activities
      final medicationQuery = await _firestore
          .collection('medication_activity_logs')
          .where('nurse_id', whereIn: previousShiftNurseIds)
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .get();

      int medicationCompleted = 0;
      int medicationMissed = 0;

      for (var doc in medicationQuery.docs) {
        final data = doc.data();
        final action = data['action'] as String?;
        if (action == 'take_completed') {
          medicationCompleted++;
        } else if (action == 'miss_take') {
          medicationMissed++;
        }
      }

      // Count vital activities
      final vitalsQuery = await _firestore
          .collection('vitals_activity_logs')
          .where('nurse_id', whereIn: previousShiftNurseIds)
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .get();

      int vitalsCompleted = 0;
      int vitalsMissed = 0;

      for (var doc in vitalsQuery.docs) {
        final data = doc.data();
        final actionType = data['action_type'] as String?;
        if (actionType == 'vital_completed' || actionType == 'vital_recorded') {
          vitalsCompleted++;
        } else if (actionType == 'vital_missed') {
          vitalsMissed++;
        }
      }

      setState(() {
        _shiftSummary = {
          'totalCompleted': medicationCompleted + vitalsCompleted,
          'totalMissed': medicationMissed + vitalsMissed,
          'medicationCompleted': medicationCompleted,
          'medicationMissed': medicationMissed,
          'vitalsCompleted': vitalsCompleted,
          'vitalsMissed': vitalsMissed,
          'previousShift': previousShift,
        };
        _isLoadingShiftSummary = false;
      });

      print('📊 Shift summary loaded: ${_shiftSummary}');
    } catch (e) {
      print('❌ Error loading shift summary: $e');
      setState(() {
        _shiftSummary = {};
        _isLoadingShiftSummary = false;
      });
    }
  }

  Future<void> _loadMedicationLogs() async {
    setState(() {
      _isMedicationLoading = true;
    });

    try {
      Query query;

      // Build query differently based on whether we're filtering by elderly or not
      if (_selectedElderlyMed != null && _selectedElderlyMed!.isNotEmpty) {
        // When filtering by elderly, use where clauses without orderBy to avoid index issues
        query = _firestore
            .collection('medication_activity_logs')
            .where('elderly_id', isEqualTo: _selectedElderlyMed)
            .limit(100);
      } else {
        // When showing all activities, query all houses
        query = _firestore.collection('medication_activity_logs').limit(100);
      }

      final querySnapshot = await query.get();
      final activities = <Map<String, dynamic>>[];

      // Create date range for the selected date (start and end of day)
      final startOfDay = DateTime(
        _selectedDateMed.year,
        _selectedDateMed.month,
        _selectedDateMed.day,
      );
      final endOfDay = DateTime(
        _selectedDateMed.year,
        _selectedDateMed.month,
        _selectedDateMed.day,
        23,
        59,
        59,
      );

      for (final doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final timestamp = data['timestamp'] as Timestamp?;

        // Filter by date on client side
        if (timestamp != null) {
          final activityDate = timestamp.toDate();
          if (activityDate.isBefore(startOfDay) ||
              activityDate.isAfter(endOfDay)) {
            continue; // Skip this activity if it's not on the selected date
          }
        }

        // Get elderly gender for proper title (Lola/Lolo)
        String elderlyTitle = 'Lola'; // Default to female
        try {
          final elderlyDoc = await _firestore
              .collection('elderly')
              .doc(data['elderly_id'])
              .get();

          if (elderlyDoc.exists) {
            final elderlyData = elderlyDoc.data() as Map<String, dynamic>;
            final gender = elderlyData['elderly_gender'] as String?;
            elderlyTitle = (gender?.toLowerCase() == 'male') ? 'Lolo' : 'Lola';
          }
        } catch (e) {
          print('Error getting elderly gender: $e');
        }

        activities.add({'id': doc.id, 'elderly_title': elderlyTitle, ...data});
      }

      // Remove duplicate 'create' actions for the same medication
      final seenCreateMedications = <String>{};
      final deduplicatedActivities = <Map<String, dynamic>>[];

      for (final activity in activities) {
        final action = activity['action'] as String?;
        final medicationId = activity['medication_id'] as String?;

        if (action == 'create' && medicationId != null) {
          if (!seenCreateMedications.contains(medicationId)) {
            seenCreateMedications.add(medicationId);
            deduplicatedActivities.add(activity);
          }
          // Skip duplicate create actions for the same medication
        } else {
          // Keep all other actions (take_completed, miss_take, etc.)
          deduplicatedActivities.add(activity);
        }
      }

      // Sort activities by timestamp in code instead of in query
      deduplicatedActivities.sort((a, b) {
        final aTimestamp = a['timestamp'] as Timestamp?;
        final bTimestamp = b['timestamp'] as Timestamp?;

        if (aTimestamp == null && bTimestamp == null) return 0;
        if (aTimestamp == null) return 1;
        if (bTimestamp == null) return -1;

        return bTimestamp.compareTo(
          aTimestamp,
        ); // Descending order (newest first)
      });

      setState(() {
        _medicationLogs = deduplicatedActivities;
        _isMedicationLoading = false;
      });
    } catch (e) {
      print('❌ Error loading medication logs: $e');
      setState(() {
        _isMedicationLoading = false;
        _medicationLogs = [];
      });
    }
  }

  // 🆕 FEATURE 2 & 3: Load comprehensive vital recordings from ALL shifts and nurses
  Future<void> _loadVitalsLogs() async {
    setState(() {
      _isVitalsLoading = true;
    });

    try {
      // Create extended date range to include previous shifts (7 days)
      final selectedStartOfDay = DateTime(
        _selectedDateVitals.year,
        _selectedDateVitals.month,
        _selectedDateVitals.day,
      );
      final endOfDay = DateTime(
        _selectedDateVitals.year,
        _selectedDateVitals.month,
        _selectedDateVitals.day,
        23,
        59,
        59,
      );
      // Extend range to 7 days back to show previous shift tasks
      final startOfDay = selectedStartOfDay.subtract(const Duration(days: 7));

      // 🆕 ENHANCED: Query for comprehensive logs including missed tasks from previous shifts
      Query query = _firestore
          .collection('vitals_activity_logs')
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('timestamp', descending: true)
          .limit(300); // Increased limit to show more activities

      // Apply elderly filter if selected
      if (_selectedElderlyVitals != null &&
          _selectedElderlyVitals!.isNotEmpty) {
        query = _firestore
            .collection('vitals_activity_logs')
            .where('elderly_id', isEqualTo: _selectedElderlyVitals)
            .where(
              'timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
            )
            .where(
              'timestamp',
              isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
            )
            .orderBy('timestamp', descending: true)
            .limit(300);
      }

      final querySnapshot = await query.get();
      final activities = <Map<String, dynamic>>[];
      final missedTasksFromPreviousShifts = <Map<String, dynamic>>[];

      for (final doc in querySnapshot.docs) {
        try {
          final docData = doc.data();
          if (docData == null) continue; // Skip if data is null

          // Safe type conversion from Firestore document data
          final data = <String, dynamic>{};
          if (docData is Map) {
            docData.forEach((key, value) {
              if (key is String) {
                data[key] = value;
              }
            });
          }
          if (data.isEmpty) continue; // Skip if data is empty

          final timestamp = data['timestamp'] as Timestamp?;
          final actionType =
              data['action_type'] as String? ?? 'vital_completed';

          // 🆕 FEATURE 3: Separate tasks from previous shifts (both completed and missed)
          final activityDate = timestamp?.toDate();
          final assignedDate = data['assigned_date'] as String?;
          final isFromPreviousShift =
              activityDate != null && activityDate.isBefore(selectedStartOfDay);

          if (isFromPreviousShift) {
            // This is a task from previous shifts (completed or missed)
            int daysDifference = 0;
            if (assignedDate != null) {
              try {
                final assignedDateTime = DateFormat(
                  'yyyy-MM-dd',
                ).parse(assignedDate);
                daysDifference = selectedStartOfDay
                    .difference(assignedDateTime)
                    .inDays;
              } catch (e) {
                print('Error parsing assigned date: $e');
              }
            }

            missedTasksFromPreviousShifts.add({
              'id': doc.id,
              'type': actionType == 'vital_missed'
                  ? 'missed_from_previous'
                  : 'completed_from_previous',
              'days_ago': daysDifference,
              ...data,
            });
            continue; // Don't include in regular activities
          }

          // 🆕 ENHANCED: Get names with better caching and error handling
          String elderlyName = data['elderly_name'] as String? ?? 'Unknown';
          String elderlyTitle = 'Lola'; // Default to female
          String nurseName = data['nurse_name'] as String? ?? 'Unknown Nurse';

          // If names are not in the log, fetch them
          if (elderlyName == 'Unknown' || nurseName == 'Unknown Nurse') {
            try {
              final elderlyId = data['elderly_id'] as String?;
              final nurseId = data['nurse_id'] as String?;

              // Get elderly info if needed
              if (elderlyId != null && elderlyName == 'Unknown') {
                final elderlyDoc = await _firestore
                    .collection('elderly')
                    .doc(elderlyId)
                    .get();

                if (elderlyDoc.exists) {
                  final elderlyData = elderlyDoc.data();
                  if (elderlyData != null) {
                    elderlyName =
                        '${elderlyData['elderly_fname'] ?? 'Unknown'} ${elderlyData['elderly_lname'] ?? 'Elderly'}'
                            .trim();
                    final gender = elderlyData['elderly_gender'] as String?;
                    elderlyTitle = (gender?.toLowerCase() == 'male')
                        ? 'Lolo'
                        : 'Lola';
                  }
                }
              }

              // Get nurse name if needed
              if (nurseId != null &&
                  (nurseName == 'Unknown Nurse' || nurseName.isEmpty)) {
                final nurseDoc = await _firestore
                    .collection('users')
                    .doc(nurseId)
                    .get();

                if (nurseDoc.exists) {
                  final nurseData = nurseDoc.data();
                  if (nurseData != null) {
                    nurseName =
                        '${nurseData['user_fname'] ?? ''} ${nurseData['user_lname'] ?? ''}'
                            .trim();
                    if (nurseName.isEmpty) nurseName = 'Unknown Nurse';
                  }
                }
              }
            } catch (e) {
              print('Error getting names: $e');
            }
          }

          // Set title based on existing elderly name pattern or gender
          if (elderlyTitle == 'Lola' && elderlyName.isNotEmpty) {
            // Try to determine gender from database if not already set
            try {
              final elderlyId = data['elderly_id'] as String?;
              if (elderlyId != null) {
                final elderlyDoc = await _firestore
                    .collection('elderly')
                    .doc(elderlyId)
                    .get();
                if (elderlyDoc.exists) {
                  final gender =
                      elderlyDoc.data()?['elderly_gender'] as String?;
                  elderlyTitle = (gender?.toLowerCase() == 'male')
                      ? 'Lolo'
                      : 'Lola';
                }
              }
            } catch (e) {
              // Keep default
            }
          }

          // Add activity with enhanced data
          activities.add({
            'id': doc.id,
            'elderly_title': elderlyTitle,
            'action_type': actionType,
            'elderly_name': elderlyName,
            'nurse_name': nurseName,
            'timestamp': data['timestamp'],
            'shift': data['shift'] ?? _getCurrentShift(),
            'new_values': (() {
              final rawValues = data['new_values'] ?? data['new_value'];
              if (rawValues == null) return <String, dynamic>{};
              if (rawValues is Map) {
                final safeMap = <String, dynamic>{};
                rawValues.forEach((key, value) {
                  if (key is String) safeMap[key] = value;
                });
                return safeMap;
              }
              return <String, dynamic>{};
            })(),
            'remarks': data['remarks'] ?? '',
            'house_id': data['house_id'] ?? widget.houseId,
            'assigned_date': data['assigned_date'],
            ...data, // Spread data
          });
        } catch (e) {
          print('Error processing vital activity document ${doc.id}: $e');
          continue; // Skip this document and continue with the next
        }
      }

      // 🆕 FEATURE 3: Combine regular activities with missed tasks from previous shifts
      final combinedActivities = <Map<String, dynamic>>[];

      // Add missed tasks from previous shifts at the top (with special styling)
      if (missedTasksFromPreviousShifts.isNotEmpty) {
        combinedActivities.addAll(missedTasksFromPreviousShifts);
      }

      // Add regular activities
      combinedActivities.addAll(activities);

      // Sort combined activities by timestamp (newest first, but keep missed tasks grouped at top if from different days)
      combinedActivities.sort((a, b) {
        final aTimestamp = a['timestamp'] as Timestamp?;
        final bTimestamp = b['timestamp'] as Timestamp?;
        final aType = a['type'] as String?;
        final bType = b['type'] as String?;

        // Keep tasks from previous shifts at top
        final aIsFromPrevious =
            aType == 'missed_from_previous' ||
            aType == 'completed_from_previous';
        final bIsFromPrevious =
            bType == 'missed_from_previous' ||
            bType == 'completed_from_previous';

        if (aIsFromPrevious && !bIsFromPrevious) return -1;
        if (bIsFromPrevious && !aIsFromPrevious) return 1;

        if (aTimestamp == null && bTimestamp == null) return 0;
        if (aTimestamp == null) return 1;
        if (bTimestamp == null) return -1;

        return bTimestamp.compareTo(
          aTimestamp,
        ); // Descending order (newest first)
      });

      setState(() {
        _vitalsLogs = combinedActivities;
        _isVitalsLoading = false;
      });
    } catch (e) {
      print('❌ Error loading vitals logs: $e');
      setState(() {
        _isVitalsLoading = false;
        _vitalsLogs = [];
      });
    }
  }

  String _formatMedicationActivityMessage(Map<String, dynamic> activity) {
    final action = activity['action'] as String;
    final nurseName = activity['nurse_name'] as String;
    final elderlyName = activity['elderly_name'] as String;
    final elderlyTitle = activity['elderly_title'] as String;
    final medicationName = activity['medication_name'] as String;
    final takeOrdinal = activity['take_ordinal'] as String?;
    final takeNumber = activity['take_number'] as int?;

    switch (action) {
      case 'create':
        return 'Nurse $nurseName created medication "$medicationName" for $elderlyTitle $elderlyName';

      case 'take_completed':
        final takeText = takeNumber != null
            ? _getOrdinalFromNumber(takeNumber)
            : (takeOrdinal ?? '1st');
        return 'Nurse $nurseName completed the $takeText take of "$medicationName" for $elderlyTitle $elderlyName';

      case 'miss_take':
      case 'take_missed':
        return 'Nurse $nurseName missed the medication "$medicationName" for $elderlyTitle $elderlyName';

      case 'edit_medication':
        return 'Nurse $nurseName edited the medication details of "$medicationName" for $elderlyTitle $elderlyName';

      case 'delete_medication':
        return 'Nurse $nurseName deleted the medication "$medicationName" of $elderlyTitle $elderlyName';

      case 'delete_individual_take':
        return 'Nurse $nurseName deleted the $takeOrdinal take of "$medicationName" for $elderlyTitle $elderlyName';

      case 'add_medication':
        return 'Nurse $nurseName added new medication "$medicationName" for $elderlyTitle $elderlyName';

      case 'status_change':
        final oldStatus = activity['old_status'] as String?;
        final newStatus = activity['new_status'] as String?;
        return 'Nurse $nurseName changed the status of "$medicationName" ${takeOrdinal != null ? "($takeOrdinal take)" : ""} for $elderlyTitle $elderlyName from ${oldStatus?.toUpperCase() ?? "UNKNOWN"} to ${newStatus?.toUpperCase() ?? "UNKNOWN"}';

      default:
        return 'Nurse $nurseName performed $action on medication "$medicationName" for $elderlyTitle $elderlyName';
    }
  }

  // 🔧 NEW: Format vital activity messages with better action descriptions
  String _formatVitalActivityMessage(Map<String, dynamic> activity) {
    final actionType = activity['action_type'] as String? ?? 'vital_recorded';
    final nurseName = activity['nurse_name'] as String? ?? 'Unknown Nurse';
    final elderlyName = activity['elderly_name'] as String? ?? 'Unknown';
    final elderlyTitle = activity['elderly_title'] as String? ?? 'Lola';
    final newValues =
        (activity['new_values'] ?? activity['new_value'])
            as Map<String, dynamic>? ??
        {};

    switch (actionType.toLowerCase()) {
      case 'vital_recorded':
      case 'vital_completed':
      case 'vitals_completed':
        if (newValues.isNotEmpty) {
          final vitals = <String>[];
          if (newValues['blood_pressure'] != null) {
            vitals.add('BP: ${newValues['blood_pressure']}');
          }
          if (newValues['pulse_rate'] != null) {
            vitals.add('Pulse: ${newValues['pulse_rate']}');
          }
          if (newValues['oxygen_saturation'] != null) {
            vitals.add('O2: ${newValues['oxygen_saturation']}%');
          }
          if (newValues['temperature'] != null) {
            vitals.add('Temp: ${newValues['temperature']}°C');
          }
          if (newValues['respiratory_rate'] != null) {
            vitals.add('RR: ${newValues['respiratory_rate']}');
          }

          final vitalsList = vitals.isNotEmpty ? vitals.join(', ') : 'vitals';
          return 'Nurse $nurseName completed vital signs ($vitalsList) for $elderlyTitle $elderlyName';
        }
        return 'Nurse $nurseName completed vital signs for $elderlyTitle $elderlyName';

      case 'vital_verified':
        return 'Nurse $nurseName verified the vitals of $elderlyTitle $elderlyName';

      case 'vital_updated':
        return 'Nurse $nurseName updated the vitals of $elderlyTitle $elderlyName';

      case 'vital_missed':
      case 'missed':
        return 'Nurse $nurseName marked vitals as MISSED for $elderlyTitle $elderlyName';

      default:
        // For backward compatibility, treat any other type as completed
        return 'Nurse $nurseName completed vital signs for $elderlyTitle $elderlyName';
    }
  }

  String _getOrdinalFromNumber(int number) {
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

  Color _getMedicationActionColor(String action) {
    switch (action) {
      case 'create':
        return Colors.blue;
      case 'create_medication':
      case 'add_medication':
        return Colors.orange;
      case 'take_completed':
        return Colors.green;
      case 'miss_take':
      case 'take_missed':
        return Colors.red;
      case 'edit_medication':
        return Colors.purple;
      case 'delete_medication':
      case 'delete_individual_take':
        return Colors.redAccent;
      case 'status_change':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  // 🔧 NEW: Get color for vital actions
  Color _getVitalActionColor(String actionType) {
    switch (actionType.toLowerCase()) {
      case 'vital_recorded':
      case 'vital_completed':
      case 'vitals_completed':
        return Colors.green;
      case 'vital_verified':
        return Colors.blue;
      case 'vital_updated':
        return Colors.orange;
      case 'vital_missed':
      case 'missed':
        return Colors.red;
      default:
        return Colors.green; // Default to green for completed vitals
    }
  }

  IconData _getMedicationActionIcon(String action) {
    switch (action) {
      case 'create_medication':
      case 'add_medication':
        return Icons.add_circle;
      case 'take_completed':
        return Icons.check_circle;
      case 'miss_take':
      case 'take_missed':
        return Icons.cancel;
      case 'edit_medication':
        return Icons.edit;
      case 'delete_medication':
      case 'delete_individual_take':
        return Icons.delete;
      case 'status_change':
        return Icons.update;
      default:
        return Icons.info;
    }
  }

  // 🔧 NEW: Get icon for vital actions
  IconData _getVitalActionIcon(String actionType) {
    switch (actionType.toLowerCase()) {
      case 'vital_recorded':
      case 'vital_completed':
      case 'vitals_completed':
        return Icons.check_circle;
      case 'vital_verified':
        return Icons.verified;
      case 'vital_updated':
        return Icons.edit;
      case 'vital_missed':
      case 'missed':
        return Icons.cancel;
      default:
        return Icons.favorite; // Default to heart for vital signs
    }
  }

  Widget _buildMedicationActivityCard(Map<String, dynamic> activity) {
    final action = activity['action'] as String;
    final actionColor = _getMedicationActionColor(action);
    final actionIcon = _getMedicationActionIcon(action);
    final message = _formatMedicationActivityMessage(activity);
    final dateFormat = DateFormat('MMM dd, yyyy');
    final timeFormat = DateFormat('h:mm a');
    final activityTimestamp = (activity['timestamp'] as Timestamp).toDate();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      color: const Color(0xFFF5F5F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Badge and Timestamp
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: actionColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(actionIcon, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          _getMedicationActionLabel(action),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${dateFormat.format(activityTimestamp)} at ${timeFormat.format(activityTimestamp)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Activity Message
              Text(
                message,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),

              // Medication name (if available)
              if (activity['medication_name'] != null &&
                  activity['medication_name'].toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: actionColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: actionColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'Medication: ${activity['medication_name']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: actionColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to get action label
  String _getMedicationActionLabel(String action) {
    switch (action) {
      case 'create':
        return 'Created';
      case 'take_completed':
        return 'Administered';
      case 'miss_take':
      case 'take_missed':
        return 'Missed';
      case 'update':
        return 'Updated';
      case 'delete':
        return 'Deleted';
      default:
        return action.toUpperCase();
    }
  }

  // 🔧 NEW: Build vital activity card
  Widget _buildVitalActivityCard(Map<String, dynamic> activity) {
    final actionType = activity['action_type'] as String? ?? 'vital_recorded';

    // 🆕 FEATURE 3: Check if this is a task from previous shift
    final isFromPreviousShift =
        activity['type'] == 'missed_from_previous' ||
        activity['type'] == 'completed_from_previous';
    final isMissedFromPrevious = activity['type'] == 'missed_from_previous';

    // Determine display label/icon/color. For auto-marked missed entries
    // (created by system/daily reset), override the badge in the UI only
    // to show a red "Missed" label without modifying stored data.
    bool isAutoMissed = false;
    try {
      final nurseNameField = (activity['nurse_name'] as String?) ?? '';
      final autoFlag = activity['auto_marked'] as bool?;
      final sourceField = (activity['source'] as String?) ?? '';
      final createdBy = (activity['created_by'] as String?) ?? '';

      if (actionType.toLowerCase() == 'vital_missed' &&
          (nurseNameField.toLowerCase() == 'system' ||
              autoFlag == true ||
              sourceField.toLowerCase() == 'system' ||
              createdBy.toLowerCase() == 'system')) {
        isAutoMissed = true;
      }
    } catch (e) {
      // ignore and treat as non-auto
      isAutoMissed = false;
    }

    final actionColor = isFromPreviousShift
        ? (isMissedFromPrevious ? Colors.red.shade700 : Colors.blue.shade600)
        : (isAutoMissed ? Colors.red : _getVitalActionColor(actionType));

    final actionIcon = isFromPreviousShift
        ? (isMissedFromPrevious ? Icons.warning : Icons.history)
        : (isAutoMissed ? Icons.cancel : _getVitalActionIcon(actionType));
    final message = _formatVitalActivityMessage(activity);
    final dateFormat = DateFormat('MMM dd, yyyy');
    final timeFormat = DateFormat('h:mm a');

    // Safe timestamp handling to prevent casting errors
    final timestamp = activity['timestamp'] as Timestamp?;
    final activityTimestamp = timestamp?.toDate() ?? DateTime.now();

    // Safe handling of new_values to prevent type casting errors
    final newValuesRaw = activity['new_values'] ?? activity['new_value'];
    final newValues = <String, dynamic>{};
    if (newValuesRaw != null && newValuesRaw is Map) {
      newValuesRaw.forEach((key, value) {
        if (key is String) {
          newValues[key] = value;
        }
      });
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: isFromPreviousShift ? 4 : 2,
      color: isFromPreviousShift
          ? (isMissedFromPrevious ? Colors.red.shade50 : Colors.blue.shade50)
          : const Color(0xFFF5F5F5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isFromPreviousShift
            ? BorderSide(
                color: isMissedFromPrevious
                    ? Colors.red.shade300
                    : Colors.blue.shade300,
                width: 1.5,
              )
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🆕 Special header for tasks from previous shifts
              if (isFromPreviousShift) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isMissedFromPrevious
                        ? Colors.red.shade100
                        : Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isMissedFromPrevious
                          ? Colors.red.shade300
                          : Colors.blue.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isMissedFromPrevious ? Icons.warning : Icons.history,
                        color: isMissedFromPrevious
                            ? Colors.red.shade700
                            : Colors.blue.shade700,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isMissedFromPrevious
                            ? 'Missed from Previous Shift'
                            : 'Completed from Previous Shift',
                        style: TextStyle(
                          color: isMissedFromPrevious
                              ? Colors.red.shade700
                              : Colors.blue.shade700,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Top Row: Badge and Timestamp
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: actionColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(actionIcon, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          // UI-only override for auto-marked missed entries:
                          // show 'Missed' (red badge) in the UI but keep the
                          // underlying activity log unchanged.
                          isFromPreviousShift
                              ? (isMissedFromPrevious ? 'MISSED' : 'COMPLETED')
                              : (isAutoMissed
                                    ? 'Missed'
                                    : _getVitalActionLabel(actionType)),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${dateFormat.format(activityTimestamp)} at ${timeFormat.format(activityTimestamp)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Activity Message
              Text(
                message,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),

              // Shift Badge (if available)
              if (activity['shift'] != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '${activity['shift'] ?? 'Unknown'} shift',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],

              // Vital Signs Details (if available)
              if (newValues.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (newValues['blood_pressure'] != null)
                      _buildVitalChip(
                        'BP',
                        '${newValues['blood_pressure']}',
                        Colors.red,
                      ),
                    if (newValues['pulse_rate'] != null)
                      _buildVitalChip(
                        'Pulse',
                        '${newValues['pulse_rate']} bpm',
                        Colors.blue,
                      ),
                    if (newValues['oxygen_saturation'] != null)
                      _buildVitalChip(
                        'O2',
                        '${newValues['oxygen_saturation']}%',
                        Colors.green,
                      ),
                    if (newValues['temperature'] != null)
                      _buildVitalChip(
                        'Temp',
                        '${newValues['temperature']}°C',
                        Colors.orange,
                      ),
                    if (newValues['respiratory_rate'] != null)
                      _buildVitalChip(
                        'RR',
                        '${newValues['respiratory_rate']}',
                        Colors.purple,
                      ),
                  ],
                ),
              ],

              // Remarks (if available)
              if (activity['remarks'] != null &&
                  activity['remarks'].toString().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.note, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          activity['remarks'].toString(),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to get vital action label
  String _getVitalActionLabel(String actionType) {
    switch (actionType.toLowerCase()) {
      case 'vital_recorded':
        return 'Recorded';
      case 'vital_completed':
      case 'vitals_completed':
        return 'Completed';
      case 'vital_verified':
        return 'Verified';
      case 'vital_updated':
        return 'Updated';
      case 'vital_deleted':
        return 'Deleted';
      case 'vital_missed':
      case 'missed':
        return 'Missed';
      default:
        return 'Recorded';
    }
  }

  // 🔧 NEW: Build vital sign chips
  Widget _buildVitalChip(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/background1.png',
              fit: BoxFit.cover,
            ),
          ),

          // Main Content
          SafeArea(
            child: Column(
              children: [
                // Header Row
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back,
                          size: 30,
                          color: Color(0xFF00588E),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Activity Logs",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF00588E),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.print, color: Color(0xFF00588E)),
                        iconSize: 30,
                        tooltip: 'Generate PDF Report',
                        onPressed: () async {
                          final report = ActivityReport();
                          await report.generateAndShareReport(
                            houseId: widget.houseId,
                            nurseName: widget.nurseName ?? 'Unknown Nurse',
                            context: context,
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // Tab Bar - Enhanced with Shift Summary
                Material(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.access_time, color: Color(0xFF00588E)),
                        text: 'Shift Summary',
                      ),
                      Tab(
                        icon: Icon(Icons.medication, color: Color(0xFF00588E)),
                        text: 'Medications',
                      ),
                      Tab(
                        icon: Icon(Icons.favorite, color: Color(0xFF00588E)),
                        text: 'Vital Signs',
                      ),
                    ],
                    indicatorColor: const Color(0xFF00588E),
                    labelColor: const Color(0xFF00588E),
                    unselectedLabelColor: Colors.grey,
                  ),
                ),

                // Tab Content
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      TabBarView(
                        controller: _tabController,
                        clipBehavior: Clip.none,
                        children: [
                          // Shift Summary Tab
                          _buildShiftSummaryTab(),
                          // Medication Activities Tab
                          _buildMedicationTab(),
                          // Vitals Activities Tab
                          _buildVitalsTab(),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicationTab() {
    return Column(
      children: [
        // Filter Section
        Material(
          elevation: 0,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.none,
          child: Container(
            margin: EdgeInsets.all(16),
            padding: EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.grey[50]?.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Elderly Filter
                Text(
                  'Filter by Elderly:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Color(0xFF00588E),
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Color(0xFF00588E)),
                    borderRadius: BorderRadius.circular(8),
                    color: const Color(0xFFD8F4FF),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedElderlyMed,
                    isExpanded: true,
                    hint: Text('All Elderly'),
                    icon: Icon(Icons.arrow_drop_down, color: Color(0xFF00588E)),
                    dropdownColor: Colors.white,
                    underline: Container(),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text('All Elderly'),
                      ),
                      ..._elderlyList.map((elderly) {
                        return DropdownMenuItem<String>(
                          value: elderly['id'],
                          child: Text(elderly['name']!),
                        );
                      }),
                    ],
                    onChanged: (String? value) {
                      setState(() {
                        _selectedElderlyMed = value;
                      });
                      _loadMedicationLogs();
                    },
                  ),
                ),
                SizedBox(height: 16),

                // Date Filter Row
                Row(
                  children: [
                    Text(
                      'Date: ${DateFormat('MMM d, yyyy').format(_selectedDateMed)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Color(0xFF00588E),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Total: ${_medicationLogs.length} activities',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDateMed,
                          firstDate: DateTime(2023),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null && picked != _selectedDateMed) {
                          setState(() {
                            _selectedDateMed = picked;
                          });
                          _loadMedicationLogs();
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Color(0xFF00588E),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.calendar_today,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Medication Logs List
        Expanded(
          child: _isMedicationLoading
              ? Center(child: CircularProgressIndicator())
              : _medicationLogs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.medication, size: 64, color: Colors.grey[400]),
                      SizedBox(height: 16),
                      Text(
                        'No medication activities',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'No medication activities found for the selected date and filters.',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Try selecting a different date or clearing filters.',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMedicationLogs,
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    itemCount: _medicationLogs.length,
                    itemBuilder: (context, index) {
                      return _buildMedicationActivityCard(
                        _medicationLogs[index],
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildVitalsTab() {
    return Column(
      children: [
        // Filter Section
        Material(
          elevation: 0,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.none,
          child: Container(
            margin: EdgeInsets.all(16),
            padding: EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.grey[50]?.withValues(alpha: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Elderly Filter
                Text(
                  'Filter by Elderly:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Color(0xFF00588E),
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Color(0xFF00588E)),
                    borderRadius: BorderRadius.circular(8),
                    color: const Color(0xFFD8F4FF),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedElderlyVitals,
                    isExpanded: true,
                    hint: Text('All Elderly'),
                    icon: Icon(Icons.arrow_drop_down, color: Color(0xFF00588E)),
                    dropdownColor: Colors.white,
                    underline: Container(),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text('All Elderly'),
                      ),
                      ..._elderlyList.map((elderly) {
                        return DropdownMenuItem<String>(
                          value: elderly['id'],
                          child: Text(elderly['name']!),
                        );
                      }),
                    ],
                    onChanged: (String? value) {
                      setState(() {
                        _selectedElderlyVitals = value;
                      });
                      _loadVitalsLogs();
                    },
                  ),
                ),
                SizedBox(height: 16),

                // Date Filter Row
                Row(
                  children: [
                    Text(
                      'Date: ${DateFormat('MMM d, yyyy').format(_selectedDateVitals)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Color(0xFF00588E),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Total: ${_vitalsLogs.length} activities',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDateVitals,
                          firstDate: DateTime(2023),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null && picked != _selectedDateVitals) {
                          setState(() {
                            _selectedDateVitals = picked;
                          });
                          _loadVitalsLogs();
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Color(0xFF00588E),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.calendar_today,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Vitals Logs List
        Expanded(
          child: _isVitalsLoading
              ? Center(child: CircularProgressIndicator())
              : _vitalsLogs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite, size: 64, color: Colors.grey[400]),
                      SizedBox(height: 16),
                      Text(
                        'No vital sign activities',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'No vital sign recordings found for the selected date and filters.',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadVitalsLogs,
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    itemCount: _vitalsLogs.length,
                    itemBuilder: (context, index) {
                      return _buildVitalActivityCard(_vitalsLogs[index]);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // 🆕 NEW: Build shift summary tab
  Widget _buildShiftSummaryTab() {
    return Column(
      children: [
        // Header with date picker
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date Filter Row
              Row(
                children: [
                  Text(
                    'Date: ${DateFormat('MMM d, yyyy').format(_selectedDate)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Color(0xFF00588E),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.calendar_today,
                      color: Color(0xFF00588E),
                    ),
                    onPressed: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 30),
                        ),
                        lastDate: DateTime.now(),
                      );
                      if (pickedDate != null) {
                        setState(() {
                          _selectedDate = pickedDate;
                        });
                        _loadShiftSummary();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        // Shift Summary Content
        Expanded(
          child: _isLoadingShiftSummary
              ? const Center(child: CircularProgressIndicator())
              : _shiftSummary.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No previous shift data',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No activities found from the previous shift on this date.',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadShiftSummary,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Previous Shift Header
                        Card(
                          elevation: 4,
                          color: const Color(0xFF00588E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${_shiftSummary['previousShift'] ?? 'Previous'} Shift Summary',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Overall Summary Cards
                        Row(
                          children: [
                            Expanded(
                              child: _buildSummaryCard(
                                'Completed Tasks',
                                _shiftSummary['totalCompleted'] ?? 0,
                                Colors.green,
                                Icons.check_circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildSummaryCard(
                                'Missed Tasks',
                                _shiftSummary['totalMissed'] ?? 0,
                                Colors.red,
                                Icons.cancel,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Detailed Breakdown
                        const Text(
                          'Task Breakdown',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00588E),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Medication Summary
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.medication,
                                      color: Colors.orange[700],
                                      size: 24,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Medications',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildDetailCard(
                                        'Completed',
                                        _shiftSummary['medicationCompleted'] ??
                                            0,
                                        Colors.green[100]!,
                                        Colors.green[700]!,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _buildDetailCard(
                                        'Missed',
                                        _shiftSummary['medicationMissed'] ?? 0,
                                        Colors.red[100]!,
                                        Colors.red[700]!,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Vitals Summary
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.favorite,
                                      color: Colors.red[700],
                                      size: 24,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Vital Signs',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildDetailCard(
                                        'Completed',
                                        _shiftSummary['vitalsCompleted'] ?? 0,
                                        Colors.green[100]!,
                                        Colors.green[700]!,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _buildDetailCard(
                                        'Missed',
                                        _shiftSummary['vitalsMissed'] ?? 0,
                                        Colors.red[100]!,
                                        Colors.red[700]!,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  // 🆕 NEW: Build summary card widget
  Widget _buildSummaryCard(
    String title,
    int count,
    Color color,
    IconData icon,
  ) {
    return Card(
      elevation: 3,
      color: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // 🆕 NEW: Build detail card widget
  Widget _buildDetailCard(
    String label,
    int count,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }
}
