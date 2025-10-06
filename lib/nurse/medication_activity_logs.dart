import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class MedicationActivityLogsScreen extends StatefulWidget {
  final String houseId;
  final String? nurseName;

  const MedicationActivityLogsScreen({
    super.key,
    required this.houseId,
    required this.nurseName,
  });

  @override
  State<MedicationActivityLogsScreen> createState() =>
      _MedicationActivityLogsScreenState();
}

class _MedicationActivityLogsScreenState
    extends State<MedicationActivityLogsScreen>
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

  String _getCurrentDay() {
    return DateFormat('EEEE').format(DateTime.now());
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

  Future<void> _loadAssignedElderly() async {
    try {
      final currentShift = _getCurrentShift();
      final currentDay = _getCurrentDay();

      // Get nurse ID
      final nameParts = widget.nurseName?.split(' ') ?? [];
      if (nameParts.length < 2) return;

      final firstName = nameParts[0];
      final lastName = nameParts[1];

      final userQuery = await _firestore
          .collection('users')
          .where('user_fname', isEqualTo: firstName)
          .where('user_lname', isEqualTo: lastName)
          .where('user_type', isEqualTo: 'nurse')
          .get();

      if (userQuery.docs.isEmpty) return;

      final nurseId = userQuery.docs.first.id;

      // Get nurse's assigned elderly for current day and shift
      final nurseElderlyQuery = await _firestore
          .collection('nurse_elderly_assign')
          .where('nurse_id', isEqualTo: nurseId)
          .where('is_current', isEqualTo: true)
          .where('house_ids', arrayContains: widget.houseId)
          .where('shift', isEqualTo: currentShift)
          .where('day', isEqualTo: currentDay)
          .get();

      if (nurseElderlyQuery.docs.isEmpty) return;

      // Get assigned elderly IDs for this nurse
      final assignedElderlyIds = List<String>.from(
        nurseElderlyQuery.docs.first.data()['elderly_ids'] ?? [],
      );

      if (assignedElderlyIds.isEmpty) return;

      // Process elderly IDs in chunks of 30
      final allElderly = <DocumentSnapshot>[];

      for (var i = 0; i < assignedElderlyIds.length; i += 30) {
        final end = (i + 30 < assignedElderlyIds.length)
            ? i + 30
            : assignedElderlyIds.length;
        final chunk = assignedElderlyIds.sublist(i, end);

        final elderlyDetailsQuery = await _firestore
            .collection('elderly')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        allElderly.addAll(elderlyDetailsQuery.docs);
      }

      // Filter and process elderly for current house
      final filteredElderly = allElderly.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['house_id'] == widget.houseId;
      }).toList();

      final newElderlyList = filteredElderly.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
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
      print('Error loading assigned elderly: $e');
    }
  }

  Future<void> _loadMedicationLogs() async {
    setState(() {
      _isMedicationLoading = true;
    });

    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) {
        setState(() {
          _isMedicationLoading = false;
          _medicationLogs = [];
        });
        return;
      }

      Query query;

      // Build query differently based on whether we're filtering by elderly or not
      if (_selectedElderlyMed != null && _selectedElderlyMed!.isNotEmpty) {
        // When filtering by elderly, use where clauses without orderBy to avoid index issues
        query = _firestore
            .collection('medication_activity_logs')
            .where('house_id', isEqualTo: widget.houseId)
            .where('elderly_id', isEqualTo: _selectedElderlyMed)
            .limit(100);
      } else {
        // When showing all activities, just filter by house_id without date restriction
        query = _firestore
            .collection('medication_activity_logs')
            .where('house_id', isEqualTo: widget.houseId)
            .limit(100);
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

      // Sort activities by timestamp in code instead of in query
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
        _medicationLogs = activities;
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

  Future<void> _loadVitalsLogs() async {
    setState(() {
      _isVitalsLoading = true;
    });

    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) {
        setState(() {
          _isVitalsLoading = false;
          _vitalsLogs = [];
        });
        return;
      }

      // Create date range for the selected date
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

      // Get missed vital assignments (these represent missed vitals from previous shifts)
      Query query;
      if (_selectedElderlyVitals != null &&
          _selectedElderlyVitals!.isNotEmpty) {
        query = _firestore
            .collection('daily_vital_assignments')
            .where('house_id', isEqualTo: widget.houseId)
            .where('elderly_id', isEqualTo: _selectedElderlyVitals)
            .where('status', isEqualTo: 'missed')
            .limit(100);
      } else {
        query = _firestore
            .collection('daily_vital_assignments')
            .where('house_id', isEqualTo: widget.houseId)
            .where('status', isEqualTo: 'missed')
            .limit(100);
      }

      final querySnapshot = await query.get();
      final activities = <Map<String, dynamic>>[];

      for (final doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final updatedAt = data['updated_at'] as Timestamp?;

        // Filter by date on client side
        if (updatedAt != null) {
          final activityDate = updatedAt.toDate();
          if (activityDate.isBefore(startOfDay) ||
              activityDate.isAfter(endOfDay)) {
            continue;
          }
        }

        // Get elderly details
        String elderlyName = 'Unknown';
        String elderlyTitle = 'Lola';
        try {
          final elderlyDoc = await _firestore
              .collection('elderly')
              .doc(data['elderly_id'])
              .get();

          if (elderlyDoc.exists) {
            final elderlyData = elderlyDoc.data() as Map<String, dynamic>;
            final firstName = elderlyData['elderly_fname'] ?? '';
            final lastName = elderlyData['elderly_lname'] ?? '';
            elderlyName = '$firstName $lastName'.trim();
            final gender = elderlyData['elderly_gender'] as String?;
            elderlyTitle = (gender?.toLowerCase() == 'male') ? 'Lolo' : 'Lola';
          }
        } catch (e) {
          print('Error getting elderly details: $e');
        }

        // Get original nurse name who missed the vital
        String nurseName = 'Unknown Nurse';
        try {
          final originalNurseId =
              data['original_assigned_nurse_id'] ?? data['assigned_nurse_id'];
          if (originalNurseId != null) {
            final nurseDoc = await _firestore
                .collection('users')
                .doc(originalNurseId)
                .get();

            if (nurseDoc.exists) {
              final nurseData = nurseDoc.data() as Map<String, dynamic>;
              final firstName = nurseData['user_fname'] ?? '';
              final lastName = nurseData['user_lname'] ?? '';
              nurseName = '$firstName $lastName'.trim();
            }
          }
        } catch (e) {
          print('Error getting nurse details: $e');
        }

        activities.add({
          'id': doc.id,
          'elderly_name': elderlyName,
          'elderly_title': elderlyTitle,
          'nurse_name': nurseName,
          'shift': data['shift'] ?? 'Unknown',
          'assigned_date': data['assigned_date'] ?? 'Unknown',
          'timestamp': updatedAt,
          'action': 'missed_vital',
          ...data,
        });
      }

      // Sort activities by timestamp
      activities.sort((a, b) {
        final aTimestamp = a['timestamp'] as Timestamp?;
        final bTimestamp = b['timestamp'] as Timestamp?;

        if (aTimestamp == null && bTimestamp == null) return 0;
        if (aTimestamp == null) return 1;
        if (bTimestamp == null) return -1;

        return bTimestamp.compareTo(aTimestamp);
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

  String _formatActivityMessage(Map<String, dynamic> activity) {
    final action = activity['action'] as String;
    final nurseName = activity['nurse_name'] as String;
    final elderlyName = activity['elderly_name'] as String;
    final elderlyTitle = activity['elderly_title'] as String;
    final medicationName = activity['medication_name'] as String;
    final takeOrdinal = activity['take_ordinal'] as String?;

    switch (action) {
      case 'edit_medication':
        return 'Nurse $nurseName edited the medication details of $elderlyTitle $elderlyName';

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
        return 'Nurse $nurseName performed $action on medication for $elderlyTitle $elderlyName';
    }
  }

  Color _getActionColor(String action) {
    switch (action) {
      case 'edit_medication':
        return Colors.blue;
      case 'delete_medication':
      case 'delete_individual_take':
        return Colors.red;
      case 'add_medication':
        return Colors.green;
      case 'status_change':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getActionIcon(String action) {
    switch (action) {
      case 'edit_medication':
        return Icons.edit;
      case 'delete_medication':
      case 'delete_individual_take':
        return Icons.delete;
      case 'add_medication':
        return Icons.add_circle;
      case 'status_change':
        return Icons.update;
      default:
        return Icons.info;
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

  Widget _buildActivityCard(Map<String, dynamic> activity) {
    final action = activity['action'] as String;
    final actionColor = _getActionColor(action);
    final actionIcon = _getActionIcon(action);
    final message = _formatActivityMessage(activity);
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
                color: actionColor.withOpacity(0.1),
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
                      action != 'delete_medication')
                    Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Medication: ${activity['medication_name']}',
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Activity Logs',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Color(0xFF00588E),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: Icon(Icons.medication, color: Colors.white),
              text: 'Medication',
            ),
            Tab(
              icon: Icon(Icons.favorite, color: Colors.white),
              text: 'Vitals',
            ),
          ],
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Medication Activities Tab
          _buildMedicationTab(),
          // Vitals Activities Tab
          _buildVitalsTab(),
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
                    }).toList(),
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
                      'Selected Date:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      DateFormat('MMM dd, yyyy').format(_selectedDateMed),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDateMed,
                        firstDate: DateTime.now().subtract(Duration(days: 365)),
                        lastDate: DateTime.now(),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: Color(0xFF00588E),
                                onPrimary: Colors.white,
                                surface: Colors.white,
                                onSurface: Colors.black,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );

                      if (picked != null && picked != _selectedDateMed) {
                        setState(() {
                          _selectedDateMed = picked;
                        });
                        _loadMedicationLogs();
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Color(0xFF00588E).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.calendar_today,
                        size: 24,
                        color: Color(0xFF00588E),
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
                        'No medication activities found',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      SizedBox(height: 8),
                      Text(
                        _selectedElderlyMed != null
                            ? 'No activities found for the selected elderly on ${DateFormat('MMM dd, yyyy').format(_selectedDateMed)}'
                            : 'No medication activities found on ${DateFormat('MMM dd, yyyy').format(_selectedDateMed)}',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Try selecting a different date or elderly',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
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
                      return _buildActivityCard(_medicationLogs[index]);
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
                    }).toList(),
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
                      'Selected Date:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      DateFormat('MMM dd, yyyy').format(_selectedDateVitals),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDateVitals,
                        firstDate: DateTime.now().subtract(Duration(days: 365)),
                        lastDate: DateTime.now(),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: Color(0xFF00588E),
                                onPrimary: Colors.white,
                                surface: Colors.white,
                                onSurface: Colors.black,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );

                      if (picked != null && picked != _selectedDateVitals) {
                        setState(() {
                          _selectedDateVitals = picked;
                        });
                        _loadVitalsLogs();
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Color(0xFF00588E).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.calendar_today,
                        size: 24,
                        color: Color(0xFF00588E),
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
                        'No vitals activities found',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      SizedBox(height: 8),
                      Text(
                        _selectedElderlyVitals != null
                            ? 'No missed vitals found for the selected elderly on ${DateFormat('MMM dd, yyyy').format(_selectedDateVitals)}'
                            : 'No missed vitals found on ${DateFormat('MMM dd, yyyy').format(_selectedDateVitals)}',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Try selecting a different date or elderly',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
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
                      return _buildVitalsActivityCard(_vitalsLogs[index]);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildVitalsActivityCard(Map<String, dynamic> activity) {
    final timestamp = _formatTimestamp(activity['timestamp']);
    final elderlyName = activity['elderly_name'] ?? 'Unknown';
    final elderlyTitle = activity['elderly_title'] ?? 'Lola';
    final nurseName = activity['nurse_name'] ?? 'Unknown Nurse';
    final shift = activity['shift'] ?? 'Unknown';
    final assignedDate = activity['assigned_date'] ?? 'Unknown';

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.favorite_border, color: Colors.red, size: 20),
            ),
            SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Action description
                  Text(
                    'Nurse $nurseName missed vital signs for $elderlyTitle $elderlyName',
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

                  // Shift and date info
                  Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Shift: $shift • Date: $assignedDate',
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
        ),
      ),
    );
  }
}
