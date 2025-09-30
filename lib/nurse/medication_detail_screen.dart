// lib/nurse/medication_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'medication_logger.dart';

class MedicationDetailScreen extends StatefulWidget {
  final String elderlyId;
  final String elderlyName;

  const MedicationDetailScreen({
    super.key,
    required this.elderlyId,
    required this.elderlyName,
  });

  @override
  State<MedicationDetailScreen> createState() => _MedicationDetailScreenState();
}

class _MedicationDetailScreenState extends State<MedicationDetailScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final MedicationDraft draft;
  final _formKey = GlobalKey<FormState>();
  bool isSaving = false;
  String? editingMedId;

  String get nurseName =>
      FirebaseAuth.instance.currentUser?.displayName ?? "Unknown Nurse";

  @override
  void initState() {
    super.initState();
    draft = MedicationDraft();
  }

  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  void startEditing(Map<String, dynamic> medData, String medId) {
    setState(() {
      editingMedId = medId;
      draft.medNameController.text = medData["medication_name"] ?? "";
      draft.dosageController.text = medData["medication_dosage"] ?? "";
      draft.medTimes.clear();
      draft.medTimes.addAll(
        (medData["medication_times"] as List<dynamic>? ?? [])
            .map((t) => (t as Timestamp).toDate())
            .map((dt) => TimeOfDay(hour: dt.hour, minute: dt.minute)),
      );
    });
    _showMedicationBottomSheet();
  }

  Future<void> updateMedicationStatus(
      String medicationId, int index, String status) async {
    final ref =
        FirebaseFirestore.instance.collection("medication").doc(medicationId);
    final snapshot = await ref.get();
    final data = snapshot.data();

    // Make sure we have a list of statuses same length as times
    final timesCount =
        (data?["medication_times"] as List<dynamic>? ?? []).length;
    List<String> statuses =
        List<String>.filled(timesCount, "Pending", growable: true);

    if (data?["medication_status"] != null) {
      statuses = List<String>.from(data?["medication_status"]);
      while (statuses.length < timesCount) {
        statuses.add("Pending");
      }
    }

    statuses[index] = status;

    await ref.update({
      "medication_status": statuses,
      "updated_at": FieldValue.serverTimestamp(),
    });

    await logMedicationAction(
      medicationId: medicationId,
      elderlyId: widget.elderlyId,
      elderlyName: widget.elderlyName,
      nurseName: nurseName,
      actionType: "update",
      oldValue: data,
      newValue: {"medication_status": statuses},
    );
  }

  bool _allFieldsValid() {
    return _formKey.currentState?.validate() == true &&
        draft.medTimes.isNotEmpty;
  }

  Future<void> saveMedication() async {
    if (!_allFieldsValid()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please fill all fields correctly before saving.")),
      );
      return;
    }

    final confirmed = await _showConfirmationDialog();
    if (!confirmed) return;

    setState(() => isSaving = true);

    final timesAsTimestamps = draft.medTimes
        .map((t) => Timestamp.fromDate(DateTime(
              DateTime.now().year,
              DateTime.now().month,
              DateTime.now().day,
              t.hour,
              t.minute,
            )))
        .toList();

    final ref = editingMedId != null
        ? FirebaseFirestore.instance.collection("medication").doc(editingMedId)
        : FirebaseFirestore.instance.collection("medication").doc();

    final oldData = editingMedId != null
        ? (await ref.get()).data()
        : <String, dynamic>{};

    await ref.set({
      "created_at": FieldValue.serverTimestamp(),
      "elderly_id": widget.elderlyId,
      "med_verify": true,
      "medication_name": draft.medNameController.text,
      "medication_dosage": draft.dosageController.text,
      "medication_frequency": draft.medTimes.length,
      "medication_status":
          List<String>.filled(draft.medTimes.length, "Pending"), // initial
      "medication_times": timesAsTimestamps,
      "nurse_id": FirebaseAuth.instance.currentUser?.uid ?? "",
      "updated_at": FieldValue.serverTimestamp(),
    });

    await logMedicationAction(
      medicationId: ref.id,
      elderlyId: widget.elderlyId,
      elderlyName: widget.elderlyName,
      nurseName: nurseName,
      actionType: editingMedId != null ? "edit" : "add",
      oldValue: oldData,
      newValue: {
        "medication_name": draft.medNameController.text,
        "medication_dosage": draft.dosageController.text,
        "medication_frequency": draft.medTimes.length,
        "medication_times": timesAsTimestamps,
      },
    );

    setState(() {
      editingMedId = null;
      isSaving = false;
      draft.clear();
    });

    Navigator.of(context).pop();
  }

  Future<bool> _showConfirmationDialog() async {
    bool isChecked = false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text("Confirmation Form"),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "You are about to ${editingMedId != null ? "edit" : "add"} a medication record for ${widget.elderlyName}. "
                      "This action will be logged and can affect treatment. "
                      "Please review the information carefully before submitting.\n\n"
                      "Reporting Nurse: $nurseName",
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(
                          value: isChecked,
                          onChanged: (val) =>
                              setState(() => isChecked = val ?? false),
                        ),
                        const Expanded(
                          child: Text(
                            "I acknowledge that the information provided is accurate and complete. "
                            "I accept full responsibility and understand that this submission is final and cannot be modified.",
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child:
                      const Text("Cancel", style: TextStyle(color: Colors.red)),
                ),
                ElevatedButton(
                  onPressed:
                      isChecked ? () => Navigator.of(context).pop(true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isChecked ? const Color(0xFF00588E) : Colors.grey,
                  ),
                  child: const Text("Submit"),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  void _addTimePicker([int? index]) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: index != null && index < draft.medTimes.length
          ? draft.medTimes[index]
          : TimeOfDay.now(),
    );

    if (picked != null) {
      setState(() {
        if (index != null && index < draft.medTimes.length) {
          draft.medTimes[index] = picked;
        } else {
          draft.medTimes.add(picked);
        }
      });
    }
  }

  void _removeFrequency(int index) {
    setState(() => draft.medTimes.removeAt(index));
  }

  void _showMedicationBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  editingMedId != null ? "Edit Medication" : "Add New Medication",
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00588E)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: draft.medNameController,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return "Required";
                    if (!RegExp(r"^[a-zA-Z\s]+$").hasMatch(val)) {
                      return "Only letters allowed";
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                    labelText: "Medication Name",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: draft.dosageController,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return "Required";
                    if (!RegExp(r"^(?=.*\d)[\d\w\s]+$").hasMatch(val)) {
                      return "Include numbers and letters";
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                    labelText: "Dosage",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Column(
                  children: [
                    for (int i = 0; i < draft.medTimes.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Text("Take ${i + 1}:"),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _addTimePicker(i),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(draft.medTimes[i].format(context)),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _removeFrequency(i),
                              icon: const Icon(Icons.delete, color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    onPressed: () => _addTimePicker(),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text("Add Frequency / Take",
                        style: TextStyle(color: Colors.white)),
                    style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFF00588E)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        _allFieldsValid() && !isSaving ? saveMedication : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _allFieldsValid() && !isSaving
                          ? const Color(0xFF00588E)
                          : Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    child: const Text("Submit",
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: Text("Medications - ${widget.elderlyName}",
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF00588E),
                fontSize: 18)),
        iconTheme: const IconThemeData(color: Color(0xFF00588E)),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("medication")
            .where("elderly_id", isEqualTo: widget.elderlyId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No medications found"));
          }

          final meds = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: meds.length,
            itemBuilder: (context, index) {
              final med = meds[index];
              final medData = med.data() as Map<String, dynamic>;
              final times = (medData["medication_times"] as List<dynamic>? ?? [])
                  .map((t) => (t as Timestamp).toDate())
                  .map((dt) => TimeOfDay(hour: dt.hour, minute: dt.minute))
                  .toList();

              // Build status list safely
              final statusList =
                  (medData["medication_status"] as List<dynamic>? ?? [])
                      .map((e) => e?.toString() ?? "Pending")
                      .toList();
              while (statusList.length < times.length) {
                statusList.add("Pending");
              }

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ExpansionTile(
                  title: Text(medData["medication_name"] ?? "Unnamed",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      "Dosage: ${medData["medication_dosage"] ?? ""}\nFrequency: ${medData["medication_frequency"] ?? ""}x/day"),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => startEditing(medData, med.id),
                          icon: const Icon(Icons.edit),
                          label: const Text("Edit"),
                        ),
                      ],
                    ),
                    for (var i = 0; i < times.length; i++)
                      ListTile(
                        title: Text("Take ${i + 1} at ${times[i].format(context)}"),
                        trailing: DropdownButton<String>(
                          value:
                              statusList[i] != "Pending" ? statusList[i] : null,
                          hint: const Text("Status"),
                          items: const [
                            DropdownMenuItem(
                                value: "Given", child: Text("Given")),
                            DropdownMenuItem(
                                value: "Missed", child: Text("Missed")),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              updateMedicationStatus(med.id, i, val);
                            }
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showMedicationBottomSheet,
        label: const Text("Add New Medication",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add),
        backgroundColor: const Color(0xFF00588E),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class MedicationDraft {
  final TextEditingController medNameController = TextEditingController();
  final TextEditingController dosageController = TextEditingController();
  final List<TimeOfDay> medTimes = [];

  MedicationDraft();

  void clear() {
    medNameController.clear();
    dosageController.clear();
    medTimes.clear();
  }

  void dispose() {
    medNameController.dispose();
    dosageController.dispose();
  }
}
