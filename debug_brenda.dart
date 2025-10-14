import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  final firestore = FirebaseFirestore.instance;

  try {
    // Find Brenda Castro's elderly document
    print('🔍 Finding Brenda Castro...');
    final brendaQuery = await firestore
        .collection('elderly')
        .where('elderly_fname', isEqualTo: 'Brenda')
        .where('elderly_lname', isEqualTo: 'Castro')
        .get();

    if (brendaQuery.docs.isEmpty) {
      print('❌ Brenda Castro not found in elderly collection');
      return;
    }

    final brendaDoc = brendaQuery.docs.first;
    final brendaData = brendaDoc.data();
    final brendaId = brendaDoc.id;
    final brendaHouseId = brendaData['house_id'];

    print('✅ Found Brenda Castro:');
    print('   - ID: $brendaId');
    print('   - House: $brendaHouseId');
    print('   - Status: ${brendaData['elderly_status']}');

    // Check current assignments for Brenda
    print('\n🔍 Checking elderly assignments for Brenda...');
    final assignmentsQuery = await firestore
        .collection('elderly_assignments')
        .where('house_id', arrayContains: brendaHouseId)
        .where('is_current', isEqualTo: true)
        .get();

    print(
      '📋 Found ${assignmentsQuery.docs.length} assignment documents for house $brendaHouseId',
    );

    String? assignedNurseId;
    String? assignedNurseName;
    String? shift;
    String? day;

    for (final assignDoc in assignmentsQuery.docs) {
      final data = assignDoc.data();
      final elderlyIds = List<String>.from(data['elderly_ids'] ?? []);
      if (elderlyIds.contains(brendaId)) {
        assignedNurseId = data['user_id'];
        shift = data['shift'];
        day = data['day'];

        // Get nurse name
        final nurseDoc = await firestore
            .collection('users')
            .doc(assignedNurseId)
            .get();
        if (nurseDoc.exists) {
          final nurseData = nurseDoc.data()!;
          assignedNurseName =
              '${nurseData['user_fname']} ${nurseData['user_lname']}';
        }

        print('✅ Brenda is assigned to:');
        print('   - Nurse: $assignedNurseName ($assignedNurseId)');
        print('   - Shift: $shift');
        print('   - Day: $day');
        break;
      }
    }

    if (assignedNurseId == null) {
      print('❌ Brenda Castro is not assigned to any nurse!');
      return;
    }

    // Check vitals assignments for today
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    print('\n🔍 Checking vitals assignments for today ($todayStr)...');
    final vitalsQuery = await firestore
        .collection('vitals')
        .where('elderly_id', isEqualTo: brendaId)
        .where('assigned_date', isEqualTo: todayStr)
        .get();

    print(
      '📋 Found ${vitalsQuery.docs.length} vitals assignments for Brenda today',
    );

    for (final vitalDoc in vitalsQuery.docs) {
      final vitalData = vitalDoc.data();
      print('   - Status: ${vitalData['status']}');
      print('   - Assigned Nurse ID: ${vitalData['assigned_nurse_id']}');
      print('   - Shift: ${vitalData['shift']}');
      print('   - Completed: ${vitalData['completed_at'] != null}');
    }

    // Check if there are any completed vitals for today by any nurse
    final completedVitalsQuery = await firestore
        .collection('vitals')
        .where('elderly_id', isEqualTo: brendaId)
        .where('assigned_date', isEqualTo: todayStr)
        .where('status', isEqualTo: 'completed')
        .get();

    if (completedVitalsQuery.docs.isNotEmpty) {
      print('\n⚠️ Brenda\'s vitals were completed today by another nurse!');
      for (final doc in completedVitalsQuery.docs) {
        final data = doc.data();
        print('   - Completed by nurse: ${data['assigned_nurse_id']}');
        print('   - Completed at: ${data['completed_at']}');
      }
    }
  } catch (e) {
    print('❌ Error: $e');
  }
}
