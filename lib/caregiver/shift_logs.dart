import 'package:flutter/material.dart';
import '../services/cg_services/caregiver_shift_log_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

  // Method to get caregivers for a specific shift dynamically from database
  Future<List<String>> _getCaregiversByShift(String shiftType, DateTime date) async {
    try {
      final dayName = getDayName(date);
      print('🔍 DEBUG: Getting caregivers for shift: $shiftType on $dayName (${date.toString()})');
      
      // First, get current user's house assignment
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('❌ DEBUG: No authenticated user found');
        return [];
      }
      
      final currentCaregiverAssignQuery = await FirebaseFirestore.instance
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: user.uid)
          .where('user_type', isEqualTo: 'caregiver')
          .limit(1)
          .get();

      if (currentCaregiverAssignQuery.docs.isEmpty) {
        print('❌ DEBUG: No house assignment found for current caregiver');
        return [];
      }

      final currentAssignData = currentCaregiverAssignQuery.docs.first.data();
      final currentHouseId = currentAssignData['house_id'] as String?;
      
      if (currentHouseId == null) {
        print('❌ DEBUG: No house_id found in assignment');
        return [];
      }
      
      print('🏠 DEBUG: Current user house: $currentHouseId');
      
      // Query house_shift_assignments collection for caregivers with the specified shift AND same house
      final query = await FirebaseFirestore.instance
          .collection('house_shift_assignments')
          .where('house_id', isEqualTo: currentHouseId)
          .where('shift', isEqualTo: shiftType)
          .get();

      print('🔍 DEBUG: Found ${query.docs.length} total assignments for shift $shiftType in house $currentHouseId');
      
      List<String> caregiverNames = [];
      
      for (var doc in query.docs) {
        final data = doc.data();
        final caregiverId = data['user_id'] as String?;
        final userType = data['user_type'] as String?;
        final daysAssigned = data['days_assigned'] as List<dynamic>? ?? [];
        
        print('🔍 DEBUG: Checking caregiver $caregiverId - assigned days: $daysAssigned');
        
        // Check if the caregiver is assigned to work on this specific day
        if (userType == 'caregiver' && caregiverId != null && daysAssigned.contains(dayName)) {
          // Get caregiver name from users collection
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(caregiverId)
              .get();
              
          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            final name = userData['user_fname'] ?? userData['fname'] ?? userData['first_name'] ?? userData['firstName'] ?? 'Unknown';
            caregiverNames.add(name.toString());
            print('✅ DEBUG: Added caregiver: $name (works on $dayName)');
          } else {
            print('⚠️ DEBUG: User document not found for caregiver ID: $caregiverId');
          }
        } else if (caregiverId != null) {
          print('❌ DEBUG: Skipping caregiver $caregiverId - not assigned to work on $dayName (assigned days: $daysAssigned)');
        }
      }
      
      print('✅ DEBUG: Final result - Found ${caregiverNames.length} caregivers for shift $shiftType on $dayName: $caregiverNames');
      return caregiverNames;
    } catch (e) {
      print('❌ ERROR: Error getting caregivers for shift $shiftType: $e');
      return [];
    }
  }

  // Helper to get previous shift type and caregivers (now dynamic)
  Future<Map<String, dynamic>> getPreviousShiftInfo(DateTime date) async {
    // Get current user's actual shift assignment from database
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('❌ DEBUG: No authenticated user found in getPreviousShiftInfo');
      return {'shiftType': '', 'previousShiftType': '', 'previousCaregivers': <String>[], 'previousDate': date};
    }
    
    final currentCaregiverAssignQuery = await FirebaseFirestore.instance
        .collection('house_shift_assignments')
        .where('user_id', isEqualTo: user.uid)
        .where('user_type', isEqualTo: 'caregiver')
        .limit(1)
        .get();

    if (currentCaregiverAssignQuery.docs.isEmpty) {
      print('❌ DEBUG: No house assignment found for current caregiver in getPreviousShiftInfo');
      return {'shiftType': '', 'previousShiftType': '', 'previousCaregivers': <String>[], 'previousDate': date};
    }

    final currentAssignData = currentCaregiverAssignQuery.docs.first.data();
    final currentUserShift = currentAssignData['shift'] as String? ?? '';
    
    if (currentUserShift.isEmpty) {
      print('❌ DEBUG: No shift found in assignment data');
      return {'shiftType': '', 'previousShiftType': '', 'previousCaregivers': <String>[], 'previousDate': date};
    }
    
    print('🔄 DEBUG: Current user assigned shift: $currentUserShift');
    
    String shiftType = '';
    String previousShiftType = '';
    String previousShiftKey = '';
    DateTime previousDate = date;
    
    // Use the user's assigned shift, not current time
    if (currentUserShift == '1st') {
      // Current: 1st Shift (6:00 AM - 2:00 PM) -> Previous: 3rd Shift (10:00 PM - 6:00 AM)
      // For shift logs, we want to see the 3rd shift data from the SAME DATE
      shiftType = '1st Shift (6:00 AM - 2:00 PM)';
      previousShiftType = '3rd Shift (10:00 PM - 6:00 AM)';
      previousShiftKey = '3rd';
      // Keep same date - 3rd shift data is logged on the same date
    } else if (currentUserShift == '2nd') {
      // Current: 2nd Shift (2:00 PM - 10:00 PM) -> Previous: 1st Shift (6:00 AM - 2:00 PM)
      shiftType = '2nd Shift (2:00 PM - 10:00 PM)';
      previousShiftType = '1st Shift (6:00 AM - 2:00 PM)';
      previousShiftKey = '1st';
    } else if (currentUserShift == '3rd') {
      // Current: 3rd Shift (10:00 PM - 6:00 AM) -> Previous: 2nd Shift (2:00 PM - 10:00 PM)
      shiftType = '3rd Shift (10:00 PM - 6:00 AM)';
      previousShiftType = '2nd Shift (2:00 PM - 10:00 PM)';
      previousShiftKey = '2nd';
    } else {
      print('❌ DEBUG: Unknown shift type: $currentUserShift');
      return {'shiftType': '', 'previousShiftType': '', 'previousCaregivers': <String>[], 'previousDate': date};
    }
    
    // Get caregivers dynamically from database
    final caregivers = await _getCaregiversByShift(previousShiftKey, previousDate);
    
    return {
      'shiftType': shiftType,
      'previousShiftType': previousShiftType,
      'previousCaregivers': caregivers,
      'previousDate': previousDate,
    };
  }

String getDayName(DateTime date) {
  switch (date.weekday) {
    case DateTime.monday:
      return 'Monday';
    case DateTime.tuesday:
      return 'Tuesday';
    case DateTime.wednesday:
      return 'Wednesday';
    case DateTime.thursday:
      return 'Thursday';
    case DateTime.friday:
      return 'Friday';
    case DateTime.saturday:
      return 'Saturday';
    case DateTime.sunday:
      return 'Sunday';
    default:
      return '';
  }
}
class ShiftLogsScreen extends StatefulWidget {
  const ShiftLogsScreen({super.key});

  @override
  State<ShiftLogsScreen> createState() => _ShiftLogsScreenState();
}

class _ShiftLogsScreenState extends State<ShiftLogsScreen> {
  late DateTime selectedDate;
  Future<Map<String, dynamic>?>? shiftDataFuture;
  String selectedCaregiverFilter = 'All Caregivers'; // Filter state

  @override
  void initState() {
    super.initState();
    // Explicitly set to today's date to ensure it reflects current day
    _refreshToCurrentDate();
    // Load today's shift data initially
    _loadShiftData();
  }

  void _refreshToCurrentDate() {
    final now = DateTime.now();
    selectedDate = DateTime(now.year, now.month, now.day); // Normalize to start of day
    print('🗓️ ShiftLogs: Refreshed to current date: ${_formatDate(selectedDate)}');
    print('🗓️ ShiftLogs: Raw DateTime.now(): $now');
  }

  void _loadShiftData() {
    print('🗓️ ShiftLogs: Loading shift data for date: ${_formatDate(selectedDate)}');
    setState(() {
      shiftDataFuture = _getShiftDataFromUnifiedService(selectedDate);
    });
  }

  /// Get shift data using the new unified CaregiverShiftLogService
  Future<Map<String, dynamic>?> _getShiftDataFromUnifiedService(DateTime targetDate) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('ShiftLogs: No authenticated user found');
        return null;
      }

      // First, get the current caregiver's shift assignment to determine previous shift
      final currentCaregiverAssignQuery = await FirebaseFirestore.instance
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: user.uid)
          .where('user_type', isEqualTo: 'caregiver')
          .limit(1)
          .get();

      if (currentCaregiverAssignQuery.docs.isEmpty) {
        print('❌ ShiftLogs: No house assignment found for current caregiver');
        return null;
      }

      final currentCaregiverData = currentCaregiverAssignQuery.docs.first.data();
      final currentHouseId = currentCaregiverData['house_id'];
      final currentUserShift = currentCaregiverData['shift'] as String;
      
      print('🏠 ShiftLogs: Current caregiver house: $currentHouseId');
      print('🔄 ShiftLogs: Current caregiver shift: $currentUserShift');

      // Determine the previous shift based on current shift
      String previousShiftKey = '';
      if (currentUserShift == '1st') {
        previousShiftKey = '3rd'; // 1st shift sees 3rd shift logs
      } else if (currentUserShift == '2nd') {
        previousShiftKey = '1st'; // 2nd shift sees 1st shift logs
      } else if (currentUserShift == '3rd') {
        previousShiftKey = '2nd'; // 3rd shift sees 2nd shift logs
      } else {
        print('❌ ShiftLogs: Unknown shift type: $currentUserShift');
        return null;
      }

      print('🔄 ShiftLogs: Looking for logs from previous shift: $previousShiftKey');

      // Get caregivers from the PREVIOUS shift in the same house
      final previousShiftCaregiverQuery = await FirebaseFirestore.instance
          .collection('house_shift_assignments')
          .where('house_id', isEqualTo: currentHouseId)
          .where('shift', isEqualTo: previousShiftKey)
          .get();

      final previousShiftCaregiversIds = <String>[];
      final dayName = getDayName(targetDate);
      
      // Filter caregivers by who was actually scheduled to work on this day
      for (var doc in previousShiftCaregiverQuery.docs) {
        final data = doc.data();
        final caregiverId = data['user_id'] as String?;
        final userType = data['user_type'] as String?;
        final daysAssigned = data['days_assigned'] as List<dynamic>? ?? [];
        
        if (userType == 'caregiver' && caregiverId != null && daysAssigned.contains(dayName)) {
          previousShiftCaregiversIds.add(caregiverId);
          print('✅ ShiftLogs: Including previous shift caregiver: $caregiverId (works on $dayName)');
        } else if (caregiverId != null) {
          print('❌ ShiftLogs: Skipping caregiver $caregiverId - not scheduled for $dayName');
        }
      }

      print('🏠 ShiftLogs: Found ${previousShiftCaregiversIds.length} caregivers from previous shift ($previousShiftKey) in house $currentHouseId');

      if (previousShiftCaregiversIds.isEmpty) {
        print('⚠️ ShiftLogs: No previous shift caregivers found for house $currentHouseId on $dayName');
        return null;
      }

      // Get shift logs for the selected date using the unified service
      final shiftLogsStream = CaregiverShiftLogService.getShiftLogsForDate(targetDate);
      final allShiftLogs = await shiftLogsStream.first;

      // Filter logs to only include those from PREVIOUS SHIFT caregivers
      final previousShiftLogs = allShiftLogs.where((log) {
        final logCaregiverId = log['caregiver_id'] as String?;
        final isFromPreviousShift = previousShiftCaregiversIds.contains(logCaregiverId);
        
        if (!isFromPreviousShift && logCaregiverId != null) {
          print('🚫 ShiftLogs: Filtering out log from caregiver $logCaregiverId (not from previous shift $previousShiftKey)');
        } else if (isFromPreviousShift) {
          print('✅ ShiftLogs: Including log from previous shift caregiver $logCaregiverId');
        }
        
        return isFromPreviousShift;
      }).toList();

      print('🔍 ShiftLogs: Found ${allShiftLogs.length} total shift logs, ${previousShiftLogs.length} from previous shift ($previousShiftKey) for ${_formatDate(targetDate)}');
      
      if (previousShiftLogs.isEmpty) {
        print('⚠️ ShiftLogs: No shift logs found from previous shift ($previousShiftKey) on date: ${_formatDate(targetDate)}');
        return null;
      }

      // Get unique caregiver count from the filtered logs
      final uniqueCaregivers = previousShiftLogs
          .map((log) => log['caregiver_id'] as String?)
          .where((id) => id != null)
          .toSet()
          .length;

      // Fetch additional logs for PREVIOUS SHIFT caregivers only
      String combinedAdditionalLogs = '';
      try {
        final additionalLogsFutures = previousShiftCaregiversIds.map((caregiverId) async {
          try {
            // Get additional log for this caregiver for the target date
            final dateString = DateFormat('yyyy-MM-dd').format(targetDate);
            final documentId = '${caregiverId}_$dateString';
            
            final snapshot = await FirebaseFirestore.instance
                .collection('cg_additional_logs')
                .doc(documentId)
                .get();
            
            if (snapshot.exists) {
              final data = snapshot.data() as Map<String, dynamic>;
              final content = data['content'] as String? ?? '';
              final caregiverName = data['caregiver_fname'] as String? ?? 'Unknown';
              
              if (content.isNotEmpty) {
                return '$caregiverName: $content';
              }
            }
            return null;
          } catch (e) {
            print('❌ ShiftLogs: Error getting additional log for caregiver $caregiverId: $e');
            return null;
          }
        }).toList();
        
        final additionalLogsResults = await Future.wait(additionalLogsFutures);
        final validLogs = additionalLogsResults.where((log) => log != null).cast<String>().toList();
        
        if (validLogs.isNotEmpty) {
          combinedAdditionalLogs = validLogs.join('\n\n');
        }
        
        print('📝 ShiftLogs: Retrieved ${validLogs.length} additional logs from previous shift for date ${_formatDate(targetDate)}');
      } catch (e) {
        print('❌ ShiftLogs: Error fetching additional logs: $e');
      }

      // Create a simplified shift data structure that matches what the UI expects
      return {
        'shift_info': {
          'total_caregivers': uniqueCaregivers,
          'shift_date': _formatDate(targetDate),
          'house_id': currentHouseId,
          'previous_shift': previousShiftKey,
        },
        'task_logs': previousShiftLogs, // This now includes only logs from PREVIOUS SHIFT caregivers
        'additional_log_content': combinedAdditionalLogs,
      };
    } catch (e) {
      print('❌ ShiftLogs: Error getting shift data: $e');
      return null;
    }
  }



  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1E88E5),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
      _loadShiftData();
    }
  }

  String _formatDate(DateTime date) {
    final formatted = DateFormat('MMMM dd, yyyy').format(date);
    print('🗓️ ShiftLogs: Formatting date $date to: $formatted');
    return formatted;
  }

  // Helper method to filter shift logs based on selected caregiver
  List<dynamic> _filterShiftLogs(List<dynamic> shiftLogs) {
    if (selectedCaregiverFilter == 'All Caregivers') {
      return shiftLogs;
    }
    
    return shiftLogs.where((log) {
      final sourceCaregiverName = log['source_caregiver_name'] as String?;
      final caregiverName = sourceCaregiverName ?? log['caregiver_fname'] ?? 'Unknown';
      return caregiverName == selectedCaregiverFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF22688E), size: 32),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Center(
                child: Text(
                  'Shift Logs',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF22688E),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 48), // Empty space to balance the back button
          ],
        ),
        toolbarHeight: 80,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/background1.png',
              fit: BoxFit.cover,
            ),
          ),
          Column(
            children: [
              // Date selector
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Card(
                  color: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Color(0xFF1E88E5), size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Viewing Shift Logs for:',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF1E88E5),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              Text(
                                _formatDate(selectedDate),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E88E5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Today button
                        InkWell(
                          onTap: () {
                            _refreshToCurrentDate();
                            _loadShiftData();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Today',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        // Calendar picker button
                        InkWell(
                          onTap: () => _selectDate(context),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E88E5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.edit_calendar,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Caregiver Filter Dropdown
              // Filter caregivers by schedule for previous shift and selected day
              FutureBuilder<Map<String, dynamic>>(
                future: getPreviousShiftInfo(selectedDate),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox.shrink();
                  }
                  
                  final prevShiftInfo = snapshot.data!;
                  final scheduledCaregivers = prevShiftInfo['previousCaregivers'] as List<String>;
                  if (scheduledCaregivers.length > 1) {
                    List<String> filterOptions = ['All Caregivers'];
                    filterOptions.addAll(scheduledCaregivers);
                    if (!filterOptions.contains(selectedCaregiverFilter)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        setState(() {
                          selectedCaregiverFilter = 'All Caregivers';
                        });
                      });
                    }
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Card(
                        color: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.filter_list, color: Color(0xFF1E88E5), size: 24),
                              const SizedBox(width: 12),
                              const Text(
                                'Filter by Caregiver:',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF1E88E5),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: selectedCaregiverFilter,
                                    isExpanded: true,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF1E88E5),
                                      fontWeight: FontWeight.bold,
                                    ),
                                    items: filterOptions.map((String option) {
                                      return DropdownMenuItem<String>(
                                        value: option,
                                        child: Text(option),
                                      );
                                    }).toList(),
                                    onChanged: (String? newValue) {
                                      if (newValue != null) {
                                        setState(() {
                                          selectedCaregiverFilter = newValue;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink(); // Hide if no data or single caregiver
                },
              ),
              
              // Emergency Coverage Indicator
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('temporary_assignments')
                    .where('to_user_id', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                    .where('date', isEqualTo: DateFormat('yyyy-MM-dd').format(DateTime.now()))
                    .where('assignment_type', isEqualTo: 'emergency_coverage')
                    .where('status', isEqualTo: 'active')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox.shrink();
                  }

                  if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFF9800),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFFF9800),
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Emergency Coverage',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFE65100),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'You are currently working under emergency coverage and have been reassigned to a different house. Kindly contact your peers for further clarifications regarding your temporary shift duties.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF5D4037),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
              
              Expanded(
                child: SingleChildScrollView(
                  child: FutureBuilder<Map<String, dynamic>?>(
                    future: shiftDataFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(50),
                            child: CircularProgressIndicator(
                              color: Color(0xFF00588e),
                            ),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Card(
                              color: const Color(0xFFFFEBEE),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.error, color: Colors.red, size: 48),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Error Loading Previous Shift',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${snapshot.error}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.red,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      final previousShiftData = snapshot.data;

                      if (previousShiftData == null) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Card(
                              color: const Color(0xFFF5F5F5),
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.info, color: Colors.grey, size: 48),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No Shift Data Found',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No shift handover data found for ${_formatDate(selectedDate)}. Try selecting a different date or check if any tasks were logged on this date.',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                                      final shiftInfo = previousShiftData['shift_info'] as Map<String, dynamic>;
                                      final allShiftLogs = previousShiftData['task_logs'] as List<dynamic>; // This will include all shift logs (tasks, emergency alerts, incident reports)
                                      final shiftLogs = _filterShiftLogs(allShiftLogs); // Apply filter
                                      final additionalLogContent = previousShiftData['additional_log_content'] as String;                      return Column(
                        children: [
                          // Previous Shift Header Card (fixed to show previous shift caregivers)
                          FutureBuilder<Map<String, dynamic>>(
                            future: getPreviousShiftInfo(selectedDate),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              
                              final prevShiftInfo = snapshot.data!;
                              final prevCaregivers = prevShiftInfo['previousCaregivers'] as List<String>;
                              final prevShiftType = prevShiftInfo['previousShiftType'] as String;
                              final prevDate = prevShiftInfo['previousDate'] as DateTime;
                              return Container(
                                width: double.infinity,
                                margin: const EdgeInsets.all(16),
                                child: Card(
                                  color: const Color(0xFF1E88E5),
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              prevCaregivers.length > 1 ? Icons.groups : Icons.swap_horiz,
                                              color: Colors.white,
                                              size: 24,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              prevCaregivers.length > 1 ? 'COLLECTIVE SHIFT HANDOVER' : 'SHIFT HANDOVER',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                                letterSpacing: 1.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        RichText(
                                          text: TextSpan(
                                            style: const TextStyle(
                                              fontSize: 16,
                                              color: Colors.white,
                                              height: 1.4,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: prevShiftType,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              TextSpan(
                                                text: '\n${_formatDate(prevDate)}\nFrom: ${prevCaregivers.isNotEmpty ? prevCaregivers.join(", ") : "-"}',
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (prevCaregivers.length > 1) ...[
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                                              children: [
                                                Column(
                                                  children: [
                                                    Text(
                                                      '${prevCaregivers.length}',
                                                      style: const TextStyle(
                                                        fontSize: 20,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    const Text(
                                                      'Caregivers',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.white70,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Column(
                                                  children: [
                                                    Text(
                                                      selectedCaregiverFilter == 'All Caregivers'
                                                          ? '${shiftLogs.length}'
                                                          : '${shiftLogs.length}/${allShiftLogs.length}',
                                                      style: const TextStyle(
                                                        fontSize: 20,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    Text(
                                                      selectedCaregiverFilter == 'All Caregivers'
                                                          ? 'Activities'
                                                          : 'Filtered',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.white70,
                                                      ),
                                                    ),
                                                  ],
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
                            },
                          ),

                          // Task Logs Section
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            child: Card(
                              color: const Color(0xFFB3E0E8),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            selectedCaregiverFilter == 'All Caregivers'
                                                ? ((shiftInfo['total_caregivers'] as int? ?? 1) > 1 
                                                    ? 'Collective Logged Activities:'
                                                    : 'Logged Activities:')
                                                : 'Logged Activities - $selectedCaregiverFilter:',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF00588e),
                                            ),
                                          ),
                                        ),
                                        if (selectedCaregiverFilter != 'All Caregivers')
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1E88E5),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Text(
                                              'FILTERED',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    const Divider(thickness: 1, color: Color(0xFF00588e)),
                                    const SizedBox(height: 12),
                                    if (shiftLogs.isEmpty)
                                      const Text(
                                        'No logged activities recorded.',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.grey,
                                        ),
                                      )
                                    else
                                      ...shiftLogs.asMap().entries.map((entry) {
                                        final index = entry.key;
                                        final log = entry.value as Map<String, dynamic>;
                                        
                                        final completionTime = CaregiverShiftLogService.formatCompletionTime(
                                          log['completion_time'] as Timestamp?,
                                        );
                                        
                                        // Check log type to determine how to display
                                        final logType = log['log_type'] as String? ?? 'task'; // Default to task for backward compatibility
                                        
                                        String logMessage;
                                        String? reason;
                                        
                                        if (logType == 'emergency_alert' || logType == 'incident_report') {
                                          // Use the unified service for emergency alerts and incident reports
                                          logMessage = CaregiverShiftLogService.formatLogMessage(log);
                                          reason = CaregiverShiftLogService.getLogDescription(log);
                                        } else {
                                          // Handle task logs (existing logic)
                                          // Fix caregiver name display logic to prevent duplication and resolve "Caregiver 28" issue
                                          String caregiverName = '';
                                          if (log['source_caregiver_name'] != null && (log['source_caregiver_name'] as String).isNotEmpty) {
                                            caregiverName = log['source_caregiver_name'] as String;
                                          } else if (log['caregiver_fname'] != null && (log['caregiver_fname'] as String).isNotEmpty) {
                                            caregiverName = log['caregiver_fname'] as String;
                                          } else {
                                            caregiverName = 'Unknown';
                                          }
                                          
                                          // If the caregiver name looks generic (like "Caregiver 28"), clean it up
                                          if (caregiverName.startsWith('Caregiver') && RegExp(r'Caregiver\s*\d+').hasMatch(caregiverName)) {
                                            // Extract just the number part and use it as a more readable fallback
                                            final match = RegExp(r'(\d+)').firstMatch(caregiverName);
                                            if (match != null) {
                                              caregiverName = 'CG${match.group(1)}'; // Convert "Caregiver 28" to "CG28"
                                            } else {
                                              caregiverName = 'Caregiver'; // Fallback to generic name
                                            }
                                          }
                                          
                                          // Create custom message to avoid duplication from CaregiverShiftLogService
                                          final elderlyName = log['elderly_fname'] ?? '';
                                          final taskDesc = log['task_description'] ?? '';
                                          final status = log['task_status'] ?? ''; // Changed from 'status' to 'task_status'
                                          
                                          if (status.toLowerCase() == 'completed') {
                                            logMessage = 'Caregiver $caregiverName completed the task "$taskDesc" for $elderlyName';
                                          } else if (status.toLowerCase() == 'missed') {
                                            logMessage = 'Caregiver $caregiverName missed the task "$taskDesc" for $elderlyName';
                                          } else if (status.toLowerCase() == "didn't complete" || status.toLowerCase() == 'incomplete') {
                                            logMessage = "Caregiver $caregiverName did not complete the task \"$taskDesc\" for $elderlyName";
                                          } else {
                                            logMessage = 'Caregiver $caregiverName $status the task "$taskDesc" for $elderlyName';
                                          }
                                          
                                          reason = log['inc_reason']?.toString().isNotEmpty == true // Changed from 'reason' to 'inc_reason'
                                              ? 'Reason: ${log['inc_reason']}' // Changed from 'reason' to 'inc_reason'
                                              : null;
                                        }
                                        
                                        return Column(
                                          children: [
                                            _buildTaskSummaryRow(
                                              time: completionTime,
                                              text: logMessage,
                                              reason: reason,
                                              isCollectiveHandover: log['source_caregiver_name'] != null && (log['source_caregiver_name'] as String).isNotEmpty,
                                            ),
                                            if (index < shiftLogs.length - 1) 
                                              const SizedBox(height: 10),
                                          ],
                                        );
                                      }),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Additional Logs Section
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            child: Card(
                              color: const Color(0xFFB3E0E8),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (shiftInfo['total_caregivers'] as int? ?? 1) > 1 
                                          ? 'Combined Additional Notes:'
                                          : 'Additional Notes:',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF00588e),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Divider(thickness: 1, color: Color(0xFF00588e)),
                                    const SizedBox(height: 12),
                                    if (additionalLogContent.isEmpty)
                                      const Text(
                                        'No additional notes recorded.',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.grey,
                                        ),
                                      )
                                    else
                                      Text(
                                        additionalLogContent,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskSummaryRow({
    required String time, 
    required String text, 
    String? reason,
    bool isCollectiveHandover = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(
            Icons.circle, 
            color: isCollectiveHandover ? Color(0xFF1E88E5) : Colors.red, 
            size: 12
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 16, color: Colors.black),
                  children: [
                    TextSpan(
                      text: '$time : ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: text),
                  ],
                ),
              ),
              if (reason != null)
                Padding(
                  padding: const EdgeInsets.only(left: 0, top: 2),
                  child: Text(
                    reason,
                    style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}