import 'package:cloud_firestore/cloud_firestore.dart';

/// 🔄 Database Migration Helper for Unified Activity Logs
/// This class helps migrate from separate collections to unified activity_logs collection
class ActivityLogsMigration {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 📝 Unified Activity Log Structure
  /// {
  ///   'category': 'medication' | 'vital' | 'incident' | 'shift',
  ///   'action': string,
  ///   'nurse_name': string,
  ///   'nurse_id': string,
  ///   'elderly_id': string,
  ///   'elderly_name': string,
  ///   'house_id': string,
  ///   'timestamp': Timestamp,
  ///   'details': Map<String, dynamic>, // Category-specific data
  ///   'migrated_from': string, // Original collection name
  /// }

  /// 🎯 Method 1: Create unified activity log for NEW activities
  static Future<void> createUnifiedActivityLog({
    required String category, // 'medication', 'vital', 'incident', 'shift'
    required String action,
    required String nurseName,
    required String nurseId,
    required String elderlyId,
    required String elderlyName,
    required String houseId,
    Map<String, dynamic>? details,
  }) async {
    try {
      await _firestore.collection('activity_logs').add({
        'category': category,
        'action': action,
        'nurse_name': nurseName,
        'nurse_id': nurseId,
        'elderly_id': elderlyId,
        'elderly_name': elderlyName,
        'house_id': houseId,
        'timestamp': Timestamp.now(),
        'details': details ?? {},
        'created_at': Timestamp.now(),
      });
      print('✅ Created unified activity log: $category - $action');
    } catch (e) {
      print('❌ Error creating unified activity log: $e');
      rethrow;
    }
  }

  /// 🔄 Method 2: Migrate existing medication activities
  static Future<void> migrateMedicationActivities({int batchSize = 100}) async {
    try {
      print('🔄 Starting medication activities migration...');

      int totalMigrated = 0;
      DocumentSnapshot? lastDoc;

      while (true) {
        Query query = _firestore
            .collection('medication_activity_logs')
            .orderBy(FieldPath.documentId)
            .limit(batchSize);

        if (lastDoc != null) {
          query = query.startAfterDocument(lastDoc);
        }

        final querySnapshot = await query.get();

        if (querySnapshot.docs.isEmpty) {
          break; // No more documents to migrate
        }

        final batch = _firestore.batch();

        for (final doc in querySnapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;

          // Create unified activity log entry
          final unifiedDocRef = _firestore.collection('activity_logs').doc();
          batch.set(unifiedDocRef, {
            'category': 'medication', // 🏷️ Category label
            'action': data['action'] ?? 'unknown',
            'nurse_name': data['nurse_name'] ?? 'Unknown Nurse',
            'nurse_id': data['nurse_id'] ?? '',
            'elderly_id': data['elderly_id'] ?? '',
            'elderly_name': data['elderly_name'] ?? 'Unknown Elderly',
            'house_id': data['house_id'] ?? '',
            'timestamp': data['timestamp'] ?? Timestamp.now(),
            'details': {
              // Medication-specific details
              'medication_name': data['medication_name'],
              'medication_id': data['medication_id'],
              'take_ordinal': data['take_ordinal'],
              'take_number': data['take_number'],
              'dosage': data['dosage'],
              'frequency': data['frequency'],
              'original_doc_id': doc.id, // Reference to original document
            },
            'migrated_from': 'medication_activity_logs',
            'migrated_at': Timestamp.now(),
          });
        }

        await batch.commit();
        totalMigrated += querySnapshot.docs.length;
        lastDoc = querySnapshot.docs.last;

        print('🔄 Migrated $totalMigrated medication activities...');
      }

      print(
        '✅ Medication activities migration completed! Total: $totalMigrated',
      );
    } catch (e) {
      print('❌ Error migrating medication activities: $e');
      rethrow;
    }
  }

  /// 🔄 Method 3: Migrate existing vital activities
  static Future<void> migrateVitalActivities({int batchSize = 100}) async {
    try {
      print('🔄 Starting vital activities migration...');

      int totalMigrated = 0;
      DocumentSnapshot? lastDoc;

      while (true) {
        Query query = _firestore
            .collection('vital_activity_logs')
            .orderBy(FieldPath.documentId)
            .limit(batchSize);

        if (lastDoc != null) {
          query = query.startAfterDocument(lastDoc);
        }

        final querySnapshot = await query.get();

        if (querySnapshot.docs.isEmpty) {
          break; // No more documents to migrate
        }

        final batch = _firestore.batch();

        for (final doc in querySnapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;

          // Create unified activity log entry
          final unifiedDocRef = _firestore.collection('activity_logs').doc();
          batch.set(unifiedDocRef, {
            'category': 'vital', // 🏷️ Category label
            'action': data['action_type'] ?? 'vital_action',
            'nurse_name': data['nurse_name'] ?? 'Unknown Nurse',
            'nurse_id': data['nurse_id'] ?? '',
            'elderly_id': data['elderly_id'] ?? '',
            'elderly_name': data['elderly_name'] ?? 'Unknown Elderly',
            'house_id': data['house_id'] ?? '',
            'timestamp': data['timestamp'] ?? Timestamp.now(),
            'details': {
              // Vital-specific details
              'vital_id': data['vital_id'],
              'vital_type': data['vital_type'],
              'blood_pressure_systolic': data['blood_pressure_systolic'],
              'blood_pressure_diastolic': data['blood_pressure_diastolic'],
              'heart_rate': data['heart_rate'],
              'temperature': data['temperature'],
              'respiratory_rate': data['respiratory_rate'],
              'oxygen_saturation': data['oxygen_saturation'],
              'original_doc_id': doc.id, // Reference to original document
            },
            'migrated_from': 'vital_activity_logs',
            'migrated_at': Timestamp.now(),
          });
        }

        await batch.commit();
        totalMigrated += querySnapshot.docs.length;
        lastDoc = querySnapshot.docs.last;

        print('🔄 Migrated $totalMigrated vital activities...');
      }

      print('✅ Vital activities migration completed! Total: $totalMigrated');
    } catch (e) {
      print('❌ Error migrating vital activities: $e');
      rethrow;
    }
  }

  /// 🎯 Method 4: Create indexes for better performance
  static Future<void> createIndexes() async {
    print('📋 Creating indexes for unified activity_logs collection...');
    print('');
    print('🔧 Run these commands in Firebase Console > Firestore > Indexes:');
    print('');
    print('1. Composite Index for category + timestamp:');
    print('   Collection: activity_logs');
    print('   Fields: category (Ascending), timestamp (Descending)');
    print('');
    print('2. Composite Index for category + house_id + timestamp:');
    print('   Collection: activity_logs');
    print(
      '   Fields: category (Ascending), house_id (Ascending), timestamp (Descending)',
    );
    print('');
    print('3. Composite Index for category + elderly_id + timestamp:');
    print('   Collection: activity_logs');
    print(
      '   Fields: category (Ascending), elderly_id (Ascending), timestamp (Descending)',
    );
    print('');
    print('4. Composite Index for house_id + timestamp:');
    print('   Collection: activity_logs');
    print('   Fields: house_id (Ascending), timestamp (Descending)');
    print('');
    print('📋 These indexes will significantly improve query performance!');
  }

  /// 🧹 Method 5: Clean up old collections (DANGER ZONE!)
  static Future<void> cleanupOldCollections({
    bool confirmDelete = false,
    int batchSize = 100,
  }) async {
    if (!confirmDelete) {
      print('⚠️  WARNING: This will DELETE all old activity log collections!');
      print('   Make sure migration is successful and data is verified first.');
      print('   Set confirmDelete: true to proceed.');
      return;
    }

    print('🧹 Starting cleanup of old collections...');

    // Delete medication_activity_logs
    await _deleteCollection('medication_activity_logs', batchSize);

    // Delete vital_activity_logs
    await _deleteCollection('vital_activity_logs', batchSize);

    print('✅ Old collections cleanup completed!');
  }

  static Future<void> _deleteCollection(
    String collectionName,
    int batchSize,
  ) async {
    print('🗑️ Deleting collection: $collectionName');

    int totalDeleted = 0;

    while (true) {
      final querySnapshot = await _firestore
          .collection(collectionName)
          .limit(batchSize)
          .get();

      if (querySnapshot.docs.isEmpty) {
        break;
      }

      final batch = _firestore.batch();

      for (final doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      totalDeleted += querySnapshot.docs.length;

      print('🗑️ Deleted $totalDeleted documents from $collectionName...');
    }

    print(
      '✅ Collection $collectionName deleted! Total: $totalDeleted documents',
    );
  }

  /// 🔍 Method 6: Verify migration success
  static Future<void> verifyMigration() async {
    print('🔍 Verifying migration...');

    try {
      // Count unified activities by category
      final medicationCount = await _firestore
          .collection('activity_logs')
          .where('category', isEqualTo: 'medication')
          .count()
          .get();

      final vitalCount = await _firestore
          .collection('activity_logs')
          .where('category', isEqualTo: 'vital')
          .count()
          .get();

      // Count original collections
      final oldMedicationCount = await _firestore
          .collection('medication_activity_logs')
          .count()
          .get();

      final oldVitalCount = await _firestore
          .collection('vital_activity_logs')
          .count()
          .get();

      print('');
      print('📊 Migration Verification Results:');
      print('   Unified medication activities: ${medicationCount.count}');
      print('   Original medication activities: ${oldMedicationCount.count}');
      print('   Unified vital activities: ${vitalCount.count}');
      print('   Original vital activities: ${oldVitalCount.count}');
      print('');

      if (medicationCount.count == oldMedicationCount.count &&
          vitalCount.count == oldVitalCount.count) {
        print(
          '✅ Migration verification PASSED! All data migrated successfully.',
        );
      } else {
        print(
          '⚠️  Migration verification FAILED! Data count mismatch detected.',
        );
      }
    } catch (e) {
      print('❌ Error verifying migration: $e');
    }
  }

  /// 🚀 Method 7: Run complete migration process
  static Future<void> runCompleteMigration() async {
    print('🚀 Starting complete unified activity logs migration...');
    print('');

    try {
      // Step 1: Create indexes
      await createIndexes();

      // Wait for user to create indexes
      print(
        '⏳ Please create the indexes in Firebase Console first, then continue...',
      );
      print('   Press Enter when indexes are ready...');
      // In real app, you might want to wait for user confirmation

      // Step 2: Migrate medication activities
      await migrateMedicationActivities();

      // Step 3: Migrate vital activities
      await migrateVitalActivities();

      // Step 4: Verify migration
      await verifyMigration();

      print('');
      print('🎉 Migration completed successfully!');
      print('');
      print('🔄 Next steps:');
      print('1. Test the unified activity logs screen thoroughly');
      print('2. Verify all functionality works correctly');
      print('3. Monitor performance for a few days');
      print(
        '4. Once confident, run cleanupOldCollections() to remove old data',
      );
    } catch (e) {
      print('❌ Migration failed: $e');
      rethrow;
    }
  }
}

/// 🎯 Helper class for creating activity logs in new code
class ActivityLogger {
  /// Create medication activity log
  static Future<void> logMedicationActivity({
    required String action,
    required String nurseName,
    required String nurseId,
    required String elderlyId,
    required String elderlyName,
    required String houseId,
    String? medicationName,
    String? medicationId,
    String? takeOrdinal,
    int? takeNumber,
    String? dosage,
    String? frequency,
  }) async {
    await ActivityLogsMigration.createUnifiedActivityLog(
      category: 'medication',
      action: action,
      nurseName: nurseName,
      nurseId: nurseId,
      elderlyId: elderlyId,
      elderlyName: elderlyName,
      houseId: houseId,
      details: {
        if (medicationName != null) 'medication_name': medicationName,
        if (medicationId != null) 'medication_id': medicationId,
        if (takeOrdinal != null) 'take_ordinal': takeOrdinal,
        if (takeNumber != null) 'take_number': takeNumber,
        if (dosage != null) 'dosage': dosage,
        if (frequency != null) 'frequency': frequency,
      },
    );
  }

  /// Create vital activity log
  static Future<void> logVitalActivity({
    required String action,
    required String nurseName,
    required String nurseId,
    required String elderlyId,
    required String elderlyName,
    required String houseId,
    String? vitalId,
    String? vitalType,
    int? bloodPressureSystolic,
    int? bloodPressureDiastolic,
    int? heartRate,
    double? temperature,
    int? respiratoryRate,
    int? oxygenSaturation,
  }) async {
    await ActivityLogsMigration.createUnifiedActivityLog(
      category: 'vital',
      action: action,
      nurseName: nurseName,
      nurseId: nurseId,
      elderlyId: elderlyId,
      elderlyName: elderlyName,
      houseId: houseId,
      details: {
        if (vitalId != null) 'vital_id': vitalId,
        if (vitalType != null) 'vital_type': vitalType,
        if (bloodPressureSystolic != null)
          'blood_pressure_systolic': bloodPressureSystolic,
        if (bloodPressureDiastolic != null)
          'blood_pressure_diastolic': bloodPressureDiastolic,
        if (heartRate != null) 'heart_rate': heartRate,
        if (temperature != null) 'temperature': temperature,
        if (respiratoryRate != null) 'respiratory_rate': respiratoryRate,
        if (oxygenSaturation != null) 'oxygen_saturation': oxygenSaturation,
      },
    );
  }

  /// Create incident activity log (for future use)
  static Future<void> logIncidentActivity({
    required String action,
    required String nurseName,
    required String nurseId,
    required String elderlyId,
    required String elderlyName,
    required String houseId,
    String? incidentType,
    String? severity,
    String? description,
  }) async {
    await ActivityLogsMigration.createUnifiedActivityLog(
      category: 'incident',
      action: action,
      nurseName: nurseName,
      nurseId: nurseId,
      elderlyId: elderlyId,
      elderlyName: elderlyName,
      houseId: houseId,
      details: {
        if (incidentType != null) 'incident_type': incidentType,
        if (severity != null) 'severity': severity,
        if (description != null) 'description': description,
      },
    );
  }

  /// Create shift activity log (for future use)
  static Future<void> logShiftActivity({
    required String action,
    required String nurseName,
    required String nurseId,
    required String houseId,
    String? shiftType,
    String? startTime,
    String? endTime,
  }) async {
    await ActivityLogsMigration.createUnifiedActivityLog(
      category: 'shift',
      action: action,
      nurseName: nurseName,
      nurseId: nurseId,
      elderlyId: '', // Shift logs might not have specific elderly
      elderlyName: '',
      houseId: houseId,
      details: {
        if (shiftType != null) 'shift_type': shiftType,
        if (startTime != null) 'start_time': startTime,
        if (endTime != null) 'end_time': endTime,
      },
    );
  }
}
