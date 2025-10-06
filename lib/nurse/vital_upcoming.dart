import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'vital_update_screen.dart';

class UpcomingVitalsTab extends StatefulWidget {
  final String houseId;
  final String? nurseName;

  const UpcomingVitalsTab({
    super.key,
    required this.houseId,
    required this.nurseName,
  });

  @override
  State<UpcomingVitalsTab> createState() => _UpcomingVitalsTabState();
}

class _UpcomingVitalsTabState extends State<UpcomingVitalsTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;

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

  String _getTodayDateString() {
    final now = DateTime.now();
    final currentHour = now.hour;

    // For third shift (10pm-6am), if it's after midnight (0:00-5:59),
    // we need to use the previous day's date for assignments
    if (currentHour >= 0 && currentHour < 6) {
      // It's after midnight during third shift, so get previous day's date
      final previousDay = now.subtract(Duration(days: 1));
      return DateFormat('yyyy-MM-dd').format(previousDay);
    }

    // For all other times, use current date
    return DateFormat('yyyy-MM-dd').format(now);
  }

  String _getPreviousShift() {
    final currentShift = _getCurrentShift();
    switch (currentShift) {
      case "1st":
        return "3rd"; // Previous shift was 3rd
      case "2nd":
        return "1st"; // Previous shift was 1st
      case "3rd":
        return "2nd"; // Previous shift was 2nd
      default:
        return "1st";
    }
  }

  // Check if we need to handle shift transition based on actual nurse change
  Future<void> _handleShiftTransition(String currentNurseId) async {
    final today = _getTodayDateString();
    final currentShift = _getCurrentShift();
    final previousShift = _getPreviousShift();

    print('🔄 Checking shift transition: $previousShift → $currentShift');

    // Get all pending assignments from previous shift for this house
    final previousShiftAssignments = await _firestore
        .collection('daily_vital_assignments')
        .where('house_id', isEqualTo: widget.houseId)
        .where('assigned_date', isEqualTo: today)
        .where('shift', isEqualTo: previousShift)
        .where('status', isEqualTo: 'pending')
        .get();

    print(
      '📋 Found ${previousShiftAssignments.docs.length} pending assignments from previous shift',
    );

    // Only mark as missed if a DIFFERENT nurse is now working this shift
    // (i.e., the shift has actually changed hands)
    if (previousShiftAssignments.docs.isNotEmpty) {
      // Check if the current nurse is different from the nurse who had previous shift assignments
      final firstAssignment = previousShiftAssignments.docs.first.data();
      final previousNurseId = firstAssignment['assigned_nurse_id'];
      final previousNurseName = firstAssignment['assigned_nurse_name'];

      print(
        'Previous nurse: $previousNurseName ($previousNurseId), Current nurse: ${widget.nurseName} ($currentNurseId)',
      );

      // Only transfer assignments if it's a different nurse taking over
      if (previousNurseId != currentNurseId) {
        print(
          '🔄 Different nurse detected - transferring assignments from $previousNurseName to ${widget.nurseName}',
        ); // Transfer previous shift assignments to current nurse as new pending assignments
        for (final doc in previousShiftAssignments.docs) {
          final data = doc.data();

          // First mark the original assignment as missed for logging purposes
          await doc.reference.update({
            'status': 'missed',
            'updated_at': FieldValue.serverTimestamp(),
            'missed_reason': 'Shift ended - transferred to next nurse',
          });

          // Log the missed action for the previous nurse
          await _firestore.collection('vitals_activity_logs').add({
            'assignment_id': doc.id,
            'elderly_id': data['elderly_id'],
            'elderly_name': data['elderly_name'],
            'nurse_id': data['assigned_nurse_id'],
            'nurse_name': data['assigned_nurse_name'],
            'action_type': 'missed',
            'action_timestamp': FieldValue.serverTimestamp(),
            'reason': 'Shift ended - transferred to next nurse',
            'previous_shift': previousShift,
            'current_shift': currentShift,
            'transferred_to_nurse_id': currentNurseId,
            'transferred_to_nurse_name': widget.nurseName,
          });

          // Create a new pending assignment for the current nurse
          print(
            '🏗️ Creating inherited assignment with nurse name: ${data['assigned_nurse_name']}',
          );
          await _firestore.collection('daily_vital_assignments').add({
            'elderly_id': data['elderly_id'],
            'elderly_name': data['elderly_name'],
            'elderly_profilePic': data['elderly_profilePic'] ?? '',
            'assigned_nurse_id': currentNurseId,
            'assigned_nurse_name': widget.nurseName,
            'house_id': widget.houseId,
            'assigned_date': today,
            'shift': currentShift,
            'status': 'pending',
            'created_at': FieldValue.serverTimestamp(),
            'updated_at': FieldValue.serverTimestamp(),
            'inherited_from_shift': previousShift,
            'inherited_from_nurse_id': data['assigned_nurse_id'],
            'inherited_from_nurse_name': data['assigned_nurse_name'],
          });

          print(
            '✅ Created new pending assignment for: ${data['elderly_name']} (inherited from ${data['assigned_nurse_name']} - $previousShift shift)',
          );
        }
      } else {
        print(
          '🔄 Same nurse ($previousNurseName) continuing - keeping assignments as pending',
        );
      }
    }
  }

  // Create daily vital assignments for all assigned elderly
  Future<void> _cleanupIncorrectAssignments(
    String nurseId,
    List<String> validElderlyIds,
  ) async {
    final today = _getTodayDateString();
    final currentShift = _getCurrentShift();

    print('🧹 Cleaning up incorrect assignments...');
    print('🧹 Valid elderly IDs for this nurse: $validElderlyIds');

    // Get all assignments for this nurse, today, and current shift
    final incorrectAssignments = await _firestore
        .collection('daily_vital_assignments')
        .where('assigned_nurse_id', isEqualTo: nurseId)
        .where('assigned_date', isEqualTo: today)
        .where('shift', isEqualTo: currentShift)
        .get();

    int deletedCount = 0;
    for (final doc in incorrectAssignments.docs) {
      final data = doc.data();
      final elderlyId = data['elderly_id'];
      final assignmentHouseId = data['house_id'];
      bool shouldDelete = false;
      String deleteReason = '';

      // Check if elderly ID is in the valid list for this nurse
      if (!validElderlyIds.contains(elderlyId)) {
        shouldDelete = true;
        deleteReason = 'Elderly not assigned to this nurse';
      }
      // Check if house_id matches the current tab's house
      else if (assignmentHouseId != widget.houseId) {
        shouldDelete = true;
        deleteReason =
            'Wrong house_id (was: $assignmentHouseId, should be: ${widget.houseId})';
      }
      // Double-check against actual elderly data
      else {
        final elderlyDoc = await _firestore
            .collection('elderly')
            .doc(elderlyId)
            .get();

        if (elderlyDoc.exists) {
          final elderlyData = elderlyDoc.data()!;
          final actualHouseId = elderlyData['house_id'];
          final elderlyStatus = elderlyData['elderly_status'];

          // Delete if elderly's actual house doesn't match assignment house
          if (actualHouseId != assignmentHouseId) {
            shouldDelete = true;
            deleteReason =
                'Elderly actual house mismatch (assignment: $assignmentHouseId, actual: $actualHouseId)';
          }
          // Delete if elderly is not alive
          else if (elderlyStatus != 'Alive') {
            shouldDelete = true;
            deleteReason =
                'Elderly status is not Alive (status: $elderlyStatus)';
          }
        } else {
          shouldDelete = true;
          deleteReason = 'Elderly document does not exist';
        }
      }

      if (shouldDelete) {
        await doc.reference.delete();
        deletedCount++;
        print(
          '🗑️ Deleted incorrect assignment: ${data['elderly_name']} - $deleteReason',
        );
      }
    }

    print('🧹 Cleanup complete: Deleted $deletedCount incorrect assignments');
  }

  Future<void> _createDailyVitalAssignments(
    String nurseId,
    List<String> elderlyIds,
  ) async {
    final today = _getTodayDateString();
    final currentShift = _getCurrentShift();

    print(
      '🏗️ Creating daily vital assignments for date: $today, shift: $currentShift',
    );
    print('🏗️ Nurse ID: $nurseId');
    print('🏗️ House ID: ${widget.houseId}');
    print('🏗️ Elderly IDs count: ${elderlyIds.length}');

    for (final elderlyId in elderlyIds) {
      // Check if assignment already exists for today - simplified check
      final existingQuery = await _firestore
          .collection('daily_vital_assignments')
          .where('elderly_id', isEqualTo: elderlyId)
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .get();

      print(
        '🔍 Checking existing assignments for elderly: $elderlyId on $today, shift: $currentShift',
      );
      print('🔍 Found ${existingQuery.docs.length} existing assignments');

      if (existingQuery.docs.isEmpty) {
        print(
          '📋 No existing assignment found for elderly: $elderlyId - CREATING NEW',
        );
        // Get elderly details
        final elderlyDoc = await _firestore
            .collection('elderly')
            .doc(elderlyId)
            .get();
        if (elderlyDoc.exists) {
          final elderlyData = elderlyDoc.data()!;

          // IMPORTANT: Only create assignment if elderly belongs to this house
          if (elderlyData['house_id'] == widget.houseId &&
              elderlyData['elderly_status'] == 'Alive') {
            final elderlyName =
                '${elderlyData['elderly_fname'] ?? ''} ${elderlyData['elderly_lname'] ?? ''}'
                    .trim();

            // Create daily assignment with CORRECT house_id from elderly data
            await _firestore.collection('daily_vital_assignments').add({
              'elderly_id': elderlyId,
              'elderly_name': elderlyName,
              'elderly_profilePic': elderlyData['elderly_profilePic'] ?? '',
              'house_id':
                  elderlyData['house_id'], // Use ACTUAL house_id from elderly data
              'assigned_nurse_id': nurseId,
              'assigned_nurse_name': widget.nurseName,
              'status': 'pending', // pending, completed, missed
              'assigned_date': today,
              'shift': currentShift,
              'created_at': FieldValue.serverTimestamp(),
              'updated_at': FieldValue.serverTimestamp(),
            });
            print(
              '✅ CREATED daily vital assignment for elderly: $elderlyName (House: ${elderlyData['house_id']})',
            );
          } else {
            print(
              '❌ SKIPPED elderly $elderlyId - belongs to house ${elderlyData['house_id']}, not ${widget.houseId}, or status: ${elderlyData['elderly_status']}',
            );
          }
        }
      } else {
        print(
          '⏭️ EXISTING assignment found for elderly: $elderlyId, skipping creation',
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _getUpcomingVitals() async {
    try {
      final currentShift = _getCurrentShift();
      final currentDay = _getCurrentDay();

      print(
        'Fetching for nurse: ${widget.nurseName}, shift: $currentShift, day: $currentDay',
      );
      print('🏠 CURRENT TAB: Filtering for house: "${widget.houseId}"');

      // First get the nurse's ID from users collection
      final nameParts = widget.nurseName?.split(' ') ?? [];
      if (nameParts.length < 2) {
        print('Invalid nurse name format: ${widget.nurseName}');
        return [];
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
        return [];
      }

      final nurseId = userQuery.docs.first.id;
      print('Found nurse ID: $nurseId');

      // Handle shift transition - only mark as missed if different nurse is taking over
      await _handleShiftTransition(nurseId);

      // First check if nurse is assigned to work this shift on this day
      print('Checking shift assignment for nurseId: $nurseId');
      print('Looking for - Shift: $currentShift, Day: $currentDay');

      final shiftQuery = await _firestore
          .collection('nurse_shift_assign')
          .where('nurse_id', isEqualTo: nurseId)
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .where('days_assigned', arrayContains: currentDay)
          .get();

      if (shiftQuery.docs.isEmpty) {
        print('Nurse is not assigned to this shift on this day');
        return [];
      }

      print('Found shift assignment: ${shiftQuery.docs.first.data()}');

      // Get nurse's assigned elderly for current day and shift for THIS HOUSE
      final nurseElderlyQuery = await _firestore
          .collection('nurse_elderly_assign')
          .where('nurse_id', isEqualTo: nurseId)
          .where('is_current', isEqualTo: true)
          .where('house_ids', arrayContains: widget.houseId)
          .where('shift', isEqualTo: currentShift)
          .where('day', isEqualTo: currentDay)
          .get();

      print(
        'Found ${nurseElderlyQuery.docs.length} matching nurse assignments for house ${widget.houseId}',
      );

      if (nurseElderlyQuery.docs.isEmpty) {
        print(
          'No assignments found for the current day and shift in house ${widget.houseId}',
        );
        return [];
      }

      // Get the assignment document
      final assignmentDoc = nurseElderlyQuery.docs.first;
      final data = assignmentDoc.data();
      print('Assignment data for house ${widget.houseId}: $data');

      // Get ALL elderly IDs assigned to this nurse
      final allElderlyIds = List<String>.from(data['elderly_ids'] ?? []);
      print('All elderly IDs assigned to nurse: $allElderlyIds');

      // Filter to get ONLY elderly that belong to THIS HOUSE
      final elderlyIdsForThisHouse = <String>[];

      for (final elderlyId in allElderlyIds) {
        final elderlyDoc = await _firestore
            .collection('elderly')
            .doc(elderlyId)
            .get();

        if (elderlyDoc.exists) {
          final elderlyData = elderlyDoc.data()!;
          final elderlyHouseId = elderlyData['house_id'];
          final elderlyName =
              '${elderlyData['elderly_fname']} ${elderlyData['elderly_lname']}';

          if (elderlyHouseId == widget.houseId &&
              elderlyData['elderly_status'] == 'Alive') {
            elderlyIdsForThisHouse.add(elderlyId);
            print(
              '✅ Including elderly: $elderlyName (belongs to house ${widget.houseId})',
            );
          } else {
            print(
              '❌ Excluding elderly: $elderlyName (belongs to house $elderlyHouseId, not ${widget.houseId})',
            );
          }
        }
      }

      print(
        'Found ${elderlyIdsForThisHouse.length} elderly IDs that belong to house ${widget.houseId}: $elderlyIdsForThisHouse',
      );

      if (elderlyIdsForThisHouse.isEmpty) {
        print('No elderly found for house ${widget.houseId}');
        return [];
      }

      // Clean up any incorrect assignments first (now that we have valid elderly IDs)
      await _cleanupIncorrectAssignments(nurseId, elderlyIdsForThisHouse);

      // Create daily vital assignments for elderly in THIS HOUSE ONLY
      print(
        '🚀 About to call _createDailyVitalAssignments with nurseId: $nurseId and ${elderlyIdsForThisHouse.length} elderly',
      );
      await _createDailyVitalAssignments(nurseId, elderlyIdsForThisHouse);
      print('✅ Finished calling _createDailyVitalAssignments');

      final today = _getTodayDateString();

      // Get pending daily vital assignments for today - ONLY for this house
      print('Querying daily_vital_assignments with:');
      print('- assigned_nurse_id: $nurseId');
      print('- house_id: ${widget.houseId}');
      print('- assigned_date: $today');
      print('- shift: $currentShift');
      print('- status: pending');

      // Debug: Check ALL assignments first
      final nurseAssignmentsQuery = await _firestore
          .collection('daily_vital_assignments')
          .where('assigned_nurse_id', isEqualTo: nurseId)
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .get();

      print('🔍 DEBUG: All assignments for nurse:');
      for (final doc in nurseAssignmentsQuery.docs) {
        final data = doc.data();
        print(
          '   - ${data['elderly_name']} → House: ${data['house_id']} (Expected: ${widget.houseId})',
        );
        print(
          '     → Status: ${data['status']}, Date: ${data['assigned_date']}, Shift: ${data['shift']}',
        );
      }

      // Get only pending assignments for current nurse (including inherited ones that were created as new pending assignments)
      final currentNurseAssignments = await _firestore
          .collection('daily_vital_assignments')
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .where('assigned_nurse_id', isEqualTo: nurseId)
          .where('house_id', isEqualTo: widget.houseId)
          .where('status', isEqualTo: 'pending')
          .get();

      print(
        '🔍 Found ${currentNurseAssignments.docs.length} pending assignments for current nurse',
      );

      final availableAssignments = currentNurseAssignments.docs;

      print('Found ${availableAssignments.length} total pending assignments');

      final upcomingVitals = <Map<String, dynamic>>[];
      final seenElderlyIds = <String>{}; // Prevent duplicates

      for (final assignmentDoc in availableAssignments) {
        final assignmentData = assignmentDoc.data();
        final elderlyId = assignmentData['elderly_id'];
        final status = assignmentData['status'];
        final originalNurse = assignmentData['assigned_nurse_name'];

        // CRITICAL VALIDATION: Only show elderly that are actually assigned to this nurse AND belong to this house
        if (assignmentData['house_id'] == widget.houseId &&
            !seenElderlyIds.contains(elderlyId) &&
            elderlyIdsForThisHouse.contains(elderlyId)) {
          // ADDED: Must be in the valid assigned list
          seenElderlyIds.add(elderlyId);

          print(
            '✅ VALIDATED: Including elderly ${assignmentData['elderly_name']} - assigned to this nurse and belongs to this house',
          );

          // Determine if this is an inherited assignment (created from previous shift)
          final isInherited = assignmentData['inherited_from_shift'] != null;

          // Debug: Check what's actually stored in the database
          if (isInherited) {
            print('🔍 DEBUG Inherited assignment data:');
            print(
              '   - inherited_from_nurse_name: ${assignmentData['inherited_from_nurse_name']}',
            );
            print(
              '   - inherited_from_shift: ${assignmentData['inherited_from_shift']}',
            );
            print(
              '   - inherited_from_nurse_id: ${assignmentData['inherited_from_nurse_id']}',
            );
          }

          // Get the original nurse name for display
          String originalNurseForDisplay = originalNurse;

          if (isInherited) {
            // First try the stored nurse name
            print(
              '🔍 Stored nurse name: ${assignmentData['inherited_from_nurse_name']}',
            );
            if (assignmentData['inherited_from_nurse_name'] != null &&
                assignmentData['inherited_from_nurse_name'] != '') {
              originalNurseForDisplay =
                  assignmentData['inherited_from_nurse_name'];
              print('✅ Using stored nurse name: $originalNurseForDisplay');
            } else {
              // If not available, look up from vitals activity logs who missed this elderly's vitals
              try {
                print(
                  '🔍 Looking up nurse name from activity logs for elderly: $elderlyId',
                );

                final activityQuery = await _firestore
                    .collection('vitals_activity_logs')
                    .where('elderly_id', isEqualTo: elderlyId)
                    .where('action_type', isEqualTo: 'missed')
                    .limit(10)
                    .get();

                print(
                  '🔍 Found ${activityQuery.docs.length} missed activity logs for elderly $elderlyId',
                );

                if (activityQuery.docs.isNotEmpty) {
                  // Find the most recent activity log manually since we can't use orderBy
                  Map<String, dynamic>? mostRecentLog;
                  Timestamp? mostRecentTime;

                  for (final doc in activityQuery.docs) {
                    final data = doc.data();
                    final timestamp = data['action_timestamp'] as Timestamp?;

                    if (timestamp != null &&
                        (mostRecentTime == null ||
                            timestamp.compareTo(mostRecentTime) > 0)) {
                      mostRecentTime = timestamp;
                      mostRecentLog = data;
                    }
                  }

                  if (mostRecentLog != null) {
                    print('🔍 Most recent activity log data: $mostRecentLog');

                    final nurseName = mostRecentLog['nurse_name'];
                    final actionType = mostRecentLog['action_type'];
                    final elderlyIdFromLog = mostRecentLog['elderly_id'];

                    print('🔍 Extracted data:');
                    print('   - nurse_name: $nurseName');
                    print('   - action_type: $actionType');
                    print('   - elderly_id: $elderlyIdFromLog');
                    print('   - Looking for elderly_id: $elderlyId');

                    if (nurseName != null && nurseName != '') {
                      originalNurseForDisplay = nurseName;
                      print(
                        '✅ SUCCESS: Found nurse from activity logs: $originalNurseForDisplay',
                      );
                    } else {
                      final previousShift =
                          assignmentData['inherited_from_shift'];
                      originalNurseForDisplay =
                          'Previous Nurse ($previousShift shift)';
                      print(
                        '❌ FAILED: Nurse name is null/empty in activity logs',
                      );
                    }
                  } else {
                    final previousShift =
                        assignmentData['inherited_from_shift'];
                    originalNurseForDisplay =
                        'Previous Nurse ($previousShift shift)';
                    print(
                      '❌ FAILED: No valid timestamp found in activity logs',
                    );
                  }
                } else {
                  final previousShift = assignmentData['inherited_from_shift'];
                  originalNurseForDisplay =
                      'Previous Nurse ($previousShift shift)';
                  print(
                    '❌ No missed activity logs found for elderly $elderlyId',
                  );
                }
              } catch (e) {
                print('❌ Error fetching from activity logs: $e');
                // Final fallback - if we can't get from activity logs,
                // the assignment should have been created with the correct nurse name
                final previousShift = assignmentData['inherited_from_shift'];
                originalNurseForDisplay =
                    'Previous Nurse ($previousShift shift)';
              }
            }
          }
          print(
            'Adding elderly: ${assignmentData['elderly_name']} - Status: $status, ${isInherited ? "INHERITED from previous shift" : "CURRENT ASSIGNMENT"}',
          );

          upcomingVitals.add({
            'assignment_id': assignmentDoc.id,
            'elderly_id': assignmentData['elderly_id'],
            'elderly_name': assignmentData['elderly_name'],
            'elderly_profilePic': assignmentData['elderly_profilePic'] ?? '',
            'house_id': assignmentData['house_id'],
            'status':
                'pending', // All assignments shown are pending for current nurse
            'assigned_date': assignmentData['assigned_date'],
            'shift': assignmentData['shift'],
            'original_nurse': originalNurseForDisplay,
            'is_inherited': isInherited,
            'inherited_from_shift': assignmentData['inherited_from_shift'],
            'last_vital': null, // Will be loaded separately if needed
          });
        } else if (seenElderlyIds.contains(elderlyId)) {
          print(
            '🔄 DUPLICATE: Skipping duplicate elderly: ${assignmentData['elderly_name']} (${elderlyId})',
          );
        } else {
          // Debug: Why was this elderly rejected?
          final reasons = <String>[];
          if (assignmentData['house_id'] != widget.houseId) {
            reasons.add(
              'wrong house (${assignmentData['house_id']} != ${widget.houseId})',
            );
          }
          if (!elderlyIdsForThisHouse.contains(elderlyId)) {
            reasons.add('not assigned to this nurse');
          }
          print(
            '❌ REJECTED: Skipping elderly ${assignmentData['elderly_name']} - ${reasons.join(', ')}',
          );
        }
      }

      // Sort by elderly name
      upcomingVitals.sort(
        (a, b) => (a['elderly_name'] as String).compareTo(
          b['elderly_name'] as String,
        ),
      );

      print('DEBUG: Returning ${upcomingVitals.length} elderly for display');
      return upcomingVitals;
    } catch (e) {
      print('Error getting upcoming vitals: $e');
      return [];
    }
  }

  Future<void> _updateVitals(Map<String, dynamic> elderlyInfo) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VitalUpdateScreen(
          assignmentId: elderlyInfo['assignment_id'],
          elderlyId: elderlyInfo['elderly_id'],
          elderlyName: elderlyInfo['elderly_name'],
          nurseName: widget.nurseName,
        ),
      ),
    );

    // Refresh the list if vitals were updated
    if (result == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    print(
      '🏗️ UpcomingVitalsTab build() called with houseId: ${widget.houseId}',
    );

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getUpcomingVitals(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final upcomingVitals = snapshot.data ?? [];

        if (upcomingVitals.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.elderly, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No elderly assigned',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text(
                  'No elderly assigned to you for this shift',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.symmetric(vertical: 8),
          itemCount: upcomingVitals.length,
          itemBuilder: (context, index) {
            final elderlyInfo = upcomingVitals[index];
            final lastVital =
                elderlyInfo['last_vital'] as Map<String, dynamic>?;

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
                        CircleAvatar(
                          backgroundColor: const Color(0xFF00588E),
                          child:
                              elderlyInfo['elderly_profilePic']?.isNotEmpty ==
                                  true
                              ? ClipOval(
                                  child: Image.network(
                                    elderlyInfo['elderly_profilePic'],
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Icon(Icons.person, color: Colors.white),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            elderlyInfo['elderly_name'] ?? 'Unknown',
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

                    // Status and Tap to Update
                    GestureDetector(
                      onTap: () => _updateVitals(elderlyInfo),
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: elderlyInfo['status'] == 'missed'
                                ? Colors.red.withOpacity(0.3)
                                : Colors.orange.withOpacity(0.3),
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: elderlyInfo['status'] == 'missed'
                              ? Colors.red.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              elderlyInfo['status'] == 'missed'
                                  ? Icons.warning
                                  : Icons.pending_actions,
                              color: elderlyInfo['status'] == 'missed'
                                  ? Colors.red
                                  : Colors.orange,
                              size: 24,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              elderlyInfo['is_inherited'] ==
                                                  true
                                              ? Colors.blue
                                              : Colors.orange,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          elderlyInfo['is_inherited'] == true
                                              ? 'INHERITED'
                                              : 'PENDING',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          elderlyInfo['is_inherited'] == true
                                              ? 'From Previous Shift'
                                              : 'Not Updated Today',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color:
                                                elderlyInfo['is_inherited'] ==
                                                    true
                                                ? Colors.blue
                                                : Colors.orange,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 4),
                                  // Split the inherited info into separate lines to prevent overflow
                                  if (elderlyInfo['is_inherited'] == true) ...[
                                    Text(
                                      'Originally: ${elderlyInfo['original_nurse']}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${elderlyInfo['inherited_from_shift']} shift - Tap to complete',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ] else
                                    Text(
                                      'Tap to update vital signs for ${_getTodayDateString()}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              color: elderlyInfo['is_inherited'] == true
                                  ? Colors.blue
                                  : Colors.orange,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Last vital info if available
                    if (lastVital != null) ...[
                      SizedBox(height: 12),
                      Text(
                        'Last recorded vitals:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.3),
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.withOpacity(0.1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'BP: ${lastVital['blood_pressure'] ?? 'N/A'}',
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'Pulse: ${lastVital['pulse_rate'] ?? 'N/A'}',
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'O₂: ${lastVital['o2_sat'] ?? 'N/A'}%',
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'Temp: ${lastVital['temperature'] ?? 'N/A'}°C',
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Text(
                              'RR: ${lastVital['respiratory_rate'] ?? 'N/A'}',
                            ),
                            if (lastVital['vital_record_at'] != null)
                              Text(
                                'Recorded: ${DateFormat('MMM dd, yyyy HH:mm').format((lastVital['vital_record_at'] as Timestamp).toDate())}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
