import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Initialize notifications (call sa initState)
void initEmergencyNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);

  await flutterLocalNotificationsPlugin.initialize(
    settings,
  );
}

/// Show emergency alert
Future<void> showEmergencyAlert(String title, String body) async {
  // Custom vibration pattern
  final vibrationPattern = Int64List.fromList([0, 1000, 500, 1000, 500, 1000]);

  // Android notification details
  final androidDetails = AndroidNotificationDetails(
    'emergency_channel',
    'Emergency Alerts',
    channelDescription: 'Notifications for emergency alerts',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    fullScreenIntent: true, // pop-up over lockscreen
    enableVibration: true,
    vibrationPattern: vibrationPattern,
    sound: RawResourceAndroidNotificationSound('siren'), // put siren.mp3 in android/app/src/main/res/raw
  );

  final notificationDetails = NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    0,
    title,
    body,
    notificationDetails,
    payload: 'emergency_alert',
  );
}
