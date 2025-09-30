import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class IncidentReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Caregiver Name
  Future<String?> _loadCaregiverName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return "${doc['user_fname']} ${doc['user_lname']}";
  }

  // Load Elderly Assignments
  Future<Map<String, dynamic>> _loadElderlyAssignments() async {
    bool isOnDuty = false;
    List<Map<String, dynamic>> elderlyList = [];
    DateTime shiftStart = DateTime.now();
    DateTime shiftEnd = DateTime.now();

    try {
      final now = DateTime.now();
      final dayName = DateFormat('EEEE').format(now);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return {'isOnDuty': false, 'elderlyList': []};

      final caregiverId = user.uid;

      final houseSnapshot = await _firestore
          .collection('cg_house_assign')
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('is_current', isEqualTo: true)
          .where('is_absent', isEqualTo: false)
          .limit(1)
          .get();

      if (houseSnapshot.docs.isEmpty) {
        return {'isOnDuty': false, 'elderlyList': []};
      }

      final houseData = houseSnapshot.docs.first.data();
      final daysAssigned = List<String>.from(houseData['days_assigned'] ?? []);
      final houseId = houseData['house_id'] ?? '';
      final startDate = (houseData['start_date'] as Timestamp).toDate();
      final endDate = (houseData['end_date'] as Timestamp).toDate();

      if (now.isBefore(startDate) || now.isAfter(endDate)) return {'isOnDuty': false, 'elderlyList': []};
      if (!daysAssigned.contains(dayName)) return {'isOnDuty': false, 'elderlyList': []};

      // Time range
      final timeRange = Map<String, dynamic>.from(houseData['time_range'] ?? {});
      int startHour = 6, startMinute = 0, endHour = 14, endMinute = 0;
      if (timeRange.isNotEmpty) {
        final startParts = (timeRange['start'] as String).split(':');
        final endParts = (timeRange['end'] as String).split(':');
        startHour = int.parse(startParts[0]);
        startMinute = int.parse(startParts[1]);
        endHour = int.parse(endParts[0]);
        endMinute = int.parse(endParts[1]);
      }

      DateTime calculatedShiftStart = DateTime(now.year, now.month, now.day, startHour, startMinute);
      DateTime calculatedShiftEnd = DateTime(now.year, now.month, now.day, endHour, endMinute);

      if (calculatedShiftEnd.isBefore(calculatedShiftStart)) {
        if (now.isBefore(calculatedShiftEnd)) {
          calculatedShiftStart = calculatedShiftStart.subtract(const Duration(days: 1));
        } else {
          calculatedShiftEnd = calculatedShiftEnd.add(const Duration(days: 1));
        }
      }

      final isWithinShift = !(now.isBefore(calculatedShiftStart) || now.isAfter(calculatedShiftEnd));
      if (!isWithinShift) return {'isOnDuty': false, 'elderlyList': []};

      // Elderly assignments
      final assignSnapshot = await _firestore
          .collection('elderly_caregiver_assign')
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('day', isEqualTo: dayName)
          .get();

      if (assignSnapshot.docs.isNotEmpty) {
        final elderlyIds = assignSnapshot.docs.map((doc) => doc.data()['elderly_id'] as String).toSet().toList();
        for (int i = 0; i < elderlyIds.length; i += 30) {
          final chunk = elderlyIds.skip(i).take(30).toList();
          final chunkSnapshot = await _firestore.collection('elderly').where(FieldPath.documentId, whereIn: chunk).get();
          for (var doc in chunkSnapshot.docs) {
            final data = doc.data();
            if (data['house_id'] == houseId) {
              elderlyList.add({
                'id': doc.id,
                'name': '${data['elderly_fname'] ?? ''} ${data['elderly_lname'] ?? ''}',
              });
            }
          }
        }
        elderlyList.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      }

      return {
        'isOnDuty': true,
        'elderlyList': elderlyList,
        'shiftStart': calculatedShiftStart,
        'shiftEnd': calculatedShiftEnd,
      };
    } catch (e) {
      return {'isOnDuty': false, 'elderlyList': []};
    }
  }

  // Check Shift & Schedule Dialog
  Future<void> _checkShiftAndShowDialog(Function showWarningDialog) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final currentDay = DateFormat('EEEE').format(now);

    final query = await _firestore
        .collection('cg_house_assign')
        .where('caregiver_id', isEqualTo: user.uid)
        .where('is_current', isEqualTo: true)
        .where('is_absent', isEqualTo: false)
        .get();

    if (query.docs.isEmpty) {
      showWarningDialog("No active shift found.");
      return;
    }

    final data = query.docs.first.data();
    final List daysAssigned = data['days_assigned'] ?? [];
    final String shift = data['shift'] ?? "";
    final Map<String, dynamic> timeRange = Map<String, dynamic>.from(data['time_range']);

    if (!daysAssigned.contains(currentDay)) {
      showWarningDialog("You are not scheduled today.");
      return;
    }

    final startParts = (timeRange['start'] as String).split(":");
    final endParts = (timeRange['end'] as String).split(":");

    DateTime start = DateTime(now.year, now.month, now.day, int.parse(startParts[0]), int.parse(startParts[1]));
    DateTime end = DateTime(now.year, now.month, now.day, int.parse(endParts[0]), int.parse(endParts[1]));

    if (shift == "3rd" && end.isBefore(start)) end = end.add(const Duration(days: 1));

    // Return shift times for UI usage
    return {'shiftStart': start, 'shiftEnd': end};
  }

  // Submit incident report
  Future<void> submitIncidentReport({
    required String selectedElderlyId,
    required String reportText,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || selectedElderlyId.isEmpty) return;

    final caregiverId = user.uid;

    final elderlyDoc = await _firestore.collection('elderly').doc(selectedElderlyId).get();
    final houseId = elderlyDoc['house_id'] ?? '';

    // Nurses scheduled today
    final todayDay = DateFormat('EEEE').format(DateTime.now());
    final nowTime = DateFormat('HH:mm').format(DateTime.now());

    final nurseQuery = await _firestore.collection('nurse_shift_assign').where('is_current', isEqualTo: true).get();

    List<String> nurseIdsToSend = [];
    for (var doc in nurseQuery.docs) {
      final daysAssigned = List<String>.from(doc['days_assigned'] ?? []);
      final startTime = doc['start_time'] ?? "00:00";
      final endTime = doc['end_time'] ?? "23:59";

      if (daysAssigned.contains(todayDay)) {
        final start = DateFormat('HH:mm').parse(startTime);
        final end = DateFormat('HH:mm').parse(endTime);
        final nowParsed = DateFormat('HH:mm').parse(nowTime);
        bool inShift = end.isBefore(start) ? nowParsed.isAfter(start) || nowParsed.isBefore(end) : nowParsed.isAfter(start) && nowParsed.isBefore(end);

        if (inShift) nurseIdsToSend.add(doc['nurse_id']);
      }
    }

    if (nurseIdsToSend.isNotEmpty) {
      final incidentDocRef = _firestore.collection('incident_report').doc();
      await incidentDocRef.set({
        'elderly_id': selectedElderlyId,
        'house_id': houseId,
        'incident_date_time': DateTime.now(),
        'incident_desc': reportText.trim(),
        'incident_id': incidentDocRef.id,
        'incident_verify': true,
        'user_id_cg': caregiverId,
        'user_id_nu': nurseIdsToSend,
      });
    }
  }
}
