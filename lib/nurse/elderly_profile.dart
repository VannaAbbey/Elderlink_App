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
  Map<String, dynamic> elderly = {};
  bool isLoading = true;

  late String lifeStatus;
  late String healthCondition;
  late String mobilityStatus;
  late String dietNotes;
  late String sex;
  String houseName = '-';

  // New fields for deceased details
  TextEditingController causeController = TextEditingController();
  DateTime? dateOfDeath;

  @override
  void initState() {
    super.initState();
    fetchElderlyDetails();
  }

  Future<void> fetchElderlyDetails() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('elderly')
          .doc(widget.elderlyId)
          .get();

      if (!doc.exists) {
        setState(() => isLoading = false);
        return;
      }

      elderly = doc.data()!;
      lifeStatus = elderly['elderly_status'] ?? 'Alive';
      healthCondition = elderly['elderly_condition'] ?? '';
      mobilityStatus = elderly['elderly_mobilityStatus'] ?? 'Independent';
      dietNotes = elderly['elderly_dietNotes'] ?? '';
      sex = elderly['elderly_sex'] ?? 'Female';

      // If already deceased, load details
      causeController.text = elderly['elderly_causeDeath'] ?? '';
      if (elderly['elderly_deathDate'] != null &&
          elderly['elderly_deathDate'].toString().isNotEmpty) {
        dateOfDeath =
            DateTime.tryParse(elderly['elderly_deathDate'].toString());
      }

      // Fetch house name
      if (elderly['house_id'] != null) {
        final houseId = elderly['house_id'].toString();

        final houseDoc = await FirebaseFirestore.instance
            .collection('house')
            .doc(houseId)
            .get();

        if (houseDoc.exists) {
          houseName = houseDoc['house_name'] ?? '-';
        } else {
          final query = await FirebaseFirestore.instance
              .collection('house')
              .where('house_id', isEqualTo: houseId)
              .limit(1)
              .get();

          if (query.docs.isNotEmpty) {
            houseName = query.docs.first['house_name'] ?? '-';
          }
        }
      }

      setState(() => isLoading = false);
    } catch (e) {
      print("Error fetching elderly details: $e");
      setState(() => isLoading = false);
    }
  }

  void showDropdownOverlay(String title, String field, List<String> options) {
    String selectedValue =
        field == 'elderly_mobilityStatus' ? mobilityStatus : lifeStatus;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: DropdownButton<String>(
            isExpanded: true,
            value: selectedValue,
            items: options
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (val) {
              if (val == null) return;
              setState(() {
                if (field == 'elderly_mobilityStatus') {
                  mobilityStatus = val;
                } else {
                  lifeStatus = val;
                }
              });
              Navigator.pop(context);

              if (val == 'Deceased') {
                showDeceasedForm();
              }
            },
          ),
        ),
      ),
    );
  }

  void showDeceasedForm() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Provide Deceased Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('Date of Death: '),
                    TextButton(
                      onPressed: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                        );
                        if (pickedDate != null) {
                          setState(() => dateOfDeath = pickedDate);
                        }
                      },
                      child: Text(
                        dateOfDeath == null
                            ? 'Select Date'
                            : DateFormat('MMMM d, yyyy').format(dateOfDeath!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: causeController,
                  decoration: const InputDecoration(
                    labelText: 'Cause of Death',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (dateOfDeath == null || causeController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please provide all details'),
                    ),
                  );
                  return;
                }
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void showSubmitConfirmation() {
    bool isChecked = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text(
            'Confirmation Form',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'You are requested to change the details in the elderly profile. '
                'This action cannot be undone once submitted for admin approval.',
              ),
              Row(
                children: [
                  Checkbox(
                    value: isChecked,
                    onChanged: (val) =>
                        setState(() => isChecked = val ?? false),
                  ),
                  const Expanded(
                    child: Text(
                      'I acknowledge that the information provided is accurate and complete.',
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              onPressed: isChecked
                  ? () async {
                      try {
                        if (lifeStatus == 'Deceased' &&
                            (dateOfDeath == null ||
                                causeController.text.isEmpty)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Please provide Date of Death and Cause of Death'),
                            ),
                          );
                          return;
                        }

                        final currentUser =
                            FirebaseAuth.instance.currentUser;
                        if (currentUser == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('User not logged in')),
                          );
                          return;
                        }

                        final userDoc = await FirebaseFirestore.instance
                            .collection('users')
                            .doc(currentUser.uid)
                            .get();

                        if (!userDoc.exists) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Nurse details not found')),
                          );
                          return;
                        }

                        final nurseName =
                            "${userDoc['user_fname']} ${userDoc['user_lname']}";
                        final nurseId = currentUser.uid;

                        await FirebaseFirestore.instance
                            .collection('notifications')
                            .add({
                          'elderly_id': widget.elderlyId,
                          'elderly_name':
                              '${elderly['elderly_fname']} ${elderly['elderly_lname']}',
                          'elderly_profilePic':
                              elderly['elderly_profilePic'] ?? '',
                          'elderly_status': lifeStatus,
                          'elderly_deathDate':
                              lifeStatus == 'Deceased' && dateOfDeath != null
                                  ? Timestamp.fromDate(dateOfDeath!)
                                  : null,
                          'elderly_causeDeath': lifeStatus == 'Deceased'
                              ? causeController.text
                              : '',
                          'house_name': houseName,
                          'updated_by': 'Nurse $nurseName',
                          'updated_by_id': nurseId,
                          'createdAt': FieldValue.serverTimestamp(),
                          'action_status': 'pending',
                          'reason_for_rejection': '',
                        });

                        Navigator.pop(context);
                        Navigator.pop(context);

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Elderly details submitted for admin approval')),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    }
                  : null,
              child: const Text('Submit'),
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
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    const double fieldFontSize = 17;
    const double buttonFontSize = 18;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF00588E),
        title: const Text(
          'Elderly Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
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
                Container(
                  width: 180,
                  height: 180,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF00588E),
                  ),
                  child: ClipOval(
                    child: elderly['elderly_profilePic'] != null &&
                            elderly['elderly_profilePic'].toString().isNotEmpty
                        ? Image.network(
                            elderly['elderly_profilePic'],
                            fit: BoxFit.contain,
                          )
                        : Image.asset(
                            'assets/images/profile.png',
                            fit: BoxFit.contain,
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    border: Border.all(
                      color: Color(0xFF216386),
                      width: 1,
                    ),
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
                          color: Color(0xFF216386),
                        ),
                      ),
                      const Divider(color: Color(0xFF216386), thickness: 1),
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
                      buildField('House Location', houseName, fieldFontSize),
                      const SizedBox(height: 16),
                      buildEditableRow('Mobility Status', mobilityStatus, () {
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
                        );
                      }, fieldFontSize),
                      const SizedBox(height: 2),
                      buildEditableRow(
                        'Dietary Notes',
                        dietNotes,
                        showDietOverlay,
                        fieldFontSize,
                      ),
                      const SizedBox(height: 2),
                      buildEditableRow('Life Status', lifeStatus, () {
                        showDropdownOverlay('Edit Life Status', 'life_status', [
                          'Alive',
                          'Deceased',
                        ]);
                      }, fieldFontSize),
                      const SizedBox(height: 2),
                      buildEditableRow(
                        'Health Condition',
                        healthCondition,
                        showHealthOverlay,
                        fieldFontSize,
                      ),
                      if (lifeStatus == 'Deceased') ...[
                        const SizedBox(height: 10),
                        buildField(
                          'Date of Death',
                          dateOfDeath != null
                              ? DateFormat('MMMM d, yyyy').format(dateOfDeath!)
                              : 'Not set',
                          fieldFontSize,
                        ),
                        const SizedBox(height: 10),
                        buildField(
                          'Cause of Death',
                          causeController.text.isNotEmpty
                              ? causeController.text
                              : 'Not set',
                          fieldFontSize,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00588E),
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: buttonFontSize,
                    ),
                  ),
                  onPressed: showSubmitConfirmation,
                  child: const Text('Update and Submit to Admin'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildField(String label, String value, double fontSize) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black,
              fontSize: fontSize,
            ),
          ),
          TextSpan(
            text: value,
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

  void showHealthOverlay() {
    TextEditingController controller = TextEditingController(
      text: healthCondition,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Edit Health Condition',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => healthCondition = controller.text);
              Navigator.pop(context);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  void showDietOverlay() {
    TextEditingController controller = TextEditingController(text: dietNotes);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Edit Dietary Notes',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => dietNotes = controller.text);
              Navigator.pop(context);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
