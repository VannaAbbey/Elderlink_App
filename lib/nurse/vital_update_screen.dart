import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'vital_logger.dart';

class VitalUpdateScreen extends StatefulWidget {
  final String vitalsId;
  final String elderlyId;
  final String elderlyName;
  final String assignedDate;
  final String? houseId;

  const VitalUpdateScreen({
    super.key,
    required this.vitalsId,
    required this.elderlyId,
    required this.elderlyName,
    required this.assignedDate,
    this.houseId,
  });

  @override
  State<VitalUpdateScreen> createState() => _VitalUpdateScreenState();
}

class _VitalUpdateScreenState extends State<VitalUpdateScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _getCurrentShift() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 14) return '1st';
    if (hour >= 14 && hour < 22) return '2nd';
    return '3rd';
  }

  final TextEditingController _bloodPressureController =
      TextEditingController();
  final TextEditingController _pulseRateController = TextEditingController();
  final TextEditingController _o2SatController = TextEditingController();
  final TextEditingController _temperatureController = TextEditingController();
  final TextEditingController _respiratoryRateController =
      TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isLoading = false;
  String? _currentNurseId;
  String? _currentNurseName;

  final List<String> _bloodPressureOptions = [
    '120/80',
    '110/70',
    '130/85',
    '140/90',
    '100/60',
    '150/95',
  ];
  final List<String> _pulseRateOptions = [
    '60',
    '65',
    '70',
    '75',
    '80',
    '85',
    '90',
    '95',
    '100',
  ];
  final List<String> _o2SatOptions = ['95', '96', '97', '98', '99', '100'];
  final List<String> _temperatureOptions = [
    '36.0',
    '36.5',
    '37.0',
    '37.5',
    '38.0',
    '38.5',
    '39.0',
  ];
  final List<String> _respiratoryRateOptions = [
    '12',
    '14',
    '16',
    '18',
    '20',
    '22',
    '24',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadExistingVitals();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentNurseId = user.uid;
      final nurseDoc = await _firestore.collection('users').doc(user.uid).get();
      if (nurseDoc.exists) {
        final data = nurseDoc.data();
        setState(() {
          _currentNurseName =
              '${data?['user_fname'] ?? ''} ${data?['user_lname'] ?? ''}'
                  .trim();
        });
      }
    }
  }

  Future<void> _loadExistingVitals() async {
    try {
      final doc = await _firestore
          .collection('vitals_daily')
          .doc(widget.vitalsId)
          .get();
      if (doc.exists) {
        final data = doc.data();
        final vitalValues =
            data?['vital_values'] as Map<String, dynamic>? ?? {};

        setState(() {
          _bloodPressureController.text =
              vitalValues['blood_pressure']?.toString() ?? '';
          _pulseRateController.text =
              vitalValues['pulse_rate']?.toString() ?? '';
          _o2SatController.text =
              vitalValues['oxygen_saturation']?.toString() ?? '';
          _temperatureController.text =
              vitalValues['temperature']?.toString() ?? '';
          _respiratoryRateController.text =
              vitalValues['respiratory_rate']?.toString() ?? '';
          _notesController.text = vitalValues['notes']?.toString() ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading vitals: $e')));
      }
    }
  }

  Future<void> _saveVitals() async {
    if (!_formKey.currentState!.validate()) return;

    if (_currentNurseId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User not authenticated')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentShift = _getCurrentShift();
      final now = Timestamp.now();

      final newVitalValues = {
        'blood_pressure': _bloodPressureController.text.trim(),
        'pulse_rate': _pulseRateController.text.trim(),
        'oxygen_saturation': _o2SatController.text.trim(),
        'temperature': _temperatureController.text.trim(),
        'respiratory_rate': _respiratoryRateController.text.trim(),
        'notes': _notesController.text.trim(),
      };

      await _firestore.collection('vitals_daily').doc(widget.vitalsId).update({
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

      await logVitalAction(
        vitalsId: widget.vitalsId,
        elderlyId: widget.elderlyId,
        elderlyName: widget.elderlyName,
        assignedDate: widget.assignedDate,
        actionType: 'vitals_update',
        shift: currentShift,
        nurseId: _currentNurseId,
        nurseName: _currentNurseName,
        newValue: newVitalValues,
        remarks: 'Vitals completed for $currentShift shift',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vitals saved successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving vitals: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _bloodPressureController.dispose();
    _pulseRateController.dispose();
    _o2SatController.dispose();
    _temperatureController.dispose();
    _respiratoryRateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Update Vitals - ${widget.elderlyName}'),
        backgroundColor: Colors.teal,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoCard(),
                    const SizedBox(height: 16),
                    _buildComboField(
                      'Blood Pressure',
                      _bloodPressureController,
                      _bloodPressureOptions,
                    ),
                    _buildComboField(
                      'Pulse Rate (bpm)',
                      _pulseRateController,
                      _pulseRateOptions,
                    ),
                    _buildComboField(
                      'O₂ Saturation (%)',
                      _o2SatController,
                      _o2SatOptions,
                    ),
                    _buildComboField(
                      'Temperature (°C)',
                      _temperatureController,
                      _temperatureOptions,
                    ),
                    _buildComboField(
                      'Respiratory Rate',
                      _respiratoryRateController,
                      _respiratoryRateOptions,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveVitals,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Save Vitals',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Elderly: ${widget.elderlyName}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Date: ${widget.assignedDate}'),
            Text('Shift: ${_getCurrentShift()}'),
          ],
        ),
      ),
    );
  }

  Widget _buildComboField(
    String label,
    TextEditingController controller,
    List<String> options,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: controller,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'Enter $label',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter $label';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.arrow_drop_down),
                onSelected: (value) => controller.text = value,
                itemBuilder: (context) => options.map((option) {
                  return PopupMenuItem(value: option, child: Text(option));
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
