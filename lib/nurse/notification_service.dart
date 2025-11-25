import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

// Top-level function for Android Alarm Manager callback
@pragma('vm:entry-point')
void showMedicationNotificationCallback(
  int id,
  Map<String, dynamic>? params,
) async {
  final title = params?['title'] as String? ?? 'Medication Reminder';
  final body = params?['body'] as String? ?? 'Time for medication';
  final payload = params?['payload'] as String?;

  final notifications = FlutterLocalNotificationsPlugin();
  const androidDetails = AndroidNotificationDetails(
    'task_channel',
    'Medical Tasks',
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
    fullScreenIntent: true,
  );
  final details = NotificationDetails(android: androidDetails);

  await notifications.show(id, title, body, details, payload: payload);
}

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static String? _pendingPayload;

  static Future<void> init({
    required GlobalKey<NavigatorState> navigatorKey,
    Function(String?)? onNotificationTap,
    Function(String?)? onNotificationReceived,
  }) async {
    // Initialize Android Alarm Manager
    await AndroidAlarmManager.initialize();

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
        print('Notification tapped with payload: ${response.payload}');
        if (onNotificationTap != null) {
          if (navigatorKey.currentContext != null) {
            print('Calling onNotificationTap with context available');
            onNotificationTap(response.payload);
          } else {
            print('Context not available, storing pending payload');
            _pendingPayload = response.payload;
          }
        }
      },
    );

    // Ensure notifications are shown even when app is in foreground
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    // Initialize FCM with enhanced permissions and token management
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: true,
      carPlay: true,
      criticalAlert: true,
    );

    print('🔔 FCM permission requested');

    // AUTOMATIC TOKEN MANAGEMENT - Always get fresh token on app start
    try {
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        await _saveFCMToken(token);
        print('🎯 AUTOMATIC: Fresh FCM token obtained and saved on app start');
      } else {
        print('⚠️ Failed to get FCM token on app start');
      }
    } catch (e) {
      print('❌ Error getting initial FCM token: $e');
    }

    // AUTOMATIC TOKEN REFRESH - Listen for token updates (handles expiration automatically)
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      print('🔄 AUTOMATIC: FCM token refreshed due to expiration/update');
      _saveFCMToken(newToken);
    });

    // AUTOMATIC TOKEN VALIDATION - Set up periodic validation
    _setupPeriodicTokenValidation();

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  static String? getAndClearPendingPayload() {
    final payload = _pendingPayload;
    _pendingPayload = null;
    return payload;
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

    // 🔋 CRITICAL: Request to ignore battery optimizations
    // This ensures notifications work even when app is closed
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
      print(
        '🔋 Battery optimization exemption requested - CRITICAL for background notifications',
      );
    }

    print('✅ All notification permissions requested for background operation');
  }

  static Future<void> _firebaseMessagingBackgroundHandler(
    RemoteMessage message,
  ) async {
    print(
      '🔔 BACKGROUND: Handling message when app is closed/background: ${message.messageId}',
    );

    // Enhanced debugging for medication notifications
    print('🔍 BACKGROUND: Message data: ${message.data}');
    print('🔍 BACKGROUND: Notification title: ${message.notification?.title}');
    print('🔍 BACKGROUND: Notification body: ${message.notification?.body}');
    print('🔍 BACKGROUND: Message type: ${message.data['type']}');

    if (message.data['type'] == 'medication') {
      print('💊 BACKGROUND: MEDICATION NOTIFICATION RECEIVED!');
      print('💊 BACKGROUND: Medication: ${message.data['medicationName']}');
      print('💊 BACKGROUND: Elderly: ${message.data['elderlyName']}');
      print('💊 BACKGROUND: Scheduled time: ${message.data['scheduledTime']}');
      print(
        '💊 BACKGROUND: Notification type: ${message.data['notificationType']}',
      );
    }

    // CRITICAL: This runs even when app is completely closed!
    try {
      // Initialize notifications if not already done
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      await _notifications.initialize(
        InitializationSettings(android: androidSettings),
      );

      // ❌ REMOVED: Local notification that was creating duplicates
      // Firebase FCM already shows notifications automatically when app is in background
      // This local notification was creating duplicate "medication" notifications

      // Show HIGH PRIORITY notification that works when app is closed
      // if (message.notification != null) {
      //   await _showHighPriorityBackgroundNotification(
      //     title: message.notification!.title ?? 'ElderLink Alert',
      //     body: message.notification!.body ?? 'New notification received',
      //     data: message.data,
      //   );
      //   print('✅ BACKGROUND: Notification shown while app closed/background');
      //
      //   if (message.data['type'] == 'medication') {
      //     print('💊 BACKGROUND: MEDICATION NOTIFICATION SUCCESSFULLY SHOWN!');
      //   }
      // } else {
      //   print('⚠️ BACKGROUND: No notification content in message');
      // }

      print(
        '✅ BACKGROUND: FCM notification handled (Firebase shows automatically)',
      );
      if (message.data['type'] == 'medication') {
        print(
          '💊 BACKGROUND: MEDICATION NOTIFICATION RECEIVED - Firebase will show it',
        );
      }
    } catch (e) {
      print('❌ BACKGROUND: Error showing notification: $e');
    }
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    print('Handling foreground message: ${message.messageId}');

    // ❌ REMOVED: Local notification that was creating duplicates
    // Firebase FCM handles notifications properly - we don't need additional local ones
    // This was creating the second "medication" notification that users complained about

    // When app is in foreground, FCM doesn't show notifications automatically
    // So we need to show a local notification for foreground messages only
    // if (message.notification != null) {
    //   _showLocalNotification(
    //     title: message.notification!.title ?? 'Notification',
    //     body: message.notification!.body ?? '',
    //   );
    //   print('✅ Showed local notification for foreground FCM message');
    // }

    print(
      '✅ FOREGROUND: FCM notification received - no duplicate local notification',
    );
    if (message.data['type'] == 'medication') {
      print(
        '💊 FOREGROUND: MEDICATION NOTIFICATION RECEIVED - Firebase handles display',
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

  // High priority notification for background/app-closed scenarios
  static Future<void> _showHighPriorityBackgroundNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      // Determine channel based on notification type
      String channelId = 'emergency_channel';
      String channelName = 'Emergency Alerts';
      String channelDescription =
          'Critical notifications that work when app is closed';

      // Use medication channel for medication notifications
      if (data?['type'] == 'medication') {
        channelId = 'medication_channel';
        channelName = 'Medication Reminders';
        channelDescription =
            'Medication time notifications that work when app is closed';
      }

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        fullScreenIntent: true, // Shows over lockscreen
        showWhen: true,
        when: null,
        autoCancel: false, // Don't auto-dismiss
        ongoing: false,
        visibility: NotificationVisibility.public, // Show on lockscreen
        category: AndroidNotificationCategory.alarm, // High priority category
      );

      final notificationDetails = NotificationDetails(android: androidDetails);

      final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await _notifications.show(
        notificationId,
        title,
        body,
        notificationDetails,
        payload: data?.toString(),
      );

      print('🚨 HIGH PRIORITY notification shown: $title');
    } catch (e) {
      print('❌ Error showing high priority notification: $e');
    }
  }

  static Future<void> _saveFCMToken(String token) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId != null) {
        // Enhanced token saving with device info and validation
        await _firestore.collection('fcm_tokens').doc(currentUserId).set({
          'token': token,
          'updated_at': FieldValue.serverTimestamp(),
          'device_type': 'android',
          'app_version': '1.0.0',
          'is_active': true,
          'last_seen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)); // Use merge to preserve other fields

        print('✅ FCM Token saved/updated for user: $currentUserId');
        print('🔐 Token: ${token.substring(0, 20)}...');

        // Also trigger a token validation check
        await _validateAndRefreshToken();
      } else {
        print('❌ No current user, cannot save FCM token');
      }
    } catch (e) {
      print('❌ Error saving FCM token: $e');
    }
  }

  // New method to validate and refresh tokens periodically
  static Future<void> _validateAndRefreshToken() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      // Check if current token is still valid
      String? currentToken = await _firebaseMessaging.getToken();
      if (currentToken != null) {
        // Update last validation timestamp
        await _firestore.collection('fcm_tokens').doc(currentUserId).update({
          'last_validated': FieldValue.serverTimestamp(),
          'token': currentToken, // Refresh token
        });
        print('🔄 Token validated and refreshed for user: $currentUserId');
      }
    } catch (e) {
      print('⚠️ Error validating token: $e');
    }
  }

  // Method to manually refresh token (can be called when needed)
  static Future<void> refreshFCMToken() async {
    try {
      await _firebaseMessaging.deleteToken();
      String? newToken = await _firebaseMessaging.getToken();
      if (newToken != null) {
        await _saveFCMToken(newToken);
        print('🔄 FCM Token manually refreshed');
      }
    } catch (e) {
      print('❌ Error manually refreshing FCM token: $e');
    }
  }

  // Setup periodic token validation to ensure tokens stay fresh
  static void _setupPeriodicTokenValidation() {
    // Validate token every hour when app is active
    Stream.periodic(Duration(hours: 1)).listen((_) async {
      if (FirebaseAuth.instance.currentUser != null) {
        await _validateAndRefreshToken();
      }
    });

    // Also validate when app comes to foreground
    // Note: This would be enhanced with proper lifecycle handling in a production app
    print('⏰ Periodic FCM token validation setup complete');
  }

  // Call this method when nurse logs in to ensure fresh token
  static Future<void> ensureFreshTokenOnLogin() async {
    try {
      print('🔐 Ensuring fresh FCM token on nurse login...');

      // Force get fresh token
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        await _saveFCMToken(token);
        print('✅ Fresh FCM token ensured for logged-in nurse');
      }

      // Mark user as active in token record
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId != null) {
        await _firestore.collection('fcm_tokens').doc(currentUserId).update({
          'last_login': FieldValue.serverTimestamp(),
          'is_active': true,
          'login_count': FieldValue.increment(1),
        });
      }
    } catch (e) {
      print('❌ Error ensuring fresh token on login: $e');
    }
  }

  // Call this when nurse logs out to mark token as inactive
  static Future<void> deactivateTokenOnLogout() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId != null) {
        await _firestore.collection('fcm_tokens').doc(currentUserId).update({
          'is_active': false,
          'last_logout': FieldValue.serverTimestamp(),
        });
        print('🔓 FCM token marked as inactive on logout');
      }
    } catch (e) {
      print('❌ Error deactivating token on logout: $e');
    }
  }

  // Test method to verify background notifications work
  static Future<void> testBackgroundNotification() async {
    try {
      await _showHighPriorityBackgroundNotification(
        title: '🧪 TEST: Background Notification',
        body:
            'If you see this while app is closed, background notifications are working!',
        data: {'test': 'background_notification'},
      );
      print('🧪 Test background notification sent');
    } catch (e) {
      print('❌ Error sending test notification: $e');
    }
  }

  // Method to check if notifications will work in background
  static Future<bool> isBackgroundNotificationReady() async {
    try {
      // Check if all required permissions are granted
      final notificationGranted = await Permission.notification.isGranted;
      final batteryOptGranted =
          await Permission.ignoreBatteryOptimizations.isGranted;

      // Check if FCM token exists
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      bool tokenExists = false;
      if (currentUserId != null) {
        final tokenDoc = await _firestore
            .collection('fcm_tokens')
            .doc(currentUserId)
            .get();
        tokenExists = tokenDoc.exists && tokenDoc.data()?['token'] != null;
      }

      final isReady = notificationGranted && batteryOptGranted && tokenExists;

      print('📊 Background notification readiness:');
      print('   Notification permission: $notificationGranted');
      print('   Battery optimization exemption: $batteryOptGranted');
      print('   FCM token exists: $tokenExists');
      print('   Overall ready: $isReady');

      return isReady;
    } catch (e) {
      print('❌ Error checking background notification readiness: $e');
      return false;
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
    String? payload,
  }) async {
    // Don't schedule notifications for past times
    if (dateTime.isBefore(DateTime.now())) {
      return;
    }

    // Use Android Alarm Manager for reliable scheduling
    await AndroidAlarmManager.oneShotAt(
      dateTime,
      id,
      showMedicationNotificationCallback,
      params: {'title': title, 'body': body, 'payload': payload},
      exact: true,
      wakeup: true,
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
