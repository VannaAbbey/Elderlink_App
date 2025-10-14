import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'vital_update_screen.dart';

class FollowUpVitalsSelectionScreen extends StatefulWidget {
  final String? nurseName;
  final String houseId;

  const FollowUpVitalsSelectionScreen({
    super.key,
    required this.nurseName,
    required this.houseId,
  });

  @override
  State<FollowUpVitalsSelectionScreen> createState() =>
      _FollowUpVitalsSelectionScreenState();
}

class _FollowUpVitalsSelectionScreenState
    extends State<FollowUpVitalsSelectionScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _assignedElderly = [];
  bool _isLoading = true;

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

  String _getTodayDateString() {
    final now = DateTime.now();
    final currentHour = now.hour;

    // For third shift (10pm-6am), if it's after midnight (0:00-5:59),
    // we need to use the previous day's date for assignments
    if (currentHour >= 0 && currentHour < 6) {
      final previousDay = now.subtract(Duration(days: 1));
      return DateFormat('yyyy-MM-dd').format(previousDay);
    }

    // For all other times, use current date
    return DateFormat('yyyy-MM-dd').format(now);
  }

  String _getCurrentDay() {
    final now = DateTime.now();
    final currentHour = now.hour;

    // For third shift (10pm-6am), if it's after midnight (0:00-5:59),
    // we need to look at the previous day's assignments
    if (currentHour >= 0 && currentHour < 6) {
      final previousDay = now.subtract(Duration(days: 1));
      return DateFormat('EEEE').format(previousDay);
    }

    // For all other times, use current day
    return DateFormat('EEEE').format(now);
  }

  @override
  void initState() {
    super.initState();
    _loadAssignedElderly();
  }

  Future<String?> _getNurseId() async {
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
  }

  // 🔧 OPTIMIZATION: Helper method to fetch elderly names in parallel
  Future<Map<String, String>> _fetchElderlyNames(Set<String> elderlyIds) async {
    final elderlyNamesCache = <String, String>{};

    if (elderlyIds.isEmpty) return elderlyNamesCache;

    // Split into chunks of 30 (Firestore limit for whereIn)
    final chunks = <List<String>>[];
    final idsList = elderlyIds.toList();
    for (var i = 0; i < idsList.length; i += 30) {
      final end = (i + 30 < idsList.length) ? i + 30 : idsList.length;
      chunks.add(idsList.sublist(i, end));
    }

    // Fetch all chunks in parallel
    final futures = chunks.map(
      (chunk) => _firestore
          .collection('elderly')
          .where(FieldPath.documentId, whereIn: chunk)
          .get(),
    );

    final results = await Future.wait(futures);

    for (final result in results) {
      for (final doc in result.docs) {
        final data = doc.data();
        final fullName =
            '${data['elderly_fname'] ?? ''} ${data['elderly_lname'] ?? ''}'
                .trim();
        elderlyNamesCache[doc.id] = fullName.isNotEmpty ? fullName : 'Unknown';
      }
    }

    return elderlyNamesCache;
  }

  // 🔧 OPTIMIZATION: Helper method to fetch nurse names in parallel
  Future<Map<String, String>> _fetchNurseNames(Set<String> nurseIds) async {
    final nurseNamesCache = <String, String>{};

    if (nurseIds.isEmpty) return nurseNamesCache;

    // Split into chunks of 30 (Firestore limit for whereIn)
    final chunks = <List<String>>[];
    final idsList = nurseIds.toList();
    for (var i = 0; i < idsList.length; i += 30) {
      final end = (i + 30 < idsList.length) ? i + 30 : idsList.length;
      chunks.add(idsList.sublist(i, end));
    }

    // Fetch all chunks in parallel
    final futures = chunks.map(
      (chunk) => _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get(),
    );

    final results = await Future.wait(futures);

    for (final result in results) {
      for (final doc in result.docs) {
        final data = doc.data();
        final fullName =
            '${data['user_fname'] ?? ''} ${data['user_lname'] ?? ''}'.trim();
        nurseNamesCache[doc.id] = fullName.isNotEmpty
            ? fullName
            : 'Unknown Nurse';
      }
    }

    return nurseNamesCache;
  }

  Future<void> _loadAssignedElderly() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final nurseId = await _getNurseId();
      if (nurseId == null) return;

      final today = _getTodayDateString();

      print('🔍 Loading ALL assigned elderly for follow-up (any shift)...');
      print('Nurse: ${widget.nurseName} ($nurseId)');
      print('House: ${widget.houseId}');
      print('Date: $today');

      // 🔧 OPTIMIZATION: Run initial queries in parallel
      final currentDay = _getCurrentDay();
      final currentShift = _getCurrentShift();

      final [allVitalsQuery, nurseElderlyQuery] = await Future.wait([
        // Get ALL vitals for today in this house (any nurse, any shift)
        _firestore
            .collection('vitals')
            .where('house_id', isEqualTo: widget.houseId)
            .where('assigned_date', isEqualTo: today)
            .get(),
        // Get ALL elderly assigned to current nurse from elderly_assignments collection
        _firestore
            .collection('elderly_assignments')
            .where('user_id', isEqualTo: nurseId)
            .where('user_type', isEqualTo: 'nurse')
            .where('is_current', isEqualTo: true)
            .where('shift', isEqualTo: currentShift)
            .where('day', isEqualTo: currentDay)
            .get(),
      ]);

      print('📋 Found ${allVitalsQuery.docs.length} total vitals for today');

      // 🔧 OPTIMIZATION: Process nurse assignments more efficiently
      final nurseAssignedElderlyIds = <String>{};
      for (final doc in nurseElderlyQuery.docs) {
        final assignmentData = doc.data();
        final elderlyIds = List<String>.from(
          assignmentData['elderly_ids'] ?? [],
        );
        nurseAssignedElderlyIds.addAll(elderlyIds);
      }

      print('🔍 Assigned elderly IDs: $nurseAssignedElderlyIds');

      // 🔧 OPTIMIZATION: Early exit if no assignments
      if (nurseAssignedElderlyIds.isEmpty) {
        setState(() {
          _assignedElderly = [];
          _isLoading = false;
        });
        return;
      }

      // � OPTIMIZATION: Filter elderly by house and fetch names in parallel
      final filteredElderlyIds = <String>{};

      // Split into chunks of 30 (Firestore limit for whereIn)
      final chunks = <List<String>>[];
      final idsList = nurseAssignedElderlyIds.toList();
      for (var i = 0; i < idsList.length; i += 30) {
        final end = (i + 30 < idsList.length) ? i + 30 : idsList.length;
        chunks.add(idsList.sublist(i, end));
      }

      // 🔧 OPTIMIZATION: Fetch elderly data in parallel chunks
      final elderlyFutures = chunks.map(
        (chunk) => _firestore
            .collection('elderly')
            .where(FieldPath.documentId, whereIn: chunk)
            .where('house_id', isEqualTo: widget.houseId)
            .get(),
      );

      final elderlyChunks = await Future.wait(elderlyFutures);

      for (final chunk in elderlyChunks) {
        for (final doc in chunk.docs) {
          filteredElderlyIds.add(doc.id);
        }
      }

      print(
        '🔍 Filtered elderly IDs for house ${widget.houseId}: $filteredElderlyIds',
      );

      // 🔧 OPTIMIZATION: Early exit if no elderly in this house
      if (filteredElderlyIds.isEmpty) {
        setState(() {
          _assignedElderly = [];
          _isLoading = false;
        });
        return;
      }

      // Use filtered IDs instead of all assigned IDs
      final finalAssignedElderlyIds = filteredElderlyIds;

      // 🔧 OPTIMIZATION: Pre-fetch nurse names while processing elderly names
      final nurseIdsToFetch = <String>{};
      for (final vitalDoc in allVitalsQuery.docs) {
        final vitalData = vitalDoc.data();
        final assignedNurseId = vitalData['assigned_nurse_id'];
        final updatedByNurseId = vitalData['updated_by_nurse_id'];
        final recordedBy = vitalData['recorded_by'];

        if (assignedNurseId != null) nurseIdsToFetch.add(assignedNurseId);
        if (updatedByNurseId != null) nurseIdsToFetch.add(updatedByNurseId);
        if (recordedBy != null) nurseIdsToFetch.add(recordedBy);
      }

      // 🔧 OPTIMIZATION: Fetch elderly and nurse names in parallel
      final [elderlyNamesCache, nurseNamesCache] = await Future.wait([
        _fetchElderlyNames(finalAssignedElderlyIds),
        _fetchNurseNames(nurseIdsToFetch),
      ]);

      print('📋 Elderly names cache populated: $elderlyNamesCache');
      print('👩‍⚕️ Nurse names cache populated: $nurseNamesCache');

      final elderlyList = <Map<String, dynamic>>[];

      // 🔧 OPTIMIZATION: Process vitals more efficiently
      final elderlyLatestVitals = <String, Map<String, dynamic>>{};

      for (final vitalDoc in allVitalsQuery.docs) {
        final vitalData = vitalDoc.data();
        final elderlyId = vitalData['elderly_id'];

        // Only process if this elderly is assigned to current nurse
        if (!finalAssignedElderlyIds.contains(elderlyId)) {
          continue;
        }

        // 🔧 FIXED: Get elderly name from vitals data first, then from cache if not available
        String elderlyName = vitalData['elderly_name'] ?? '';
        if (elderlyName.isEmpty || elderlyName == 'Unknown') {
          elderlyName = elderlyNamesCache[elderlyId] ?? 'Unknown';
        }

        print(
          '📋 Processing vital: $elderlyName ($elderlyId) - Status: ${vitalData['status']} - Nurse: ${vitalData['assigned_nurse_id'] ?? 'Unknown'}',
        );

        print('   ✅ Including - assigned to current nurse');

        // Get completion timestamp to find most recent vital
        final completedAt = vitalData['completed_at'];
        final createdAt = vitalData['created_at'];

        // Use completed_at if available, otherwise created_at for sorting
        final timestamp = completedAt ?? createdAt;

        if (!elderlyLatestVitals.containsKey(elderlyId) ||
            (timestamp != null &&
                elderlyLatestVitals[elderlyId]!['timestamp'] == null) ||
            (timestamp != null &&
                elderlyLatestVitals[elderlyId]!['timestamp'] != null &&
                timestamp.compareTo(
                      elderlyLatestVitals[elderlyId]!['timestamp'],
                    ) >
                    0)) {
          elderlyLatestVitals[elderlyId] = {
            'elderly_id': elderlyId,
            'elderly_name': elderlyName,
            'assignment_id': vitalDoc.id,
            'status': vitalData['status'],
            'assigned_nurse_id': vitalData['assigned_nurse_id'],
            'assigned_nurse_name':
                nurseNamesCache[vitalData['assigned_nurse_id']] ??
                'Unknown Nurse',
            'updated_by_nurse_id': vitalData['updated_by_nurse_id'],
            'shift': vitalData['shift'],
            'timestamp': timestamp,
            'vitals_data': {
              'blood_pressure': vitalData['blood_pressure'],
              'pulse_rate': vitalData['pulse_rate'],
              'oxygen_saturation': vitalData['oxygen_saturation'],
              'temperature': vitalData['temperature'],
              'respiratory_rate': vitalData['respiratory_rate'],
              'completed_at': vitalData['completed_at'],
              'recorded_by_name':
                  vitalData['recorded_by_name'] ??
                  nurseNamesCache[vitalData['assigned_nurse_id']] ??
                  nurseNamesCache[vitalData['updated_by_nurse_id']] ??
                  nurseNamesCache[vitalData['recorded_by']] ??
                  'Unknown Nurse',
            },
          };
        }
      }

      // 🔧 STEP 3: Build the final elderly list - include ALL assigned elderly
      for (final elderlyId in finalAssignedElderlyIds) {
        final elderlyName = elderlyNamesCache[elderlyId] ?? 'Unknown';
        print('🔍 Processing elderly $elderlyId: cached name = "$elderlyName"');

        // Check if this elderly has vitals data
        final elderlyData = elderlyLatestVitals[elderlyId];

        if (elderlyData != null) {
          // Elderly has vitals - use existing logic
          final status = elderlyData['status'];
          final vitalsData = elderlyData['vitals_data'] as Map<String, dynamic>;
          final hasAnyVitals = vitalsData['completed_at'] != null;
          final canFollowUp = hasAnyVitals;

          print(
            '🔍 Building elderly item (with vitals): $elderlyName - Status: $status - HasVitals: $hasAnyVitals - CanFollowUp: $canFollowUp',
          );

          elderlyList.add({
            'elderly_id': elderlyId,
            'elderly_name': elderlyName,
            'assignment_id': elderlyData['assignment_id'],
            'status': status,
            'previous_vitals': hasAnyVitals ? vitalsData : null,
            'can_follow_up': canFollowUp,
            'completed_by_nurse':
                nurseNamesCache[elderlyData['assigned_nurse_id']] ??
                'Unknown Nurse',
            'completed_in_shift': elderlyData['shift'],
          });
        } else {
          // Elderly has no vitals yet - show as pending
          print(
            '🔍 Building elderly item (no vitals): $elderlyName - Status: pending - CanFollowUp: false',
          );

          elderlyList.add({
            'elderly_id': elderlyId,
            'elderly_name': elderlyName,
            'assignment_id': null,
            'status': 'pending',
            'previous_vitals': null,
            'can_follow_up': false,
            'completed_by_nurse': 'None',
            'completed_in_shift': 'N/A',
          });
        }
      }

      // Sort: completed vitals first (eligible for follow-up), then pending
      elderlyList.sort((a, b) {
        if (a['can_follow_up'] != b['can_follow_up']) {
          return a['can_follow_up'] ? -1 : 1; // completed first
        }
        return a['elderly_name'].compareTo(b['elderly_name']);
      });

      setState(() {
        _assignedElderly = elderlyList;
        _isLoading = false;
      });

      print('✅ Loaded ${elderlyList.length} elderly for follow-up selection');
      print('📋 Elderly list details:');
      for (final elderly in elderlyList) {
        print(
          '   - ${elderly['elderly_name']} (${elderly['elderly_id']}) - Can follow up: ${elderly['can_follow_up']}',
        );
      }
    } catch (e) {
      print('❌ Error loading assigned elderly: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _recordFollowUpVitals(Map<String, dynamic> elderlyInfo) async {
    // Create a new follow-up assignment
    final now = DateTime.now();
    final currentShift = _getCurrentShift();
    final today = _getTodayDateString();
    final nurseId = await _getNurseId();

    if (nurseId == null) return;

    try {
      // Create new follow-up assignment
      final followUpAssignmentRef = await _firestore.collection('vitals').add({
        'elderly_id': elderlyInfo['elderly_id'],
        'elderly_name': elderlyInfo['elderly_name'],
        'assigned_nurse_id': nurseId,
        'assigned_nurse_name': widget.nurseName ?? 'Unknown',
        'house_id': widget.houseId,
        'assigned_date': today,
        'shift': currentShift,
        'status': 'pending',
        'created_at': Timestamp.fromDate(now),

        // 🆕 FOLLOW-UP METADATA: Track that this is a follow-up
        'is_follow_up': true,
        'previous_assignment_id': elderlyInfo['assignment_id'],
        'previous_vitals': elderlyInfo['previous_vitals'],
        'follow_up_reason': 'Additional monitoring requested by nurse',

        // Vital fields (null until recorded)
        'blood_pressure': null,
        'pulse_rate': null,
        'oxygen_saturation': null,
        'temperature': null,
        'respiratory_rate': null,
        'remarks': null,
        'completed_at': null,
        'recorded_by': null,
        'recorded_by_name': null,
      });

      print('✅ Created follow-up assignment: ${followUpAssignmentRef.id}');

      // Navigate to vitals recording screen with follow-up context
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VitalUpdateScreen(
            assignmentId: followUpAssignmentRef.id,
            elderlyId: elderlyInfo['elderly_id'],
            elderlyName: elderlyInfo['elderly_name'],
            nurseName: widget.nurseName,
            houseId: widget.houseId,
          ),
        ),
      );

      if (result == true && mounted) {
        // Return success to refresh the main list
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('❌ Error creating follow-up assignment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating follow-up: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';

    DateTime dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    } else {
      return timestamp.toString();
    }

    return DateFormat('MMM dd, hh:mm a').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Follow-up Vitals Selection',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green[600],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _assignedElderly.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No assignments found',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No elderly assigned to you for this shift',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Header with instructions
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  margin: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.green[600]),
                          SizedBox(width: 8),
                          Text(
                            'Follow-up Vitals Recording',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Select an elderly to record follow-up vitals. You can record follow-ups for ANY elderly assigned to you, even if their vitals were completed by other nurses from previous shifts.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                ),

                // List of assigned elderly
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _assignedElderly.length,
                    itemBuilder: (context, index) {
                      final elderlyInfo = _assignedElderly[index];
                      final canFollowUp = elderlyInfo['can_follow_up'] as bool;
                      final previousVitals =
                          elderlyInfo['previous_vitals']
                              as Map<String, dynamic>?;

                      return Card(
                        margin: EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: canFollowUp
                                        ? Colors.green[600]
                                        : Colors.grey[400],
                                    radius: 24,
                                    child: Icon(
                                      Icons.person,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          elderlyInfo['elderly_name'],
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF2C3E50),
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: canFollowUp
                                                ? Colors.green[100]
                                                : Colors.grey[200],
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          child: Text(
                                            canFollowUp
                                                ? '✅ Completed by ${elderlyInfo['completed_by_nurse'] ?? 'Unknown'} (${elderlyInfo['completed_in_shift'] ?? 'Unknown'} shift)'
                                                : '⏳ Vitals Pending',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: canFollowUp
                                                  ? Colors.green[700]
                                                  : Colors.grey[600],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              // Show previous vitals if completed
                              if (canFollowUp && previousVitals != null) ...[
                                SizedBox(height: 20),
                                Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey[200]!,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.monitor_heart,
                                            size: 16,
                                            color: Colors.grey[600],
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Previous Vitals',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 12),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (previousVitals['blood_pressure'] !=
                                              null)
                                            Text(
                                              'BP: ${previousVitals['blood_pressure']}',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          if (previousVitals['pulse_rate'] !=
                                              null)
                                            Text(
                                              'HR: ${previousVitals['pulse_rate']} bpm',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          if (previousVitals['temperature'] !=
                                              null)
                                            Text(
                                              'Temp: ${previousVitals['temperature']}°C',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          if (previousVitals['oxygen_saturation'] !=
                                              null)
                                            Text(
                                              'O2: ${previousVitals['oxygen_saturation']}%',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          if (previousVitals['respiratory_rate'] !=
                                              null)
                                            Text(
                                              'RR: ${previousVitals['respiratory_rate']} breaths/min',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                        ],
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Recorded by: ${previousVitals['recorded_by_name']} • ${_formatTimestamp(previousVitals['completed_at'])}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[500],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              // Follow-up button at bottom
                              if (canFollowUp) ...[
                                SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  height: 45,
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _recordFollowUpVitals(elderlyInfo),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green[600],
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    icon: Icon(
                                      Icons.add_circle_outline,
                                      size: 20,
                                    ),
                                    label: Text(
                                      'Record Follow-up Vitals',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ] else ...[
                                SizedBox(height: 16),
                                Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Complete Initial Vitals First',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
