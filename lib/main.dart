import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'widgets/auth_wrapper.dart';
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
import 'package:firebase_auth/firebase_auth.dart';
import 'providers/auth_provider.dart' as my_auth;
import 'nurse/notification_service.dart';

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

        try {
          // Show a local notification mirroring the FCM message
          const androidDetails = AndroidNotificationDetails(
            'emergency_channel',
            'Emergency Alerts',
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
  }) async {
    if (_modalOpen) return;
    _modalOpen = true;

    final doc = await FirebaseFirestore.instance
        .collection('emergency_alert')
        .doc(alertId)
        .get();

    if (!doc.exists) {
      _modalOpen = false;
      return;
    }

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
        houseName = houseDoc.docs.first.data()['house_name'] ?? 'Unknown house';
      }
    }

    final timestampRaw = data['alert_timestamp']?.toDate();
    final formattedTime = timestampRaw != null
        ? DateFormat('M/dd/yyyy | h:mm a').format(timestampRaw)
        : 'Unknown time';

    // Compose description: prefer provided description, but fall back to
    // emergency_type and additional_info values (value-only, no labels)
    String finalDescription = description.toString().trim();
    if (finalDescription.isEmpty ||
        finalDescription.toLowerCase() == 'no description') {
      final et = (data['emergency_type'] ?? '').toString().trim();
      final ai = (data['additional_info'] ?? '').toString().trim();
      String composed = '';
      if (et.isNotEmpty) composed = et;
      if (ai.isNotEmpty) {
        composed = composed.isNotEmpty ? '$composed - $ai' : ai;
      }
      finalDescription = composed.isNotEmpty ? composed : 'No description';
    }

    try {
      _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('sounds/alarm.mp3'));
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
    } catch (e) {
      print('❌ Notification error: $e');
    }

    await _showModal(
      alertId,
      description: finalDescription,
      timestamp: formattedTime,
    );
  }

  static Future<void> _showModal(
    String alertId, {
    String description = '',
    String timestamp = '',
  }) async {
    final ctx = navigatorKey.currentState?.context;
    if (ctx == null) {
      _modalOpen = false;
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('emergency_alert')
          .doc(alertId)
          .get();

      if (!doc.exists) return;

      final data = doc.data()!;
      final descriptionData = data['alert_description'] ?? 'No description';
      final emergencyType = data['emergency_type'] ?? '';
      final additionalInfo = data['additional_info'] ?? '';
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

      await showDialog(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => EmergencyScreenModal(
          alertId: alertId,
          alertDescription: descriptionData,
          alertTimestamp: formattedTime,
          houseName: houseName,
          caregiverName: caregiverName,
          emergencyType: emergencyType,
          additionalInfo: additionalInfo,
        ),
      );
    } catch (e) {
      print('❌ Error showing emergency modal: $e');
    } finally {
      _modalOpen = false;
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
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('✅ Firebase initialized');
    } else {
      print('⚠️ Firebase already initialized');
    }
  } catch (e) {
    print('❌ Firebase init failed: $e');
  }

  await EmergencyService.initNotifications();
  await IncidentService.initNotifications();

  // <-- Add this for task notifications
  await NotificationService.init();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static DateTime? _lastIncidentTime; // store latest notified incident

  void _listenForEmergencies() {
    try {
      FirebaseFirestore.instance
          .collection('emergency_alert')
          .where(
            'alert_viewed',
            isEqualTo: false,
          ) // Only listen for unviewed alerts
          .orderBy('alert_timestamp', descending: true)
          .snapshots()
          .listen((snapshot) {
            final currentUserId = FirebaseAuth.instance.currentUser?.uid;
            for (var doc in snapshot.docs) {
              final data = doc.data();
              final alertId = doc.id;
              final emergencyType = data['emergency_type'] ?? 'Emergency Alert';
              final additionalInfo = data['additional_info'] ?? '';
              final description = additionalInfo.isNotEmpty
                  ? '$emergencyType - $additionalInfo'
                  : emergencyType;
              final assignedNurseId = data['user_id_nu'] as String?;

              if (currentUserId != null && assignedNurseId == currentUserId) {
                EmergencyService.showEmergencyAlert(
                  alertId: alertId,
                  description: description,
                );
              }
            }
          });
    } catch (e) {
      print('❌ Firestore emergency listener error: $e');
    }
  }

  void _listenForIncidents() {
    try {
      FirebaseFirestore.instance
          .collection('incident_report')
          .orderBy('incident_date_time', descending: true)
          .snapshots()
          .listen((snapshot) async {
            final currentUserId = FirebaseAuth.instance.currentUser?.uid;

            for (var doc in snapshot.docs) {
              final data = doc.data();
              final incidentId = doc.id;
              final incidentType = data['incident_type'] ?? 'No incident type';
              final additionalInfo = data['additional_info'] ?? '';
              final description = additionalInfo.isNotEmpty
                  ? '$incidentType - $additionalInfo'
                  : incidentType;
              final timestampRaw = data['incident_date_time']?.toDate();
              if (timestampRaw == null) continue;

              // skip if already notified
              if (MyApp._lastIncidentTime != null &&
                  !timestampRaw.isAfter(MyApp._lastIncidentTime!)) {
                continue;
              }

              final houseId = data['house_id'];
              String houseName = 'Unknown house';
              if (houseId != null) {
                final houseDoc = await FirebaseFirestore.instance
                    .collection('house')
                    .where('house_id', isEqualTo: houseId.toString())
                    .limit(1)
                    .get();
                if (houseDoc.docs.isNotEmpty) {
                  houseName =
                      houseDoc.docs.first.data()['house_name'] ??
                      'Unknown house';
                }
              }

              final nurseData = data['user_id_nu'];
              List<String> nurseArray = [];
              if (nurseData is List) {
                nurseArray = List<String>.from(nurseData);
              } else if (nurseData is String) {
                nurseArray = [nurseData];
              }
              if (currentUserId != null && nurseArray.contains(currentUserId)) {
                final formattedTime = DateFormat('h:mm a').format(timestampRaw);
                await IncidentService.showIncidentNotification(
                  incidentId: incidentId,
                  title: '📝 Incident Report',
                  description: description,
                  houseName: houseName,
                  timestamp: formattedTime,
                );

                // update last notified timestamp
                if (MyApp._lastIncidentTime == null ||
                    timestampRaw.isAfter(MyApp._lastIncidentTime!)) {
                  MyApp._lastIncidentTime = timestampRaw;
                }
              }
            }
          });
    } catch (e) {
      print('❌ Firestore incident listener error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    _listenForEmergencies();
    _listenForIncidents();

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
