import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'caregiver_sidebar.dart';
import 'notifications.dart';

class IncidentScreen extends StatefulWidget {
  const IncidentScreen({super.key});

  @override
  State<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends State<IncidentScreen> {
  bool isSidebarOpen = false;
  void toggleSidebar() => setState(() => isSidebarOpen = !isSidebarOpen);

  String? selectedElderlyId;
  String? selectedElderlyName;
  final TextEditingController reportController = TextEditingController();
  bool isLoading = true;
  bool isOnDuty = false;
  List<Map<String, dynamic>> elderlyList = [];

  // caregiver name
  String? caregiverName;

  // Shift state
  DateTime shiftStart = DateTime.now();
  DateTime shiftEnd = DateTime.now();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadElderlyAssignments();
    _loadCaregiverName();
  }

  Future<void> _loadCaregiverName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        setState(() {
          caregiverName = "${doc['user_fname']} ${doc['user_lname']}";
        });
      }
    }
  }

  Future<void> _loadElderlyAssignments() async {
    setState(() => isLoading = true);

    final now = DateTime.now();
    final dayName = DateFormat('EEEE').format(now);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          elderlyList = [];
          isOnDuty = false;
          isLoading = false;
        });
        return;
      }

      final caregiverId = user.uid;

      final houseSnapshot = await _firestore
          .collection('cg_house_assign')
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('is_current', isEqualTo: true)
          .where('is_absent', isEqualTo: false)
          .limit(1)
          .get();

      if (houseSnapshot.docs.isEmpty) {
        setState(() {
          elderlyList = [];
          isOnDuty = false;
          isLoading = false;
        });
        return;
      }

      final houseData = houseSnapshot.docs.first.data();
      final daysAssigned = List<String>.from(houseData['days_assigned'] ?? []);
      final houseId = houseData['house_id'] as String;
      final startDate = (houseData['start_date'] as Timestamp).toDate();
      final endDate = (houseData['end_date'] as Timestamp).toDate();

      if (now.isBefore(startDate) || now.isAfter(endDate)) {
        setState(() {
          elderlyList = [];
          isOnDuty = false;
          isLoading = false;
        });
        return;
      }

      if (!daysAssigned.contains(dayName)) {
        setState(() {
          elderlyList = [];
          isOnDuty = false;
          isLoading = false;
        });
        return;
      }

      final timeRange = Map<String, dynamic>.from(
        houseData['time_range'] ?? {},
      );
      int startHour = 6, startMinute = 0, endHour = 14, endMinute = 0;
      if (timeRange.isNotEmpty) {
        final startParts = (timeRange['start'] as String).split(':');
        final endParts = (timeRange['end'] as String).split(':');
        startHour = int.parse(startParts[0]);
        startMinute = int.parse(startParts[1]);
        endHour = int.parse(endParts[0]);
        endMinute = int.parse(endParts[1]);
      }

      DateTime calculatedShiftStart = DateTime(
        now.year,
        now.month,
        now.day,
        startHour,
        startMinute,
      );
      DateTime calculatedShiftEnd = DateTime(
        now.year,
        now.month,
        now.day,
        endHour,
        endMinute,
      );

      if (calculatedShiftEnd.isBefore(calculatedShiftStart)) {
        if (now.isBefore(calculatedShiftEnd)) {
          calculatedShiftStart = calculatedShiftStart.subtract(
            const Duration(days: 1),
          );
        } else {
          calculatedShiftEnd = calculatedShiftEnd.add(const Duration(days: 1));
        }
      }

      final isWithinShift =
          !(now.isBefore(calculatedShiftStart) ||
              now.isAfter(calculatedShiftEnd));

      if (!isWithinShift) {
        setState(() {
          elderlyList = [];
          isOnDuty = false;
          isLoading = false;
        });
        return;
      }

      final assignSnapshot = await _firestore
          .collection('elderly_caregiver_assign')
          .where('caregiver_id', isEqualTo: caregiverId)
          .where('day', isEqualTo: dayName)
          .get();

      List<Map<String, dynamic>> elderlyDetails = [];

      if (assignSnapshot.docs.isNotEmpty) {
        final elderlyIds = assignSnapshot.docs
            .map((doc) => doc.data()['elderly_id'] as String)
            .toSet()
            .toList();

        for (int i = 0; i < elderlyIds.length; i += 30) {
          final chunk = elderlyIds.skip(i).take(30).toList();
          final chunkSnapshot = await _firestore
              .collection('elderly')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();

          for (var doc in chunkSnapshot.docs) {
            final data = doc.data();
            if (data['house_id'] == houseId) {
              elderlyDetails.add({
                'id': doc.id,
                'name':
                    '${data['elderly_fname'] ?? ''} ${data['elderly_lname'] ?? ''}',
              });
            }
          }
        }

        elderlyDetails.sort(
          (a, b) => (a['name'] as String).compareTo(b['name'] as String),
        );
      }

      setState(() {
        elderlyList = elderlyDetails;
        isOnDuty = true;
        isLoading = false;
        selectedElderlyId = null;
        selectedElderlyName = null;
        shiftStart = calculatedShiftStart;
        shiftEnd = calculatedShiftEnd;
      });
    } catch (e) {
      setState(() {
        elderlyList = [];
        isOnDuty = false;
        isLoading = false;
        selectedElderlyId = null;
        selectedElderlyName = null;
      });
    }
  }

  /// 🔔 Function to check caregiver schedule + shift
  Future<void> checkScheduleAndShowError(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // ✅ Get caregiver ID
      final caregiverId = user.uid;

      // ✅ Get caregiver schedule (assuming may "caregiver_schedules" collection)
      final scheduleSnap = await FirebaseFirestore.instance
          .collection("caregiver_schedules")
          .where("caregiver_id", isEqualTo: caregiverId)
          .limit(1)
          .get();

      if (scheduleSnap.docs.isEmpty) {
        if (mounted) _showError(context, "No schedule found for this caregiver.");
        return;
      }

      final scheduleData = scheduleSnap.docs.first.data();
      final scheduledDay = scheduleData["day"]; // e.g., "Monday"
      final shiftTime = scheduleData["shift_time"]; // e.g., "08:00-16:00"

      // ✅ Check if today is caregiver’s schedule
      final today = DateTime.now();
      final todayDay = _getDayName(today.weekday);

      if (todayDay != scheduledDay) {
        if (mounted) {
          _showError(
            context,
            "You are not scheduled today.\n\nYour schedule: $scheduledDay ($shiftTime)",
          );
        }
        return;
      }

      // ✅ Optional: Check if current time is within shift
      final now = TimeOfDay.fromDateTime(today);
      final parts = shiftTime.split("-");
      if (parts.length == 2) {
        final startParts = parts[0].split(":");
        final endParts = parts[1].split(":");

        final start = TimeOfDay(
          hour: int.parse(startParts[0]),
          minute: int.parse(startParts[1]),
        );
        final end = TimeOfDay(
          hour: int.parse(endParts[0]),
          minute: int.parse(endParts[1]),
        );

        if (!_isWithinShift(now, start, end)) {
          if (mounted) {
            _showError(
              context,
              "You are outside your shift time.\n\n $shiftTime",
            );
          }
          return;
        }
      }

      // ✅ If all good (within schedule & shift), proceed normally
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Access granted — within schedule ✅")),
        );
      }
    } catch (e) {
      if (mounted) _showError(context, "Error checking schedule: $e");
    }
  }

  /// 🔴 Error Dialog UI
  void _showError(BuildContext context, String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 12),
            const Text(
              "Incident Report Not Sent",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
          ],
        ),
        actions: [
          Center(
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF00588e),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 60,
                  vertical: 10,
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "OK",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 🔧 Helper: Get day name
  String _getDayName(int weekday) {
    switch (weekday) {
      case 1:
        return "Monday";
      case 2:
        return "Tuesday";
      case 3:
        return "Wednesday";
      case 4:
        return "Thursday";
      case 5:
        return "Friday";
      case 6:
        return "Saturday";
      case 7:
        return "Sunday";
      default:
        return "";
    }
  }

  /// 🔧 Helper: Check if time is within shift
  bool _isWithinShift(TimeOfDay now, TimeOfDay start, TimeOfDay end) {
    final nowMinutes = now.hour * 60 + now.minute;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;

    return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
  }

  /// ⚠️ Warning Dialog (Out of Shift)
  void _showWarningDialog(BuildContext context, String shiftRange) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 12),
            const Text(
              "Incident Report Not Sent",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "You are not allowed to forward an incident report right now.\n\n"
              "$shiftRange",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
          ],
        ),
        actions: [
          Center(
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF00588e),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 50,
                  vertical: 10,
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "OK",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkShiftAndShowDialog(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final currentDay = DateFormat('EEEE').format(now); // e.g. "Monday"

    // 1. Get caregiver assignment
    final query = await FirebaseFirestore.instance
        .collection('cg_house_assign')
        .where('caregiver_id', isEqualTo: user.uid)
        .where('is_current', isEqualTo: true)
        .where('is_absent', isEqualTo: false)
        .get();

    if (query.docs.isEmpty) {
      _showWarningDialog(context, "No active shift found.");
      return;
    }

    final data = query.docs.first.data();
    final List daysAssigned = data['days_assigned'] ?? [];
    final String shift = data['shift'] ?? "";
    final Map<String, dynamic> timeRange = Map<String, dynamic>.from(
      data['time_range'],
    );

    // 2. Check if today is included
    if (!daysAssigned.contains(currentDay)) {
      _showWarningDialog(context, "You are not scheduled today.");
      return;
    }

    // 3. Parse time range
    final startParts = (timeRange['start'] as String).split(":");
    final endParts = (timeRange['end'] as String).split(":");

    DateTime start = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(startParts[0]),
      int.parse(startParts[1]),
    );
    DateTime end = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(endParts[0]),
      int.parse(endParts[1]),
    );

    // Handle overnight shift
    if (shift == "3rd" && end.isBefore(start)) {
      end = end.add(const Duration(days: 1));
    }

    // 4. Always update the state so modal can use it
    setState(() {
      shiftStart = start;
      shiftEnd = end;
    });

    // Format for modal
    final shiftRange =
        "${DateFormat.jm().format(shiftStart)} - ${DateFormat.jm().format(shiftEnd)}";

    // Show modal
    if (now.isBefore(start) || now.isAfter(end)) {
      _showWarningDialog(context, "Your shift: $shiftRange");
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {

    Future<void> handleLogout() async {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/get_started',
        (route) => false,
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/background1.png',
            fit: BoxFit.cover,
          ),
        ),
        Column(
          children: [
            const SizedBox(height: 16),
            Expanded(
              child: Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  backgroundColor: const Color(0x00FFFFFF),
                  title: const Text(
                    'Incident Report',
                    style: TextStyle(
                      color: Color(0xFF00588e),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  centerTitle: true,
                  leading: IconButton(
                    icon: const Icon(Icons.menu, color: Color(0xFF00588e)),
                    onPressed: toggleSidebar,
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(
                        Icons.notifications,
                        color: Color(0xFF00588e),
                        size: 35,
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const NotificationsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                body: Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.person, color: Color(0xFF00588e)),
                              SizedBox(width: 8),
                              Text(
                                'Name of the Elderly:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF00588e),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Color(0xFFE6F3FA),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedElderlyId,
                                hint: Text(
                                  isLoading
                                      ? 'Loading...'
                                      : (isOnDuty
                                            ? 'Select Elderly'
                                            : 'Not your schedule today/shift'),
                                ),
                                isExpanded: true,
                                icon: const Icon(
                                  Icons.arrow_drop_down,
                                  color: Color(0xFF00588e),
                                ),
                                menuMaxHeight: 200,
                                items: elderlyList.map((elderly) {
                                  return DropdownMenuItem<String>(
                                    value: elderly['id'],
                                    child: Text(elderly['name']),
                                  );
                                }).toList(),
                                onChanged: isOnDuty
                                    ? (value) {
                                        setState(() {
                                          selectedElderlyId = value;
                                          selectedElderlyName = elderlyList
                                              .firstWhere(
                                                (e) => e['id'] == value,
                                              )['name'];
                                        });
                                      }
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            decoration: BoxDecoration(
                              color: Color(0xFFE6F3FA),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                              controller: reportController,
                              maxLines: 20,
                              enabled: isOnDuty,
                              decoration: const InputDecoration(
                                hintText: 'Write the incident report here.',
                                hintStyle: TextStyle(
                                  fontStyle: FontStyle.italic,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: isOnDuty
                                  ? () {
                                      final formattedDate = DateFormat(
                                        'MM/dd/yy | h:mm a',
                                      ).format(DateTime.now());

                                      showDialog(
                                        context: context,
                                        barrierDismissible: true,
                                        builder: (BuildContext ctx) {
                                          bool acknowledged = false;
                                          return StatefulBuilder(
                                            builder: (context, setState) {
                                              return Dialog(
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                insetPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 24,
                                                      vertical: 40,
                                                    ),
                                                child: Container(
                                                  width: 380,

                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                        20, // left
                                                        2, // top
                                                        20, // right
                                                        20, // bottom
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          20,
                                                        ),
                                                  ),
                                                  child: SingleChildScrollView(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        // Exit button row (uplifted sa taas right)
                                                        Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .end,
                                                          children: [
                                                            IconButton(
                                                              padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                              constraints:
                                                                  const BoxConstraints(),
                                                              icon: const Icon(
                                                                Icons.close,
                                                                size: 28,
                                                                color: Color(
                                                                  0xFF00588e,
                                                                ),
                                                              ),
                                                              onPressed: () =>
                                                                  Navigator.of(
                                                                    context,
                                                                  ).pop(),
                                                            ),
                                                          ],
                                                        ),

                                                        // Header text row (centered)
                                                        Center(
                                                          child: Text(
                                                            'Confirmation Form',
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 24,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: Color(
                                                                    0xFF00588e,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),

                                                        const SizedBox(
                                                          height: 12,
                                                        ),
                                                        const Divider(),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),

                                                        const Text(
                                                          'Please review the following information before submitting:',
                                                          textAlign:
                                                              TextAlign.justify,
                                                          style: TextStyle(
                                                            fontSize: 15,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 12,
                                                        ),
                                                        Row(
                                                          children: [
                                                            const Icon(
                                                              Icons.person,
                                                              color: Color(
                                                                0xFF00588e,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            const Text(
                                                              'Elderly Name:',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Color(
                                                                  0xFF00588e,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 4,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                selectedElderlyName ??
                                                                    '',
                                                                style:
                                                                    const TextStyle(
                                                                      fontSize:
                                                                          15,
                                                                    ),
                                                                overflow:
                                                                    TextOverflow
                                                                        .visible,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 10,
                                                        ),
                                                        Row(
                                                          children: [
                                                            const Icon(
                                                              Icons.access_time,
                                                              color: Color(
                                                                0xFF00588e,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            const Text(
                                                              'Date & Time:',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Color(
                                                                  0xFF00588e,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 4,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                formattedDate,
                                                                style:
                                                                    const TextStyle(
                                                                      fontSize:
                                                                          15,
                                                                    ),
                                                                overflow:
                                                                    TextOverflow
                                                                        .visible,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 20,
                                                        ),
                                                        Row(
                                                          children: [
                                                            const Icon(
                                                              Icons.warning,
                                                              color: Color(
                                                                0xFF00588e,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            const Text(
                                                              'Incident Description:',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Color(
                                                                  0xFF00588e,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 10,
                                                        ),
                                                        Container(
                                                          decoration:
                                                              BoxDecoration(
                                                                color: Color(
                                                                  0xFFE6F3FA,
                                                                ),
                                                                boxShadow: [
                                                                  BoxShadow(
                                                                    color: Colors
                                                                        .black12,
                                                                  ),
                                                                ],
                                                              ),
                                                          padding:
                                                              const EdgeInsets.all(
                                                                10,
                                                              ),
                                                          child: SizedBox(
                                                            height: 120,
                                                            child: Align(
                                                              alignment:
                                                                  Alignment
                                                                      .topLeft,
                                                              child: Text(
                                                                reportController
                                                                    .text,
                                                                style: const TextStyle(
                                                                  fontStyle:
                                                                      FontStyle
                                                                          .italic,
                                                                  fontSize: 15,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 20,
                                                        ),
                                                        Row(
                                                          children: [
                                                            const Icon(
                                                              Icons.person,
                                                              color: Color(
                                                                0xFF00588e,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            const Text(
                                                              'Caregiver:',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Color(
                                                                  0xFF00588e,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 4,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                caregiverName ??
                                                                    'Loading...',
                                                                style:
                                                                    const TextStyle(
                                                                      fontSize:
                                                                          15,
                                                                    ),
                                                                overflow:
                                                                    TextOverflow
                                                                        .visible,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 16,
                                                        ),
                                                        Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Checkbox(
                                                              value:
                                                                  acknowledged,
                                                              activeColor:
                                                                  const Color(
                                                                    0xFF00588e,
                                                                  ),
                                                              onChanged: (val) {
                                                                setState(() {
                                                                  acknowledged =
                                                                      val ??
                                                                      false;
                                                                });
                                                              },
                                                            ),
                                                            const Expanded(
                                                              child: Padding(
                                                                padding:
                                                                    EdgeInsets.only(
                                                                      right:
                                                                          8.0,
                                                                    ),
                                                                child: Text(
                                                                  'I acknowledge that the information provided is accurate and complete. I accept full responsibility and understand that this submission is final and cannot be modified.',
                                                                  textAlign:
                                                                      TextAlign
                                                                          .justify,
                                                                  style:
                                                                      TextStyle(
                                                                        fontSize:
                                                                            13,
                                                                      ),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 20,
                                                        ),
                                                        Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceEvenly,
                                                          children: [
                                                            // ✅ Submit Button (left side)
                                                            Flexible(
                                                              child: SizedBox(
                                                                height: 44,
                                                                child: ElevatedButton(
                                                                // Inside your Submit button onPressed
                                                                onPressed:
                                                                    (acknowledged &&
                                                                        selectedElderlyName !=
                                                                            null &&
                                                                        selectedElderlyName!
                                                                            .isNotEmpty &&
                                                                        reportController
                                                                            .text
                                                                            .trim()
                                                                            .isNotEmpty)
                                                                    ? () async {
                                                                        Navigator.of(
                                                                          ctx,
                                                                        ).pop(); // Close modal first

                                                                        final user = FirebaseAuth
                                                                            .instance
                                                                            .currentUser;
                                                                        if (user ==
                                                                                null ||
                                                                            selectedElderlyId ==
                                                                                null) {
                                                                          return;
                                                                        }

                                                                        final formattedDate =
                                                                            DateTime.now();

                                                                        try {
                                                                          // 1️⃣ Get caregiver info
                                                                          final caregiverId =
                                                                              user.uid;

                                                                          // 2️⃣ Get house_id of the elderly
                                                                          final elderlyDoc = await _firestore
                                                                              .collection(
                                                                                'elderly',
                                                                              )
                                                                              .doc(
                                                                                selectedElderlyId,
                                                                              )
                                                                              .get();
                                                                          final houseId =
                                                                              elderlyDoc['house_id'] ??
                                                                              '';

                                                                          // 3️⃣ Find nurses scheduled today & currently on shift
                                                                          final todayDay =
                                                                              DateFormat(
                                                                                'EEEE',
                                                                              ).format(
                                                                                DateTime.now(),
                                                                              );
                                                                          final nowTime =
                                                                              DateFormat(
                                                                                'HH:mm',
                                                                              ).format(
                                                                                DateTime.now(),
                                                                              );

                                                                          final nurseQuery = await _firestore
                                                                              .collection(
                                                                                'nurse_shift_assign',
                                                                              )
                                                                              .where(
                                                                                'is_current',
                                                                                isEqualTo: true,
                                                                              )
                                                                              .get();

                                                                          List<
                                                                            String
                                                                          >
                                                                          nurseIdsToSend =
                                                                              [];
                                                                          for (var doc
                                                                              in nurseQuery.docs) {
                                                                            final daysAssigned =
                                                                                List<
                                                                                  String
                                                                                >.from(
                                                                                  doc['days_assigned'] ??
                                                                                      [],
                                                                                );
                                                                            final startTime =
                                                                                doc['start_time'] ??
                                                                                "00:00";
                                                                            final endTime =
                                                                                doc['end_time'] ??
                                                                                "23:59";
                                                                            if (daysAssigned.contains(
                                                                              todayDay,
                                                                            )) {
                                                                              // check if now is within shift
                                                                              final start =
                                                                                  DateFormat(
                                                                                    'HH:mm',
                                                                                  ).parse(
                                                                                    startTime,
                                                                                  );
                                                                              final end =
                                                                                  DateFormat(
                                                                                    'HH:mm',
                                                                                  ).parse(
                                                                                    endTime,
                                                                                  );
                                                                              final nowParsed =
                                                                                  DateFormat(
                                                                                    'HH:mm',
                                                                                  ).parse(
                                                                                    nowTime,
                                                                                  );
                                                                              bool
                                                                              inShift = false;

                                                                              if (end.isBefore(
                                                                                start,
                                                                              )) {
                                                                                // overnight shift
                                                                                inShift =
                                                                                    nowParsed.isAfter(
                                                                                      start,
                                                                                    ) ||
                                                                                    nowParsed.isBefore(
                                                                                      end,
                                                                                    );
                                                                              } else {
                                                                                inShift =
                                                                                    nowParsed.isAfter(
                                                                                      start,
                                                                                    ) &&
                                                                                    nowParsed.isBefore(
                                                                                      end,
                                                                                    );
                                                                              }

                                                                              if (inShift) {
                                                                                nurseIdsToSend.add(
                                                                                  doc['nurse_id'],
                                                                                );
                                                                              }
                                                                            }
                                                                          }

                                                                          // 4️⃣ Save incident report for each nurse
                                                                          // 4️⃣ Save incident report once, with all nurses in an array
                                                                          if (nurseIdsToSend
                                                                              .isNotEmpty) {
                                                                            final incidentDocRef = _firestore
                                                                                .collection(
                                                                                  'incident_report',
                                                                                )
                                                                                .doc(); // Auto ID
                                                                            await incidentDocRef.set({
                                                                              'elderly_id': selectedElderlyId,
                                                                              'house_id': houseId,
                                                                              'incident_date_time': formattedDate,
                                                                              'incident_desc': reportController.text.trim(),
                                                                              'incident_id': incidentDocRef.id,
                                                                              'incident_verify': true,
                                                                              'user_id_cg': caregiverId,
                                                                              'user_id_nu': nurseIdsToSend, // ✅ array of all nurses
                                                                            });
                                                                          }

                                                                          // 5️⃣ Clear fields + show success
                                                                          reportController
                                                                              .clear();
                                                                          setState(() {
                                                                            selectedElderlyId =
                                                                                null;
                                                                            selectedElderlyName =
                                                                                null;
                                                                          });

                                                                          // ✅ Success notification at top
                                                                          if (mounted) {
                                                                            ScaffoldMessenger.of(
                                                                              context,
                                                                            ).showSnackBar(
                                                                              SnackBar(
                                                                                content: const Text(
                                                                                  "Incident report submitted successfully.",
                                                                                ),
                                                                                behavior: SnackBarBehavior.floating,
                                                                                margin: const EdgeInsets.fromLTRB(
                                                                                  16,
                                                                                  50,
                                                                                  16,
                                                                                  0,
                                                                                ),
                                                                                backgroundColor: const Color(
                                                                                  0xFF00588e,
                                                                                ),
                                                                                shape: RoundedRectangleBorder(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    10,
                                                                                  ),
                                                                                ),
                                                                                duration: const Duration(
                                                                                  seconds: 3,
                                                                                ),
                                                                              ),
                                                                            );
                                                                          }
                                                                        } catch (
                                                                          e
                                                                        ) {
                                                                          if (mounted) {
                                                                            ScaffoldMessenger.of(
                                                                              context,
                                                                            ).showSnackBar(
                                                                              SnackBar(
                                                                                content: Text(
                                                                                  "Failed to submit report: $e",
                                                                                ),
                                                                                behavior: SnackBarBehavior.floating,
                                                                                margin: const EdgeInsets.fromLTRB(
                                                                                  16,
                                                                                  50,
                                                                                  16,
                                                                                  0,
                                                                                ),
                                                                                backgroundColor: Colors.redAccent,
                                                                                shape: RoundedRectangleBorder(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    10,
                                                                                  ),
                                                                                ),
                                                                                duration: const Duration(
                                                                                  seconds: 4,
                                                                                ),
                                                                              ),
                                                                            );
                                                                          }
                                                                        }
                                                                      }
                                                                    : null, // ❌ Disabled kapag kulang
                                                                style: ElevatedButton.styleFrom(
                                                                  backgroundColor:
                                                                      (acknowledged &&
                                                                          selectedElderlyName !=
                                                                              null &&
                                                                          selectedElderlyName!
                                                                              .isNotEmpty &&
                                                                          reportController
                                                                              .text
                                                                              .trim()
                                                                              .isNotEmpty)
                                                                      ? const Color(
                                                                          0xFF00588e,
                                                                        ) // Blue kapag enabled
                                                                      : Colors
                                                                            .grey, // Grey kapag disabled
                                                                  shape: RoundedRectangleBorder(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          18,
                                                                        ),
                                                                  ),
                                                                ),
                                                                child: const Text(
                                                                  'Submit',
                                                                  style: TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                            ),

                                                            // ❌ Cancel Button (right side)
                                                            Flexible(
                                                              child: SizedBox(
                                                                height: 44,
                                                                child: ElevatedButton(
                                                                  onPressed: () {
                                                                    Navigator.of(
                                                                      ctx,
                                                                    ).pop();
                                                                  },
                                                                  style: ElevatedButton.styleFrom(
                                                                    backgroundColor:
                                                                        const Color(
                                                                          0xFF900000,
                                                                        ),
                                                                    shape: RoundedRectangleBorder(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            18,
                                                                          ),
                                                                    ),
                                                                  ),
                                                                  child: const Text(
                                                                    'Cancel',
                                                                    style: TextStyle(
                                                                      color: Colors
                                                                          .white,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          );
                                        },
                                      );
                                    }
                                  : () {
                                      // ❌ If not on duty, show warning

                                      _checkShiftAndShowDialog(context);
                                      // ✅ instead of SnackBar
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00588e),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                elevation: 4,
                              ),
                              child: const Text(
                                'Forward the Report',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        CaregiverSidebar(
          onLogout: handleLogout,
          isSidebarOpen: isSidebarOpen,
          toggleSidebar: toggleSidebar,
          parentContext: context,
        ),
      ],
    );
  }
}
