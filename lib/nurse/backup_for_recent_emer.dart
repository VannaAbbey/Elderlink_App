import 'dart:typed_data'; 
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart'; // for fallback vibration
import 'edit_profile.dart';

class EmergencyScreen  extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _showCalendar = false;
  bool isSidebarOpen = false;

  String? nurseName;
  List<Map<String, dynamic>> emergencyAlerts = [];
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  String? _lastNotifiedAlertId;
  String? _lastViewedAlertId;
  bool _isModalShown = false;

  // Audio player for alarm
  final AudioPlayer _alarmPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _loadNurseData();
    _listenEmergencyAlerts();
  }

  /// Initialize notifications
  void _initNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);

    await flutterLocalNotificationsPlugin.initialize(settings);
  }

  /// Load nurse name from Firestore
  Future<void> _loadNurseData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
          setState(() {
            nurseName = "${doc['user_fname'] ?? ''} ${doc['user_lname'] ?? ''}";
          });
        }
      }
    } catch (e) {
      print("❌ Error loading nurse data: $e");
    }
  }

  /// Show notification + start alarm
  void _showNotification(String title, String body) async {
    final androidDetails = AndroidNotificationDetails(
      'emergency_channel',
      'Emergency Alerts',
      channelDescription: 'Notifications for emergency alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      fullScreenIntent: true,
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      notificationDetails,
      payload: 'emergency_alert',
    );

    // fallback vibration
    try {
      HapticFeedback.vibrate();
    } catch (_) {}

    // Start looping alarm
    _startAlarmLoop();
  }

  /// Start alarm loop
  void _startAlarmLoop() async {
    try {
      await _alarmPlayer.setSource(AssetSource('sounds/alarm.mp3'));
      _alarmPlayer.setReleaseMode(ReleaseMode.loop);
      await _alarmPlayer.resume();
    } catch (e) {
      debugPrint('❌ Failed to play alarm: $e');
    }
  }

  /// Stop alarm manually
  Future<void> _stopAlarm() async {
    try {
      await _alarmPlayer.stop();
    } catch (e) {
      debugPrint('❌ Failed to stop alarm: $e');
    }
  }

  /// Listen to emergency alerts in real-time
  void _listenEmergencyAlerts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseFirestore.instance
        .collection('emergency_alert')
        .where('user_id_nu', arrayContains: user.uid)
        .snapshots()
        .listen((snapshot) {
      final alerts = snapshot.docs
          .map((doc) => {...doc.data(), 'id': doc.id})
          .toList();

      alerts.sort((a, b) => (b['alert_timestamp'] as Timestamp)
          .compareTo(a['alert_timestamp'] as Timestamp));

      setState(() => emergencyAlerts = alerts);

      if (alerts.isNotEmpty) {
        final latest = alerts.first;

        if (_lastNotifiedAlertId != latest['id']) {
          _lastNotifiedAlertId = latest['id'];
          _showNotification(
            '🚨 Emergency Alert - ${latest['house_name'] ?? 'Unknown House'}',
            latest['alert_description'] ?? 'No description',
          );
        }

        if (_lastViewedAlertId != latest['id']) {
          _showLatestAlertModal(latest);
        }
      }
    });
  }

  Future<void> _loadEmergencyAlertsForDate(DateTime date) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final snap = await FirebaseFirestore.instance
          .collection('emergency_alert')
          .where('user_id_nu', arrayContains: user.uid)
          .get();

      final filtered = snap.docs
          .map((doc) => {...doc.data(), 'id': doc.id})
          .where((alert) {
        final ts = alert['alert_timestamp'] as Timestamp;
        final dt = ts.toDate();
        return dt.isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
            dt.isBefore(endOfDay);
      }).toList();

      filtered.sort((a, b) => (b['alert_timestamp'] as Timestamp)
          .compareTo(a['alert_timestamp'] as Timestamp));

      setState(() => emergencyAlerts = filtered);
    } catch (e) {
      print("❌ Error loading alerts for date: $e");
    }
  }

  void _pickDate() => setState(() => _showCalendar = true);

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      _showCalendar = false;
    });
    _loadEmergencyAlertsForDate(date);
  }

  void toggleSidebar() => setState(() => isSidebarOpen = !isSidebarOpen);

  void _showLatestAlertModal(Map<String, dynamic> alert) {
    if (_isModalShown || _lastViewedAlertId == alert['id']) return;

    _isModalShown = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final timestamp = (alert['alert_timestamp'] as Timestamp).toDate();
        return AlertDialog(
          title: const Text('🚨 Emergency Alert'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('House: ${alert['house_name'] ?? 'Unknown'}'),
              Text('Time: ${DateFormat.jm().format(timestamp)}'),
              const SizedBox(height: 10),
              Text(alert['alert_description'] ?? ''),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _markAlertAsViewed(alert['id']);
                await _stopAlarm();
                Navigator.of(context).pop();
                _isModalShown = false;
              },
              child: const Text('Mark as Viewed'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _markAlertAsViewed(String alertId) async {
    setState(() => _lastViewedAlertId = alertId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/background1.png',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: toggleSidebar,
                        child: const Icon(Icons.menu, size: 30, color: Color(0xFF00588E)),
                      ),
                      const Text(
                        'Emergency Report',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00588E),
                        ),
                      ),
                      const Icon(Icons.notifications, size: 30, color: Color(0xFF00588E)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search an Elderly...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('MMMM dd, yyyy').format(_selectedDate),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87),
                      ),
                      IconButton(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today,
                            color: Color(0xFF00588E), size: 30),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: emergencyAlerts.length,
                      itemBuilder: (context, index) {
                        final alert = emergencyAlerts[index];
                        final timestamp =
                            (alert['alert_timestamp'] as Timestamp).toDate();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('🚨 Emergency Alert',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.red)),
                              const SizedBox(height: 4),
                              Text('House: ${alert['house_name'] ?? 'Unknown'}'),
                              const Text('Reported by: Caregiver'),
                              Text('Time: ${DateFormat.jm().format(timestamp)}'),
                              const SizedBox(height: 4),
                              Text(alert['alert_description'] ?? ''),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showCalendar)
            GestureDetector(
              onTap: () => setState(() => _showCalendar = false),
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: CalendarDatePicker(
                      initialDate: _selectedDate,
                      firstDate: DateTime(_selectedDate.year - 1),
                      lastDate: DateTime(_selectedDate.year + 1),
                      onDateChanged: _onDateSelected,
                    ),
                  ),
                ),
              ),
            ),
          if (isSidebarOpen) _buildSidebarOverlay(),
        ],
      ),
    );
  }

  Widget _buildSidebarOverlay() {
    return Stack(
      children: [
        GestureDetector(onTap: toggleSidebar, child: Container(color: Colors.black54)),
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          child: Material(
            elevation: 5,
            borderRadius: const BorderRadius.only(
                topRight: Radius.circular(10), bottomRight: Radius.circular(10)),
            child: Container(
              width: 250,
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 50),
                  Text(
                    nurseName != null ? "Nurse $nurseName" : "No name found",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.edit, color: Color(0xFF00588E)),
                    title: const Text("Edit Profile"),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const EditProfile()));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings, color: Color(0xFF00588E)),
                    title: const Text("Settings"),
                    onTap: toggleSidebar,
                  ),
                  ListTile(
                    leading: const Icon(Icons.help, color: Color(0xFF00588E)),
                    title: const Text("Help & Support"),
                    onTap: toggleSidebar,
                  ),
                  const Divider(),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1D5B78),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 10, horizontal: 60),
                    ),
                    onPressed: toggleSidebar,
                    child: const Text('LOGOUT',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
