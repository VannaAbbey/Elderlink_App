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
    extends State<MedicationActivityLogsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _activityLogs = [];
  bool _isLoading = false;
  String? _selectedElderly;
  List<Map<String, String>> _elderlyList = [];
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadAssignedElderly();
    _loadActivityLogs();
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

  Future<void> _loadActivityLogs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) {
        setState(() {
          _isLoading = false;
          _activityLogs = [];
        });
        return;
      }

      Query query;

      // Build query differently based on whether we're filtering by elderly or not
      if (_selectedElderly != null && _selectedElderly!.isNotEmpty) {
        // When filtering by elderly, use where clauses without orderBy to avoid index issues
        query = _firestore
            .collection('medication_activity_logs')
            .where('house_id', isEqualTo: widget.houseId)
            .where('elderly_id', isEqualTo: _selectedElderly)
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
        _activityLogs = activities;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading activity logs: $e');
      setState(() {
        _isLoading = false;
        _activityLogs = [];
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
          'Medication Activity Logs',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Color(0xFF00588E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
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
                    value: _selectedElderly,
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
                        _selectedElderly = value;
                      });
                      _loadActivityLogs();
                    },
                  ),
                ),
                SizedBox(height: 16),

                // Date Filter Row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('MMM dd, yyyy').format(_selectedDate),
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
                          initialDate: _selectedDate,
                          firstDate: DateTime.now().subtract(
                            Duration(days: 365),
                          ), // Allow up to 1 year back
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

                        if (picked != null && picked != _selectedDate) {
                          setState(() {
                            _selectedDate = picked;
                          });
                          _loadActivityLogs();
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

          // Activity Logs List
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _activityLogs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 64, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text(
                          'No activity logs found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          _selectedElderly != null
                              ? 'No activities found for the selected elderly on ${DateFormat('MMM dd, yyyy').format(_selectedDate)}'
                              : 'No medication activities found on ${DateFormat('MMM dd, yyyy').format(_selectedDate)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Try selecting a different date or elderly',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[400],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadActivityLogs,
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      itemCount: _activityLogs.length,
                      itemBuilder: (context, index) {
                        return _buildActivityCard(_activityLogs[index]);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
