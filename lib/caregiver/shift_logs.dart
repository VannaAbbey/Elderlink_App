
import 'package:flutter/material.dart';
import '../services/shift_handover_service.dart';
import '../services/task_log_service.dart';
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
          .collection('cg_house_assign')
          .where('caregiver_id', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (currentCaregiverAssignQuery.docs.isEmpty) {
        print('❌ DEBUG: No house assignment found for current caregiver');
        return [];
      }

      final currentHouseId = currentCaregiverAssignQuery.docs.first.data()['house_id'];
      print('🏠 DEBUG: Current user house: $currentHouseId');
      
      // Query cg_house_assign collection for caregivers with the specified shift AND same house
      final query = await FirebaseFirestore.instance
          .collection('cg_house_assign')
          .where('house_id', isEqualTo: currentHouseId)
          .where('shift', isEqualTo: shiftType)
          .get();

      print('🔍 DEBUG: Found ${query.docs.length} total assignments for shift $shiftType in house $currentHouseId');
      
      List<String> caregiverNames = [];
      
      for (var doc in query.docs) {
        final data = doc.data();
        final caregiverId = data['caregiver_id'] as String?;
        final daysAssigned = data['days_assigned'] as List<dynamic>? ?? [];
        
        print('🔍 DEBUG: Checking caregiver $caregiverId - assigned days: $daysAssigned');
        
        // Check if the caregiver is assigned to work on this specific day
        if (caregiverId != null && daysAssigned.contains(dayName)) {
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
        .collection('cg_house_assign')
        .where('caregiver_id', isEqualTo: user.uid)
        .limit(1)
        .get();

    if (currentCaregiverAssignQuery.docs.isEmpty) {
      print('❌ DEBUG: No house assignment found for current caregiver in getPreviousShiftInfo');
      return {'shiftType': '', 'previousShiftType': '', 'previousCaregivers': <String>[], 'previousDate': date};
    }

    final currentUserShift = currentCaregiverAssignQuery.docs.first.data()['shift'] as String;
    print('🔄 DEBUG: Current user assigned shift: $currentUserShift');
    
    String shiftType = '';
    String previousShiftType = '';
    String previousShiftKey = '';
    DateTime previousDate = date;
    
    // Use the user's assigned shift, not current time
    if (currentUserShift == '1st') {
      // Current: 1st Shift (6:00 AM - 2:00 PM) -> Previous: 3rd Shift (10:00 PM - 6:00 AM)
      shiftType = '1st Shift (6:00 AM - 2:00 PM)';
      previousShiftType = '3rd Shift (10:00 PM - 6:00 AM)';
      previousShiftKey = '3rd';
      previousDate = date.subtract(const Duration(days: 1)); // 3rd shift is from previous night
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
  DateTime selectedDate = DateTime.now();
  Future<Map<String, dynamic>?>? shiftDataFuture;
  String selectedCaregiverFilter = 'All Caregivers'; // Filter state

  @override
  void initState() {
    super.initState();
    // Load today's shift data initially
    _loadShiftData();
  }

  void _loadShiftData() {
    setState(() {
      shiftDataFuture = ShiftHandoverService.getPreviousShiftDataForDate(selectedDate);
    });
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
    return DateFormat('MMMM dd, yyyy').format(date);
  }

  // Helper method to filter task logs based on selected caregiver
  List<dynamic> _filterTaskLogs(List<dynamic> taskLogs) {
    if (selectedCaregiverFilter == 'All Caregivers') {
      return taskLogs;
    }
    
    return taskLogs.where((log) {
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
                      final allTaskLogs = previousShiftData['task_logs'] as List<dynamic>;
                      final taskLogs = _filterTaskLogs(allTaskLogs); // Apply filter
                      final additionalLogContent = previousShiftData['additional_log_content'] as String;

                      return Column(
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
                                                          ? '${taskLogs.length}'
                                                          : '${taskLogs.length}/${allTaskLogs.length}',
                                                      style: const TextStyle(
                                                        fontSize: 20,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    Text(
                                                      selectedCaregiverFilter == 'All Caregivers'
                                                          ? 'Tasks'
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
                                                    ? 'Collective Task Activities:'
                                                    : 'Task Activities:')
                                                : 'Task Activities - $selectedCaregiverFilter:',
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
                                    if (taskLogs.isEmpty)
                                      const Text(
                                        'No task activities recorded.',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.grey,
                                        ),
                                      )
                                    else
                                      ...taskLogs.asMap().entries.map((entry) {
                                        final index = entry.key;
                                        final log = entry.value as Map<String, dynamic>;
                                        
                                        final completionTime = TaskLogService.formatCompletionTime(
                                          log['completion_time'] as Timestamp?,
                                        );
                                        
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
                                        
                                        // Create custom message to avoid duplication from TaskLogService
                                        final elderlyName = log['elderly_fname'] ?? '';
                                        final taskDesc = log['task_description'] ?? '';
                                        final status = log['status'] ?? '';
                                        
                                        String logMessage;
                                        if (status.toLowerCase() == 'completed') {
                                          logMessage = 'Caregiver $caregiverName completed the task "$taskDesc" for $elderlyName';
                                        } else if (status.toLowerCase() == 'missed') {
                                          logMessage = 'Caregiver $caregiverName missed the task "$taskDesc" for $elderlyName';
                                        } else if (status.toLowerCase() == "didn't complete" || status.toLowerCase() == 'incomplete') {
                                          logMessage = "Caregiver $caregiverName did not complete the task \"$taskDesc\" for $elderlyName";
                                        } else {
                                          logMessage = 'Caregiver $caregiverName $status the task "$taskDesc" for $elderlyName';
                                        }
                                        
                                        final reason = log['reason']?.toString().isNotEmpty == true 
                                            ? 'Reason: ${log['reason']}'
                                            : null;
                                        
                                        return Column(
                                          children: [
                                            _buildTaskSummaryRow(
                                              time: completionTime,
                                              text: logMessage,
                                              reason: reason,
                                              isCollectiveHandover: log['source_caregiver_name'] != null && (log['source_caregiver_name'] as String).isNotEmpty,
                                            ),
                                            if (index < taskLogs.length - 1) 
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