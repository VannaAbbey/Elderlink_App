import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ElderlyProfile extends StatefulWidget {
  final String elderlyId;
  const ElderlyProfile({super.key, required this.elderlyId});

  @override
  State<ElderlyProfile> createState() => _ElderlyProfileState();
}

class _ElderlyProfileState extends State<ElderlyProfile> {
  // New fields for deceased details
  TextEditingController causeController = TextEditingController();
  DateTime? dateOfDeath;
  TextEditingController dateController = TextEditingController();

  // Pending edits (not yet submitted to admin)
  String? pendingMobilityStatus;
  String? pendingLifeStatus;
  String? pendingHealthCondition;
  String? pendingDietNotes;
  DateTime? pendingDeathDate;
  String? pendingCause;

  String currentHouseId = '';

  // House name mapping - constant values
  final Map<String, String> houseNames = {
    'H001': 'St. Sebastian',
    'H002': 'St. Emmanuel',
    'H003': 'St. Charbell',
    'H004': 'St. Rose of Lima',
    'H005': 'St. Gabriel',
  };

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
  }

  String _getSelectedDay() {
    return DateFormat('EEEE').format(DateTime.now());
  }

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

  Future<String?> _getNurseId() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      return currentUser.uid;
    } catch (e) {
      print('Error getting nurse ID: $e');
      return null;
    }
  }

  Future<List<String>> _getNurseWorkingDays(String nurseId) async {
    try {
      final currentShift = _getCurrentShift();

      final shiftQuery = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .get();

      if (shiftQuery.docs.isNotEmpty) {
        final data = shiftQuery.docs.first.data();
        return List<String>.from(data['days_assigned'] ?? []);
      }
      return [];
    } catch (e) {
      print('Error getting nurse working days: $e');
      return [];
    }
  }

  Future<bool> _isNurseScheduledForToday() async {
    try {
      final nurseId = await _getNurseId();
      if (nurseId == null) return false;

      final workingDays = await _getNurseWorkingDays(nurseId);
      final today = _getSelectedDay();

      return workingDays.contains(today);
    } catch (e) {
      print('Error checking if nurse is scheduled for today: $e');
      return false;
    }
  }

  void _showNotScheduledDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 45),
              SizedBox(height: 8),
              Text(
                'Not Scheduled \n Today',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF00588E),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            'It is not your shift or schedule today. You cannot submit updates when you are not scheduled.',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.justify,
          ),
          actions: [
            Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF00588E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Stream<DocumentSnapshot> _getElderlyStream() {
    return FirebaseFirestore.instance
        .collection('elderly')
        .doc(widget.elderlyId)
        .snapshots();
  }

  void showDropdownOverlay(
    String title,
    String field,
    List<String> options,
    String currentMobilityStatus,
    String currentLifeStatus,
  ) {
    // pick a sensible initial value
    String currentValue = field == 'elderly_mobilityStatus'
        ? currentMobilityStatus
        : currentLifeStatus;

    String selectedValue = options.contains(currentValue)
        ? currentValue
        : options.first;

    final mainSetState = setState;

    TextEditingController controller = TextEditingController(
      text: selectedValue,
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  iconSize: 28,
                  icon: const Icon(Icons.close, color: Color(0xFF00588E)),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                ),
                const Expanded(child: SizedBox()),
                const SizedBox(width: 36),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00588E),
                        fontSize: 26,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Color(0xFF00588E), thickness: 2),
                  const SizedBox(height: 12),
                  const Text(
                    'Please choose the appropriate option from the list below. Your selection will be submitted for administrator review.',
                    style: TextStyle(fontSize: 15, color: Colors.black),
                    textAlign: TextAlign.justify,
                  ),
                  const SizedBox(height: 24),

                  Builder(
                    builder: (ctx) {
                      return SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: () async {
                            final RenderBox fieldBox =
                                ctx.findRenderObject() as RenderBox;
                            final Offset pos = fieldBox.localToGlobal(
                              Offset.zero,
                            );
                            final Size size = fieldBox.size;

                            final selected = await showMenu<String>(
                              context: ctx,
                              position: RelativeRect.fromLTRB(
                                pos.dx,
                                pos.dy + size.height,
                                pos.dx + size.width,
                                pos.dy + size.height + 400,
                              ),
                              items: options
                                  .map(
                                    (e) => PopupMenuItem(
                                      value: e,
                                      child: SizedBox(
                                        width: size.width * 0.70,
                                        child: Text(
                                          e,
                                          style: const TextStyle(fontSize: 16),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            );

                            if (selected == null) return;

                            // For mobility status, just update the display, submit later
                            if (field == 'elderly_mobilityStatus') {
                              controller.text = selected;
                              setState(() {});
                              return;
                            }

                            // life status
                            if (selected == 'Deceased') {
                              // open deceased details so user can provide date & cause
                              Navigator.pop(context);
                              // set pending selection to Deceased only after user provides details
                              showDeceasedForm();
                              return;
                            }

                            // other life statuses - set as pending
                            mainSetState(() {
                              pendingLifeStatus = selected;
                            });
                            controller.text = selected;
                            setState(() {});
                            Navigator.pop(context);
                          },
                          child: AbsorbPointer(
                            child: TextField(
                              controller: controller,
                              readOnly: true,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 12,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF00588E),
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                suffixIcon: const Icon(
                                  Icons.arrow_drop_down,
                                  color: Color(0xFF00588E),
                                ),
                              ),
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: field == 'elderly_mobilityStatus'
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00588E),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  minimumSize: const Size.fromHeight(44),
                                ),
                                onPressed: () async {
                                  mainSetState(() {
                                    pendingMobilityStatus = controller.text;
                                  });
                                  Navigator.pop(context);
                                },
                                child: const Text(
                                  'Submit',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 24),

                          Expanded(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  minimumSize: const Size.fromHeight(44),
                                ),
                                onPressed: () => Navigator.pop(context),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]
                : null,
          );
        },
      ),
    );
  }

  void showDeceasedForm() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        // confirmation-form style: left-top close icon, title in content, divider and centered actions
        titlePadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              iconSize: 28,
              icon: const Icon(Icons.close, color: Color(0xFF00588E)),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Close',
            ),
            const Expanded(child: SizedBox()),
            const SizedBox(width: 36),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: Text(
                  'Provide Deceased Details',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00588E),
                    fontSize: 24,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(color: Color(0xFF00588E), thickness: 2),
              const SizedBox(height: 12),

              // Date of Death
              const Text(
                'Date of Death:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: dateController,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: 'Select Date of Death',
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF00588E)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF00588E)),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );
                      if (pickedDate != null) {
                        dateOfDeath = pickedDate;
                        dateController.text = DateFormat(
                          'MMMM d, yyyy',
                        ).format(dateOfDeath!);
                      }
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Cause of Death
              const Text(
                'Cause of Death:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Builder(
                builder: (ctx) {
                  final List<String> commonCauses = [
                    'Natural causes',
                    'Heart disease',
                    'Cancer',
                    'Stroke',
                    'Alzheimer\'s disease',
                    'Pneumonia',
                    'Kidney failure',
                    'Diabetes',
                    'Accident',
                    'Other',
                  ];
                  return TextField(
                    controller: causeController,
                    decoration: InputDecoration(
                      hintText: 'Enter or select cause of death',
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF00588E)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF00588E)),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_drop_down),
                        onPressed: () async {
                          final RenderBox fieldBox =
                              ctx.findRenderObject() as RenderBox;
                          final Offset pos = fieldBox.localToGlobal(
                            Offset.zero,
                          );
                          final Size size = fieldBox.size;
                          final screenSize = MediaQuery.of(ctx).size;
                          final availableBelow =
                              screenSize.height - (pos.dy + size.height);
                          final menuHeight = 200.0; // estimated menu height
                          RelativeRect position;
                          if (availableBelow > menuHeight) {
                            // Show below
                            position = RelativeRect.fromLTRB(
                              pos.dx,
                              pos.dy + size.height,
                              pos.dx + size.width,
                              pos.dy + size.height + menuHeight,
                            );
                          } else {
                            // Show above
                            position = RelativeRect.fromLTRB(
                              pos.dx,
                              pos.dy - menuHeight,
                              pos.dx + size.width,
                              pos.dy,
                            );
                          }
                          final selected = await showMenu<String>(
                            context: ctx,
                            position: position,
                            items: commonCauses
                                .map(
                                  (cause) => PopupMenuItem<String>(
                                    value: cause,
                                    child: Text(cause),
                                  ),
                                )
                                .toList(),
                          );
                          if (selected != null) {
                            causeController.text = selected;
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00588E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        minimumSize: const Size.fromHeight(44),
                      ),
                      onPressed: () async {
                        if (dateOfDeath == null ||
                            causeController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please provide all details'),
                            ),
                          );
                          return;
                        }

                        // Save to pending variables only, not DB
                        setState(() {
                          pendingLifeStatus = 'Deceased';
                          pendingDeathDate = dateOfDeath;
                          pendingCause = causeController.text;
                        });

                        Navigator.pop(context); // close dialog
                      },
                      child: const Text(
                        'Save',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 24),

                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        minimumSize: const Size.fromHeight(44),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void showSubmitConfirmation(
    Map<String, dynamic> elderly,
    String lifeStatus,
    String houseName,
  ) {
    bool isChecked = false;
    // Prepare a future to fetch the current nurse's user document for display
    final currentUser = FirebaseAuth.instance.currentUser;
    final Future<DocumentSnapshot?> nurseFuture = currentUser != null
        ? FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get()
        : Future.value(null);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          // add a small left-top exit icon and center the title
          titlePadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top-left X/exit icon only (larger tappable area)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                iconSize: 28,
                icon: const Icon(Icons.close, color: Color(0xFF00588E)),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close',
              ),
              // consume remaining space so header moves to next row (in content)
              const Expanded(child: SizedBox()),
              const SizedBox(width: 36),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header moved to content so it sits under the exit icon
              const Center(
                child: Text(
                  'Confirmation Form',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00588E),
                    fontSize: 26,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(color: Color(0xFF00588E), thickness: 2),
              const SizedBox(height: 12),
              const Text(
                'You are requested to change the details in the elderly profile. '
                'This action cannot be undone once submitted for admin approval.',
                textAlign: TextAlign.justify,
              ),
              const SizedBox(height: 14),
              // Reporting nurse label (fetched asynchronously) - placed above the checkbox
              FutureBuilder<DocumentSnapshot?>(
                future: nurseFuture,
                builder: (context, snapshot) {
                  String nurseName = '-';
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (snapshot.hasData &&
                      snapshot.data != null &&
                      snapshot.data!.exists) {
                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    if (data != null) {
                      final f = data['user_fname'] ?? '';
                      final l = data['user_lname'] ?? '';
                      nurseName = ('$f $l').trim();
                    }
                  }
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.person,
                                size: 25,
                                color: Color(0xFF00588E),
                              ),
                              const SizedBox(width: 8),
                              // Make label colored and value black, and allow wrapping
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Reporting Nurse: ',
                                        style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          color: Color(0xFF00588E),
                                        ),
                                      ),
                                      TextSpan(
                                        text: nurseName,
                                        style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.start,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: isChecked,
                    onChanged: (val) =>
                        setState(() => isChecked = val ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    activeColor: const Color(0xFF00588E),
                    checkColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF00588E), width: 2),
                  ),
                  Expanded(
                    child: Text(
                      'I acknowledge that the information provided is accurate and complete.',
                      textAlign: TextAlign.justify,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Submit button (responsive)
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00588E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: isChecked
                            ? () async {
                                try {
                                  // Validate deceased details if pending life status is Deceased
                                  if (pendingLifeStatus == 'Deceased' &&
                                      (pendingDeathDate == null ||
                                          pendingCause == null ||
                                          pendingCause!.isEmpty)) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Please provide deceased details',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  final currentUser =
                                      FirebaseAuth.instance.currentUser;
                                  if (currentUser == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('User not authenticated'),
                                      ),
                                    );
                                    return;
                                  }

                                  final userDoc = await FirebaseFirestore
                                      .instance
                                      .collection('users')
                                      .doc(currentUser.uid)
                                      .get();

                                  if (!userDoc.exists) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Nurse record not found'),
                                      ),
                                    );
                                    return;
                                  }

                                  final nurseName =
                                      "${userDoc['user_fname']} ${userDoc['user_lname']}";
                                  final nurseId = currentUser.uid;

                                  // Prepare the request data with pending changes
                                  Map<String, dynamic> requestData = {
                                    'elderly_id': widget.elderlyId,
                                    'elderly_name':
                                        '${elderly['elderly_fname']} ${elderly['elderly_lname']}',
                                    'elderly_profilePic':
                                        elderly['elderly_profilePic'] ?? '',
                                    'updated_by': 'Nurse $nurseName',
                                    'updated_by_id': nurseId,
                                    'createdAt': FieldValue.serverTimestamp(),
                                    'action_status': 'pending',
                                    'reason_for_rejection': '',
                                  };

                                  // Add pending changes if they exist
                                  if (pendingLifeStatus != null) {
                                    requestData['elderly_status'] =
                                        pendingLifeStatus;
                                    if (pendingLifeStatus == 'Deceased') {
                                      requestData['elderly_deathDate'] =
                                          Timestamp.fromDate(pendingDeathDate!);
                                      requestData['elderly_causeOfDeath'] =
                                          pendingCause;
                                    }
                                  }
                                  if (pendingMobilityStatus != null) {
                                    requestData['elderly_mobilityStatus'] =
                                        pendingMobilityStatus;
                                  }
                                  if (pendingHealthCondition != null) {
                                    requestData['elderly_condition'] =
                                        pendingHealthCondition;
                                  }
                                  if (pendingDietNotes != null) {
                                    requestData['elderly_dietNotes'] =
                                        pendingDietNotes;
                                  }

                                  await FirebaseFirestore.instance
                                      .collection('elderly_record_requests')
                                      .add(requestData);

                                  // Clear pending edits after submission
                                  setState(() {
                                    pendingMobilityStatus = null;
                                    pendingLifeStatus = null;
                                    pendingHealthCondition = null;
                                    pendingDietNotes = null;
                                    pendingDeathDate = null;
                                    pendingCause = null;
                                  });

                                  Navigator.pop(context);
                                  Navigator.pop(context);

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Elderly details submitted for admin approval',
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              }
                            : null,
                        child: const Text(
                          'Submit',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 24),

                  // Cancel button (responsive)
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String formatBirthday(dynamic bday) {
    if (bday == null) return '-';
    DateTime date;
    if (bday is Timestamp) {
      date = bday.toDate();
    } else if (bday is String)
      date = DateTime.tryParse(bday) ?? DateTime(1900);
    else
      return '-';
    return DateFormat('MMMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _getElderlyStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(body: Center(child: Text('Elderly not found')));
        }

        final elderly = snapshot.data!.data() as Map<String, dynamic>;
        final lifeStatus = elderly['elderly_status'] ?? 'Alive';
        final healthCondition = elderly['elderly_condition'] ?? '';
        final mobilityStatus =
            elderly['elderly_mobilityStatus'] ?? 'Independent';
        final dietNotes = elderly['elderly_dietNotes'] ?? '';

        // display values prefer pending edits (not yet approved)
        final displayMobility = pendingMobilityStatus ?? mobilityStatus;
        final displayLifeStatus = pendingLifeStatus ?? lifeStatus;
        final displayHealth = pendingHealthCondition ?? healthCondition;
        final displayDiet = pendingDietNotes ?? dietNotes;
        final sex = elderly['elderly_sex'] ?? 'Female';

        // Fetch house name if house_id exists
        final houseId = elderly['house_id']?.toString() ?? '';
        final houseName = houseNames[houseId] ?? '-';
        if (houseId != currentHouseId) {
          currentHouseId = houseId;
        }

        // Update controllers
        causeController.text = elderly['elderly_causeOfDeath'] ?? '';
        if (elderly['elderly_deathDate'] != null &&
            elderly['elderly_deathDate'].toString().isNotEmpty) {
          if (elderly['elderly_deathDate'] is Timestamp) {
            dateOfDeath = (elderly['elderly_deathDate'] as Timestamp).toDate();
          } else {
            dateOfDeath = DateTime.tryParse(
              elderly['elderly_deathDate'].toString(),
            );
          }
        }

        // Fetch house name (this might need to be async, but for now sync)
        // String houseName = '-';
        // Note: House name fetching removed for simplicity

        const double fieldFontSize = 17;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF00588E),
            title: const Text(
              'Elderly Profile',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            centerTitle: true, // <-- Add this line to center the title
            elevation: 1,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/background1.png'),
                fit: BoxFit.cover,
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // 🔵 Profile Picture Circle
                        Container(
                          width: 180,
                          height: 180,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF00588E),
                          ),
                          child: ClipOval(
                            child:
                                elderly['elderly_profilePic'] != null &&
                                    elderly['elderly_profilePic']
                                        .toString()
                                        .isNotEmpty
                                ? Image.network(
                                    elderly['elderly_profilePic'],
                                    fit: BoxFit.cover,
                                  )
                                : Image.asset(
                                    'assets/images/people_icon.png',
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),

                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(
                              0.2,
                            ), // shadow color
                            blurRadius: 3, // soft edges
                            spreadRadius: 2, // spread out
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${sex == 'Female' ? 'Lola' : 'Lolo'} ${elderly['elderly_fname'] ?? ''}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00588e),
                            ),
                          ),
                          const Divider(color: Color(0xFF00588e), thickness: 1),
                          const SizedBox(height: 20),
                          buildField(
                            'Full Name',
                            '${elderly['elderly_fname'] ?? ''} ${elderly['elderly_lname'] ?? ''}',
                            fieldFontSize,
                          ),
                          const SizedBox(height: 20),
                          buildField(
                            'Birthday',
                            formatBirthday(elderly['elderly_bday']),
                            fieldFontSize,
                          ),
                          const SizedBox(height: 20),
                          buildField(
                            'Age',
                            '${elderly['elderly_age'] ?? '-'}',
                            fieldFontSize,
                          ),
                          const SizedBox(height: 20),
                          buildField('Sex', sex, fieldFontSize),
                          const SizedBox(height: 20),
                          buildField(
                            'House Location',
                            houseName,
                            fieldFontSize,
                          ),
                          const SizedBox(height: 16),
                          buildEditableRow(
                            'Mobility Status',
                            displayMobility,
                            () {
                              showDropdownOverlay(
                                'Edit Mobility Status',
                                'elderly_mobilityStatus',
                                [
                                  'Independent',
                                  'Assisted',
                                  'Wheelchair-bound',
                                  'Bedridden',
                                  'Needs Supervision',
                                ],
                                displayMobility,
                                displayLifeStatus,
                              );
                            },
                            fieldFontSize,
                          ),
                          const SizedBox(height: 2),
                          buildEditableRow(
                            'Dietary Notes',
                            displayDiet,
                            () => showDietOverlay(displayDiet),
                            fieldFontSize,
                          ),
                          const SizedBox(height: 2),
                          buildEditableRow(
                            'Health Condition',
                            displayHealth,
                            () => showHealthOverlay(displayHealth),
                            fieldFontSize,
                          ),
                          const SizedBox(height: 2),
                          buildEditableRow(
                            'Life Status',
                            displayLifeStatus,
                            () {
                              showDropdownOverlay(
                                'Edit Life Status',
                                'life_status',
                                ['Alive', 'Deceased'],
                                displayMobility,
                                displayLifeStatus,
                              );
                            },
                            fieldFontSize,
                          ),
                          if (pendingLifeStatus == 'Deceased' &&
                              pendingDeathDate != null &&
                              pendingCause != null &&
                              pendingCause!.isNotEmpty) ...[
                            const SizedBox(height: 15),
                            buildField(
                              'Date of Death',
                              DateFormat(
                                'MMMM d, yyyy',
                              ).format(pendingDeathDate!),
                              fieldFontSize,
                            ),
                            const SizedBox(height: 25),
                            buildField(
                              'Cause of Death',
                              pendingCause!,
                              fieldFontSize,
                            ),
                          ],

                          const SizedBox(height: 20),

                          // ✅ Button INSIDE container with schedule validation
                          FutureBuilder<bool>(
                            future: _isNurseScheduledForToday(),
                            builder: (context, snapshot) {
                              final isScheduled = snapshot.data ?? false;
                              return ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isScheduled
                                      ? const Color(0xFF00588E)
                                      : Colors.grey,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  // Use the Poppins family and the Bold (700) weight which
                                  // is actually included in pubspec.yaml. w900 may fall back
                                  // to a lighter weight if that exact weight isn't available.
                                  textStyle: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                    letterSpacing: 0.25,
                                  ),
                                ),
                                onPressed: isScheduled
                                    ? () => showSubmitConfirmation(
                                        elderly,
                                        lifeStatus,
                                        houseName,
                                      )
                                    : () => _showNotScheduledDialog(),
                                child: const Text(
                                  "Update and Submit to Admin",
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget buildField(String label, String value, double fontSize) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: label, // ✅ only the label
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF00588E),
              fontSize: fontSize,
            ),
          ),
          TextSpan(
            text: ': ', // ✅ separator not bold
            style: TextStyle(color: Colors.black, fontSize: fontSize),
          ),
          TextSpan(
            text: value, // ✅ plain value
            style: TextStyle(color: Colors.black, fontSize: fontSize),
          ),
        ],
      ),
    );
  }

  Widget buildEditableRow(
    String label,
    String value,
    VoidCallback onEdit,
    double fontSize,
  ) {
    return Row(
      children: [
        Expanded(child: buildField(label, value, fontSize)),
        IconButton(
          icon: const Icon(Icons.edit, color: Color(0xFF00588E)),
          onPressed: onEdit,
        ),
      ],
    );
  }

  void showHealthOverlay(String currentHealthCondition) {
    // Predefined options for quick selection (reasonable defaults)
    final List<String> options = [
      'Stable',
      'Under observation',
      'Requires monitoring',
      'Critical',
      'Improving',
    ];

    TextEditingController controller = TextEditingController(
      text: currentHealthCondition,
    );

    final mainSetState = setState;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                iconSize: 28,
                icon: const Icon(Icons.close, color: Color(0xFF00588E)),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close',
              ),
              const Expanded(child: SizedBox()),
              const SizedBox(width: 36),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Text(
                    'Edit Health Condition',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00588E),
                      fontSize: 26,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(color: Color(0xFF00588E), thickness: 2),
                const SizedBox(height: 12),
                const Text(
                  'Please choose the appropriate option from the list below or type a custom value. Your submission will be reviewed by an administrator.',
                  style: TextStyle(fontSize: 15, color: Colors.black),
                  textAlign: TextAlign.justify,
                ),
                const SizedBox(height: 24),

                // Editable combo-style TextField styled like mobility status.
                // Suffix IconButton opens preset menu; field remains writable.
                Builder(
                  builder: (ctx) {
                    return TextField(
                      controller: controller,
                      maxLines: 1,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                            color: Color(0xFF00588E),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                            color: Color(0xFF00588E),
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            color: Color(0xFF00588E),
                          ),
                          onPressed: () async {
                            final RenderBox fieldBox =
                                ctx.findRenderObject() as RenderBox;
                            final Offset pos = fieldBox.localToGlobal(
                              Offset.zero,
                            );
                            final Size size = fieldBox.size;

                            final selected = await showMenu<String>(
                              context: ctx,
                              position: RelativeRect.fromLTRB(
                                pos.dx,
                                pos.dy + size.height,
                                pos.dx + size.width,
                                pos.dy + size.height + 300,
                              ),
                              items: options
                                  .map(
                                    (e) => PopupMenuItem(
                                      value: e,
                                      child: Text(
                                        e,
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            );
                            if (selected != null) {
                              setState(() => controller.text = selected);
                            }
                          },
                          tooltip: 'Choose preset',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00588E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: () async {
                          mainSetState(() {
                            pendingHealthCondition = controller.text;
                          });
                          Navigator.pop(context);
                        },
                        child: const Text(
                          'Submit',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 24),

                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void showDietOverlay(String currentDietNotes) {
    // Predefined diet options (reasonable defaults)
    final List<String> options = [
      'Normal diet',
      'Diabetic diet',
      'Low salt',
      'Soft diet',
      'NPO',
    ];

    TextEditingController controller = TextEditingController(
      text: currentDietNotes,
    );

    final mainSetState = setState;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                iconSize: 28,
                icon: const Icon(Icons.close, color: Color(0xFF00588E)),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close',
              ),
              const Expanded(child: SizedBox()),
              const SizedBox(width: 36),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Text(
                    'Edit Dietary Notes',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00588E),
                      fontSize: 26,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(color: Color(0xFF00588E), thickness: 2),
                const SizedBox(height: 12),
                const Text(
                  'Please choose the appropriate option from the list below or type a custom value. Your selection will be submitted for administrator review.',
                  style: TextStyle(fontSize: 15, color: Colors.black),
                  textAlign: TextAlign.justify,
                ),
                const SizedBox(height: 24),

                // Editable combo-style TextField styled like mobility status.
                // Suffix IconButton opens preset menu; field remains writable.
                Builder(
                  builder: (ctx) {
                    return TextField(
                      controller: controller,
                      maxLines: 1,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                            color: Color(0xFF00588E),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                            color: Color(0xFF00588E),
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            color: Color(0xFF00588E),
                          ),
                          onPressed: () async {
                            final RenderBox fieldBox =
                                ctx.findRenderObject() as RenderBox;
                            final Offset pos = fieldBox.localToGlobal(
                              Offset.zero,
                            );
                            final Size size = fieldBox.size;

                            final selected = await showMenu<String>(
                              context: ctx,
                              position: RelativeRect.fromLTRB(
                                pos.dx,
                                pos.dy + size.height,
                                pos.dx + size.width,
                                pos.dy + size.height + 300,
                              ),
                              items: options
                                  .map(
                                    (e) => PopupMenuItem(
                                      value: e,
                                      child: Text(
                                        e,
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            );
                            if (selected != null) {
                              setState(() => controller.text = selected);
                            }
                          },
                          tooltip: 'Choose preset',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00588E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: () async {
                          mainSetState(() {
                            pendingDietNotes = controller.text;
                          });
                          Navigator.pop(context);
                        },
                        child: const Text(
                          'Submit',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 24),

                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
