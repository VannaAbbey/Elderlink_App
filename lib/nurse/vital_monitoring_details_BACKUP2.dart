// lib/nurse/vitals_monitoring_details.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'vital_logger.dart';

class VitalDetailScreen extends StatefulWidget {
  final String elderlyId;
  final String elderlyName;

  const VitalDetailScreen({
    super.key,
    required this.elderlyId,
    required this.elderlyName,
  });

  @override
  State<VitalDetailScreen> createState() => _VitalDetailScreenState();
}

class _VitalDetailScreenState extends State<VitalDetailScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _formKey = GlobalKey<FormState>();
  bool isSaving = false;

  late final VitalDraft draft;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _currentNurseId;
  String? _currentNurseName;

  String _getCurrentShift() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 14) return '1st';
    if (hour >= 14 && hour < 22) return '2nd';
    return '3rd';
  }

  @override
  void initState() {
    super.initState();
    draft = VitalDraft();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentNurseId = user.uid;
      final nurseDoc = await _firestore.collection('users').doc(user.uid).get();
      if (nurseDoc.exists && mounted) {
        setState(() {
          _currentNurseName = '${nurseDoc.data()?['firstName'] ?? ''} ${nurseDoc.data()?['lastName'] ?? ''}'.trim();
        });
      }
    }
  }

  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  bool _allFieldsValid() {
    return _formKey.currentState?.validate() == true;
  }

  Future<void> updateVital(String vitalsId) async {
    if (!_allFieldsValid()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill all fields correctly before saving."),
        ),
      );
      return;
    }

    final confirmed = await _showConfirmationDialog();
    if (!confirmed) return;

    if (_currentNurseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated')),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final currentShift = _getCurrentShift();
      final now = Timestamp.now();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final newVitalValues = {
        'blood_pressure': draft.bloodPressureController.text.trim(),
        'pulse_rate': draft.pulseRateController.text.trim(),
        'oxygen_saturation': draft.o2SatController.text.trim(),
        'temperature': draft.temperatureController.text.trim(),
        'respiratory_rate': draft.respiratoryRateController.text.trim(),
        'notes': draft.remarksController.text.trim(),
      };

      // Build vitals_id in format: {elderly_id}_{YYYY-MM-DD}
      final vitalsDocId = '${widget.elderlyId}_$today';

      await _firestore.collection('vitals_daily').doc(vitalsDocId).update({
        'vital_values': newVitalValues,
        'shift_status.$currentShift': {
          'status': 'completed',
          'completed_by': _currentNurseId,
          'completed_by_name': _currentNurseName ?? 'Unknown',
          'completed_at': now,
        },
        'any_completed': true,
        'updated_at': now,
      });

      await VitalLogger().logVitalAction(
        vitalsId: vitalsDocId,
        elderlyId: widget.elderlyId,
        elderlyName: widget.elderlyName,
        assignedDate: today,
        actionType: 'vitals_update',
        shift: currentShift,
        nurseId: _currentNurseId,
        nurseName: _currentNurseName,
        newValue: newVitalValues,
        remarks: 'Vitals updated from monitoring details for $currentShift shift',
      );

      if (mounted) {
        setState(() => isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Vitals updated successfully"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Error updating vitals: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _showConfirmationDialog() async {
      isSaving = false;
      draft.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vital record updated successfully.")),
      );
    }
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
                      "You are about to update vital records for ${widget.elderlyName}. "
                      "This action will be logged for auditing purposes.\n\n"
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
                            "I acknowledge that the information provided is accurate and complete.",
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
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                ElevatedButton(
                  onPressed: isChecked
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isChecked
                        ? const Color(0xFF00588E)
                        : Colors.grey,
                  ),
                  child: const Text("Submit"),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Vitals - ${widget.elderlyName}",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF00588E),
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF00588E)),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("vitals")
            .where("elderly_id", isEqualTo: widget.elderlyId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No vitals found"));
          }

          final vitals = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            data['vital_id'] = doc.id;
            return data;
          }).toList();

          vitals.sort((a, b) {
            final tA =
                (a['vital_record_at'] as Timestamp?)?.toDate() ??
                DateTime(2000);
            final tB =
                (b['vital_record_at'] as Timestamp?)?.toDate() ??
                DateTime(2000);
            return tB.compareTo(tA);
          });

          final latestVital = vitals.first;

          draft.loadFromData(latestVital);

          final verified = latestVital['vital_verify'] == true;
          final recordTime =
              (latestVital['vital_record_at'] as Timestamp?)?.toDate() ??
              DateTime.now();

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  _buildTextField(
                    "Blood Pressure",
                    draft.bloodPressureController,
                    "e.g. 120/80",
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    "Pulse Rate",
                    draft.pulseRateController,
                    "e.g. 72",
                    isNumber: true,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    "O₂ Saturation",
                    draft.o2SatController,
                    "e.g. 97",
                    isNumber: true,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    "Temperature",
                    draft.temperatureController,
                    "e.g. 36.7",
                    isNumber: true,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    "Respiratory Rate",
                    draft.respiratoryRateController,
                    "e.g. 18",
                    isNumber: true,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    "Remarks",
                    draft.remarksController,
                    "Optional",
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text("Verified: "),
                      Icon(
                        verified ? Icons.check_circle : Icons.cancel,
                        color: verified ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "Recorded at: ${DateFormat.yMMMd().add_jm().format(recordTime)}",
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: !isSaving
                          ? () => updateVital(latestVital['vital_id'])
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: !isSaving
                            ? const Color(0xFF00588E)
                            : Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text(
                        "Update Vitals",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    String hint, {
    bool isNumber = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      validator: (val) {
        if (val == null || val.trim().isEmpty) return "Required";
        if (isNumber && double.tryParse(val) == null) {
          return "Enter a valid number";
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class VitalDraft {
  final TextEditingController bloodPressureController = TextEditingController();
  final TextEditingController pulseRateController = TextEditingController();
  final TextEditingController o2SatController = TextEditingController();
  final TextEditingController temperatureController = TextEditingController();
  final TextEditingController respiratoryRateController =
      TextEditingController();
  final TextEditingController remarksController = TextEditingController();

  void loadFromData(Map<String, dynamic> data) {
    bloodPressureController.text = data["blood_pressure"] ?? "";
    pulseRateController.text = (data["pulse_rate"] ?? "").toString();
    o2SatController.text = (data["o2_sat"] ?? "").toString();
    temperatureController.text = (data["temperature"] ?? "").toString();
    respiratoryRateController.text = (data["respiratory_rate"] ?? "")
        .toString();
    remarksController.text = data["vital_remarks"] ?? "";
  }

  void clear() {
    bloodPressureController.clear();
    pulseRateController.clear();
    o2SatController.clear();
    temperatureController.clear();
    respiratoryRateController.clear();
    remarksController.clear();
  }

  void dispose() {
    bloodPressureController.dispose();
    pulseRateController.dispose();
    o2SatController.dispose();
    temperatureController.dispose();
    respiratoryRateController.dispose();
    remarksController.dispose();
  }
}
