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
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'providers/auth_provider.dart' as my_auth;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// ---------------------- EMERGENCY SERVICE ----------------------
class EmergencyService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static bool _modalOpen = false;

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
  }

  static Future<void> showEmergencyAlert({
    required String alertId,
    required String description,
    required String timestamp,
  }) async {
    if (_modalOpen) return;
    _modalOpen = true;

    // Start looping alarm
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
        '🚨 Emergency Alert - $houseName at $timestamp',
        description,
        notifDetails,
        payload: alertId,
      );
    } catch (e) {
      print('❌ Notification error: $e');
    }

    await _showModal(alertId, description: description, timestamp: timestamp);
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
      final description = data['alert_description'] ?? 'No description';
      final timestampRaw = data['alert_timestamp']?.toDate();
      final timestamp = timestampRaw != null
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
          alertDescription: description,
          alertTimestamp: timestamp,
          houseName: houseName,
          caregiverName: caregiverName,
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
  }) async {
    try {
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
        title,
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

  // Safe Firebase initialization
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
    if (e.toString().contains('[core/duplicate-app]')) {
      print('⚠️ Firebase already initialized (caught duplicate)');
    } else {
      print('❌ Firebase init failed: $e');
    }
  }

  // Initialize notifications
  await EmergencyService.initNotifications();
  await IncidentService.initNotifications();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  void _listenForEmergencies() {
    try {
      FirebaseFirestore.instance
          .collection('emergency_alert')
          .orderBy('alert_timestamp', descending: true)
          .snapshots()
          .listen((snapshot) {
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final alertId = doc.id;
          final description = data['alert_description'] ?? 'No description';
          final timestamp =
              data['alert_timestamp']?.toDate().toString() ?? '';
          final nurseArray = List<String>.from(data['user_id_nu'] ?? []);

          if (currentUserId != null && nurseArray.contains(currentUserId)) {
            EmergencyService.showEmergencyAlert(
              alertId: alertId,
              description: description,
              timestamp: timestamp,
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
          .listen((snapshot) {
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final incidentId = doc.id;
          final description = data['incident_desc'] ?? 'No description';
          final timestampRaw = data['incident_date_time']?.toDate();
          final timestamp = timestampRaw != null
              ? DateFormat('h:mm a').format(timestampRaw)
              : '';

          final nurseArray = List<String>.from(data['user_id_nu'] ?? []);

          if (currentUserId != null && nurseArray.contains(currentUserId)) {
            IncidentService.showIncidentNotification(
              incidentId: incidentId,
              title: '📝 Incident Report at $timestamp',
              description: description,
            );
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
          colorScheme:
              ColorScheme.fromSeed(seedColor: const Color(0xFFA5D4DC)),
          inputDecorationTheme: const InputDecorationTheme(
            contentPadding:
                EdgeInsets.symmetric(vertical: 2, horizontal: 20),
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
        home: const AuthWrapper(),
        routes: {
          '/get_started': (context) => const GetStartedPage(),
          '/login': (context) => const LoginScreen(),
          '/register_choose_role': (context) =>
              const RegisterChooseRoleScreen(),
          '/forgot_pass': (context) => const ForgotPasswordScreen(),
          '/register_success': (context) =>
              const RegisterSuccessScreen(),
          '/caregiver_home': (context) => const CaregiverHomeScreen(),
          '/nurse_home': (context) => const NurseHomeScreen(),
        },
      ),
    );
  }
}
