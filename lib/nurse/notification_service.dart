import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> init({Function(String?)? onNotificationTap}) async {
    tz.initializeTimeZones();

    // Request notification permissions
    await _requestPermissions();

    // Initialize local notifications
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();

    await _notifications.initialize(
      InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (onNotificationTap != null) {
          onNotificationTap(response.payload);
        }
      },
    );

    // Initialize FCM
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Get FCM token and save it
    String? token = await _firebaseMessaging.getToken();
    if (token != null) {
      await _saveFCMToken(token);
    }

    // Listen for token updates
    FirebaseMessaging.instance.onTokenRefresh.listen(_saveFCMToken);

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  static Future<void> _requestPermissions() async {
    // Request notification permission for local notifications
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    // Also request exact alarm permission for Android 12+
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
  }

  static Future<void> _firebaseMessagingBackgroundHandler(
    RemoteMessage message,
  ) async {
    print('Handling background message: ${message.messageId}');
    // Show local notification for background messages
    if (message.notification != null) {
      await _showLocalNotification(
        title: message.notification!.title ?? 'Notification',
        body: message.notification!.body ?? '',
      );
    }
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    print('Handling foreground message: ${message.messageId}');
    if (message.notification != null) {
      _showLocalNotification(
        title: message.notification!.title ?? 'Notification',
        body: message.notification!.body ?? '',
      );
    }
  }

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
  }) async {
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000, // Unique ID
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'fcm_channel',
          'Push Notifications',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> _saveFCMToken(String token) async {
    try {
      // You'll need to get the current user ID here
      // For now, we'll store it in a general collection
      await _firestore.collection('fcm_tokens').doc('current_user').set({
        'token': token,
        'updated_at': FieldValue.serverTimestamp(),
      });
      print('FCM Token saved: $token');
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  static Future<void> sendPushNotification({
    required String title,
    required String body,
    String? taskId,
    Map<String, dynamic>? taskDetails,
  }) async {
    try {
      // Get the FCM token
      DocumentSnapshot tokenDoc = await _firestore
          .collection('fcm_tokens')
          .doc('current_user')
          .get();

      if (!tokenDoc.exists) {
        print('No FCM token found');
        return;
      }

      String token = tokenDoc.get('token');

      // For now, we'll use a simple approach
      // In production, you'd use Firebase Cloud Functions or a server
      // to send the notification securely

      // This is a placeholder - you'll need to implement server-side sending
      print('Would send push notification to token: $token');
      print('Title: $title');
      print('Body: $body');
      print('Task ID: $taskId');
      print('Task Details: $taskDetails');

      // For immediate testing, you could use Firebase Admin SDK
      // or set up Cloud Functions
    } catch (e) {
      print('Error sending push notification: $e');
    }
  }

  static Future<void> scheduleTaskNotification({
    required int id,
    required String title,
    required String body,
    required DateTime dateTime,
  }) async {
    await _notifications.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(dateTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'task_channel',
          'Medical Tasks',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelNotification(int id) async {
    try {
      await _notifications.cancel(id);
    } catch (e) {
      // Ignore cancellation errors but log for debugging
      print('Error cancelling notification $id: $e');
    }
  }

  static Future<void> showMedicalTaskNotification({
    required String taskId,
    required String title,
    required String description,
    String? elderlyName,
    String? time,
  }) async {
    try {
      final displayTitle = elderlyName != null && time != null
          ? 'Medical Task - $elderlyName at $time'
          : 'Medical Task: $title';

      const androidDetails = AndroidNotificationDetails(
        'medical_task_channel',
        'Medical Task Alerts',
        channelDescription: 'Notifications for medical tasks',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        fullScreenIntent: true, // Show over lockscreen like emergencies
      );

      final notifDetails = NotificationDetails(android: androidDetails);

      await _notifications.show(
        taskId.hashCode,
        displayTitle,
        description,
        notifDetails,
        payload: taskId,
      );
    } catch (e) {
      print('❌ Medical task notification error: $e');
    }
  }
}
