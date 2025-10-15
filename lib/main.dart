import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
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
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'providers/auth_provider.dart' as my_auth;
import 'nurse/notification_service.dart';
import 'services/cg_services/task_reminder_service.dart';
import 'services/cg_services/missed_task_monitor_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Top-level background message handler required by firebase_messaging.
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized in background isolate
  try {
    await Firebase.initializeApp();
  } catch (_) {}

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

    const androidDetails = AndroidNotificationDetails(
      'emergency_channel',
      'Emergency Alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      ongoing: false,
    );

    final details = NotificationDetails(android: androidDetails);
    await localNotifications.show(
      message.hashCode,
      title,
      body,
      details,
      payload: data['alertId'] ?? data['alert_id'] ?? '',
    );
  } catch (e) {
    print('❌ Background message handling failed: $e');
  }
}

/// ---------------------- EMERGENCY SERVICE ----------------------
class EmergencyService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static bool _modalOpen = false;

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
        final notification = message.notification;
        final data = message.data;
        final title = notification?.title ?? data['title'] ?? 'Notification';
        String body = notification?.body ?? data['body'] ?? '';

        // If body is empty, try to fetch an emergency or incident doc using ids
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
                if (composed.isNotEmpty) {
                  body = composed;
                }
              }
            } catch (e) {
              print('❌ Error fetching emergency doc for FCM message: $e');
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
                  if (composed.isNotEmpty) {
                    body = composed;
                  }
                }
              } catch (e) {
                print('❌ Error fetching incident doc for FCM message: $e');
              }
            }
          }
        }

        // Check if this is an emergency alert
        final alertId = data['alertId'] ?? data['alert_id'] ?? '';
        if (alertId.isNotEmpty) {
          // For emergency alerts, show modal immediately
          print('🚨 Received FCM emergency alert, showing modal');
          EmergencyService.showEmergencyAlert(
            alertId: alertId,
            description: body,
          );
        } else {
          // For other messages, show local notification
          try {
            const androidDetails = AndroidNotificationDetails(
              'fcm_channel',
              'Push Notifications',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
            );
            final details = NotificationDetails(android: androidDetails);
            await _notifications.show(
              message.hashCode,
              title,
              body,
              details,
              payload: data['alertId'] ?? data['alert_id'] ?? '',
            );
          } catch (e) {
            print('❌ Error showing local notif from FCM: $e');
          }
        }
      });

      // When the app is opened from a notification
      FirebaseMessaging.onMessageOpenedApp.listen((
        RemoteMessage message,
      ) async {
        final data = message.data;
        final alertId = data['alertId'] ?? data['alert_id'] ?? '';
        if (alertId != null && alertId.toString().isNotEmpty) {
          await _showModal(alertId.toString());
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
          final data = message.data;
          final alertId = data['alertId'] ?? data['alert_id'] ?? '';
          if (alertId != null && alertId.toString().isNotEmpty) {
            // Delay slightly to allow navigator to be ready
            Future.delayed(const Duration(milliseconds: 500), () async {
              await _showModal(alertId.toString());
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
    if (_modalOpen) {
      print('⚠️ Modal already open, skipping');
      return;
    }
    _modalOpen = true;
    print('✅ Modal flag set to open');

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

      try {
        print('🔊 Attempting to play alarm sound');
        _audioPlayer.setReleaseMode(ReleaseMode.loop);
        await _audioPlayer.play(AssetSource('sounds/alarm.mp3'));
        print('✅ Alarm sound started');
      } catch (e) {
        print('❌ AudioPlayer error: $e');
      }

      const android = AndroidNotificationDetails(
        'emergency_channel',
        'Emergency Alerts',
        importance: Importance.max,
        priority: Priority.high,
        playSound: false,
        ongoing: true,
      );

      final notifDetails = NotificationDetails(android: android);

      try {
        await _notifications.show(
          0,
          '🚨 Emergency Alert - $houseName at $formattedTime',
          finalDescription,
          notifDetails,
          payload: alertId,
        );
        print('✅ Notification shown');
      } catch (e) {
        print('❌ Notification error: $e');
      }

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
      _modalOpen = false; // Reset flag on error
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
      print('🔄 Modal flag reset to false');
    }
  }

  static Future<void> stopAlarm() async {
    await _audioPlayer.stop();
    await _notifications.cancelAll();
    _modalOpen = false;
  }
}

/// ---------------------- INCIDENT SERVICE ----------------------
class IncidentService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);

    await _notifications.initialize(settings);
  }

  static Future<void> showIncidentNotification({
    required String incidentId,
    required String title,
    required String description,
    String? houseName,
    String? timestamp,
  }) async {
    try {
      final displayTitle = houseName != null && timestamp != null
          ? '$title - $houseName at $timestamp'
          : title;

      const androidDetails = AndroidNotificationDetails(
        'incident_channel',
        'Incident Alerts',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      );

      final notifDetails = NotificationDetails(android: androidDetails);

      await _notifications.show(
        0,
        displayTitle,
        description,
        notifDetails,
        payload: incidentId,
      );
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
