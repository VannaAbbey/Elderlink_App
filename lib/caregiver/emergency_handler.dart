import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'emergency_modal.dart'; // <-- UI layout ng modal

/// Main entry para sa Emergency button
Future<void> openEmergencyIfAllowed(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    _showError(context, "You are not logged in.");
    return;
  }

  final today = DateTime.now();
  final todayName = _getDayName(today.weekday); // e.g. Monday
  final now = TimeOfDay.fromDateTime(today);

  // 🔹 Hanapin assignment ng caregiver
  final cgAssignSnap = await FirebaseFirestore.instance
      .collection("cg_house_assign")
      .where("caregiver_id", isEqualTo: user.uid)
      .where("is_current", isEqualTo: true)
      .limit(1)
      .get();

  if (cgAssignSnap.docs.isEmpty) {
    _showError(context, "No caregiver assignment found.");
    return;
  }

  final assign = cgAssignSnap.docs.first.data();
  final List daysAssigned = assign["days_assigned"];
  final String shift = assign["shift"];
  final Map<String, dynamic> timeRange = assign["time_range"];
  final String houseId = assign["house_id"];

  // 🔹 Check kung pasok sa schedule today
  if (!daysAssigned.contains(todayName)) {
    // Sort schedule sa natural order ng week
    final sortedDays = List<String>.from(daysAssigned)
      ..sort((a, b) => _dayOrder[a]!.compareTo(_dayOrder[b]!));

    _showError(
      context,
      "It is not your schedule today.\n\n✅ Your schedule: ${sortedDays.join(", ")}",
    );
    return;
  }

  // 🔹 Check kung pasok sa oras ng shift
  final start = _parseTimeOfDay(timeRange["start"]);
  final end = _parseTimeOfDay(timeRange["end"]);

  bool inShift;
  if (shift == "3rd") {
    // special case: 22:00 – 06:00 crosses midnight
    inShift = now.hour >= start.hour || now.hour < end.hour;
  } else {
    inShift = (now.hour >= start.hour && now.hour < end.hour);
  }

  if (!inShift) {
    _showError(
      context,
      "It is not your shift right now.\n\n✅ Your shift: $shift (${_formatToAMPM(timeRange["start"])} - ${_formatToAMPM(timeRange["end"])})",
    );
    return;
  }

  // ✅ Allowed → convert houseId → house name
  final String houseName = houseIdToName[houseId] ?? "Unknown House";

  // ✅ Kunin caregiver display name
  final cgName = await _getCaregiverName(user.uid);

  // ✅ Open emergency modal with caregiver name
  final result = await showEmergencyModal(
    context,
    defaultHouse: houseName,
    caregiverName: cgName, // <-- ipapasa sa UI
  );

  if (result != null) {
    // ✅ Hanapin nurses na naka-duty today at this shift
    final nurseQuery = await FirebaseFirestore.instance
        .collection("house_shift_assignments")
        .where("user_type", isEqualTo: "nurse")
        .where("is_current", isEqualTo: true)
        .get();

    List<String> activeNurseIds = [];

    for (var doc in nurseQuery.docs) {
      final data = doc.data();

      final List assignedDays = (data["days_assigned"] ?? []) as List;
      final String startStr = data["start_time"];
      final String endStr = data["end_time"];
      final String nurseId = data["nurse_id"];
      final String nurseShift = data["shift"];

      // check if today is assigned
      if (!assignedDays.contains(todayName)) continue;

      // check if time fits
      final start = _parseTimeOfDay(startStr);
      final end = _parseTimeOfDay(endStr);
      bool inShift;

      if (nurseShift == "3rd") {
        // 22:00 – 06:00 case
        inShift = now.hour >= start.hour || now.hour < end.hour;
      } else {
        inShift = (now.hour >= start.hour && now.hour < end.hour);
      }

      if (inShift) {
        activeNurseIds.add(nurseId);
      }
    }

    if (activeNurseIds.isEmpty) {
      _showError(context, "No nurse is currently on duty for this shift.");
      return;
    }

    // ✅ Save to Firestore with updated schema - create separate record for each nurse
    for (final nurseId in activeNurseIds) {
      await FirebaseFirestore.instance.collection("emergency_alert").add({
        "alert_id": "EA${DateTime.now().millisecondsSinceEpoch}_$nurseId",
        "emergency_type": result["type"],
        "additional_info": result["additionalInfo"],
        "alert_timestamp": DateTime.now(),
        "alert_viewed": false,
        "house_id": [houseNameToId[result["houseName"]] ?? ""],
        "house_name": result["houseName"],
        "user_id_cg": user.uid,
        "user_id_nu": nurseId,
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "🚨 Emergency alert sent to ${activeNurseIds.length} nurse(s)!",
        ),
      ),
    );
  }
}

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
            "Emergency Access Denied",
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
              backgroundColor: Color(0xFF00588e),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 10),
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

TimeOfDay _parseTimeOfDay(String hhmm) {
  final parts = hhmm.split(":");
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

/// 🔹 Convert "14:00" → "2:00 PM"
String _formatToAMPM(String hhmm) {
  try {
    final parts = hhmm.split(":");
    final dt = DateTime(2025, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
    return DateFormat.jm().format(dt);
  } catch (e) {
    return hhmm;
  }
}

/// 🔹 Mapping House ID → House Name
const Map<String, String> houseIdToName = {
  "H001": "St. Sebastian",
  "H002": "St. Emmanuel",
  "H003": "St. Charbell",
  "H004": "St. Rose",
  "H005": "St. Gabriel",
};

/// 🔹 Reverse mapping House Name → House ID
final Map<String, String> houseNameToId = houseIdToName.map(
  (key, value) => MapEntry(value, key),
);

/// 🔹 Para maayos ang pagkakasunod ng araw
const Map<String, int> _dayOrder = {
  "Monday": 1,
  "Tuesday": 2,
  "Wednesday": 3,
  "Thursday": 4,
  "Friday": 5,
  "Saturday": 6,
  "Sunday": 7,
};

// ✅ Kunin caregiver display name
Future<String> _getCaregiverName(String uid) async {
  try {
    final userDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .get();

    if (userDoc.exists) {
      final data = userDoc.data()!;

      final fname = data["user_fname"] ?? "";
      final lname = data["user_lname"] ?? "";

      if (fname.isNotEmpty || lname.isNotEmpty) {
        return "$fname $lname".trim();
      }

      // fallback if walang fname/lname
      return data["user_email"] ?? "Unknown Caregiver";
    } else {
      return "Unknown Caregiver";
    }
  } catch (e) {
    print("Error fetching caregiver name: $e");
    return "Unknown Caregiver";
  }
}
