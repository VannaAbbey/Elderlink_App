import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Automatic vitals_daily creator service
/// Triggers on app startup to ensure vitals_daily documents exist for today
class VitalsDailyAutoCreator {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static bool _isCreating = false;
  static String? _lastCreatedDate;

  /// Auto-create vitals_daily documents for today if they don't exist
  /// Uses elderly_assignments and house_shift_assignments to populate proper nurse assignments
  /// Called when app opens or when user logs in
  static Future<void> ensureVitalsDailyExist() async {
    // Prevent duplicate calls
    if (_isCreating) {
      print('⏳ VitalsDaily creation already in progress, skipping...');
      return;
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final currentDay = DateFormat('EEEE').format(DateTime.now());

    // Skip if already created today
    if (_lastCreatedDate == today) {
      print('✅ VitalsDaily already checked for today: $today');
      return;
    }

    _isCreating = true;
    print(
      '🚀 VitalsDailyAutoCreator: Starting auto-creation for $today ($currentDay)...',
    );

    try {
      // Get all elderly_assignments for today
      final assignmentsQuery = await _firestore
          .collection('elderly_assignments')
          .where('is_current', isEqualTo: true)
          .where('day', isEqualTo: currentDay)
          .get();

      if (assignmentsQuery.docs.isEmpty) {
        print('⚠️ No elderly assignments found for $currentDay');
        _isCreating = false;
        _lastCreatedDate = today;
        return;
      }

      print(
        '📋 Found ${assignmentsQuery.docs.length} elderly assignment documents',
      );

      // Build map: elderlyId -> shift -> { nurseId, nurseName, shiftTime }
      final elderlyShiftMap = <String, Map<String, Map<String, dynamic>>>{};
      final elderlyBasicInfo =
          <String, Map<String, String>>{}; // elderlyId -> { name, houseId }

      for (final doc in assignmentsQuery.docs) {
        final data = doc.data();
        final shift = data['shift'] as String?;
        final nurseId = data['user_id'] as String?;
        final elderlyIds = List<String>.from(data['elderly_ids'] ?? []);

        if (shift == null || nurseId == null || elderlyIds.isEmpty) continue;

        // Get nurse name from users collection
        String nurseName = 'Unknown Nurse';
        try {
          final userDoc = await _firestore
              .collection('users')
              .doc(nurseId)
              .get();
          if (userDoc.exists) {
            final userData = userDoc.data()!;
            nurseName =
                '${userData['first_name'] ?? ''} ${userData['last_name'] ?? ''}'
                    .trim();
          }
        } catch (e) {
          print('⚠️ Error fetching nurse name for $nurseId: $e');
        }

        // Get shift schedule from house_shift_assignments
        Map<String, String> shiftSchedule = {'start_time': '', 'end_time': ''};
        try {
          final shiftQuery = await _firestore
              .collection('house_shift_assignments')
              .where('user_id', isEqualTo: nurseId)
              .where('user_type', isEqualTo: 'nurse')
              .where('is_current', isEqualTo: true)
              .where('shift', isEqualTo: shift)
              .limit(1)
              .get();

          if (shiftQuery.docs.isNotEmpty) {
            final shiftData = shiftQuery.docs.first.data();
            shiftSchedule['start_time'] = shiftData['start_time'] ?? '';
            shiftSchedule['end_time'] = shiftData['end_time'] ?? '';
          }
        } catch (e) {
          print('⚠️ Error fetching shift schedule: $e');
        }

        // Map each elderly to this nurse/shift
        for (final elderlyId in elderlyIds) {
          if (!elderlyShiftMap.containsKey(elderlyId)) {
            elderlyShiftMap[elderlyId] = {};
          }

          // Validate nurseId: must not be empty and must be a real nurse from assignments
          if (nurseId.isEmpty) {
            print(
              '⚠️ Skipping assignment for elderly $elderlyId, shift $shift: nurseId is empty',
            );
            continue;
          }

          // Optionally, you can maintain a list of valid nurse IDs if needed
          // For now, just check user_type == nurse in the query above (already filtered)

          elderlyShiftMap[elderlyId]![shift] = {
            'nurse_id': nurseId,
            'nurse_name': nurseName,
            'start_time': shiftSchedule['start_time'],
            'end_time': shiftSchedule['end_time'],
          };
        }
      }

      print(
        '👥 Found ${elderlyShiftMap.length} unique elderly with assignments',
      );

      // Get elderly details for those with assignments
      final elderlyIds = elderlyShiftMap.keys.toList();
      for (var i = 0; i < elderlyIds.length; i += 30) {
        final chunk = elderlyIds.skip(i).take(30).toList();
        final elderlyDocs = await _firestore
            .collection('elderly')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in elderlyDocs.docs) {
          final data = doc.data();
          final elderlyName =
              '${data['elderly_fname'] ?? ''} ${data['elderly_lname'] ?? ''}'
                  .trim();
          final houseId = data['house_id'] ?? '';

          elderlyBasicInfo[doc.id] = {'name': elderlyName, 'house_id': houseId};
        }
      }

      // Create vitals_daily documents with proper nurse assignments
      final batch = _firestore.batch();
      int createdCount = 0;
      int existingCount = 0;

      for (final elderlyId in elderlyShiftMap.keys) {
        final info = elderlyBasicInfo[elderlyId];
        if (info == null || info['house_id']!.isEmpty) {
          print('⚠️ Skipping $elderlyId - no elderly info or house_id');
          continue;
        }

        final vitalsId = '${elderlyId}_$today';

        // Check if vitals_daily already exists
        final existingDoc = await _firestore
            .collection('vitals_daily')
            .doc(vitalsId)
            .get();

        if (existingDoc.exists) {
          existingCount++;
          continue;
        }

        // Build shift_status with assigned nurses
        final shifts = elderlyShiftMap[elderlyId]!;
        final shiftStatus = <String, dynamic>{};

        for (final shift in ['1st', '2nd', '3rd']) {
          if (shifts.containsKey(shift)) {
            final assignment = shifts[shift]!;
            shiftStatus[shift] = {
              'status': 'pending',
              'assigned_nurse_id': assignment['nurse_id'],
              'assigned_nurse_name': assignment['nurse_name'],
              'shift_start_time': assignment['start_time'],
              'shift_end_time': assignment['end_time'],
              'completed_by': null,
              'completed_by_nurse_name': null,
              'completed_at': null,
              'missed_reason': null,
              'marked_at': null,
            };
          } else {
            // No assignment for this shift - set as not assigned
            shiftStatus[shift] = {
              'status': 'not_assigned',
              'assigned_nurse_id': null,
              'assigned_nurse_name': null,
              'shift_start_time': null,
              'shift_end_time': null,
              'completed_by': null,
              'completed_by_nurse_name': null,
              'completed_at': null,
              'missed_reason': null,
              'marked_at': null,
            };
          }
        }

        // Create new vitals_daily document
        final vitalsDailyRef = _firestore
            .collection('vitals_daily')
            .doc(vitalsId);
        batch.set(vitalsDailyRef, {
          'vitals_id': vitalsId,
          'elderly_id': elderlyId,
          'elderly_name': info['name'],
          'assigned_date': today,
          'house_id': info['house_id'],
          'created_at': FieldValue.serverTimestamp(),
          'created_by': 'app_auto',
          'vital_values': {
            'blood_pressure': null,
            'temperature': null,
            'pulse_rate': null,
            'oxygen_saturation': null,
            'respiratory_rate': null,
            'notes': null,
            'last_updated_at': null,
            'last_updated_by': null,
          },
          'shift_status': shiftStatus,
          'any_completed': false,
          'any_missed': false,
          'updated_at': null,
        });

        createdCount++;
      }

      // Commit batch
      if (createdCount > 0) {
        await batch.commit();
        print('✅ Created $createdCount new vitals_daily documents for $today');
      }

      if (existingCount > 0) {
        print('ℹ️ $existingCount vitals_daily documents already existed');
      }

      print(
        '🎉 VitalsDailyAutoCreator completed: $createdCount created, $existingCount existing',
      );

      _lastCreatedDate = today;
    } catch (e) {
      print('❌ Error in VitalsDailyAutoCreator: $e');
    } finally {
      _isCreating = false;
    }
  }

  /// Force re-check (useful after schedule changes)
  static void forceRecheck() {
    print('🔄 Forcing vitals_daily recheck...');
    _lastCreatedDate = null;
  }

  /// Delete all vitals_daily for today and force recreation
  static Future<void> deleteAndRecreate() async {
    if (_isCreating) {
      print('⏳ VitalsDaily operation already in progress, skipping...');
      return;
    }

    _isCreating = true;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      print('🗑️ Deleting all vitals_daily documents for $today...');

      // Get all vitals_daily for today
      final vitalsSnapshot = await _firestore
          .collection('vitals_daily')
          .where('assigned_date', isEqualTo: today)
          .get();

      if (vitalsSnapshot.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in vitalsSnapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        print(
          '✅ Deleted ${vitalsSnapshot.docs.length} old vitals_daily documents',
        );
      } else {
        print('ℹ️ No vitals_daily documents to delete');
      }

      // Force recheck and create new ones
      _lastCreatedDate = null;
      _isCreating = false;

      // Create new vitals_daily based on current assignments
      await ensureVitalsDailyExist();
    } catch (e) {
      print('❌ Error deleting and recreating vitals_daily: $e');
      _isCreating = false;
    }
  }

  /// Reset state (for testing)
  static void reset() {
    _isCreating = false;
    _lastCreatedDate = null;
  }
}
