import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class DailyResetService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🆕 FEATURE 1: Auto-mark pending vitals as missed at shift end
  static Future<void> markPendingAsMissedAtShiftEnd() async {
    try {
      final now = DateTime.now();
      final currentHour = now.hour;
      final today = DateFormat('yyyy-MM-dd').format(now);

      // 🔧 NEW LOGIC: Check for ANY past shift's pending vitals, not just at transition times
      List<String> endedShifts = [];

      // Determine which shifts have already ended based on current time
      if (currentHour >= 14 && currentHour < 22) {
        // Currently in 2nd shift (2PM-10PM) - 1st shift has ended
        endedShifts.add('1st');
      } else if (currentHour >= 22 || currentHour < 6) {
        // Currently in 3rd shift (10PM-6AM) - 1st and 2nd shifts have ended
        endedShifts.add('1st');
        endedShifts.add('2nd');
      } else if (currentHour >= 6 && currentHour < 14) {
        // Currently in 1st shift (6AM-2PM) - 3rd shift from previous day/night has ended
        endedShifts.add('3rd');
      }

      if (endedShifts.isEmpty) {
        print('No ended shifts to check');
        return;
      }

      print(
        '🔄 Checking pending vitals from ended shifts: ${endedShifts.join(", ")} (Current time: ${DateFormat('HH:mm').format(now)})',
      );

      int totalMarkedAsMissed = 0;

      // Process each ended shift
      for (final endedShift in endedShifts) {
        // Get all pending vitals for the ended shift today
        final pendingVitals = await _firestore
            .collection('vitals')
            .where('assigned_date', isEqualTo: today)
            .where('shift', isEqualTo: endedShift)
            .where('status', isEqualTo: 'pending')
            .get();

        if (pendingVitals.docs.isEmpty) {
          print('✅ No pending vitals found for $endedShift shift');
          continue;
        }

        print(
          '⚠️ Found ${pendingVitals.docs.length} pending vitals in $endedShift shift that need to be marked as missed',
        );

        final batch = _firestore.batch();

        // Get elderly and nurse names for proper logging
        final elderlyIds = <String>{};
        final nurseIds = <String>{};

        for (final doc in pendingVitals.docs) {
          final data = doc.data();
          final elderlyId = data['elderly_id'] as String?;
          final nurseId = data['assigned_nurse_id'] as String?;
          if (elderlyId != null) elderlyIds.add(elderlyId);
          if (nurseId != null) nurseIds.add(nurseId);
        }

        // Fetch names
        final elderlyNames = <String, String>{};
        final nurseNames = <String, String>{};

        for (final elderlyId in elderlyIds) {
          try {
            final doc = await _firestore
                .collection('elderly')
                .doc(elderlyId)
                .get();
            if (doc.exists) {
              final data = doc.data()!;
              elderlyNames[elderlyId] =
                  '${data['elderly_fname'] ?? ''} ${data['elderly_lname'] ?? ''}'
                      .trim();
            }
          } catch (e) {
            elderlyNames[elderlyId] = 'Unknown Elderly';
          }
        }

        for (final nurseId in nurseIds) {
          try {
            final doc = await _firestore.collection('users').doc(nurseId).get();
            if (doc.exists) {
              final data = doc.data()!;
              nurseNames[nurseId] =
                  '${data['user_fname'] ?? ''} ${data['user_lname'] ?? ''}'
                      .trim();
            }
          } catch (e) {
            nurseNames[nurseId] = 'Unknown Nurse';
          }
        }

        // Mark vitals as missed and create activity logs
        for (final doc in pendingVitals.docs) {
          final data = doc.data();
          final elderlyId = data['elderly_id'] as String? ?? 'unknown';
          final nurseId = data['assigned_nurse_id'] as String? ?? 'unknown';
          final houseId = data['house_id'] as String? ?? 'unknown';

          // Update vital status to missed
          batch.update(doc.reference, {
            'status': 'missed',
            'updated_at': FieldValue.serverTimestamp(),
            'missed_reason':
                'Auto-marked as missed - $endedShift shift ended without completion',
            'missed_at': FieldValue.serverTimestamp(),
          });

          // Create activity log for missed vital
          batch.set(_firestore.collection('vital_activity_logs').doc(), {
            'vital_id': doc.id,
            'elderly_id': elderlyId,
            'elderly_name': elderlyNames[elderlyId] ?? 'Unknown Elderly',
            'nurse_id': nurseId,
            'nurse_name': nurseNames[nurseId] ?? 'Unknown Nurse',
            'house_id': houseId,
            'action_type': 'vital_missed',
            'old_value': {'status': 'pending'},
            'new_value': {
              'status': 'missed',
              'missed_reason':
                  'Auto-marked as missed - $endedShift shift ended without completion',
            },
            'remarks':
                'Automatically marked as missed at end of $endedShift shift (${DateFormat('HH:mm').format(now)})',
            'shift': endedShift,
            'assigned_date': today,
            'timestamp': FieldValue.serverTimestamp(),
          });

          print(
            '✅ Marked vital as missed: ${elderlyNames[elderlyId]} - $endedShift shift',
          );
          totalMarkedAsMissed++;
        }

        await batch.commit();
        print(
          '🎯 Marked ${pendingVitals.docs.length} pending vitals as missed for $endedShift shift',
        );
      }

      if (totalMarkedAsMissed > 0) {
        print(
          '🎯 TOTAL: Marked $totalMarkedAsMissed pending vitals as missed across all ended shifts',
        );
      } else {
        print(
          '✅ All vitals are up to date - no pending vitals from ended shifts',
        );
      }
    } catch (e) {
      print('❌ Error marking pending vitals as missed: $e');
    }
  }

  // 🆕 FEATURE 4: Daily reset - Remove old vitals and create new based on current schedule
  static Future<void> resetDailyVitalAssignments() async {
    try {
      final now = DateTime.now();
      final currentHour = now.hour;

      // Only run reset between 3:00 AM and 6:00 AM (after 3rd shift ends, before 1st shift starts)
      if (currentHour < 3 || currentHour >= 6) {
        print('Daily reset can only run between 3:00 AM and 6:00 AM');
        return;
      }

      final yesterday = now.subtract(Duration(days: 1));
      final yesterdayString = DateFormat('yyyy-MM-dd').format(yesterday);
      final todayString = DateFormat('yyyy-MM-dd').format(now);

      print('🔄 Starting daily reset: $yesterdayString → $todayString');
      print(
        '🗑️ Cleaning old vitals data and creating fresh assignments based on current schedule',
      );

      // 🗑️ STEP 1: Remove ALL old vitals data (yesterday and older)
      // Data is preserved in vital_activity_logs for history
      final oldVitals = await _firestore
          .collection('vitals')
          .where('assigned_date', isLessThan: todayString)
          .get();

      print('Found ${oldVitals.docs.length} old vitals to remove');

      final batch = _firestore.batch();
      int removedCount = 0;
      int newPendingCount = 0;

      // Remove old vitals data
      for (final doc in oldVitals.docs) {
        batch.delete(doc.reference);
        removedCount++;
      }

      print('🗑️ Removing $removedCount old vitals from database...');

      // 🆕 STEP 2: Create new vitals based on CURRENT schedule assignments
      print('📋 Creating new vitals based on current nurse assignments...');

      // Get all current nurse assignments (current schedule)
      final assignmentsQuery = await _firestore.collection('assignments').get();

      // Process each assignment to create fresh vitals
      for (final assignDoc in assignmentsQuery.docs) {
        final assignData = assignDoc.data();
        final nurseId = assignData['nurse_id'] as String?;
        final houseId = assignData['house_id'] as String?;
        final shift = assignData['shift'] as String?;
        final elderlyIds = List<String>.from(assignData['elderly_ids'] ?? []);

        // Skip if essential assignment data is missing
        if (nurseId == null ||
            houseId == null ||
            shift == null ||
            elderlyIds.isEmpty) {
          continue;
        }

        // Create pending vital for each assigned elderly
        for (final elderlyId in elderlyIds) {
          // Verify elderly is still alive
          final elderlyDoc = await _firestore
              .collection('elderly')
              .doc(elderlyId)
              .get();

          if (!elderlyDoc.exists ||
              elderlyDoc.data()?['elderly_status'] != 'Alive') {
            continue; // Skip deceased or non-existent elderly
          }

          // Create fresh pending vital for today
          final newVitalRef = _firestore.collection('vitals').doc();

          batch.set(newVitalRef, {
            // Assignment fields based on CURRENT schedule
            'elderly_id': elderlyId,
            'assigned_nurse_id': nurseId,
            'house_id': houseId,
            'shift': shift,
            'assigned_date': todayString,
            'status': 'pending',
            'created_at': FieldValue.serverTimestamp(),

            // Fresh vital fields
            'blood_pressure': null,
            'pulse_rate': null,
            'oxygen_saturation': null,
            'temperature': null,
            'respiratory_rate': null,
            'vital_remarks': null,

            // Fresh completion fields
            'completed_at': null,
            'updated_by_nurse_id': null,
            'updated_by_nurse_name': null,
          });

          newPendingCount++;
        }
      }

      await batch.commit();

      print('🎯 Daily reset completed successfully:');
      print(
        '   - Removed: $removedCount old vitals (data preserved in activity logs)',
      );
      print(
        '   - Created: $newPendingCount new pending vitals for $todayString',
      );
      print('   - All vitals based on current schedule assignments');
    } catch (e) {
      print('❌ Error during daily reset: $e');
    }
  }

  // 🆕 ENHANCED: Check and run both shift transitions and daily reset
  static Future<void> checkAndRunDailyReset() async {
    try {
      final now = DateTime.now();
      final currentHour = now.hour;

      // Check for shift transitions first (every shift end)
      await markPendingAsMissedAtShiftEnd();

      // Run daily reset if it's between 3:00 AM and 6:00 AM
      if (currentHour >= 3 && currentHour < 6) {
        await resetDailyVitalAssignments();
      }
    } catch (e) {
      print('Error checking daily reset: $e');
    }
  }

  // ⚡ FAST: Initialize comprehensive vital monitoring system
  static Future<void> initializeVitalMonitoringSystem() async {
    try {
      print('⚡ Initializing FAST vital monitoring system...');

      // Run immediate checks
      await checkAndRunDailyReset();

      // ⚡ Add vitals for current assignments (FAST startup)
      await addVitalsForNewAssignments();

      // No activity log entry - keep logs clean for nursing activities only
      print('✅ FAST vital monitoring system initialized');
    } catch (e) {
      print('❌ Error initializing vital monitoring system: $e');
    }
  }

  // ⚡ ULTRA FAST: Add new vitals IMMEDIATELY (no duplicate check)
  static Future<void> addVitalsForNewAssignments() async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      print(
        '⚡ ULTRA FAST: Adding ALL new assignments instantly (no duplicate check)',
      );

      // Get ALL current assignments
      final assignments = await _firestore.collection('assignments').get();

      if (assignments.docs.isEmpty) {
        print('✅ No assignments found');
        return;
      }

      final batch = _firestore.batch();
      int addedCount = 0;

      // STEP 1: ADD ALL VITALS IMMEDIATELY (no existence check for speed)
      for (final assignDoc in assignments.docs) {
        final data = assignDoc.data();
        final nurseId = data['nurse_id'] as String?;
        final houseId = data['house_id'] as String?;
        final shift = data['shift'] as String?;
        final elderlyIds = List<String>.from(data['elderly_ids'] ?? []);

        if (nurseId == null || houseId == null || shift == null) continue;

        for (final elderlyId in elderlyIds) {
          // CREATE VITAL IMMEDIATELY (no duplicate check for maximum speed)
          final newVitalRef = _firestore.collection('vitals').doc();

          batch.set(newVitalRef, {
            'elderly_id': elderlyId,
            'assigned_nurse_id': nurseId,
            'house_id': houseId,
            'shift': shift,
            'assigned_date': today,
            'status': 'pending',
            'created_at': FieldValue.serverTimestamp(),
            'blood_pressure': null,
            'pulse_rate': null,
            'oxygen_saturation': null,
            'temperature': null,
            'respiratory_rate': null,
            'vital_remarks': null,
            'completed_at': null,
            'updated_by_nurse_id': null,
            'updated_by_nurse_name': null,
          });

          addedCount++;
          print(
            '⚡ INSTANTLY added: $elderlyId (shift: $shift, nurse: $nurseId)',
          );
        }
      }

      // Commit all new vitals IMMEDIATELY
      if (addedCount > 0) {
        await batch.commit();
        print('🚀 ULTRA FAST: Added $addedCount vitals INSTANTLY');

        // STEP 2: Clean duplicates in BACKGROUND (doesn't block UI)
        Timer(Duration(seconds: 2), () {
          cleanupDuplicateVitals();
        });
      } else {
        print('✅ No new vitals to add');
      }
    } catch (e) {
      print('❌ Error adding vitals instantly: $e');
    }
  }

  // 🧹 BACKGROUND: Clean up duplicate vitals (runs after adding new ones)
  static Future<void> cleanupDuplicateVitals() async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      print('🧹 BACKGROUND: Cleaning duplicate vitals...');

      // Get ALL vitals for today
      final allVitals = await _firestore
          .collection('vitals')
          .where('assigned_date', isEqualTo: today)
          .get();

      print('🔍 Found ${allVitals.docs.length} total vitals for today');

      // Group vitals by elderly_id + shift + assigned_date
      final vitalGroups = <String, List<QueryDocumentSnapshot>>{};

      for (final doc in allVitals.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        final elderlyId = data['elderly_id'] as String?;
        final shift = data['shift'] as String?;

        if (elderlyId == null || shift == null) continue;

        final groupKey = '${elderlyId}_${shift}_$today';

        if (!vitalGroups.containsKey(groupKey)) {
          vitalGroups[groupKey] = [];
        }
        vitalGroups[groupKey]!.add(doc);
      }

      // Find and remove duplicates
      final batch = _firestore.batch();
      int removedCount = 0;

      for (final entry in vitalGroups.entries) {
        final vitals = entry.value;

        if (vitals.length > 1) {
          // Sort by creation time (keep the latest)
          vitals.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>?;
            final bData = b.data() as Map<String, dynamic>?;
            final aTime =
                (aData?['created_at'] as Timestamp?)?.toDate() ??
                DateTime(1970);
            final bTime =
                (bData?['created_at'] as Timestamp?)?.toDate() ??
                DateTime(1970);
            return bTime.compareTo(aTime); // Latest first
          });

          // Keep the first (latest), remove the rest
          for (int i = 1; i < vitals.length; i++) {
            final duplicateData = vitals[i].data() as Map<String, dynamic>?;
            if (duplicateData != null) {
              print(
                '🗑️ Removing duplicate: ${duplicateData['elderly_id']} (${duplicateData['shift']})',
              );
              batch.delete(vitals[i].reference);
              removedCount++;
            }
          }
        }
      }

      if (removedCount > 0) {
        await batch.commit();
        print('🧹 CLEANUP: Removed $removedCount duplicate vitals');
      } else {
        print('✅ No duplicates found - data is clean');
      }
    } catch (e) {
      print('❌ Error cleaning duplicate vitals: $e');
    }
  }

  // 🚨 MANUAL: Force regenerate all vitals (call this if vitals are missing)
  static Future<void> forceRegenerateAllVitals() async {
    try {
      print('🚨 FORCE REGENERATING all vitals from current assignments...');

      // Clear any existing cleanup timers
      // Then immediately add vitals for all current assignments
      await addVitalsForNewAssignments();

      print('✅ Force regeneration completed');
    } catch (e) {
      print('❌ Error force regenerating vitals: $e');
    }
  }

  // 🆕 REAL-TIME: Sync vitals when schedule assignments change
  static Future<void> syncVitalsWithCurrentSchedule({
    String? specificHouseId,
    String? specificNurseId,
  }) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      print('🔄 REAL-TIME: Syncing vitals with current schedule assignments');
      print('   📅 Date: $today');
      if (specificHouseId != null) print('   🏠 House: $specificHouseId');
      if (specificNurseId != null) print('   👩‍⚕️ Nurse: $specificNurseId');

      // STEP 1: Get current assignments from assignments collection
      Query assignmentsQuery = _firestore.collection('assignments');

      if (specificHouseId != null) {
        assignmentsQuery = assignmentsQuery.where(
          'house_id',
          isEqualTo: specificHouseId,
        );
      }
      if (specificNurseId != null) {
        assignmentsQuery = assignmentsQuery.where(
          'nurse_id',
          isEqualTo: specificNurseId,
        );
      }

      final currentAssignments = await assignmentsQuery.get();

      // STEP 2: Get existing vitals for today
      Query vitalsQuery = _firestore
          .collection('vitals')
          .where('assigned_date', isEqualTo: today);

      if (specificHouseId != null) {
        vitalsQuery = vitalsQuery.where('house_id', isEqualTo: specificHouseId);
      }
      if (specificNurseId != null) {
        vitalsQuery = vitalsQuery.where(
          'assigned_nurse_id',
          isEqualTo: specificNurseId,
        );
      }

      final existingVitals = await vitalsQuery.get();

      // STEP 3: Build current assignment map
      final currentAssignmentMap = <String, Map<String, dynamic>>{};

      for (final assignDoc in currentAssignments.docs) {
        final data = assignDoc.data() as Map<String, dynamic>;
        final nurseId = data['nurse_id'] as String?;
        final houseId = data['house_id'] as String?;
        final shift = data['shift'] as String?;
        final elderlyIds = List<String>.from(data['elderly_ids'] ?? []);

        if (nurseId == null || houseId == null || shift == null) continue;

        for (final elderlyId in elderlyIds) {
          // Verify elderly is alive
          final elderlyDoc = await _firestore
              .collection('elderly')
              .doc(elderlyId)
              .get();
          if (!elderlyDoc.exists ||
              elderlyDoc.data()?['elderly_status'] != 'Alive') {
            continue;
          }

          final key = '${elderlyId}_${shift}_$today';
          currentAssignmentMap[key] = {
            'elderly_id': elderlyId,
            'nurse_id': nurseId,
            'house_id': houseId,
            'shift': shift,
          };
        }
      }

      // STEP 4: Check existing vitals against current assignments
      final vitalsToRemove = <String>[];
      final existingVitalKeys = <String>{};

      for (final vitalDoc in existingVitals.docs) {
        final data = vitalDoc.data() as Map<String, dynamic>;
        final elderlyId = data['elderly_id'] as String?;
        final shift = data['shift'] as String?;
        final assignedNurse = data['assigned_nurse_id'] as String?;
        final vitalHouse = data['house_id'] as String?;

        if (elderlyId == null || shift == null) {
          vitalsToRemove.add(vitalDoc.id);
          continue;
        }

        final vitalKey = '${elderlyId}_${shift}_$today';
        existingVitalKeys.add(vitalKey);

        // Check if this vital matches current assignment
        final currentAssignment = currentAssignmentMap[vitalKey];

        if (currentAssignment == null) {
          // No current assignment for this vital - remove it
          vitalsToRemove.add(vitalDoc.id);
          print(
            '❌ Removing outdated vital: $elderlyId (shift: $shift) - no longer assigned',
          );
        } else {
          // Check if nurse or house assignment changed
          final currentNurse = currentAssignment['nurse_id'];
          final currentHouse = currentAssignment['house_id'];

          if (assignedNurse != currentNurse || vitalHouse != currentHouse) {
            // Assignment changed - remove old vital, will create new one
            vitalsToRemove.add(vitalDoc.id);
            print(
              '🔄 Removing reassigned vital: $elderlyId (nurse: $assignedNurse→$currentNurse, house: $vitalHouse→$currentHouse)',
            );
          }
        }
      }

      // STEP 5: Create vitals for new assignments
      final vitalsToCreate = <Map<String, dynamic>>[];

      for (final entry in currentAssignmentMap.entries) {
        final assignment = entry.value;

        // Check if vital already exists and is correct
        bool needsCreation = true;

        for (final vitalDoc in existingVitals.docs) {
          final data = vitalDoc.data() as Map<String, dynamic>;
          final elderlyId = data['elderly_id'] as String?;
          final shift = data['shift'] as String?;
          final assignedNurse = data['assigned_nurse_id'] as String?;
          final vitalHouse = data['house_id'] as String?;

          if (elderlyId == assignment['elderly_id'] &&
              shift == assignment['shift'] &&
              assignedNurse == assignment['nurse_id'] &&
              vitalHouse == assignment['house_id'] &&
              !vitalsToRemove.contains(vitalDoc.id)) {
            needsCreation = false;
            break;
          }
        }

        if (needsCreation) {
          vitalsToCreate.add({
            'elderly_id': assignment['elderly_id'],
            'assigned_nurse_id': assignment['nurse_id'],
            'house_id': assignment['house_id'],
            'shift': assignment['shift'],
            'assigned_date': today,
            'status': 'pending',
            'created_at': FieldValue.serverTimestamp(),
            'blood_pressure': null,
            'pulse_rate': null,
            'oxygen_saturation': null,
            'temperature': null,
            'respiratory_rate': null,
            'vital_remarks': null,
            'completed_at': null,
            'updated_by_nurse_id': null,
            'updated_by_nurse_name': null,
          });

          print(
            '✅ Creating new vital: ${assignment['elderly_id']} (shift: ${assignment['shift']}, nurse: ${assignment['nurse_id']})',
          );
        }
      }

      // STEP 6: Execute changes in batch
      if (vitalsToRemove.isNotEmpty || vitalsToCreate.isNotEmpty) {
        final batch = _firestore.batch();

        // Remove outdated vitals
        for (final vitalId in vitalsToRemove) {
          batch.delete(_firestore.collection('vitals').doc(vitalId));
        }

        // Create new vitals
        for (final vitalData in vitalsToCreate) {
          final newVitalRef = _firestore.collection('vitals').doc();
          batch.set(newVitalRef, vitalData);
        }

        await batch.commit();

        print('🎯 REAL-TIME SYNC COMPLETED:');
        print('   ❌ Removed: ${vitalsToRemove.length} outdated vitals');
        print('   ✅ Created: ${vitalsToCreate.length} new vitals');
        print(
          '   📊 Total current assignments: ${currentAssignmentMap.length}',
        );
      } else {
        print(
          '✅ Vitals already in sync with current schedule - no changes needed',
        );
      }
    } catch (e) {
      print('❌ Error syncing vitals with current schedule: $e');
    }
  }

  // ⚡ FAST: Listen for assignment changes and add new vitals only
  static StreamSubscription<QuerySnapshot>? _assignmentListener;
  static StreamSubscription<QuerySnapshot>? _vitalsListener;

  static void startRealTimeScheduleMonitoring() {
    try {
      print('⚡ Starting FAST real-time schedule monitoring...');

      // Listen to assignments collection for any changes
      _assignmentListener = _firestore.collection('assignments').snapshots().listen((
        snapshot,
      ) async {
        // Process ANY assignment changes (added, modified, removed)
        if (snapshot.docChanges.isNotEmpty) {
          print(
            '⚡ ASSIGNMENT CHANGES DETECTED: ${snapshot.docChanges.length} changes',
          );

          // STEP 1: Add vitals instantly (may create duplicates temporarily)
          await addVitalsForNewAssignments();

          print(
            '✅ New vitals added ULTRA FAST - duplicates will be cleaned in background',
          );
        }
      });

      print('✅ FAST real-time monitoring started (add-only)');
    } catch (e) {
      print('❌ Error starting real-time monitoring: $e');
    }
  }

  static void stopRealTimeScheduleMonitoring() {
    _assignmentListener?.cancel();
    _assignmentListener = null;
    _vitalsListener?.cancel();
    _vitalsListener = null;
    print('🛑 Real-time schedule monitoring stopped');
  }

  // 🆕 FEATURE 4: Start comprehensive monitoring with background checks
  static Future<void> startComprehensiveMonitoring() async {
    try {
      print('🔄 Starting comprehensive vital monitoring...');

      // Initialize the system first
      await initializeVitalMonitoringSystem();

      // 🆕 Start real-time schedule monitoring
      startRealTimeScheduleMonitoring();

      // 🔧 IMMEDIATE: Run the check right now to catch any missed shifts
      print('🔍 Running immediate shift check...');
      await checkAndRunDailyReset();

      // Set up periodic checks (every 3 minutes for faster response)
      // Note: In production, this would be better handled by Firebase Cloud Functions
      Timer.periodic(const Duration(minutes: 3), (timer) async {
        await checkAndRunDailyReset();
      });

      print('✅ Comprehensive monitoring started with real-time schedule sync');
    } catch (e) {
      print('❌ Error starting comprehensive monitoring: $e');
    }
  }

  // 🆕 MANUAL TRIGGER: Force check for missed vitals NOW (for testing/debugging)
  static Future<void> forceCheckMissedVitals() async {
    try {
      print('🚨 MANUAL TRIGGER: Force checking for missed vitals...');
      await markPendingAsMissedAtShiftEnd();
      print('✅ Manual check completed');
    } catch (e) {
      print('❌ Error in manual check: $e');
    }
  }

  // 🆕 FEATURE 2 & 3: Get comprehensive activity logs for all shifts and nurses
  static Future<List<Map<String, dynamic>>> getComprehensiveActivityLogs({
    String? houseId,
    String? elderlyId,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? actionTypes, // ['vital_completed', 'vital_missed', etc.]
    int limit = 200,
  }) async {
    try {
      final now = DateTime.now();
      final defaultStartDate = startDate ?? now.subtract(Duration(days: 7));
      final defaultEndDate = endDate ?? now;

      Query query = _firestore.collection('vital_activity_logs');

      // Apply filters
      if (houseId != null) {
        query = query.where('house_id', isEqualTo: houseId);
      }

      if (elderlyId != null) {
        query = query.where('elderly_id', isEqualTo: elderlyId);
      }

      if (actionTypes != null && actionTypes.isNotEmpty) {
        query = query.where('action_type', whereIn: actionTypes);
      }

      // Get logs within date range
      query = query
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(defaultStartDate),
          )
          .where(
            'timestamp',
            isLessThanOrEqualTo: Timestamp.fromDate(defaultEndDate),
          )
          .orderBy('timestamp', descending: true)
          .limit(limit);

      final querySnapshot = await query.get();
      final activities = <Map<String, dynamic>>[];

      for (final doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        activities.add({
          'id': doc.id,
          'timestamp': data['timestamp'],
          'action_type': data['action_type'],
          'elderly_id': data['elderly_id'],
          'elderly_name': data['elderly_name'],
          'nurse_id': data['nurse_id'],
          'nurse_name': data['nurse_name'],
          'house_id': data['house_id'],
          'shift': data['shift'],
          'assigned_date': data['assigned_date'],
          'old_value': data['old_value'] ?? {},
          'new_value': data['new_value'] ?? data['new_values'] ?? {},
          'remarks': data['remarks'] ?? '',
          'vital_id': data['vital_id'],
        });
      }

      print('📊 Retrieved ${activities.length} comprehensive activity logs');
      return activities;
    } catch (e) {
      print('❌ Error getting comprehensive activity logs: $e');
      return [];
    }
  }

  // 🆕 FEATURE 3: Get missed tasks from previous shifts for current nurses
  static Future<List<Map<String, dynamic>>> getMissedTasksFromPreviousShifts({
    required String nurseId,
    String? houseId,
    int daysBack = 3,
  }) async {
    try {
      final now = DateTime.now();
      final startDate = now.subtract(Duration(days: daysBack));

      Query query = _firestore
          .collection('vital_activity_logs')
          .where('action_type', isEqualTo: 'vital_missed')
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .orderBy('timestamp', descending: true)
          .limit(100);

      if (houseId != null) {
        query = query.where('house_id', isEqualTo: houseId);
      }

      final querySnapshot = await query.get();
      final missedTasks = <Map<String, dynamic>>[];

      for (final doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        // Check if the missed task involves elderly currently assigned to this nurse
        final elderlyId = data['elderly_id'] as String?;
        if (elderlyId != null) {
          // Check current assignments for this nurse
          final currentAssignments = await _firestore
              .collection('elderly_assignments')
              .where('user_id', isEqualTo: nurseId)
              .where('user_type', isEqualTo: 'nurse')
              .where('is_current', isEqualTo: true)
              .where('elderly_ids', arrayContains: elderlyId)
              .get();

          // If nurse is currently assigned to this elderly, include the missed task
          if (currentAssignments.docs.isNotEmpty) {
            final newValue = data['new_value'] as Map<String, dynamic>?;
            missedTasks.add({
              'id': doc.id,
              'timestamp': data['timestamp'],
              'elderly_id': elderlyId,
              'elderly_name': data['elderly_name'],
              'original_nurse_id': data['nurse_id'],
              'original_nurse_name': data['nurse_name'],
              'house_id': data['house_id'],
              'shift': data['shift'],
              'assigned_date': data['assigned_date'],
              'missed_reason': newValue?['missed_reason'] ?? 'Unknown',
              'remarks': data['remarks'] ?? '',
              'vital_id': data['vital_id'],
            });
          }
        }
      }

      print(
        '📊 Found ${missedTasks.length} missed tasks from previous shifts for nurse',
      );
      return missedTasks;
    } catch (e) {
      print('❌ Error getting missed tasks from previous shifts: $e');
      return [];
    }
  }

  // Get vital statistics for a specific elderly (for future health graph)
  static Future<List<Map<String, dynamic>>> getElderlyVitalHistory({
    required String elderlyId,
    int days = 30,
  }) async {
    try {
      final endDate = DateTime.now();
      final startDate = endDate.subtract(Duration(days: days));

      final vitalHistory = await _firestore
          .collection('vitals')
          .where('elderly_id', isEqualTo: elderlyId)
          .where(
            'vital_record_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .where(
            'vital_record_at',
            isLessThanOrEqualTo: Timestamp.fromDate(endDate),
          )
          .orderBy('vital_record_at', descending: true)
          .get();

      return vitalHistory.docs.map((doc) {
        final data = doc.data();
        return {
          'date': (data['vital_record_at'] as Timestamp).toDate(),
          'blood_pressure': data['blood_pressure'],
          'pulse_rate': data['pulse_rate'],
          'o2_sat': data['o2_sat'],
          'temperature': data['temperature'],
          'respiratory_rate': data['respiratory_rate'],
          'recorded_by': data['updated_by_nurse_name'],
        };
      }).toList();
    } catch (e) {
      print('Error getting vital history: $e');
      return [];
    }
  }

  // 🆕 ENHANCED: Get comprehensive completion statistics with shift breakdown
  static Future<Map<String, dynamic>> getDailyCompletionStats({
    required String houseId,
    String? nurseId,
    String? date,
    String? shift,
  }) async {
    try {
      final queryDate = date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

      var query = _firestore
          .collection('vitals')
          .where('house_id', isEqualTo: houseId)
          .where('assigned_date', isEqualTo: queryDate);

      if (nurseId != null) {
        query = query.where('assigned_nurse_id', isEqualTo: nurseId);
      }

      if (shift != null) {
        query = query.where('shift', isEqualTo: shift);
      }

      final assignments = await query.get();

      int pending = 0;
      int completed = 0;
      int missed = 0;

      final shiftBreakdown = <String, Map<String, int>>{
        '1st': {'pending': 0, 'completed': 0, 'missed': 0},
        '2nd': {'pending': 0, 'completed': 0, 'missed': 0},
        '3rd': {'pending': 0, 'completed': 0, 'missed': 0},
      };

      for (final doc in assignments.docs) {
        final data = doc.data();
        final status = data['status'] as String;
        final vitalShift = data['shift'] as String? ?? 'unknown';

        // Overall counts
        switch (status) {
          case 'pending':
            pending++;
            break;
          case 'completed':
            completed++;
            break;
          case 'missed':
            missed++;
            break;
        }

        // Shift-specific counts
        if (shiftBreakdown.containsKey(vitalShift)) {
          shiftBreakdown[vitalShift]![status] =
              (shiftBreakdown[vitalShift]![status] ?? 0) + 1;
        }
      }

      return {
        'pending': pending,
        'completed': completed,
        'missed': missed,
        'total': assignments.docs.length,
        'shift_breakdown': shiftBreakdown,
        'query_date': queryDate,
        'query_house': houseId,
        'query_nurse': nurseId,
        'query_shift': shift,
      };
    } catch (e) {
      print('Error getting completion stats: $e');
      return {
        'pending': 0,
        'completed': 0,
        'missed': 0,
        'total': 0,
        'shift_breakdown': {},
        'error': e.toString(),
      };
    }
  }
}
