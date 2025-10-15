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

  // ⚡ OPTIMIZATION: Cache for elderly data to avoid repeated fetches
  static final Map<String, List<Map<String, String>>> _elderlyCache = {};
  static final Map<String, DateTime> _elderlyCacheTime = {};
  static const Duration _elderlyCacheDuration = Duration(
    hours: 1,
  ); // Cache for 1 hour

  // ⚡ OPTIMIZATION: Cache for user data (nurse/elderly names)
  static final Map<String, Map<String, dynamic>> _userDataCache = {};
  static final Map<String, DateTime> _userDataCacheTime = {};
  static const Duration _userDataCacheDuration = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAssignedElderly();
    _loadMedicationLogs();
    _loadVitalsLogs();
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
          // Keep all other actions (complete_take, miss_take, etc.)
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

  // Load vital recordings from vital_activity_logs collection
  Future<void> _loadVitalsLogs() async {
    setState(() {
      _isVitalsLoading = true;
    });

    try {
      // Create date range for filtering
      final startOfDay = DateTime(
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

      // Query all houses - apply elderly filter if selected
      Query query = _firestore.collection('vital_activity_logs');

      // Apply elderly filter if selected
      if (_selectedElderlyVitals != null &&
          _selectedElderlyVitals!.isNotEmpty) {
        query = query.where('elderly_id', isEqualTo: _selectedElderlyVitals);
      }

      final querySnapshot = await query.get();
      final activities = <Map<String, dynamic>>[];

      for (final doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue; // Skip if data is null

        // Filter activities by selected date
        final timestamp = data['timestamp'] as Timestamp?;
        if (timestamp != null) {
          final activityDate = timestamp.toDate();
          if (activityDate.isBefore(startOfDay) ||
              activityDate.isAfter(endOfDay)) {
            continue; // Skip activities not on selected date
          }
        }

        // Get elderly name and gender for proper title (Lola/Lolo)
        String elderlyName = 'Unknown';
        String elderlyTitle = 'Lola'; // Default to female
        String nurseName = widget.nurseName ?? 'Unknown Nurse';

        try {
          final elderlyId = data['elderly_id'] as String?;
          final nurseId = data['nurse_id'] as String?;

          // Get elderly info
          if (elderlyId != null) {
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

          // Get nurse name
          if (nurseId != null) {
            final nurseDoc = await _firestore
                .collection('users')
                .doc(nurseId)
                .get();

            if (nurseDoc.exists) {
              final nurseData = nurseDoc.data();
              nurseName = nurseData?['user_fname'] ?? 'Unknown Nurse';
            }
          }
        } catch (e) {
          print('Error getting names: $e');
        }

        // Add activity with enhanced data
        activities.add({
          'id': doc.id,
          'elderly_title': elderlyTitle,
          'action_type': data['action_type'] ?? 'vital_completed',
          'elderly_name': elderlyName,
          'nurse_name': nurseName,
          'timestamp': data['timestamp'],
          'shift': data['shift'] ?? _getCurrentShift(),
          'new_values': data['new_values'] ?? {},
          'remarks': data['remarks'] ?? '',
          ...data, // Spread data
        });
      }

      // Sort activities by timestamp (newest first)
      activities.sort((a, b) {
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
        _vitalsLogs = activities;
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

      case 'complete_take':
        final takeText = takeNumber != null
            ? _getOrdinalFromNumber(takeNumber)
            : (takeOrdinal ?? '1st');
        return 'Nurse $nurseName completed the $takeText take of "$medicationName" for $elderlyTitle $elderlyName';

      case 'miss_take':
        final takeText = takeNumber != null
            ? _getOrdinalFromNumber(takeNumber)
            : (takeOrdinal ?? '1st');
        return 'Nurse $nurseName marked the $takeText take of "$medicationName" as MISSED for $elderlyTitle $elderlyName';

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
    final newValues = activity['new_values'] as Map<String, dynamic>? ?? {};

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
      case 'create_medication':
      case 'add_medication':
        return Colors.green;
      case 'complete_take':
        return Colors.blue;
      case 'miss_take':
        return Colors.orange;
      case 'edit_medication':
        return Colors.purple;
      case 'delete_medication':
      case 'delete_individual_take':
        return Colors.red;
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
      case 'complete_take':
        return Icons.check_circle;
      case 'miss_take':
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

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown time';

    try {
      DateTime dateTime;
      if (timestamp is Timestamp) {
        dateTime = timestamp.toDate();
      } else if (timestamp is DateTime) {
        dateTime = timestamp;
      } else {
        return 'Invalid time';
      }

      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return DateFormat('MMM dd, yyyy • HH:mm').format(dateTime);
      }
    } catch (e) {
      return 'Invalid time';
    }
  }

  Widget _buildMedicationActivityCard(Map<String, dynamic> activity) {
    final action = activity['action'] as String;
    final actionColor = _getMedicationActionColor(action);
    final actionIcon = _getMedicationActionIcon(action);
    final message = _formatMedicationActivityMessage(activity);
    final timestamp = _formatTimestamp(activity['timestamp']);

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Action Icon
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: actionColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(actionIcon, color: actionColor, size: 20),
            ),
            SizedBox(width: 12),

            // Activity Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Activity Message
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 4),

                  // Timestamp
                  Text(
                    timestamp,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),

                  // Medication name (if available)
                  if (activity['medication_name'] != null &&
                      activity['medication_name'].toString().isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: actionColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          activity['medication_name'],
                          style: TextStyle(
                            fontSize: 11,
                            color: actionColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🔧 NEW: Build vital activity card
  Widget _buildVitalActivityCard(Map<String, dynamic> activity) {
    final actionType = activity['action_type'] as String? ?? 'vital_recorded';
    final actionColor = _getVitalActionColor(actionType);
    final actionIcon = _getVitalActionIcon(actionType);
    final message = _formatVitalActivityMessage(activity);
    final timestamp = _formatTimestamp(activity['timestamp']);
    final newValues = activity['new_values'] as Map<String, dynamic>? ?? {};

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Action Icon
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: actionColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(actionIcon, color: actionColor, size: 20),
            ),
            SizedBox(width: 12),

            // Activity Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Activity Message
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 4),

                  // Timestamp and Shift
                  Row(
                    children: [
                      Text(
                        timestamp,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      if (activity['shift'] != null) ...[
                        SizedBox(width: 8),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${activity['shift']} shift',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Vital Signs Details (if available)
                  if (newValues.isNotEmpty) ...[
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (newValues['blood_pressure'] != null)
                          _buildVitalChip(
                            'BP',
                            newValues['blood_pressure'].toString(),
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
                    SizedBox(height: 6),
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.note, size: 14, color: Colors.grey[600]),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              activity['remarks'].toString(),
                              style: TextStyle(
                                fontSize: 12,
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
          ],
        ),
      ),
    );
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
          fontSize: 10,
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

                // Tab Bar
                Material(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    tabs: const [
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
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Medication Activities Tab
                      _buildMedicationTab(),
                      // Vitals Activities Tab
                      _buildVitalsTab(),
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
        Container(
          padding: EdgeInsets.all(16),
          color: Colors.grey[50],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Elderly Filter
              Text(
                'Filter by Elderly:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: DropdownButton<String>(
                  value: _selectedElderlyMed,
                  isExpanded: true,
                  hint: Text('All Elderly'),
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
                  Expanded(
                    child: Text(
                      'Date: ${DateFormat('MMM dd, yyyy').format(_selectedDateMed)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
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
        Container(
          padding: EdgeInsets.all(16),
          color: Colors.grey[50],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Elderly Filter
              Text(
                'Filter by Elderly:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: DropdownButton<String>(
                  value: _selectedElderlyVitals,
                  isExpanded: true,
                  hint: Text('All Elderly'),
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
                  Expanded(
                    child: Text(
                      'Date: ${DateFormat('MMM dd, yyyy').format(_selectedDateVitals)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
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
}
