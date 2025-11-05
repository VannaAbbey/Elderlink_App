import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

  bool _isNurseScheduled = false;

  @override
  void initState() {
    super.initState();
    _isNurseScheduledForToday().then((scheduled) {
      if (mounted) setState(() => _isNurseScheduled = scheduled);
    });
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
    final currentShift = _getCurrentShift();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
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
            'It is not your $currentShift shift or schedule today. You cannot submit updates when you are not scheduled.',
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
            backgroundColor: Colors.white,
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
                  const Divider(
                    color: Color.fromARGB(255, 204, 203, 203),
                    thickness: 2,
                  ),
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
                                  borderRadius: BorderRadius.circular(30),
                                  borderSide: const BorderSide(
                                    color: Colors.white,
                                  ),
                                ),
                                filled: true,
                                fillColor: Color(0xFFB7DDF5),
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
        backgroundColor: Colors.white,
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
              const Divider(
                color: Color.fromARGB(255, 204, 203, 203),
                thickness: 2,
              ),
              const SizedBox(height: 12),

              // Date of Death
              const Text(
                'Date of Death:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF00588E),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: dateController,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: 'Select Date of Death',
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(color: Colors.white),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(color: Colors.white),
                  ),
                  filled: true,
                  fillColor: Color(0xFFB7DDF5),
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
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF00588E),
                ),
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
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Colors.white),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Color(0xFF00588E)),
                      ),
                      filled: true,
                      fillColor: Color(0xFFB7DDF5),
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
          backgroundColor: Colors.white,
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
              const Divider(
                color: Color.fromARGB(255, 204, 203, 203),
                thickness: 2,
              ),
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

                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Elderly details submitted for admin approval',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e')),
                                    );
                                  }
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

  String _getElderlyName(Map<String, dynamic> elderlyData) {
    // Try different possible field combinations for name
    if (elderlyData['name'] != null &&
        elderlyData['name'].toString().trim().isNotEmpty) {
      return elderlyData['name'].toString().trim();
    }

    // Try fname + lname combination
    final fname = elderlyData['elderly_fname']?.toString() ?? '';
    final lname = elderlyData['elderly_lname']?.toString() ?? '';
    final fullName = '$fname $lname'.trim();

    if (fullName.isNotEmpty) {
      return fullName;
    }

    return 'Name not specified';
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'Not specified';

    try {
      DateTime dateTime;
      if (date is String) {
        dateTime = DateTime.parse(date);
      } else if (date is DateTime) {
        dateTime = date;
      } else if (date is Timestamp) {
        dateTime = date.toDate();
      } else {
        return 'Not specified';
      }

      final months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];

      final monthName = months[dateTime.month - 1];
      return '$monthName ${dateTime.day}, ${dateTime.year}';
    } catch (e) {
      return 'Not specified';
    }
  }

  List<Widget> _buildInformationCards(
    Map<String, dynamic> elderly,
    String displayMobility,
    String displayDiet,
    String displayHealth,
    String displayLifeStatus,
    DateTime? deathDateToShow,
    String causeToShow,
    String houseName,
    bool isAlive,
  ) {
    List<Widget> cards = [];

    // Common fields for both alive and deceased
    cards.addAll([
      _buildInfoCard(
        icon: Icons.person,
        title: 'Full Name',
        content: _getElderlyName(elderly),
        isEditable: false,
        onEdit: null,
      ),
      const SizedBox(height: 16),

      _buildInfoCard(
        icon: Icons.cake,
        title: 'Birthday',
        content: (elderly['elderly_bday'] ?? elderly['birthdate']) != null
            ? _formatDate(elderly['elderly_bday'] ?? elderly['birthdate'])
            : 'Not specified',
        isEditable: false,
        onEdit: null,
      ),
      const SizedBox(height: 16),

      _buildInfoCard(
        icon: Icons.wc,
        title: 'Gender',
        content:
            elderly['elderly_sex'] ??
            elderly['sex'] ??
            elderly['gender'] ??
            'Not specified',
        isEditable: false,
        onEdit: null,
      ),
      const SizedBox(height: 16),
    ]);

    if (isAlive) {
      // Additional fields for alive elderly
      cards.addAll([
        _buildInfoCard(
          icon: Icons.event,
          title: 'Age',
          content: elderly['elderly_age']?.toString() ?? 'Not specified',
          isEditable: false,
          onEdit: null,
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          icon: Icons.home,
          title: 'House Allocation',
          content: houseName,
          isEditable: false,
          onEdit: null,
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          icon: Icons.accessible,
          title: 'Mobility Status',
          content: displayMobility,
          isEditable: true,
          onEdit: _isNurseScheduled
              ? () {
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
                }
              : null,
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          icon: Icons.restaurant,
          title: 'Dietary Notes',
          content: displayDiet.isEmpty ? 'Not specified' : displayDiet,
          isEditable: true,
          onEdit: _isNurseScheduled ? () => showDietOverlay(displayDiet) : null,
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          icon: Icons.health_and_safety,
          title: 'Health Condition',
          content: displayHealth.isEmpty ? 'Not specified' : displayHealth,
          isEditable: true,
          onEdit: _isNurseScheduled
              ? () => showHealthOverlay(displayHealth)
              : null,
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          icon: Icons.favorite,
          title: 'Life Status',
          content: displayLifeStatus,
          isEditable: true,
          onEdit: _isNurseScheduled
              ? () {
                  showDropdownOverlay(
                    'Edit Life Status',
                    'life_status',
                    ['Alive', 'Deceased'],
                    displayMobility,
                    displayLifeStatus,
                  );
                }
              : null,
        ),
      ]);
    } else {
      // Additional fields for deceased elderly
      cards.addAll([
        _buildInfoCard(
          icon: Icons.home_outlined,
          title: 'Former House Allocation',
          content: houseName,
          isEditable: false,
          onEdit: null,
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          icon: Icons.health_and_safety,
          title: 'Health Condition',
          content: displayHealth.isEmpty ? 'Not specified' : displayHealth,
          isEditable: false,
          onEdit: null,
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          icon: Icons.warning,
          title: 'Cause of Death',
          content: causeToShow.isNotEmpty ? causeToShow : 'Not specified',
          isEditable: false,
          onEdit: null,
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          icon: Icons.calendar_today,
          title: 'Date of Passing',
          content: deathDateToShow != null
              ? _formatDate(deathDateToShow)
              : 'Not specified',
          isEditable: false,
          onEdit: null,
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          icon: Icons.favorite,
          title: 'Life Status',
          content: displayLifeStatus,
          isEditable: false,
          onEdit: null,
        ),
      ]);
    }

    return cards;
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String content,
    required bool isEditable,
    required VoidCallback? onEdit,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFD8F4FF),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: const Color(0xFF00588e).withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00588e).withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF00588e), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF00588e).withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF00588e),
                  ),
                ),
              ],
            ),
          ),
          if (isEditable && onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit, color: Color(0xFF00588e)),
              onPressed: onEdit,
              tooltip: 'Edit',
            )
          else if (isEditable)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.grey),
              onPressed: null,
              tooltip: 'Not scheduled today',
            ),
        ],
      ),
    );
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

        final deathDateToShow = pendingDeathDate ?? dateOfDeath;
        final causeToShow = pendingCause ?? causeController.text;

        final profilePic = elderly['elderly_profilePic'] as String?;
        final isAlive =
            displayLifeStatus == 'Alive' || displayLifeStatus == 'alive';

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // Background
              Positioned.fill(
                child: Image.asset(
                  'assets/images/background1.png',
                  fit: BoxFit.cover,
                ),
              ),
              // Content
              SafeArea(
                child: Column(
                  children: [
                    // Custom App Bar
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Color(0xFF00588e),
                              size: 28,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const Expanded(
                            child: Text(
                              'Elderly Information',
                              style: TextStyle(
                                color: Color(0xFF00588e),
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 48), // Balance the back button
                        ],
                      ),
                    ),
                    // Main Content
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Profile Picture
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 10,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(80),
                                child:
                                    profilePic != null && profilePic.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: profilePic,
                                        width: 160,
                                        height: 160,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) =>
                                            Container(
                                              width: 160,
                                              height: 160,
                                              decoration: BoxDecoration(
                                                color: Colors.grey[300],
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.person,
                                                color: Colors.grey,
                                                size: 80,
                                              ),
                                            ),
                                        errorWidget: (context, url, error) =>
                                            Container(
                                              width: 160,
                                              height: 160,
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white,
                                              ),
                                              child: ClipOval(
                                                child: Image.asset(
                                                  'assets/images/people_icon.png',
                                                  width: 160,
                                                  height: 160,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                      )
                                    : Container(
                                        width: 160,
                                        height: 160,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                        ),
                                        child: ClipOval(
                                          child: Image.asset(
                                            'assets/images/people_icon.png',
                                            width: 160,
                                            height: 160,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Name
                            Text(
                              _getElderlyName(elderly),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588e),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),

                            // Information Cards
                            ..._buildInformationCards(
                              elderly,
                              displayMobility,
                              displayDiet,
                              displayHealth,
                              displayLifeStatus,
                              deathDateToShow,
                              causeToShow,
                              houseName,
                              isAlive,
                            ),

                            // Submit Button
                            const SizedBox(height: 24),
                            FutureBuilder<bool>(
                              future: _isNurseScheduledForToday(),
                              builder: (context, snapshot) {
                                final isScheduled = snapshot.data ?? false;
                                final hasEdits =
                                    pendingMobilityStatus != null ||
                                    pendingLifeStatus != null ||
                                    pendingHealthCondition != null ||
                                    pendingDietNotes != null;
                                final canSubmit = isScheduled && hasEdits;
                                if (!isAlive) {
                                  return const SizedBox.shrink();
                                }
                                return SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: canSubmit
                                          ? const Color(0xFF00588E)
                                          : Colors.grey,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                        horizontal: 32,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      elevation: canSubmit ? 4 : 0,
                                    ),
                                    onPressed: canSubmit
                                        ? () => showSubmitConfirmation(
                                            elderly,
                                            lifeStatus,
                                            houseName,
                                          )
                                        : (isScheduled
                                              ? null
                                              : () =>
                                                    _showNotScheduledDialog()),
                                    child: const Text(
                                      "Submit to Supervisor",
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
          backgroundColor: Colors.white,
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
                const Divider(
                  color: Color.fromARGB(255, 204, 203, 203),
                  thickness: 2,
                ),
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
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Colors.white),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(
                            color: Color(0xFF00588E),
                          ),
                        ),
                        filled: true,
                        fillColor: Color(0xFFB7DDF5),
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
          backgroundColor: Colors.white,
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
                const Divider(
                  color: Color.fromARGB(255, 204, 203, 203),
                  thickness: 2,
                ),
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
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Colors.white),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(
                            color: Color(0xFF00588E),
                          ),
                        ),
                        filled: true,
                        fillColor: Color(0xFFB7DDF5),
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
