import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'emergency_modal.dart'; // <-- UI layout ng modal
import '../services/cg_services/caregiver_shift_log_service.dart'; // <-- New unified logging service
import '../providers/cg_providers/absence_provider.dart';

// Helper function to show absence dialog
void _showAbsenceDialog(BuildContext context, String absenceType) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Row(
          children: [
            Icon(
              absenceType == 'leave' ? Icons.event_busy : Icons.cancel_outlined,
              color: Colors.orange,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                absenceType == 'leave' ? 'On Leave Today' : 'Marked Absent Today',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'You are currently Absent/On Leave for the day, come back soon!',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(); // Close dialog
            },
            child: const Text(
              'OK',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Main entry para sa Emergency button
Future<void> openEmergencyIfAllowed(BuildContext context) async {
  // Check if caregiver is absent first
  final absenceProvider = Provider.of<AbsenceProvider>(context, listen: false);
  if (absenceProvider.isAbsentToday) {
    _showAbsenceDialog(context, absenceProvider.absenceType ?? 'absent');
    return;
  }

  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    if (context.mounted) _showError(context, "You are not logged in.");
    return;
  }

  final today = DateTime.now();
  final now = TimeOfDay.fromDateTime(today);

  // 🔹 Hanapin assignment ng caregiver
  final cgAssignSnap = await FirebaseFirestore.instance
      .collection("house_shift_assignments")
      .where("user_id", isEqualTo: user.uid)
      .where("user_type", isEqualTo: "caregiver")
      .where("is_current", isEqualTo: true)
      .limit(1)
      .get();

  if (cgAssignSnap.docs.isEmpty) {
    if (context.mounted) _showError(context, "No caregiver assignment found.");
    return;
  }

  final assign = cgAssignSnap.docs.first.data();
  
  // 🔹 Null safety checks for all required fields
  final daysAssigned = assign["days_assigned"] as List<dynamic>?;
  final shift = assign["shift"] as String?;
  final startTime = assign["start_time"] as String?;
  final endTime = assign["end_time"] as String?;
  final houseId = assign["house_id"] as String?;
  
  if (daysAssigned == null || shift == null || startTime == null || endTime == null || houseId == null) {
    if (context.mounted) _showError(context, "Invalid assignment data. Please contact administrator.");
    return;
  }

  // 🔹 Parse shift times
  final start = _parseTimeOfDay(startTime);
  final end = _parseTimeOfDay(endTime);

  // 🔹 Determine if this is an overnight shift
  final isOvernightShift = end.hour < start.hour || (end.hour == start.hour && end.minute <= start.minute);
  
  // 🔹 For overnight shifts, determine which day to check based on current time
  String todayName;
  if (isOvernightShift && today.hour >= 0 && today.hour < end.hour) {
    // Current time is in the "end period" of an overnight shift (e.g., 12:01 AM - 6:00 AM)
    // Check if the previous day is assigned (e.g., if it's Monday 1 AM, check if Sunday is assigned)
    final previousDay = today.subtract(const Duration(days: 1));
    todayName = _getDayName(previousDay.weekday);
  } else {
    // Regular shift or "start period" of overnight shift or after shift ends
    todayName = _getDayName(today.weekday);
  }

  // 🔹 Check kung pasok sa schedule today
  if (!daysAssigned.contains(todayName)) {
    // Sort schedule sa natural order ng week
    final sortedDays = List<String>.from(daysAssigned)
      ..sort((a, b) => _dayOrder[a]!.compareTo(_dayOrder[b]!));

    if (context.mounted) {
      _showError(
        context,
        "It is not your schedule today.\n\n✅ Your schedule: ${sortedDays.join(", ")}",
      );
    }
    return;
  }

  bool inShift;
  if (shift == "3rd") {
    // special case: 22:00 – 06:00 crosses midnight
    inShift = now.hour >= start.hour || now.hour < end.hour;
  } else {
    inShift = (now.hour >= start.hour && now.hour < end.hour);
  }

  if (!inShift) {
    if (context.mounted) {
      _showError(
        context,
        "It is not your shift right now.\n\nYour shift: $shift (${_formatToAMPM(startTime)} - ${_formatToAMPM(endTime)})",
      );
    }
    return;
  }

  // ✅ Allowed → convert houseId → house name
  final String houseName = houseIdToName[houseId] ?? "Unknown House";

  // ✅ Kunin caregiver display name
  final cgName = await _getCaregiverName(user.uid);

  // ✅ Open emergency modal with caregiver name
  if (!context.mounted) return;
  final result = await showEmergencyModal(
    context,
    defaultHouse: houseName,
    caregiverName: cgName, // <-- ipapasa sa UI
  );

  if (result != null) {
  // ✅ Hanapin nurses na naka-duty today at this shift
  final nurseQuery = await FirebaseFirestore.instance
      .collection("nurse_shift_assign")
      .where("is_current", isEqualTo: true)
      .get();

  List<String> activeNurseIds = [];

  for (var doc in nurseQuery.docs) {
    final data = doc.data();

    final assignedDays = (data["days_assigned"] as List<dynamic>?) ?? [];
    final startStr = data["start_time"] as String?;
    final endStr = data["end_time"] as String?;
    final nurseId = data["nurse_id"] as String?;
    final nurseShift = data["shift"] as String?;
    
    // Skip if missing critical data
    if (startStr == null || endStr == null || nurseId == null || nurseShift == null) {
      continue;
    }

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
    if (context.mounted) _showError(context, "No nurse is currently on duty for this shift.");
    return;
  }

  // ✅ Save to Firestore with BOTH house_id & house_name
  await FirebaseFirestore.instance.collection("emergency_alert").add({
    "alert_id": "EA${DateTime.now().millisecondsSinceEpoch}",
    "emergency_type": result["emergencyType"] ?? "", // Main field for emergency type
    "additional_info": result["description"] ?? "", // Optional additional information
    "alert_timestamp": DateTime.now(),
    "alert_verify": false,
    "house_id": houseNameToId[result["houseName"]] ?? "",
    "house_name": result["houseName"] ?? "",
    "caregiver_name": result["caregiverName"] ?? "", // Add caregiver name field
    "user_id_cg": user.uid,
    "user_id_nu": FieldValue.arrayUnion(activeNurseIds), // ✅ force array save
  });

  // ✅ Also save to unified shift logs collection
  try {
    final emergencyType = result["emergencyType"] as String? ?? "";
    final description = result["description"] as String? ?? "";
    final caregiverName = result["caregiverName"] as String? ?? "Unknown";
    
    await CaregiverShiftLogService.createEmergencyAlertLog(
      caregiverId: user.uid,
      emergencyType: emergencyType,
      description: description,
      caregiverFname: caregiverName.split(' ').first, // Extract first name
    );
    print('✅ Emergency alert logged to shift logs successfully');
  } catch (e) {
    print('❌ Error logging emergency alert to shift logs: $e');
    // Don't fail the entire operation if logging fails
  }

  // Fetch nurse names to display in dialog
  List<String> nurseNames = [];
  for (String nurseId in activeNurseIds) {
    try {
      final nurseDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(nurseId)
          .get();
      if (nurseDoc.exists) {
        final nurseFname = nurseDoc['user_fname'] ?? '';
        final nurseLname = nurseDoc['user_lname'] ?? '';
        final fullName = '$nurseFname $nurseLname'.trim();
        if (fullName.isNotEmpty) {
          nurseNames.add(fullName);
        }
      }
    } catch (e) {
      print('❌ Error fetching nurse name: $e');
    }
  }

  // Show success dialog with nurse names
  if (context.mounted) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 32,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Alert Sent',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00588e),
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your emergency alert has been sent to:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 12),
              if (nurseNames.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No nurses currently on shift',
                    style: TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[600],
                    ),
                  ),
                )
              else
                Container(
                  constraints: BoxConstraints(
                    maxHeight: 200,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: nurseNames.map((name) {
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.person,
                                size: 20,
                                color: Color(0xFF00588e),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF00588e),
                  padding: EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'OK',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
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
  try {
    final parts = hhmm.split(":");
    if (parts.length != 2) {
      return const TimeOfDay(hour: 0, minute: 0);
    }
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  } catch (e) {
    print("Error parsing time: $hhmm - $e");
    return const TimeOfDay(hour: 0, minute: 0);
  }
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
final Map<String, String> houseNameToId =
    houseIdToName.map((key, value) => MapEntry(value, key));

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
    final userDoc =
        await FirebaseFirestore.instance.collection("users").doc(uid).get();

    if (userDoc.exists) {
      final data = userDoc.data();
      
      if (data == null) {
        return "Unknown Caregiver";
      }

      final fname = data["user_fname"] as String? ?? "";
      final lname = data["user_lname"] as String? ?? "";

      if (fname.isNotEmpty || lname.isNotEmpty) {
        return "$fname $lname".trim();
      }

      // fallback if walang fname/lname
      return data["user_email"] as String? ?? "Unknown Caregiver";
    } else {
      return "Unknown Caregiver";
    }
  } catch (e) {
    print("Error fetching caregiver name: $e");
    return "Unknown Caregiver";
  }
}