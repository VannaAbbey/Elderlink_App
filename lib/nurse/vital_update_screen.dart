import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class VitalUpdateScreen extends StatefulWidget {
  final String assignmentId;
  final String elderlyId;
  final String elderlyName;
  final String? nurseName;
  final String? houseId;

  const VitalUpdateScreen({
    super.key,
    required this.assignmentId,
    required this.elderlyId,
    required this.elderlyName,
    this.nurseName,
    this.houseId,
  });

  @override
  State<VitalUpdateScreen> createState() => _VitalUpdateScreenState();
}

class _VitalUpdateScreenState extends State<VitalUpdateScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

  // Controllers for vital signs (editable combo box)
  final TextEditingController _bloodPressureController =
      TextEditingController();
  final TextEditingController _pulseRateController = TextEditingController();
  final TextEditingController _o2SatController = TextEditingController();
  final TextEditingController _temperatureController = TextEditingController();
  final TextEditingController _respiratoryRateController =
      TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isLoading = false;

  // Get current nurse ID from Firebase Auth
  String? get _currentNurseId => FirebaseAuth.instance.currentUser?.uid;

  // Predefined options for combo boxes (like medication management)
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
    _loadLastVitalData();
  }

  Future<void> _loadLastVitalData() async {
    try {
      // Get the latest vital signs for this elderly person
      final vitalsSnapshot = await _firestore
          .collection('vitals')
          .where('elderly_id', isEqualTo: widget.elderlyId)
          .orderBy('recorded_at', descending: true)
          .limit(1)
          .get();

      if (vitalsSnapshot.docs.isNotEmpty) {
        final lastVital = vitalsSnapshot.docs.first.data();

        setState(() {
          _bloodPressureController.text =
              lastVital['blood_pressure']?.toString() ?? '';
          _pulseRateController.text = lastVital['pulse_rate']?.toString() ?? '';
          _o2SatController.text =
              lastVital['oxygen_saturation']?.toString() ??
              lastVital['o2_sat']?.toString() ??
              ''; // 🔧 FIXED: Check both field names for compatibility
          _temperatureController.text =
              lastVital['temperature']?.toString() ?? '';
          _respiratoryRateController.text =
              lastVital['respiratory_rate']?.toString() ?? '';
        });
      }
    } catch (e) {
      print('Error loading last vital data: $e');
    }
  }

  // Editable combo box widget - allows typing OR selecting from dropdown
  Widget _buildEditableComboBox({
    required String label,
    required TextEditingController controller,
    required List<String> options,
    String? suffix,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Color(0xFF2C3E50),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            hintText: 'Type here or select from dropdown',
            suffixIcon: PopupMenuButton<String>(
              icon: const Icon(Icons.arrow_drop_down),
              onSelected: (String value) {
                controller.text = value;
              },
              itemBuilder: (BuildContext context) {
                return options.map((String option) {
                  return PopupMenuItem<String>(
                    value: option,
                    child: Text('$option${suffix ?? ''}'),
                  );
                }).toList();
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.grey),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF00588E), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveVitalData() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    print('🔄 Starting to save vital data...');
    print('🏥 Assignment ID: ${widget.assignmentId}');
    print('👴 Elderly ID: ${widget.elderlyId}');
    print('👩‍⚕️ Nurse Name: ${widget.nurseName}');
    print('🆔 Current Nurse ID: $_currentNurseId');
    print('📊 Vital Values:');
    print('   - Blood Pressure: ${_bloodPressureController.text}');
    print('   - Pulse Rate: ${_pulseRateController.text}');
    print('   - O2 Sat: ${_o2SatController.text}');
    print('   - Temperature: ${_temperatureController.text}');
    print('   - Respiratory Rate: ${_respiratoryRateController.text}');
    print('   - Notes: ${_notesController.text}');
    setState(() {
      _isLoading = true;
    });

    try {
      final now = DateTime.now();

      // 🔧 CLEANED: Prepare vital data for activity log with standardized field names
      final vitalValues = {
        'blood_pressure': _bloodPressureController.text.trim(),
        'pulse_rate': _pulseRateController.text.trim(),
        'oxygen_saturation': _o2SatController.text
            .trim(), // ✅ Standardized field name
        'temperature': _temperatureController.text.trim(),
        'respiratory_rate': _respiratoryRateController.text.trim(),
      };

      // 🔧 FIXED: Prepare activity log data using assignment ID
      final activityLogData = {
        'vital_assignment_id':
            widget.assignmentId, // Use existing assignment ID
        'elderly_id': widget.elderlyId,
        'elderly_name': widget.elderlyName,
        'assignment_id': widget.assignmentId,
        'house_id': widget.houseId,
        'shift': _getCurrentShift(),
        'action_type': 'vital_completed',
        'nurse_id': _currentNurseId ?? 'Unknown',
        'nurse_name': widget.nurseName ?? 'Unknown',
        'timestamp': Timestamp.fromDate(now),
        'old_values': {},
        'new_values': vitalValues,
        'remarks': _notesController.text
            .trim(), // ✅ FIXED: Use 'remarks' consistently
      };

      print('💾 Starting batch write operation...');

      // 🔧 FIXED: Use batch write for atomic operations (faster & more reliable)
      final batch = _firestore.batch();

      // 🔧 ULTRA CLEAN: First get existing assignment to preserve inheritance info
      final assignmentDoc = await _firestore
          .collection('vitals')
          .doc(widget.assignmentId)
          .get();
      final assignmentData = assignmentDoc.exists ? assignmentDoc.data()! : {};

      // Prepare update data with essential fields only
      final updateData = <String, dynamic>{
        // Assignment status
        'status': 'completed',
        'completed_at': Timestamp.fromDate(now), // ✅ Main completion timestamp
        // 🔧 CLEAN: Only the 5 vital fields from the form + notes
        'blood_pressure': _bloodPressureController.text.trim(),
        'pulse_rate': _pulseRateController.text.trim(),
        'oxygen_saturation': _o2SatController.text.trim(),
        'temperature': _temperatureController.text.trim(),
        'respiratory_rate': _respiratoryRateController.text.trim(),
        'remarks': _notesController.text
            .trim(), // ✅ FIXED: Use 'remarks' not 'vital_remarks'
        // ✅ Minimal recording tracking
        'recorded_by': _currentNurseId ?? 'Unknown',
        'recorded_by_name': widget.nurseName ?? 'Unknown',
      };

      // ✅ PRESERVE inheritance info if it exists
      if (assignmentData['inherited_from_shift'] != null) {
        updateData['inherited_from'] =
            '${assignmentData['inherited_from_nurse_name']} (${assignmentData['inherited_from_shift']} shift)';
      }

      batch.update(
        _firestore.collection('vitals').doc(widget.assignmentId),
        updateData,
      );

      // Write activity log
      batch.set(
        _firestore.collection('vital_activity_logs').doc(),
        activityLogData,
      );

      // Execute all operations atomically
      await batch.commit();

      // 🧹 CLEANUP: Remove any redundant fields from the document
      await _cleanupRedundantFields();

      print('✅ Batch write completed successfully - all data saved atomically');
      print('💾 Assignment document ID: ${widget.assignmentId}');
      print('📋 Assignment status updated to completed');
      print('📝 Activity log created');

      print('🎉 All database operations completed successfully!');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vital signs saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('❌ Error saving vital signs: $e');
      print('📊 Error details: ${e.toString()}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving vital signs: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 🧹 ULTRA CLEANUP: Remove ALL redundant fields from the vital document
  Future<void> _cleanupRedundantFields() async {
    try {
      final fieldsToRemove = [
        // Old field names
        'heart_rate', 'o2_sat',
        // Unused form fields
        'blood_pressure_systolic', 'blood_pressure_diastolic',
        // Redundant tracking fields (replaced with recorded_by/recorded_by_name)
        'recorded_at', 'recorded_by_nurse_id', 'updated_by_nurse', 'updated_at',
        'updated_by_nurse_id', 'updated_by_nurse_name', // Old tracking fields
        // 🔧 Remove redundant timestamp fields
        'last_updated', 'last_updated_at', 'vital_record_at',
        // 🔧 Remove unnecessary profile pic
        'elderly_profilePic',
        // 🔧 Remove old remarks field name
        'vital_remarks', // Keep only 'remarks'
      ];
      final updateData = <String, dynamic>{};
      for (String field in fieldsToRemove) {
        updateData[field] = FieldValue.delete();
      }

      if (updateData.isNotEmpty) {
        await _firestore
            .collection('vitals')
            .doc(widget.assignmentId)
            .update(updateData);
        print(
          '🧹 Cleaned up redundant fields from document: ${widget.assignmentId}',
        );
      }
    } catch (e) {
      print('⚠️ Error cleaning up fields: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Vital Signs - ${widget.elderlyName}'),
        backgroundColor: const Color(0xFF00588E),
        foregroundColor: Colors.white,
        elevation: 0,
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
                    // Patient Info Card
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.person_outline,
                              size: 40,
                              color: Color(0xFF00588E),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.elderlyName,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2C3E50),
                                    ),
                                  ),
                                  Text(
                                    'Nurse: ${widget.nurseName ?? 'Unknown'}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    'Date: ${DateFormat('MMM dd, yyyy - hh:mm a').format(DateTime.now())}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Vital Signs Form
                    const Text(
                      'Vital Signs',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _buildEditableComboBox(
                      label: 'Blood Pressure',
                      controller: _bloodPressureController,
                      options: _bloodPressureOptions,
                      suffix: ' mmHg',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter blood pressure';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    _buildEditableComboBox(
                      label: 'Pulse Rate',
                      controller: _pulseRateController,
                      options: _pulseRateOptions,
                      suffix: ' bpm',
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter pulse rate';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    _buildEditableComboBox(
                      label: 'O2 Saturation',
                      controller: _o2SatController,
                      options: _o2SatOptions,
                      suffix: '%',
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter O2 saturation';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    _buildEditableComboBox(
                      label: 'Temperature',
                      controller: _temperatureController,
                      options: _temperatureOptions,
                      suffix: ' °C',
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter temperature';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    _buildEditableComboBox(
                      label: 'Respiratory Rate',
                      controller: _respiratoryRateController,
                      options: _respiratoryRateOptions,
                      suffix: ' breaths/min',
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter respiratory rate';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Notes Field
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Notes (Optional)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF2C3E50),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _notesController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText:
                                'Enter any additional notes or observations...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Colors.grey),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF00588E),
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _saveVitalData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00588E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 2,
                        ),
                        child: const Text(
                          'Save Vital Signs',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
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
}
