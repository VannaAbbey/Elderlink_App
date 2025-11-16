import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'caregiver_sidebar.dart';
import '../widgets/cg_widgets/notification_icon_button.dart';
import '../services/cg_services/caregiver_shift_log_service.dart';
import '../services/cg_services/absence_service.dart';
import '../providers/cg_providers/absence_provider.dart';
import '../widgets/loading_overlay.dart';

// Helper function to show error modal
void _showErrorModal(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 60, color: Colors.red),
          const SizedBox(height: 12),
          const Text(
            "Can't submit incident report",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
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

class IncidentScreen extends StatefulWidget {
  final VoidCallback? onResetToHome;
  
  const IncidentScreen({super.key, this.onResetToHome});

  @override
  State<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends State<IncidentScreen> {
  bool isSidebarOpen = false;
  void toggleSidebar() => setState(() => isSidebarOpen = !isSidebarOpen);

  String? selectedElderlyId;
  String? selectedElderlyName;
  String? selectedIncidentType; // new incident type variable
  final TextEditingController reportController = TextEditingController();
  bool isLoading = true;
  bool isOnDuty = false;
  List<Map<String, dynamic>> elderlyList = [];

  // caregiver name
  String? caregiverName;

  // Incident types list
  final List<String> incidentTypes = [
    'Elderly fought with another elderly',
    'Verbal abuse or aggressive behavior',
    'Refusal of care (e.g., won\'t bathe, won\'t eat)',
    'Wandering into another residential house',
    'Equipment malfunction/not working as intended',
    'Personal belongings lost or damaged',
    'Refusal to participate in activities',
    'Crying, agitation, or loneliness episodes',
    'Elderly showing confusion or disorientation',
    'Others (please specify below)',
  ];

  // Shift state
  DateTime shiftStart = DateTime.now();
  DateTime shiftEnd = DateTime.now();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Save reference to ScaffoldMessenger to avoid context issues
  ScaffoldMessengerState? _scaffoldMessenger;
  bool _dialogShown = false;

  void _showAbsenceDialog(BuildContext context, String absenceType) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  absenceType == 'leave' ? Icons.event_busy : Icons.cancel_outlined,
                  color: Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 8),
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
                  Navigator.of(dialogContext).pop(); // Close dialog only
                },
                style: TextButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      // After dialog closes, reset to home tab
      // Use post frame callback to avoid crashes during build/dispose
      if (mounted && widget.onResetToHome != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            try {
              widget.onResetToHome?.call();
            } catch (e) {
              print('Error resetting to home: $e');
            }
          }
        });
      }
    });
  }

  void _checkAbsenceStatus() {
    if (_dialogShown) return;
    
    final absenceProvider = Provider.of<AbsenceProvider>(context, listen: false);
    if (absenceProvider.isAbsentToday) {
      _dialogShown = true;
      _showAbsenceDialog(context, absenceProvider.absenceType ?? 'absent');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadElderlyAssignments();
    _loadCaregiverName();
    // Check absence status after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAbsenceStatus();
      // Set up listener for absence status changes
      _setupAbsenceListener();
    });
  }
  
  void _setupAbsenceListener() {
    print('👂 [Incident] Setting up absence listener');
    // Listen to absence provider changes
    final absenceProvider = Provider.of<AbsenceProvider>(context, listen: false);
    absenceProvider.addListener(_onAbsenceStatusChanged);
    print('✅ [Incident] Absence listener attached');
  }
  
  void _onAbsenceStatusChanged() {
    print('🔔 [Incident] Absence status changed callback fired');
    print('   mounted: $mounted, _dialogShown: $_dialogShown');
    
    if (!mounted) {
      print('⚠️ [Incident] Widget not mounted, ignoring');
      return;
    }
    
    final absenceProvider = Provider.of<AbsenceProvider>(context, listen: false);
    print('   isAbsentToday: ${absenceProvider.isAbsentToday}');
    print('   absenceType: ${absenceProvider.absenceType}');
    
    // If caregiver becomes absent and dialog not yet shown
    if (absenceProvider.isAbsentToday && !_dialogShown) {
      print('✅ [Incident] Will show absence dialog');
      _dialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          print('📱 [Incident] Showing absence dialog now');
          _showAbsenceDialog(context, absenceProvider.absenceType ?? 'absent');
        } else {
          print('⚠️ [Incident] Widget unmounted before showing dialog');
        }
      });
    }
    
    // If caregiver is no longer absent, reset dialog flag
    if (!absenceProvider.isAbsentToday && _dialogShown) {
      print('✅ [Incident] Resetting dialog flag (no longer absent)');
      _dialogShown = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Save reference to ScaffoldMessenger to use safely later
    try {
      _scaffoldMessenger = ScaffoldMessenger.of(context);
    } catch (e) {
      // Context might not be available yet, ignore
      _scaffoldMessenger = null;
    }
  }

  @override
  void dispose() {
    // Remove listener to prevent memory leaks
    try {
      final absenceProvider = Provider.of<AbsenceProvider>(context, listen: false);
      absenceProvider.removeListener(_onAbsenceStatusChanged);
    } catch (e) {
      // Provider might not be available, ignore
    }
    reportController.dispose();
    _scaffoldMessenger = null;
    super.dispose();
  }

  Future<void> _loadCaregiverName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && mounted) {
        setState(() {
          caregiverName = "${doc['user_fname']} ${doc['user_lname']}";
        });
      }
    }
  }

  Future<void> _loadElderlyAssignments() async {
    if (mounted) setState(() => isLoading = true);

    final now = DateTime.now();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('🔴 INCIDENT: No user logged in');
        if (mounted) {
          setState(() {
            elderlyList = [];
            isOnDuty = false;
            isLoading = false;
          });
        }
        return;
      }

      final caregiverId = user.uid;
      print('🔍 INCIDENT: Checking for caregiver $caregiverId at ${now.toString()}');

      final houseSnapshot = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .where('is_current', isEqualTo: true)
          .limit(1)
          .get();

      print('🔍 INCIDENT: Found ${houseSnapshot.docs.length} house assignments with is_current=true');

      if (houseSnapshot.docs.isEmpty) {
        print('🔴 INCIDENT: No valid house assignment found');
        if (mounted) {
          setState(() {
            elderlyList = [];
            isOnDuty = false;
            isLoading = false;
          });
        }
        return;
      }

      final houseData = houseSnapshot.docs.first.data();
      print('🔍 INCIDENT: Raw house data: $houseData');
      
      // Safe parsing with detailed error checking
      final daysAssigned = List<String>.from(houseData['days_assigned'] ?? []);
      print('🔍 INCIDENT: Days assigned parsed: $daysAssigned');
      
      final houseId = houseData['house_id'] as String?;
      if (houseId == null) {
        print('🔴 INCIDENT: house_id is null!');
        if (mounted) {
          setState(() {
            elderlyList = [];
            isOnDuty = false;
            isLoading = false;
          });
        }
        return;
      }
      print('🔍 INCIDENT: House ID parsed: $houseId');
      
      // Get dates from nested schedule_period object
      final schedulePeriod = houseData['schedule_period'] as Map<String, dynamic>?;
      
      if (schedulePeriod == null) {
        print('🔴 INCIDENT: schedule_period is null!');
        if (mounted) {
          setState(() {
            elderlyList = [];
            isOnDuty = false;
            isLoading = false;
          });
        }
        return;
      }
      
      final startDateTimestamp = schedulePeriod['start_date'] as Timestamp?;
      final endDateTimestamp = schedulePeriod['end_date'] as Timestamp?;
      
      if (startDateTimestamp == null || endDateTimestamp == null) {
        print('🔴 INCIDENT: start_date or end_date is null in schedule_period!');
        print('🔴 INCIDENT: start_date: $startDateTimestamp, end_date: $endDateTimestamp');
        if (mounted) {
          setState(() {
            elderlyList = [];
            isOnDuty = false;
            isLoading = false;
          });
        }
        return;
      }
      
      final startDate = startDateTimestamp.toDate();
      final endDate = endDateTimestamp.toDate();
      print('🔍 INCIDENT: Dates parsed - start: $startDate, end: $endDate');

      // Normalize dates to compare only date parts (ignore time)
      final nowDate = DateTime(now.year, now.month, now.day);
      final normalizedStartDate = DateTime(startDate.year, startDate.month, startDate.day);
      final normalizedEndDate = DateTime(endDate.year, endDate.month, endDate.day);

      print('🔍 INCIDENT: ========== HOUSE ASSIGNMENT DATA ==========');
      print('🔍 INCIDENT: House ID: $houseId');
      print('🔍 INCIDENT: Days assigned: $daysAssigned');
      print('🔍 INCIDENT: Start date: ${startDate.toString()}');
      print('🔍 INCIDENT: End date: ${endDate.toString()}');
      print('🔍 INCIDENT: Current date/time: ${now.toString()}');
      print('🔍 INCIDENT: nowDate.isBefore(normalizedStartDate): ${nowDate.isBefore(normalizedStartDate)}');
      print('🔍 INCIDENT: nowDate.isAfter(normalizedEndDate): ${nowDate.isAfter(normalizedEndDate)}');
      print('🔍 INCIDENT: ================================================');

      if (nowDate.isBefore(normalizedStartDate) || nowDate.isAfter(normalizedEndDate)) {
        print('🔴 INCIDENT: Current date outside assignment period');
        if (mounted) {
          setState(() {
            elderlyList = [];
            isOnDuty = false;
            isLoading = false;
          });
        }
        return;
      }

      final startTime = houseData['start_time'] as String?;
      final endTime = houseData['end_time'] as String?;
      
      int startHour = 6, startMinute = 0, endHour = 14, endMinute = 0;
      
      if (startTime != null && endTime != null && startTime.isNotEmpty && endTime.isNotEmpty) {
        final startParts = startTime.split(':');
        final endParts = endTime.split(':');
        startHour = int.parse(startParts[0]);
        startMinute = int.parse(startParts[1]);
        endHour = int.parse(endParts[0]);
        endMinute = int.parse(endParts[1]);
      }

      // Determine if this is an overnight shift
      final isOvernightShift = endHour < startHour || (endHour == startHour && endMinute <= startMinute);

      // For overnight shifts, determine which day to check based on current time
      String dayToCheck;
      if (isOvernightShift && now.hour >= 0 && now.hour < endHour) {
        // Current time is in the "end period" of an overnight shift (e.g., 12:01 AM - 6:00 AM)
        // Check if the previous day is assigned (e.g., if it's Monday 1 AM, check if Sunday is assigned)
        final previousDay = now.subtract(const Duration(days: 1));
        dayToCheck = DateFormat('EEEE').format(previousDay);
        print('🌙 INCIDENT: Overnight shift end period - checking previous day: $dayToCheck');
      } else {
        // Regular shift or "start period" of overnight shift or after shift ends
        dayToCheck = DateFormat('EEEE').format(now);
        print('☀️ INCIDENT: Regular/overnight start - checking current day: $dayToCheck');
      }

      print('🔍 INCIDENT: Shift times: $startHour:${startMinute.toString().padLeft(2, '0')} - $endHour:${endMinute.toString().padLeft(2, '0')}');
      print('🔍 INCIDENT: Is overnight shift: $isOvernightShift');
      print('🔍 INCIDENT: Day to check: $dayToCheck');
      print('🔍 INCIDENT: Days assigned contains day? ${daysAssigned.contains(dayToCheck)}');

      if (!daysAssigned.contains(dayToCheck)) {
        print('🔴 INCIDENT: Day $dayToCheck not in assigned days $daysAssigned');
        if (mounted) {
          setState(() {
            elderlyList = [];
            isOnDuty = false;
            isLoading = false;
          });
        }
        return;
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

      print('🔍 INCIDENT: ========== SHIFT TIME VALIDATION ==========');
      print('🔍 INCIDENT: Start time from DB: $startTime');
      print('🔍 INCIDENT: End time from DB: $endTime');
      print('🔍 INCIDENT: Parsed start hour:minute: $startHour:$startMinute');
      print('🔍 INCIDENT: Parsed end hour:minute: $endHour:$endMinute');
      print('🔍 INCIDENT: Calculated shift start: $calculatedShiftStart');
      print('🔍 INCIDENT: Calculated shift end: $calculatedShiftEnd');
      print('🔍 INCIDENT: Current time (now): $now');
      print('🔍 INCIDENT: now.isBefore(calculatedShiftStart): ${now.isBefore(calculatedShiftStart)}');
      print('🔍 INCIDENT: now.isAfter(calculatedShiftEnd): ${now.isAfter(calculatedShiftEnd)}');
      print('🔍 INCIDENT: Is within shift: $isWithinShift');
      print('🔍 INCIDENT: =======================================');

      if (!isWithinShift) {
        print('🔴 INCIDENT: Not within shift hours');
        if (mounted) {
          setState(() {
            elderlyList = [];
            isOnDuty = false;
            isLoading = false;
          });
        }
        return;
      }

      final assignSnapshot = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .where('day', isEqualTo: dayToCheck)
          .get();

      print('🔍 INCIDENT: Found ${assignSnapshot.docs.length} elderly assignment documents for day $dayToCheck');

      List<Map<String, dynamic>> elderlyDetails = [];

      if (assignSnapshot.docs.isNotEmpty) {
        // NEW STRUCTURE: Each document has elderly_ids array instead of individual elderly_id
        Set<String> elderlyIds = {};
        for (var doc in assignSnapshot.docs) {
          final data = doc.data();
          // Get elderly_ids array from the document
          final idsFromDoc = List<String>.from(data['elderly_ids'] ?? []);
          elderlyIds.addAll(idsFromDoc);
          print('🔍 INCIDENT: Document has ${idsFromDoc.length} elderly IDs: $idsFromDoc');
        }

        print('🔍 INCIDENT: Total unique elderly IDs: ${elderlyIds.length}');

        if (elderlyIds.isNotEmpty) {
          // Fetch elderly details in chunks (max 30 per query due to Firestore limit)
          final elderlyIdsList = elderlyIds.toList();
          for (int i = 0; i < elderlyIdsList.length; i += 30) {
            final chunk = elderlyIdsList.skip(i).take(30).toList();
            final chunkSnapshot = await _firestore
                .collection('elderly')
                .where(FieldPath.documentId, whereIn: chunk)
                .get();

            for (var doc in chunkSnapshot.docs) {
              final data = doc.data();
              // Filter out deceased elderly and only include those in the same house
              if (data['house_id'] == houseId &&
                  data['elderly_status'] != 'Deceased') {
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
      }

      // Fetch temporary elderly assignments from absent caregivers
      print('🔍 INCIDENT: Fetching temporary elderly assignments...');
      try {
        final temporaryElderlyIds = await AbsenceService.getTodayTemporaryElderlyIds(caregiverId);
        print('🔍 INCIDENT: Found ${temporaryElderlyIds.length} temporary elderly IDs');
        
        if (temporaryElderlyIds.isNotEmpty) {
          // Fetch temporary elderly details in chunks (max 30 per query due to Firestore limit)
          for (int i = 0; i < temporaryElderlyIds.length; i += 30) {
            final chunk = temporaryElderlyIds.skip(i).take(30).toList();
            final chunkSnapshot = await _firestore
                .collection('elderly')
                .where(FieldPath.documentId, whereIn: chunk)
                .get();

            for (var doc in chunkSnapshot.docs) {
              final data = doc.data();
              // Filter out deceased elderly and only include those in the same house
              if (data['house_id'] == houseId &&
                  data['elderly_status'] != 'Deceased') {
                // Check if this elderly is not already in the list (avoid duplicates)
                final alreadyExists = elderlyDetails.any((e) => e['id'] == doc.id);
                if (!alreadyExists) {
                  elderlyDetails.add({
                    'id': doc.id,
                    'name':
                        '${data['elderly_fname'] ?? ''} ${data['elderly_lname'] ?? ''} (TEMP)',
                  });
                  print('🔍 INCIDENT: Added temporary elderly: ${data['elderly_fname']} ${data['elderly_lname']}');
                }
              }
            }
          }

          // Re-sort after adding temporary elderly
          elderlyDetails.sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String),
          );
        }
      } catch (e) {
        print('🔴 INCIDENT: Error fetching temporary elderly: $e');
        // Continue even if temporary fetch fails - regular elderly will still be shown
      }

      print('🔍 INCIDENT: Final elderly list count: ${elderlyDetails.length}');

      if (mounted) {
        setState(() {
          elderlyList = elderlyDetails;
          isOnDuty = true;
          isLoading = false;
          selectedElderlyId = null;
          selectedElderlyName = null;
          shiftStart = calculatedShiftStart;
          shiftEnd = calculatedShiftEnd;
        });
      }
    } catch (e, stackTrace) {
      print('🔴 INCIDENT: ========== ERROR OCCURRED ==========');
      print('🔴 INCIDENT: Error: $e');
      print('🔴 INCIDENT: Stack trace: $stackTrace');
      print('🔴 INCIDENT: =======================================');
      if (mounted) {
        setState(() {
          elderlyList = [];
          isOnDuty = false;
          isLoading = false;
          selectedElderlyId = null;
          selectedElderlyName = null;
        });
      }
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
      _safeShowSnackBar("Access granted — within schedule ✅");
    } catch (e) {
      if (mounted) _showError(context, "Error checking schedule: $e");
    }
  }

  /// 🔴 Safe message display helper
  void _safeShowSnackBar(String message, {bool isError = false}) {
    if (!mounted || _scaffoldMessenger == null) return;
    
    // Use post-frame callback to ensure the widget is still mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scaffoldMessenger == null) return;
      _scaffoldMessenger!.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  /// 🔴 Error Dialog UI
  void _showError(BuildContext context, String msg) {
    if (!mounted) return;
    
    // Use a post-frame callback to ensure the widget is still in the tree
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
    });
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

    // Handle overnight shifts (e.g., 22:00 - 06:00)
    if (endMinutes < startMinutes) {
      // Overnight shift: current time should be either after start OR before end
      return nowMinutes >= startMinutes || nowMinutes <= endMinutes;
    } else {
      // Regular shift: current time should be between start and end
      return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
    }
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
        .collection('house_shift_assignments')
        .where('user_id', isEqualTo: user.uid)
        .where('user_type', isEqualTo: 'caregiver')
        .where('is_current', isEqualTo: true)
        .get();

    if (query.docs.isEmpty) {
      _showWarningDialog(context, "No active shift found.");
      return;
    }

    final data = query.docs.first.data();
    final daysAssigned = data['days_assigned'] as List<dynamic>? ?? [];
    final shift = data['shift'] as String? ?? "";
    final startTime = data['start_time'] as String?;
    final endTime = data['end_time'] as String?;
    
    if (startTime == null || endTime == null || startTime.isEmpty || endTime.isEmpty) {
      _showWarningDialog(context, "Invalid shift time configuration.");
      return;
    }

    // 2. Check if today is included
    if (!daysAssigned.contains(currentDay)) {
      _showWarningDialog(context, "You are not scheduled today.");
      return;
    }

    // 3. Parse time range
    final startParts = startTime.split(":");
    final endParts = endTime.split(":");

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
                    const NotificationIconButton(),
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
                                            : 'Shift ended/Not scheduled today'),
                                ),
                                isExpanded: true,
                                icon: const Icon(
                                  Icons.arrow_drop_down,
                                  color: Color(0xFF00588e),
                                ),
                                menuMaxHeight: 200,
                                items: elderlyList.map((elderly) {
                                  // Check if this elderly has (TEMP) in the name
                                  final elderlyName = elderly['name'] as String;
                                  final isTemporary = elderlyName.contains('(TEMP)');
                                  // Remove (TEMP) from display name
                                  final displayName = elderlyName.replaceAll(' (TEMP)', '');
                                  
                                  return DropdownMenuItem<String>(
                                    value: elderly['id'],
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(displayName),
                                        ),
                                        if (isTemporary)
                                          Container(
                                            width: 10,
                                            height: 10,
                                            margin: const EdgeInsets.only(left: 8),
                                            decoration: BoxDecoration(
                                              color: Colors.orange,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 1,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
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

                          // Incident Type
                          Row(
                            children: const [
                              Icon(Icons.warning, color: Color(0xFF00588e)),
                              SizedBox(width: 8),
                              Text(
                                'What is the Incident?',
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
                                value: selectedIncidentType,
                                hint: Text(
                                  isLoading
                                      ? 'Loading...'
                                      : (isOnDuty
                                            ? 'Select incident type'
                                            : 'Shift ended/Not scheduled today'),
                                ),
                                isExpanded: true,
                                icon: const Icon(
                                  Icons.arrow_drop_down,
                                  color: Color(0xFF00588e),
                                ),
                                menuMaxHeight: 300, // Make dropdown scrollable
                                items: incidentTypes.map((type) {
                                  return DropdownMenuItem<String>(
                                    value: type,
                                    child: Text(type),
                                  );
                                }).toList(),
                                onChanged: isOnDuty
                                    ? (value) {
                                        setState(() {
                                          selectedIncidentType = value;
                                        });
                                      }
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Other information
                          Row(
                            children: const [
                              Icon(
                                Icons.info_outline,
                                color: Color(0xFF00588e),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Other information',
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
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                              controller: reportController,
                              maxLines: 15,
                              enabled: isOnDuty,
                              decoration: const InputDecoration(
                                hintText: 'Write here what happened... (optional)',
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
                                      // Validation checks
                                      if (selectedElderlyId == null) {
                                        _showErrorModal(context, "Please select an elderly person.");
                                        return;
                                      }
                                      
                                      if (selectedIncidentType == null) {
                                        _showErrorModal(context, "Please select an incident type.");
                                        return;
                                      }
                                      
                                      // Check if "Others" is selected but text field is empty
                                      if (selectedIncidentType == "Others (please specify below)" &&
                                          reportController.text.trim().isEmpty) {
                                        _showErrorModal(context, "Please fill in the additional information field!");
                                        return;
                                      }

                                      final formattedDate = DateFormat(
                                        'MM/dd/yy | h:mm a',
                                      ).format(DateTime.now());

                                      showDialog(
                                        context: context,
                                        barrierDismissible: true, // Will be controlled by WillPopScope
                                        builder: (BuildContext ctx) {
                                          bool acknowledged = false;
                                          bool isSubmitting = false; // Local loading state for this dialog
                                          return StatefulBuilder(
                                            builder: (context, dialogSetState) {
                                              return WillPopScope(
                                                onWillPop: () async => !isSubmitting, // Prevent back button when submitting
                                                child: Dialog(
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(20),
                                                  ),
                                                insetPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 24,
                                                      vertical: 40,
                                                    ),
                                                child: Stack(
                                                  children: [
                                                    Container(
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
                                                            Transform.translate(
                                                              offset: const Offset(16, -3),
                                                              child: IconButton(
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
                                                                onPressed: isSubmitting
                                                                  ? null // Disable when submitting
                                                                  : () =>
                                                                    Navigator.of(
                                                                      ctx,
                                                                    ).pop(),
                                                              ),
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
                                                          height: 10,
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
                                                              'Incident Type:',
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
                                                                selectedIncidentType ?? '',
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
                                                              Icons.info_outline,
                                                              color: Color(
                                                                0xFF00588e,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            const Text(
                                                              'Additional Information:',
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
                                                                reportController.text.trim().isEmpty 
                                                                    ? 'No additional information provided.'
                                                                    : reportController.text,
                                                                style: TextStyle(
                                                                  fontStyle: reportController.text.trim().isEmpty 
                                                                      ? FontStyle.italic
                                                                      : FontStyle.normal,
                                                                  fontSize: 15,
                                                                  color: reportController.text.trim().isEmpty
                                                                      ? Colors.grey[600]
                                                                      : Colors.black,
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
                                                                // Use a try-catch to handle potential disposal issues
                                                                try {
                                                                  dialogSetState(() {
                                                                    acknowledged = val ?? false;
                                                                  });
                                                                } catch (e) {
                                                                  // Dialog was disposed, ignore the state change
                                                                }
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
                                                                        // Prevent multiple submissions
                                                                        if (isSubmitting) return;
                                                                        
                                                                        // Safety check: ensure the main widget is still mounted before proceeding
                                                                        if (!mounted) return;

                                                                        final user = FirebaseAuth
                                                                            .instance
                                                                            .currentUser;
                                                                        if (user ==
                                                                                null ||
                                                                            selectedElderlyId ==
                                                                                null) {
                                                                          return;
                                                                        }

                                                                        // Show loading state using dialogSetState
                                                                        dialogSetState(() => isSubmitting = true);

                                                                        try {
                                                                        final formattedDate =
                                                                            DateTime.now();

                                                                          // Safety check before Firestore operations
                                                                          if (!mounted) return;
                                                                          
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
                                                                          final today = DateTime.now();
                                                                          final todayDay =
                                                                              DateFormat(
                                                                                'EEEE',
                                                                              ).format(today);
                                                                          final nowTime =
                                                                              DateFormat(
                                                                                'HH:mm',
                                                                              ).format(today);

                                                                          print('🔍 === INCIDENT REPORT: Finding on-duty nurses ===');
                                                                          print('Current time: $nowTime');
                                                                          print('Current day: $todayDay');

                                                                          final nurseQuery = await _firestore
                                                                              .collection(
                                                                                'house_shift_assignments',
                                                                              )
                                                                              .where(
                                                                                'user_type',
                                                                                isEqualTo: 'nurse',
                                                                              )
                                                                              .where(
                                                                                'is_current',
                                                                                isEqualTo: true,
                                                                              )
                                                                              .get();

                                                                          print('📋 Total nurse assignments found: ${nurseQuery.docs.length}');

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
                                                                            final nurseId =
                                                                                doc['user_id']; // Changed from nurse_id to user_id
                                                                            
                                                                            print('\n--- Checking Nurse: $nurseId ---');
                                                                            print('   Time: $startTime - $endTime');
                                                                            print('   Assigned Days: $daysAssigned');
                                                                            
                                                                            // Parse shift times to determine if overnight
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
                                                                            
                                                                            final isOvernightShift = end.isBefore(start);
                                                                            
                                                                            // For overnight shifts, determine which day to check
                                                                            String dayToCheck;
                                                                            if (isOvernightShift && today.hour >= 0 && today.hour < end.hour) {
                                                                              // Current time is in the "end period" of an overnight shift
                                                                              final previousDay = today.subtract(const Duration(days: 1));
                                                                              dayToCheck = DateFormat('EEEE').format(previousDay);
                                                                              print('   Day to check: $dayToCheck (previous day - in end period of overnight)');
                                                                            } else {
                                                                              dayToCheck = todayDay;
                                                                              print('   Day to check: $dayToCheck (current day)');
                                                                            }
                                                                            
                                                                            final isDayAssigned = daysAssigned.contains(dayToCheck);
                                                                            print('   Day assigned: $isDayAssigned');
                                                                            
                                                                            if (isDayAssigned) {
                                                                              // check if now is within shift
                                                                              final nowParsed =
                                                                                  DateFormat(
                                                                                    'HH:mm',
                                                                                  ).parse(
                                                                                    nowTime,
                                                                                  );
                                                                              bool
                                                                              inShift = false;

                                                                              if (isOvernightShift) {
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
                                                                              
                                                                              print('   In shift: $inShift');

                                                                              if (inShift) {
                                                                                nurseIdsToSend.add(
                                                                                  nurseId,
                                                                                );
                                                                                print('   ✅ ADDED: Nurse is on duty');
                                                                              } else {
                                                                                print('   ❌ SKIPPED: Not currently in shift time');
                                                                              }
                                                                            } else {
                                                                              print('   ❌ SKIPPED: Not assigned for $dayToCheck');
                                                                            }
                                                                          }
                                                                          
                                                                          print('\n🎯 Total on-duty nurses found: ${nurseIdsToSend.length}');
                                                                          print('Nurse IDs: $nurseIdsToSend');
                                                                          print('=== END INCIDENT REPORT NURSE SEARCH ===\n');

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
                                                                              'incident_type': selectedIncidentType, // Main field for incident type
                                                                              'additional_info': reportController.text.trim(), // Optional additional information
                                                                              'incident_id': incidentDocRef.id,
                                                                              'user_id_cg': caregiverId,
                                                                              'user_id_nu': nurseIdsToSend, // ✅ array of all nurses
                                                                            });

                                                                            // ✅ Also save to unified shift logs collection
                                                                            try {
                                                                              await CaregiverShiftLogService.createIncidentReportLog(
                                                                                caregiverId: caregiverId,
                                                                                incidentType: selectedIncidentType ?? 'Unknown',
                                                                                description: reportController.text.trim(),
                                                                                caregiverFname: caregiverName?.split(' ').first,
                                                                              );
                                                                              print('✅ Incident report logged to shift logs successfully');
                                                                            } catch (e) {
                                                                              print('❌ Error logging incident report to shift logs: $e');
                                                                              // Don't fail the entire operation if logging fails
                                                                            }

                                                                            // 📋 Fetch nurse names to display in dialog
                                                                            List<String> nurseNames = [];
                                                                            for (String nurseId in nurseIdsToSend) {
                                                                              try {
                                                                                final nurseDoc = await _firestore
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
                                                                            
                                                                            // Final safety check before showing dialog
                                                                            if (!mounted) return;

                                                                            // Show success dialog with nurse names
                                                                            showDialog(
                                                                              context: ctx,
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
                                                                                          'Report Submitted',
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
                                                                                        'Your incident report has been sent to:',
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
                                                                                          // Close the dialog first
                                                                                          Navigator.of(dialogContext).pop();
                                                                                          // Then close the modal
                                                                                          Navigator.of(ctx).pop();
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

                                                                          // Final safety check before cleanup
                                                                          if (!mounted) return;

                                                                          // 5️⃣ Clear fields + show success
                                                                          reportController
                                                                              .clear();
                                                                          
                                                                          // Use post-frame callback to safely clear state
                                                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                                                            if (mounted) {
                                                                              setState(() {
                                                                                selectedElderlyId = null;
                                                                                selectedElderlyName = null;
                                                                                selectedIncidentType = null;
                                                                              });
                                                                            }
                                                                          });

                                                                        } catch (
                                                                          e
                                                                        ) {
                                                                          _safeShowSnackBar("Failed to submit report: $e", isError: true);
                                                                        } finally {
                                                                          // Reset loading state using dialogSetState
                                                                          dialogSetState(() => isSubmitting = false);
                                                                        }
                                                                      }
                                                                    : null, // ❌ Disabled kapag kulang
                                                                style: ElevatedButton.styleFrom(
                                                                  backgroundColor:
                                                                      isSubmitting
                                                                      ? Colors.grey
                                                                      : (acknowledged &&
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
                                                                child: isSubmitting
                                                                  ? const SizedBox(
                                                                      height: 20,
                                                                      width: 20,
                                                                      child: CircularProgressIndicator(
                                                                        strokeWidth: 2,
                                                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                                      ),
                                                                    )
                                                                  : const Text(
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
                                                // Loading overlay
                                                if (isSubmitting)
                                                  const LoadingOverlay(
                                                    message: 'Submitting incident report...',
                                                  ),
                                              ],
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