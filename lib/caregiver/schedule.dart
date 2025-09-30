import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final user = FirebaseAuth.instance.currentUser;

  Map<String, dynamic>? scheduleData;
  String? houseName;

  @override
  void initState() {
    super.initState();
    fetchSchedule();
  }

  Future<void> fetchSchedule() async {
    if (user == null) return;

    try {
      final assignSnap = await FirebaseFirestore.instance
          .collection("cg_house_assign")
          .where("caregiver_id", isEqualTo: user!.uid)
          .where("is_current", isEqualTo: true)
          .limit(1)
          .get();

      if (assignSnap.docs.isNotEmpty) {
        final schedule = assignSnap.docs.first.data();

        // Fetch house by house_id
        final houseSnap = await FirebaseFirestore.instance
            .collection("house")
            .where("house_id", isEqualTo: schedule["house_id"])
            .limit(1)
            .get();

        setState(() {
          scheduleData = schedule;
          houseName = houseSnap.docs.isNotEmpty
              ? houseSnap.docs.first.data()["house_name"]
              : "Unknown House";
        });
      }
    } catch (e) {
      debugPrint("Error fetching schedule: $e");
    }
  }

  String getShiftTime(String shift) {
    switch (shift) {
      case "1st":
        return "06:00 AM - 02:00 PM";
      case "2nd":
        return "02:00 PM - 10:00 PM";
      case "3rd":
        return "10:00 PM - 06:00 AM";
      default:
        return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: Color(0xFF00588e),
    );

    return Scaffold(
      // White header with blue title + back button
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF00588e)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "My Schedule",
          style: TextStyle(
            color: Color(0xFF00588e),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      // Background image + content
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              "assets/images/background1.png",
              fit: BoxFit.cover,
            ),
          ),

          // Foreground content
          scheduleData == null
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Card(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // House
                          Row(
                            children: const [
                              Icon(Icons.home, color: Color(0xFF00588e), size: 30),
                              SizedBox(width: 8),
                              Text(
                                "House Assigned:",
                                style: labelStyle,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.only(left: 32.0),
                            child: Text(
                              houseName ?? "Loading...",
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588e),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Days assigned
                          Row(
                            children: const [
                              Icon(Icons.calendar_today,
                                  color: Color(0xFF00588e), size: 24),
                              SizedBox(width: 10),
                              Text(
                                "Days Assigned:",
                                style: labelStyle,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.only(left: 34.0),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: (() {
                                final daysOrder = [
                                  "Monday",
                                  "Tuesday",
                                  "Wednesday",
                                  "Thursday",
                                  "Friday",
                                  "Saturday",
                                  "Sunday"
                                ];

                                final assignedDays =
                                    (scheduleData?["days_assigned"]
                                            as List<dynamic>?)
                                        ?.cast<String>() ??
                                        [];

                                assignedDays.sort((a, b) =>
                                    daysOrder.indexOf(a)
                                        .compareTo(daysOrder.indexOf(b)));

                                return assignedDays
                                    .map((day) => Chip(
                                          label: Text(day),
                                          backgroundColor:
                                              const Color(0xFFE6F3FA),
                                          labelStyle: const TextStyle(
                                            color: Color(0xFF00588e),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ))
                                    .toList();
                              })(),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Shift
                          Row(
                            children: const [
                              Icon(Icons.schedule, color: Color(0xFF00588e)),
                              SizedBox(width: 8),
                              Text(
                                "Shift Time:",
                                style: labelStyle,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.only(left: 34.0),
                            child: Text(
                              getShiftTime(scheduleData?["shift"] ?? ""),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588e),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
