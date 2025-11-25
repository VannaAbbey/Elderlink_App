import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'widgets/auth_wrapper.dart';
import 'providers/cg_providers/absence_provider.dart';
import 'auth/get_started.dart';
import 'auth/login.dart';
import 'auth/register_choose_role.dart';
import 'auth/forgot_pass.dart';
import 'auth/register_success.dart';
import 'caregiver/home.dart';
import 'nurse/home.dart';
import 'nurse/emergency_screen_modal.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/auth_provider.dart' as my_auth;
import 'nurse/notification_service.dart';
import 'services/cg_services/task_reminder_service.dart';
import 'services/cg_services/missed_task_monitor_service.dart';
import 'services/attendance_check_service.dart';
import 'package:workmanager/workmanager.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Track processed messages to prevent duplicates
final Set<String> _processedMessages = <String>{};

// Clean up old processed messages periodically (keep only last 100)
void _cleanupProcessedMessages() {
  if (_processedMessages.length > 100) {
    final messages = _processedMessages.toList();
    _processedMessages.clear();
    // Keep only the most recent 50 messages
    _processedMessages.addAll(messages.skip(messages.length - 50));
  }
}

// Top-level background message handler required by firebase_messaging.
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized in background isolate
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  print('🔔 BACKGROUND (main.dart): Message received: ${message.messageId}');
  print('🔔 BACKGROUND (main.dart): Message type: ${message.data['type']}');

  // Special handling for medication notifications
  if (message.data['type'] == 'medication') {
    print('💊 BACKGROUND (main.dart): ⚡ MEDICATION NOTIFICATION DETECTED! ⚡');
    print('💊 BACKGROUND (main.dart): Title: ${message.notification?.title}');
    print('💊 BACKGROUND (main.dart): Body: ${message.notification?.body}');
    print('💊 BACKGROUND (main.dart): Data: ${message.data}');
  }

  // Prevent duplicate processing
  final messageId = message.messageId ?? message.data['messageId'] ?? '';
  if (messageId.isNotEmpty && _processedMessages.contains(messageId)) {
    print('⚠️ Background: Already processed message $messageId, skipping');
    return;
  }
  if (messageId.isNotEmpty) {
    _processedMessages.add(messageId);
    _cleanupProcessedMessages();
  }

  try {
    final notification = message.notification;
    final data = message.data;
    final title = notification?.title ?? data['title'] ?? 'Notification';
    String body = notification?.body ?? data['body'] ?? '';

    // If body empty, attempt to compose from emergency or incident doc
    if (body.trim().isEmpty) {
      final alertId = data['alertId'] ?? data['alert_id'] ?? '';
      if (alertId != null && alertId.toString().isNotEmpty) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('emergency_alert')
              .doc(alertId.toString())
              .get();
          if (doc.exists) {
            final d = doc.data()!;
            final et = (d['emergency_type'] ?? '').toString().trim();
            final ai = (d['additional_info'] ?? '').toString().trim();
            String composed = '';
            if (et.isNotEmpty) composed = et;
            if (ai.isNotEmpty) {
              composed = composed.isNotEmpty ? '$composed - $ai' : ai;
            }
            if (composed.isNotEmpty) body = composed;
          }
        } catch (e) {
          // ignore fetch error
        }
      } else {
        final incidentId = data['incidentId'] ?? data['incident_id'] ?? '';
        if (incidentId != null && incidentId.toString().isNotEmpty) {
          try {
            final doc = await FirebaseFirestore.instance
                .collection('incident_report')
                .doc(incidentId.toString())
                .get();
            if (doc.exists) {
              final d = doc.data()!;
              final it = (d['incident_type'] ?? '').toString().trim();
              final ai = (d['additional_info'] ?? '').toString().trim();
              String composed = '';
              if (it.isNotEmpty) composed = it;
              if (ai.isNotEmpty) {
                composed = composed.isNotEmpty ? '$composed - $ai' : ai;
              }
              if (composed.isNotEmpty) body = composed;
            }
          } catch (e) {
            // ignore
          }
        }
      }
    }

    // Initialize a local notifications instance and show a notification
    final FlutterLocalNotificationsPlugin localNotifications =
        FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await localNotifications.initialize(
      const InitializationSettings(android: androidInit),
    );

    // Determine channel based on notification type
    String channelId = 'emergency_channel';
    String channelName = 'Emergency Alerts';
    String payload = data['alertId'] ?? data['alert_id'] ?? '';

    // Handle medication notifications with proper channel
    if (data['type'] == 'medication') {
      channelId = 'medication_channel';
      channelName = 'Medication Reminders';
      payload = data['takeId'] ?? '';
      print('💊 BACKGROUND (main.dart): Processing MEDICATION notification');
      print('💊 BACKGROUND: Medication: ${data['medicationName']}');
      print('💊 BACKGROUND: Elderly: ${data['elderlyName']}');
      print('💊 BACKGROUND: Scheduled time: ${data['scheduledTime']}');
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.max,
      priority: Priority.max, // MAX priority for medications
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true, // Show over lockscreen for medications
      ongoing: false,
      visibility: NotificationVisibility.public, // Show on lockscreen
      category: channelId == 'medication_channel'
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.message,
    );

    final details = NotificationDetails(android: androidDetails);
    await localNotifications.show(
      message.hashCode,
      title,
      body,
      details,
      payload: payload,
    );

    if (data['type'] == 'medication') {
      print(
        '💊 BACKGROUND (main.dart): MEDICATION NOTIFICATION SHOWN SUCCESSFULLY!',
      );
    }
  } catch (e) {
    print('❌ Background message handling failed: $e');
  }
}

/// ---------------------- EMERGENCY SERVICE ----------------------
class EmergencyService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _modalOpen = false;
  static String? _currentAlertId;
  static final List<String> _pendingAlerts = [];

  static bool get isModalOpen => _modalOpen;

  static Future<void> initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        if (response.payload != null && response.payload!.isNotEmpty) {
          await _showModal(response.payload!);
        }
      },
    );

    // Initialize Firebase Messaging handlers so push notifications work
    try {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      final messaging = FirebaseMessaging.instance;

      // Request permissions on iOS/macOS
      NotificationSettings settingsPerm = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      print('🔔 FCM permission status: ${settingsPerm.authorizationStatus}');

      // Get FCM token (useful for server-side sends). You can send this to your backend.
      try {
        final token = await messaging.getToken();
        print('🔑 FCM token: $token');
      } catch (e) {
        print('❌ Failed to get FCM token: $e');
      }

      // Foreground messages: show local notification and optionally open modal
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        // Prevent duplicate processing
        final messageId = message.messageId ?? message.data['messageId'] ?? '';
        if (messageId.isNotEmpty && _processedMessages.contains(messageId)) {
          print(
            '⚠️ Foreground: Already processed message $messageId, skipping',
          );
          return;
        }
        if (messageId.isNotEmpty) {
          _processedMessages.add(messageId);
        }

        final notification = message.notification;
        final data = message.data;
        String title = notification?.title ?? data['title'] ?? 'Notification';
        String body = notification?.body ?? data['body'] ?? '';

        // Check if this is an emergency alert and override title/body format
        final alertId = data['alertId'] ?? data['alert_id'] ?? '';
        if (alertId.isNotEmpty) {
          try {
            // Fetch emergency details to create proper notification format
            final doc = await FirebaseFirestore.instance
                .collection('emergency_alert')
                .doc(alertId.toString())
                .get();
            if (doc.exists) {
              final d = doc.data()!;
              final et = (d['emergency_type'] ?? '').toString().trim();
              final ai = (d['additional_info'] ?? '').toString().trim();

              // Get house name
              String houseName = 'Unknown House';
              final houseId = d['house_id'];
              if (houseId != null && houseId.toString().isNotEmpty) {
                final houseDoc = await FirebaseFirestore.instance
                    .collection('house')
                    .where('house_id', isEqualTo: houseId.toString())
                    .limit(1)
                    .get();
                if (houseDoc.docs.isNotEmpty) {
                  houseName =
                      houseDoc.docs.first.data()['house_name'] ??
                      'Unknown House';
                }
              }

              // Format timestamp
              final timestampRaw = d['alert_timestamp']?.toDate();
              final formattedTime = timestampRaw != null
                  ? DateFormat('M/dd/yyyy | h:mm a').format(timestampRaw)
                  : 'Unknown time';

              // Override title with new format: "Emergency Alert - House at Date Time"
              title = 'Emergency Alert - $houseName at $formattedTime';

              // Override body with new format: "Emergency Type - Additional Info"
              String newBody = '';
              if (et.isNotEmpty) newBody = et;
              if (ai.isNotEmpty &&
                  ai != 'No description' &&
                  ai != 'Emergency alert received') {
                newBody = newBody.isNotEmpty ? '$newBody - $ai' : ai;
              }
              if (newBody.isEmpty) {
                newBody = 'Emergency reported - please check immediately';
              }
              body = newBody;

              print('🔄 Overrode FCM notification format:');
              print('📋 Title: $title');
              print('📝 Body: $body');
            }
          } catch (e) {
            print('❌ Error formatting emergency notification: $e');
          }

          // For emergency alerts, show modal only (no duplicate local notification)
          print('🚨 Received FCM emergency alert, showing modal');
          EmergencyService.showEmergencyAlert(
            alertId: alertId,
            description: body,
          );
        } else {
          // Check for incident notifications
          final incidentId = data['incidentId'] ?? data['incident_id'] ?? '';
          if (incidentId != null && incidentId.toString().isNotEmpty) {
            try {
              final doc = await FirebaseFirestore.instance
                  .collection('incident_report')
                  .doc(incidentId.toString())
                  .get();
              if (doc.exists) {
                final d = doc.data()!;
                final it = (d['incident_type'] ?? '').toString().trim();
                final ai = (d['additional_info'] ?? '').toString().trim();
                String composed = '';
                if (it.isNotEmpty) composed = it;
                if (ai.isNotEmpty) {
                  composed = composed.isNotEmpty ? '$composed - $ai' : ai;
                }
                if (composed.isNotEmpty) {
                  body = composed;
                }
              }
            } catch (e) {
              print('❌ Error fetching incident doc for FCM message: $e');
            }
          }

          // FCM already shows the notification automatically
          // No need to create additional local notification to prevent duplicates
          print(
            '✅ FCM notification shown automatically - no duplicate local notification needed',
          );
        }
      });

      // When the app is opened from a notification
      FirebaseMessaging.onMessageOpenedApp.listen((
        RemoteMessage message,
      ) async {
        // Prevent duplicate processing
        final messageId = message.messageId ?? message.data['messageId'] ?? '';
        if (messageId.isNotEmpty && _processedMessages.contains(messageId)) {
          print(
            '⚠️ OnMessageOpenedApp: Already processed message $messageId, skipping',
          );
          return;
        }
        if (messageId.isNotEmpty) {
          _processedMessages.add(messageId);
        }

        final data = message.data;
        final alertId = data['alertId'] ?? data['alert_id'] ?? '';
        if (alertId != null && alertId.toString().isNotEmpty) {
          // Use showEmergencyAlert to preserve bottom nav
          EmergencyService.showEmergencyAlert(
            alertId: alertId.toString(),
            description: '',
          );
          return;
        }

        final incidentId = data['incidentId'] ?? data['incident_id'] ?? '';
        if (incidentId != null && incidentId.toString().isNotEmpty) {
          // Navigate to nurse home (adjust as needed to open incident details)
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => NurseHomeScreen()),
          );
        }
      });

      // Handle when app is launched from terminated state via notification
      FirebaseMessaging.instance.getInitialMessage().then((
        RemoteMessage? message,
      ) async {
        if (message != null) {
          // Prevent duplicate processing
          final messageId =
              message.messageId ?? message.data['messageId'] ?? '';
          if (messageId.isNotEmpty && _processedMessages.contains(messageId)) {
            print(
              '⚠️ GetInitialMessage: Already processed message $messageId, skipping',
            );
            return;
          }
          if (messageId.isNotEmpty) {
            _processedMessages.add(messageId);
          }

          final data = message.data;
          final alertId = data['alertId'] ?? data['alert_id'] ?? '';
          if (alertId != null && alertId.toString().isNotEmpty) {
            // Delay slightly to allow navigator to be ready
            Future.delayed(const Duration(milliseconds: 500), () async {
              EmergencyService.showEmergencyAlert(
                alertId: alertId.toString(),
                description: '',
              );
            });
            return;
          }

          final incidentId = data['incidentId'] ?? data['incident_id'] ?? '';
          if (incidentId != null && incidentId.toString().isNotEmpty) {
            Future.delayed(const Duration(milliseconds: 500), () async {
              navigatorKey.currentState?.push(
                MaterialPageRoute(builder: (_) => NurseHomeScreen()),
              );
            });
          }
        }
      });
    } catch (e) {
      print('❌ FirebaseMessaging init error: $e');
    }
  }

  static Future<void> showEmergencyAlert({
    required String alertId,
    required String description,
    String? emergencyType,
  }) async {
    print(
      '🚨 showEmergencyAlert called with alertId: $alertId, description: $description',
    );
    // Only check if modal is already showing this specific alert
    if (_modalOpen && _currentAlertId == alertId) {
      print('⚠️ Emergency alert $alertId is already being displayed, skipping');
      return;
    }

    // If modal is open with different alert, queue this alert
    if (_modalOpen && _currentAlertId != alertId) {
      print('⚠️ Modal already open with different alert, queuing: $alertId');
      _pendingAlerts.add(alertId);
      return;
    }
    _modalOpen = true;
    _currentAlertId = alertId;
    print('✅ Modal flag set to open for alert: $alertId');

    try {
      final doc = await FirebaseFirestore.instance
          .collection('emergency_alert')
          .doc(alertId)
          .get();

      if (!doc.exists) {
        print('❌ Alert document does not exist');
        return;
      }
      print('✅ Alert document exists');

      final data = doc.data()!;
      // Get house name from Firestore using house_id
      String houseName = 'Unknown house';
      final houseId = data['house_id'];
      if (houseId != null && houseId.toString().isNotEmpty) {
        final houseDoc = await FirebaseFirestore.instance
            .collection('house')
            .where('house_id', isEqualTo: houseId.toString())
            .limit(1)
            .get();

        if (houseDoc.docs.isNotEmpty) {
          houseName =
              houseDoc.docs.first.data()['house_name'] ?? 'Unknown house';
        }
      }
      print('🏠 House name resolved: $houseName');

      final timestampRaw = data['alert_timestamp']?.toDate();
      final formattedTime = timestampRaw != null
          ? DateFormat('M/dd/yyyy | h:mm a').format(timestampRaw)
          : 'Unknown time';

      // Compose description for notification: include emergency type and additional info
      String finalDescription = emergencyType ?? '';
      if (description.isNotEmpty && description != 'Emergency alert received') {
        finalDescription = finalDescription.isNotEmpty
            ? '$finalDescription - $description'
            : description;
      }
      if (finalDescription.isEmpty) {
        finalDescription = 'Emergency alert received';
      }
      print('📝 Final description: $finalDescription');

      // No local notification - FCM notification will be the only one
      print('🚫 Skipping local notification to prevent duplicates');

      print('📞 Calling _showModal');
      await _showModal(
        alertId,
        description: description, // This is now only additional info
        timestamp: formattedTime,
        emergencyType: emergencyType ?? data['emergency_type'] ?? '',
      );
      print('📞 _showModal completed');
    } catch (e) {
      print('❌ Error in showEmergencyAlert: $e');
      _modalOpen = false;
      _currentAlertId = null; // Reset both flags on error
    }
  }

  static Future<void> _showModal(
    String alertId, {
    String description = '',
    String timestamp = '',
    String emergencyType = '',
  }) async {
    print('🔔 Attempting to show emergency modal for alert: $alertId');

    // Remove delay - show immediately
    // await Future.delayed(const Duration(seconds: 2));
    print('⏳ Proceeding with modal immediately');

    // Check context right before showing dialog
    final ctx = navigatorKey.currentState?.context;
    if (ctx == null) {
      print('❌ Navigator context is null, cannot show modal');
      _modalOpen = false;
      return;
    }
    print('✅ Navigator context available, showing modal');

    try {
      final doc = await FirebaseFirestore.instance
          .collection('emergency_alert')
          .doc(alertId)
          .get();

      if (!doc.exists) {
        print('❌ Alert document not found in _showModal');
        _modalOpen = false;
        _currentAlertId = null;
        return;
      }
      print('✅ Alert document found in _showModal');

      final data = doc.data()!;
      final emergencyType = data['emergency_type'] ?? '';
      final timestampRaw = data['alert_timestamp']?.toDate();
      final formattedTime = timestampRaw != null
          ? DateFormat('M/dd/yyyy | h:mm a').format(timestampRaw)
          : 'Unknown time';
      final houseName = data['house_name'] ?? 'Unknown house';

      String caregiverName = 'Unknown caregiver';
      final cgId = data['user_id_cg'];
      if (cgId != null && cgId.toString().isNotEmpty) {
        final cgDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(cgId.toString().trim())
            .get();
        if (cgDoc.exists) {
          final cgData = cgDoc.data();
          final firstName = cgData?['user_fname'] ?? '';
          final lastName = cgData?['user_lname'] ?? '';
          caregiverName = (firstName + ' ' + lastName).trim();
        }
      }
      print('👤 Caregiver name resolved: $caregiverName');

      // Use the passed description (additional info only) and emergency type
      String fullDescription = description;

      print('🎯 About to show dialog');
      try {
        await showDialog(
          context: ctx,
          barrierDismissible: false,
          builder: (_) => EmergencyScreenModal(
            alertId: alertId,
            alertDescription: fullDescription.isNotEmpty
                ? fullDescription
                : 'No description',
            alertTimestamp: formattedTime,
            houseName: houseName,
            caregiverName: caregiverName,
            emergencyType: emergencyType,
          ),
        );
        print('✅ Dialog shown and dismissed successfully');
      } catch (dialogError) {
        print('❌ Error in showDialog: $dialogError');
      }
    } catch (e) {
      print('❌ Error showing emergency modal: $e');
    } finally {
      _modalOpen = false;
      _currentAlertId = null;
      print('🔄 Modal flag and current alert ID reset');

      // Process next queued alert if any
      _processNextQueuedAlert();
    }
  }

  static void _processNextQueuedAlert() {
    if (_pendingAlerts.isNotEmpty && !_modalOpen) {
      final nextAlertId = _pendingAlerts.removeAt(0);
      print('📋 Processing queued alert: $nextAlertId');

      // Process the queued alert after a brief delay
      Future.delayed(const Duration(milliseconds: 500), () {
        showEmergencyAlert(
          alertId: nextAlertId,
          description: 'Queued emergency alert',
        );
      });
    }
  }

  static Future<void> stopAlarm() async {
    await _notifications.cancelAll();
    _modalOpen = false;
    _currentAlertId = null;

    // Process any queued alerts
    _processNextQueuedAlert();
  }
}

/// ---------------------- GLOBAL ATTENDANCE SERVICE ----------------------
class GlobalAttendanceService {
  static bool _attendanceDialogShown = false;
  static Timer? _attendanceTimer;

  /// Initialize global attendance checking for current user
  static Future<void> initializeAttendanceCheck() async {
    print('🔄 GLOBAL ATTENDANCE: Initializing attendance check');

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      print('❌ GLOBAL ATTENDANCE: No user logged in');
      return;
    }

    // Initialize attendance checking
    await _scheduleNextAttendanceCheck();
  }

  /// Schedule next attendance check
  static Future<void> _scheduleNextAttendanceCheck() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final now = DateTime.now();
      print('🔍 GLOBAL ATTENDANCE: Scheduling next check at $now');

      // Get user's shift assignment
      final houseSnapshot = await FirebaseFirestore.instance
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: currentUser.uid)
          .where('is_current', isEqualTo: true)
          .limit(1)
          .get();

      if (houseSnapshot.docs.isEmpty) {
        print('❌ GLOBAL ATTENDANCE: No assignment found');
        return;
      }

      final houseData = houseSnapshot.docs.first.data();
      final startTime = houseData['start_time'] as String?;
      if (startTime == null) return;

      // Parse shift start time
      final timeParts = startTime.split(':');
      final shiftStartHour = int.parse(timeParts[0]);
      final shiftStartMinute = int.parse(timeParts[1]);

      // Calculate next shift start (show dialog 30 minutes before)
      DateTime nextShiftStart = DateTime(
        now.year,
        now.month,
        now.day,
        shiftStartHour,
        shiftStartMinute,
      );

      // Subtract 30 minutes to show dialog before shift starts
      nextShiftStart = nextShiftStart.subtract(const Duration(minutes: 30));

      // If dialog time has passed today, schedule for tomorrow
      if (nextShiftStart.isBefore(now)) {
        nextShiftStart = nextShiftStart.add(const Duration(days: 1));
      }

      final waitDuration = nextShiftStart.difference(now);
      print(
        '⏰ GLOBAL ATTENDANCE: Next check in ${waitDuration.inHours}h ${waitDuration.inMinutes % 60}m',
      );

      // Cancel existing timer
      _attendanceTimer?.cancel();

      // Schedule new timer
      _attendanceTimer = Timer(waitDuration, () async {
        await _checkAndShowAttendanceDialog();
        // Schedule next check for tomorrow
        await _scheduleNextAttendanceCheck();
      });
    } catch (e) {
      print('❌ GLOBAL ATTENDANCE: Error scheduling: $e');
      // Fallback: check every minute
      _attendanceTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
        _checkAndShowAttendanceDialog();
      });
    }
  }

  /// Check if attendance dialog should be shown and display it
  static Future<void> _checkAndShowAttendanceDialog() async {
    if (_attendanceDialogShown) {
      print('⚠️ GLOBAL ATTENDANCE: Dialog already shown');
      return;
    }

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Check if user is scheduled today
      final scheduled = await AttendanceCheckService.isScheduledToday();
      if (!scheduled) {
        print('❌ GLOBAL ATTENDANCE: User not scheduled today');
        return;
      }

      // Check if at shift start time (30 minutes before)
      final atShiftStart = await AttendanceCheckService.isAtShiftStart();
      if (!atShiftStart) {
        print('❌ GLOBAL ATTENDANCE: Not at shift start time');
        return;
      }

      // Check if already marked attendance
      final hasMarked = await AttendanceCheckService.hasMarkedAttendanceToday();
      if (hasMarked) {
        print('✅ GLOBAL ATTENDANCE: Already marked attendance');
        return;
      }

      // Show global attendance dialog
      await _showGlobalAttendanceDialog();
    } catch (e) {
      print('❌ GLOBAL ATTENDANCE: Error checking: $e');
    }
  }

  /// Show attendance dialog on any screen
  static Future<void> _showGlobalAttendanceDialog() async {
    final ctx = navigatorKey.currentState?.context;
    if (ctx == null) {
      print('❌ GLOBAL ATTENDANCE: No context available');
      return;
    }

    if (_attendanceDialogShown) {
      print('⚠️ GLOBAL ATTENDANCE: Dialog already shown');
      return;
    }

    _attendanceDialogShown = true;
    print('🎯 GLOBAL ATTENDANCE: Showing dialog');

    try {
      await showDialog(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => GlobalAttendanceDialog(
          onAttendanceMarked: () {
            _attendanceDialogShown = false;
            print('✅ GLOBAL ATTENDANCE: Dialog completed');
          },
        ),
      );
    } catch (e) {
      print('❌ GLOBAL ATTENDANCE: Error showing dialog: $e');
      _attendanceDialogShown = false;
    }
  }

  /// Stop attendance checking (call on logout)
  static void stopAttendanceCheck() {
    _attendanceTimer?.cancel();
    _attendanceTimer = null;
    _attendanceDialogShown = false;
    print('🛑 GLOBAL ATTENDANCE: Stopped attendance checking');
  }

  /// Force show attendance dialog (for testing)
  static Future<void> forceShowAttendanceDialog() async {
    _attendanceDialogShown = false;
    await _showGlobalAttendanceDialog();
  }
}

/// Global Attendance Dialog Widget
class GlobalAttendanceDialog extends StatefulWidget {
  final VoidCallback onAttendanceMarked;

  const GlobalAttendanceDialog({super.key, required this.onAttendanceMarked});

  @override
  State<GlobalAttendanceDialog> createState() => _GlobalAttendanceDialogState();
}

class _GlobalAttendanceDialogState extends State<GlobalAttendanceDialog> {
  bool _isLoading = false;
  int _remainingSeconds = 60 * 60; // 1 hour
  Timer? _countdownTimer;
  bool _showAbsentReason = false;
  String? _selectedReason;
  final TextEditingController _customReasonController = TextEditingController();
  String? _assignedShift;
  DateTime? _shiftStartTime;

  final List<String> _absentReasons = [
    'Sick/Not feeling well',
    'Family emergency',
    'Transportation issue',
    'Personal matter',
    'Other (specify below)',
  ];

  @override
  void initState() {
    super.initState();
    _initializeDialog();
  }

  Future<void> _initializeDialog() async {
    await _fetchAssignedShift();
    if (mounted) {
      setState(() {
        _calculateRemainingTime();
      });
      _startCountdown();
    }
  }

  Future<void> _fetchAssignedShift() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final assignmentSnapshot = await FirebaseFirestore.instance
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: currentUser.uid)
          .where('is_current', isEqualTo: true)
          .limit(1)
          .get();

      if (assignmentSnapshot.docs.isNotEmpty) {
        final assignmentData = assignmentSnapshot.docs.first.data();
        _assignedShift = assignmentData['shift'] as String?;
        final startTime = assignmentData['start_time'] as String?;

        if (startTime != null) {
          final timeParts = startTime.split(':');
          final hour = int.parse(timeParts[0]);
          final minute = int.parse(timeParts[1]);
          final now = DateTime.now();

          _shiftStartTime = DateTime(
            now.year,
            now.month,
            now.day,
            hour,
            minute,
          );

          if (_assignedShift == '3rd' && now.hour < 6) {
            _shiftStartTime = _shiftStartTime!.subtract(
              const Duration(days: 1),
            );
          }
        }
      }
    } catch (e) {
      print('❌ GLOBAL ATTENDANCE DIALOG: Error fetching shift: $e');
    }
  }

  void _calculateRemainingTime() {
    final now = DateTime.now();
    final shift = _assignedShift ?? AttendanceCheckService.getCurrentShift();

    DateTime shiftStartTime;
    if (_shiftStartTime != null) {
      shiftStartTime = _shiftStartTime!;
    } else {
      if (shift == '1st') {
        shiftStartTime = DateTime(now.year, now.month, now.day, 6, 0);
      } else if (shift == '2nd') {
        shiftStartTime = DateTime(now.year, now.month, now.day, 14, 0);
      } else {
        shiftStartTime = DateTime(now.year, now.month, now.day, 22, 0);
        if (now.hour < 6) {
          shiftStartTime = shiftStartTime.subtract(const Duration(days: 1));
        }
      }
    }

    final elapsedTime = now.difference(shiftStartTime);
    final elapsedSeconds = elapsedTime.inSeconds;

    final totalSeconds = 60 * 60; // 1 hour
    _remainingSeconds = totalSeconds - elapsedSeconds;

    if (_remainingSeconds < 0) {
      _remainingSeconds = 0;
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
        if (mounted) {
          _autoCloseWithWarning();
        }
      }
    });
  }

  Future<void> _autoCloseWithWarning() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ You did not respond within 1 hour. Please contact your supervisor.',
              style: TextStyle(fontSize: 16),
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );

        Navigator.of(context).pop();
        widget.onAttendanceMarked();
      }
    } catch (e) {
      print('❌ GLOBAL ATTENDANCE DIALOG: Error closing: $e');
      if (mounted) {
        Navigator.of(context).pop();
        widget.onAttendanceMarked();
      }
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _markAttendance(bool isPresent) async {
    if (_isLoading) return;

    if (!isPresent && !_showAbsentReason) {
      setState(() {
        _showAbsentReason = true;
      });
      return;
    }

    if (!isPresent) {
      if (_selectedReason == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a reason for absence'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      if (_selectedReason == 'Other (specify below)' &&
          _customReasonController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please specify your reason'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String reason;
      if (isPresent) {
        reason = 'Marked present at shift start';
      } else {
        if (_selectedReason == 'Other (specify below)') {
          reason = _customReasonController.text.trim();
        } else {
          reason = _selectedReason!;
        }
      }

      await AttendanceCheckService.recordAttendance(
        isPresent: isPresent,
        reason: reason,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPresent
                  ? '✅ Attendance marked - You are present for your shift'
                  : '⚠️ You have been marked as absent',
              style: const TextStyle(fontSize: 16),
            ),
            backgroundColor: isPresent ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );

        Navigator.of(context).pop();
        widget.onAttendanceMarked();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error marking attendance: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _customReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shift = _assignedShift ?? AttendanceCheckService.getCurrentShift();
    final shiftName = shift == "1st"
        ? "1st Shift (6:00 AM - 2:00 PM)"
        : shift == "2nd"
        ? "2nd Shift (2:00 PM - 10:00 PM)"
        : "3rd Shift (10:00 PM - 6:00 AM)";

    return WillPopScope(
      onWillPop: () async => false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.only(
          left: 20,
          right: 20,
          top: 50,
          bottom: 100, // Leave space for bottom navigation
        ),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 600),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB3E0E8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.access_time_filled,
                    size: 50,
                    color: Color(0xFF00588E),
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  'Attendance Check',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00588E),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F4F8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    shiftName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF00588E),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  'Please confirm your attendance for your shift today.',
                  style: TextStyle(fontSize: 16, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Timer
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _remainingSeconds <= 60
                        ? Colors.red.withOpacity(0.1)
                        : const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _remainingSeconds <= 60
                          ? Colors.red
                          : Colors.orange,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        color: _remainingSeconds <= 60
                            ? Colors.red
                            : Colors.orange,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Time remaining: ${_formatTime(_remainingSeconds)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _remainingSeconds <= 60
                              ? Colors.red
                              : Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  'Please mark your attendance within 1 hour',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Buttons or Reason Selection
                if (_isLoading)
                  const CircularProgressIndicator(color: Color(0xFF00588E))
                else if (_showAbsentReason)
                  // Absent reason selection UI...
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Please select a reason for absence:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF00588E),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            hint: const Text('Select reason'),
                            value: _selectedReason,
                            items: _absentReasons.map((String reason) {
                              return DropdownMenuItem<String>(
                                value: reason,
                                child: Text(reason),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              setState(() {
                                _selectedReason = newValue;
                              });
                            },
                          ),
                        ),
                      ),
                      if (_selectedReason == 'Other (specify below)') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _customReasonController,
                          decoration: InputDecoration(
                            hintText: 'Enter your reason here...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          maxLines: 2,
                          maxLength: 100,
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _showAbsentReason = false;
                                  _selectedReason = null;
                                  _customReasonController.clear();
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                side: const BorderSide(color: Colors.grey),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Back',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: () => _markAttendance(false),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Confirm Absent',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () => _markAttendance(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF22688E),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 24,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'I am Present',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () => _markAttendance(false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cancel, color: Colors.white, size: 24),
                              SizedBox(width: 8),
                              Text(
                                'I am Absent',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------------- INCIDENT SERVICE ----------------------
class IncidentService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final Set<String> _shownIncidents = <String>{};
  static const String _incidentPrefsKey = 'shown_incidents';

  static Future<void> initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);

    await _notifications.initialize(settings);

    // Load previously shown incidents from persistent storage
    await _loadShownIncidents();
  }

  static Future<void> _loadShownIncidents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shownList = prefs.getStringList(_incidentPrefsKey) ?? [];
      _shownIncidents.addAll(shownList);
      print('📋 Loaded ${shownList.length} previously shown incidents');
    } catch (e) {
      print('❌ Error loading shown incidents: $e');
    }
  }

  static Future<void> _saveShownIncident(String incidentId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _shownIncidents.add(incidentId);

      // Keep only recent incidents (last 1000 to prevent unlimited growth)
      final recentIncidents = _shownIncidents.toList();
      if (recentIncidents.length > 1000) {
        recentIncidents.removeRange(0, recentIncidents.length - 1000);
        _shownIncidents.clear();
        _shownIncidents.addAll(recentIncidents);
      }

      await prefs.setStringList(_incidentPrefsKey, _shownIncidents.toList());
    } catch (e) {
      print('❌ Error saving shown incident: $e');
    }
  }

  static Future<void> showIncidentNotification({
    required String incidentId,
    required String title,
    required String description,
    String? houseName,
    String? timestamp,
  }) async {
    // Check if this incident has already been shown (persistent check)
    if (_shownIncidents.contains(incidentId)) {
      print('! Incident notification $incidentId already processed, skipping');
      return;
    }

    // Also check the temporary processed messages for this session
    if (_processedMessages.contains('incident_$incidentId')) {
      print(
        '! Incident notification $incidentId already processed this session, skipping',
      );
      return;
    }

    // Mark as processed in both temporary and persistent storage
    _processedMessages.add('incident_$incidentId');
    await _saveShownIncident(incidentId);
    _cleanupProcessedMessages();

    try {
      // New format: "Incident Report - House at Date Time" (matching emergency alert format)
      final displayTitle = houseName != null && timestamp != null
          ? 'Incident Report - $houseName at $timestamp'
          : 'Incident Report';

      // Use emergency-style notification channel for consistency
      const androidDetails = AndroidNotificationDetails(
        'emergency_channel', // Use same channel as emergency for consistency
        'Emergency & Incident Alerts',
        channelDescription:
            'Critical alerts for emergency situations and incident reports',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        showWhen: true,
        icon: '@mipmap/ic_launcher',
      );

      final notifDetails = NotificationDetails(android: androidDetails);

      await _notifications.show(
        incidentId.hashCode, // Use unique ID for each incident
        displayTitle,
        description,
        notifDetails,
        payload: incidentId,
      );

      print('✅ Incident notification shown: $incidentId - $displayTitle');
    } catch (e) {
      print('❌ Incident notification error: $e');
    }
  }
}

/// ---------------------- MAIN APP ----------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Only initialize Firebase if not already initialized
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('Firebase initialized successfully');
    } else {
      print('Firebase already initialized');
    }

    // Cancel all old WorkManager tasks (especially background_attendance_check)
    try {
      print('🧹 Canceling all old WorkManager tasks...');
      await Workmanager().cancelAll();
      print('✅ All WorkManager tasks canceled successfully');
    } catch (e) {
      print('❌ Failed to cancel WorkManager tasks: $e');
    }

    // Initialize task reminder service
    try {
      print('🔧 Starting TaskReminderService initialization...');
      await TaskReminderService().initialize();
      print('✅ TaskReminderService initialization completed');

      // Schedule reminders for existing upcoming tasks
      print('🔧 Scheduling reminders for existing tasks...');
      await TaskReminderService().scheduleAllUpcomingTaskReminders();
      print('✅ Existing task reminders scheduled');
    } catch (e) {
      print('❌ TaskReminderService initialization failed: $e');
      print('❌ Stack trace: ${StackTrace.current}');
    }

    // Start missed task monitor service (runs every 30 seconds)
    try {
      print('🔧 Starting MissedTaskMonitorService...');
      await MissedTaskMonitorService().startMonitoring();
      print('✅ MissedTaskMonitorService started successfully');
    } catch (e) {
      print('❌ MissedTaskMonitorService failed to start: $e');
    }

    // NOTE: Other services are initialized in AuthWrapper after user authentication

    // UNCOMMENT THE LINE BELOW TO CLEAR DATABASE AND CREATE ADMIN ACCOUNT (kung back to 002 uli increment start ng user)
    // WARNING: This will delete ALL user data!
    // await _initializeDatabase();
  } catch (e) {
    print('❌ Firebase init failed: $e');
  }

  await EmergencyService.initNotifications();
  await IncidentService.initNotifications();

  // <-- Add this for task notifications
  await NotificationService.init(navigatorKey: navigatorKey);

  // Initialize global attendance service
  print('🔧 Initializing Global Attendance Service...');
  await GlobalAttendanceService.initializeAttendanceCheck();
  print('✅ Global Attendance Service initialized');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => my_auth.AuthProvider()),
        ChangeNotifierProvider(create: (_) => AbsenceProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => my_auth.AuthProvider()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'ElderLink',
        theme: ThemeData(
          fontFamily: 'Poppins',
          textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 15)),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFA5D4DC)),
          inputDecorationTheme: const InputDecorationTheme(
            contentPadding: EdgeInsets.symmetric(vertical: 2, horizontal: 20),
            filled: true,
            fillColor: Color(0xFFC1E5E9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(30)),
              borderSide: BorderSide.none,
            ),
            hintStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
          useMaterial3: true,
        ),
        home: AuthWrapper(), // removed const
        routes: {
          '/get_started': (context) => GetStartedPage(),
          '/login': (context) => LoginScreen(),
          '/register_choose_role': (context) => RegisterChooseRoleScreen(),
          '/forgot_pass': (context) => ForgotPasswordScreen(),
          '/register_success': (context) => RegisterSuccessScreen(),
          '/caregiver_home': (context) => CaregiverHomeScreen(),
          '/nurse_home': (context) => NurseHomeScreen(),
        },
      ),
    );
  }
}
