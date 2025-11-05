import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'cg_services/notification_service.dart';
import '../models/cg_models/notification_model.dart';

/// Monitors `medical_tasks` and auto-marks medication tasks as missed
/// if they remain pending more than 1 hour after their scheduled `task_start`.
class MedicationMissedMonitorService {
  static final MedicationMissedMonitorService _instance =
      MedicationMissedMonitorService._internal();
  factory MedicationMissedMonitorService() => _instance;
  MedicationMissedMonitorService._internal();

  Timer? _timer;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    // Initial check
    await _checkAndMarkMissed();
    // Periodic check every minute
    _timer = Timer.periodic(const Duration(minutes: 1), (_) async {
      await _checkAndMarkMissed();
    });
    print('✅ MedicationMissedMonitorService started');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    print('🛑 MedicationMissedMonitorService stopped');
  }

  Future<void> _checkAndMarkMissed() async {
    try {
      final now = DateTime.now();

      // Query pending medical tasks where task_start <= now - 1 hour
      final cutoff = now.subtract(const Duration(hours: 1));

      print('🔍 MedicationMissedMonitorService: Checking for missed tasks');
      print('🔍 Current time: $now');
      print('🔍 Cutoff time: $cutoff');
      print('🔍 Cutoff timestamp: ${Timestamp.fromDate(cutoff)}');

      // First, let's get all medical tasks to see what's in the database
      final allTasksQuery = await FirebaseFirestore.instance
          .collection('medical_tasks')
          .where('task_source', isEqualTo: 'Medication')
          .get();

      print('🔍 Total medical tasks in DB: ${allTasksQuery.docs.length}');
      for (final doc in allTasksQuery.docs) {
        final data = doc.data();
        final taskStart = data['task_start'];
        final taskStatus = data['task_status'];
        print(
          '🔍 Task ${doc.id}: task_start=$taskStart, task_status=$taskStatus, type=${taskStatus.runtimeType}',
        );
      }

      final query = await FirebaseFirestore.instance
          .collection('medical_tasks')
          .where('task_source', isEqualTo: 'Medication')
          .where(
            'task_status',
            whereIn: ['pending', 'Pending'],
          ) // Handle both cases
          .where('task_start', isLessThanOrEqualTo: Timestamp.fromDate(cutoff))
          .get();

      print(
        '🔍 Found ${query.docs.length} pending medical tasks that might be missed',
      );

      if (query.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      int marked = 0;

      for (final doc in query.docs) {
        final data = doc.data();
        final taskStart = data['task_start'];
        print(
          '🔍 Checking task ${doc.id}: task_start = $taskStart, type = ${taskStart.runtimeType}',
        );

        final ref = doc.reference;
        batch.update(ref, {
          'task_status': 'missed',
          'marked_missed_at': FieldValue.serverTimestamp(),
          'marked_by': 'med_miss_monitor',
        });
        marked++;

        print('✅ Marked task ${doc.id} as missed');

        // Send a Firestore-backed notification and local notification
        try {
          NotificationService().createNotification(
            userId: data['assigned_nurse_id'] ?? data['nurse_id'] ?? '',
            title: '⚠️ Missed Medication',
            message:
                'Medication task "${data['task_title'] ?? 'Medication'}" was not completed and has been marked missed.',
            type: NotificationType.taskMissed,
            taskId: doc.id,
            elderlyId: data['elderly_id'],
            priority: NotificationPriority.high,
          );
        } catch (e) {
          print(
            '⚠️ Failed to create notification for missed med ${doc.id}: $e',
          );
        }
      }

      if (marked > 0) {
        await batch.commit();
        print(
          '✅ MedicationMissedMonitorService: marked $marked medical_tasks as missed',
        );
      } else {
        print('🔍 No tasks were marked as missed');
      }
    } catch (e) {
      print('❌ MedicationMissedMonitorService error: $e');
    }
  }
}
