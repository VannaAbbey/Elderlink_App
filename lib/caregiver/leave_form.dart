import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';
import '../services/leave_request_service.dart';

class LeaveForm extends StatefulWidget {
  const LeaveForm({super.key});

  @override
  State<LeaveForm> createState() => _LeaveFormState();
}

class _LeaveFormState extends State<LeaveForm> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  late TextEditingController _fullNameController;
  late TextEditingController _contactInfoController;
  final TextEditingController _emergencyContactController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  
  // Dropdown values
  String? _selectedLeaveType;
  final List<String> _leaveTypes = [
    'Sick Leave',
    'Vacation',
    'Emergency',
    'Personal',
    'Others'
  ];
  
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSubmitting = false;
  
  // Caregiver's assigned working days
  List<String> _assignedDays = [];
  String? _shiftStartTime; // Store shift start time (e.g., "08:00")

  @override
  void initState() {
    super.initState();
    // Initialize controllers with user data
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _fullNameController = TextEditingController(
      text: '${authProvider.userFirstName} ${authProvider.userLastName}'.trim()
    );
    _contactInfoController = TextEditingController(
      text: authProvider.userContactNum
    );
    
    // Load caregiver's assigned days
    _loadCaregiverSchedule();
  }
  
  /// Load caregiver's assigned working days from Firestore
  Future<void> _loadCaregiverSchedule() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final caregiverId = authProvider.currentUser?.uid;
      
      if (caregiverId == null) {
        print('⚠️ LeaveForm: No caregiver ID found');
        setState(() {
        });
        return;
      }
      
      print('🔍 LeaveForm: Loading schedule for caregiver: $caregiverId');
      
      // Query house_shift_assignments to get assigned days
      final assignSnapshot = await FirebaseFirestore.instance
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .limit(1)
          .get();
      
      if (assignSnapshot.docs.isNotEmpty) {
        final assignData = assignSnapshot.docs.first.data();
        final daysAssigned = List<String>.from(assignData['days_assigned'] ?? []);
        final startTime = assignData['start_time'] as String? ?? '00:00';
        
        setState(() {
          _assignedDays = daysAssigned;
          _shiftStartTime = startTime;
        });
        
        print('✅ LeaveForm: Assigned days loaded: $_assignedDays');
        print('✅ LeaveForm: Shift start time: $_shiftStartTime');
      } else {
        print('⚠️ LeaveForm: No assignment found for caregiver');
        setState(() {
        });
      }
    } catch (e) {
      print('❌ LeaveForm: Error loading caregiver schedule: $e');
      setState(() {
      });
    }
  }
  
  /// Check if a date falls on one of the caregiver's assigned working days
  bool _isWorkingDay(DateTime date) {
    if (_assignedDays.isEmpty) {
      // If no assigned days loaded, allow all dates (fallback)
      return true;
    }
    
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final dayName = weekdays[date.weekday - 1];
    
    return _assignedDays.contains(dayName);
  }
  
  /// Check if the caregiver's duty has already started for today
  bool _hasDutyStartedToday(DateTime date) {
    final now = DateTime.now();
    
    // Only check for today
    if (date.year != now.year || date.month != now.month || date.day != now.day) {
      return false; // Not today, so duty hasn't started
    }
    
    // Check if today is a working day
    if (!_isWorkingDay(date)) {
      return false; // Not a working day, so no duty
    }
    
    // Parse shift start time
    if (_shiftStartTime == null || _shiftStartTime!.isEmpty) {
      return false; // No start time defined, allow selection
    }
    
    try {
      final timeParts = _shiftStartTime!.split(':');
      if (timeParts.length != 2) {
        return false; // Invalid format
      }
      
      final shiftHour = int.parse(timeParts[0]);
      final shiftMinute = int.parse(timeParts[1]);
      
      final shiftStartDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        shiftHour,
        shiftMinute,
      );
      
      // If current time is past shift start time, duty has started
      final dutyStarted = now.isAfter(shiftStartDateTime) || now.isAtSameMomentAs(shiftStartDateTime);
      
      if (dutyStarted) {
        print('⏰ LeaveForm: Duty has already started today at $_shiftStartTime (current: ${now.hour}:${now.minute})');
      }
      
      return dutyStarted;
    } catch (e) {
      print('❌ LeaveForm: Error parsing shift start time: $e');
      return false; // On error, allow selection
    }
  }
  
  /// Check if a date is selectable in the date picker
  bool _isDateSelectable(DateTime date) {
    // First check if it's a working day
    if (!_isWorkingDay(date)) {
      return false;
    }
    
    // Then check if duty has already started for today
    if (_hasDutyStartedToday(date)) {
      return false;
    }
    
    return true;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _contactInfoController.dispose();
    _emergencyContactController.dispose();
    _reasonController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF00588e)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Leave Request', style: TextStyle(color: Color(0xFF00588e), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/background1.png',
              fit: BoxFit.cover,
            ),
          ),
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Header Section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 48,
                            color: const Color(0xFF00588e),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Submit Leave Request',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00588e),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Please fill out the form below to request time off',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // ...existing code...
                    // Form Fields Container and rest of the form
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFormField(
                            icon: Icons.person,
                            label: 'Full Name',
                            controller: _fullNameController,
                            enabled: false,
                            hint: 'Your full name (auto-filled)',
                          ),
                          const SizedBox(height: 20),
                          _buildFormField(
                            icon: Icons.phone,
                            label: 'Contact Information',
                            controller: _contactInfoController,
                            enabled: false,
                            hint: 'Your contact number (auto-filled)',
                          ),
                          const SizedBox(height: 20),
                          _buildFormField(
                            icon: Icons.contact_emergency,
                            label: 'Emergency Contact Person',
                            controller: _emergencyContactController,
                            hint: 'Name and phone number of emergency contact',
                            required: true,
                          ),
                          const SizedBox(height: 20),
                          _buildDropdownField(),
                          const SizedBox(height: 20),
                          _buildFormField(
                            icon: Icons.edit_note,
                            label: 'Reason for Leave',
                            controller: _reasonController,
                            hint: 'Please provide details about your leave request',
                            maxLines: 4,
                            required: true,
                          ),
                          const SizedBox(height: 20),
                          // Info message about working days
                          if (_assignedDays.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00588e).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF00588e).withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.info_outline,
                                        color: Color(0xFF00588e),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'You can only request leave for your assigned working days: ${_assignedDays.join(", ")}',
                                          style: const TextStyle(
                                            color: Color(0xFF00588e),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  // Check if today is a working day and duty has started
                                  if (_hasDutyStartedToday(DateTime.now())) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.schedule,
                                          color: Colors.orange,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Your duty has already started today. You cannot select today for leave.',
                                            style: const TextStyle(
                                              color: Colors.orange,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: _buildDateField(
                                  label: 'Start Date',
                                  controller: _startDateController,
                                  selectedDate: _startDate,
                                  onDateSelected: (date) {
                                    setState(() {
                                      _startDate = date;
                                      _startDateController.text = 
                                          '${date.day}/${date.month}/${date.year}';
                                    });
                                    // Validate date range after setting start date
                                    _validateDateRange();
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildDateField(
                                  label: 'End Date',
                                  controller: _endDateController,
                                  selectedDate: _endDate,
                                  onDateSelected: (date) {
                                    setState(() {
                                      _endDate = date;
                                      _endDateController.text = 
                                          '${date.day}/${date.month}/${date.year}';
                                    });
                                    // Validate date range after setting end date
                                    _validateDateRange();
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          // Submit Button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isSubmitting ? null : _submitLeaveRequest,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00588e),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                              child: _isSubmitting
                                  ? const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Text(
                                          'Submitting...',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Text(
                                      'Submit Leave Request',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormField({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    String? hint,
    bool enabled = true,
    bool required = false,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF00588e), size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00588e),
              ),
            ),
            if (required)
              const Text(
                ' *',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          enabled: enabled,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00588e), width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            filled: true,
            fillColor: enabled ? Colors.white : Colors.grey[50],
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          validator: required
              ? (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '$label is required';
                  }
                  return null;
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildDropdownField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.category, color: Color(0xFF00588e), size: 20),
            SizedBox(width: 8),
            Text(
              'Type of Leave',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00588e),
              ),
            ),
            Text(
              ' *',
              style: TextStyle(
                color: Colors.red,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedLeaveType,
          hint: Text(
            'Select leave type',
            style: TextStyle(color: Colors.grey[400]),
          ),
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00588e), width: 2),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          items: _leaveTypes.map((String type) {
            return DropdownMenuItem<String>(
              value: type,
              child: Text(type),
            );
          }).toList(),
          onChanged: (String? newValue) {
            setState(() {
              _selectedLeaveType = newValue;
            });
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please select a leave type';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildDateField({
    required String label,
    required TextEditingController controller,
    required DateTime? selectedDate,
    required Function(DateTime) onDateSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.calendar_today, color: Color(0xFF00588e), size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00588e),
              ),
            ),
            const Text(
              ' *',
              style: TextStyle(
                color: Colors.red,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          readOnly: true,
          decoration: InputDecoration(
            hintText: 'Select date',
            hintStyle: TextStyle(color: Colors.grey[400]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00588e), width: 2),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            suffixIcon: const Icon(Icons.calendar_today, color: Color(0xFF00588e)),
          ),
          onTap: () async {
            // Find the initial date for the picker
            DateTime initialPickerDate = selectedDate ?? DateTime.now();
            
            // If the initial date is not selectable, find the next selectable date
            if (!_isDateSelectable(initialPickerDate)) {
              DateTime candidate = initialPickerDate;
              bool found = false;
              // Search up to 60 days ahead for the next selectable date
              for (int i = 1; i <= 60; i++) {
                candidate = initialPickerDate.add(Duration(days: i));
                if (_isDateSelectable(candidate)) {
                  initialPickerDate = candidate;
                  found = true;
                  break;
                }
              }
              // If no selectable date found in 60 days, use today anyway (will be disabled)
              if (!found) {
                print('⚠️ LeaveForm: No selectable date found in next 60 days');
                initialPickerDate = DateTime.now();
              }
            }
            
            final DateTime? picked = await showDatePicker(
              context: context,
              initialDate: initialPickerDate,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              selectableDayPredicate: (DateTime date) {
                // Check if date is selectable (working day + duty not started)
                return _isDateSelectable(date);
              },
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: Color(0xFF00588e),
                      onPrimary: Colors.white,
                      surface: Colors.white,
                      onSurface: Colors.black,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (picked != null) {
              onDateSelected(picked);
            }
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please select $label';
            }
            return null;
          },
        ),
      ],
    );
  }

  Future<void> _submitLeaveRequest() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all required fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Additional validation for date range
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both start and end dates'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate dates using service
    if (!LeaveRequestService.validateLeaveDates(_startDate!, _endDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid dates. Start date cannot be in the past and end date must be after start date.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate maximum 3 days restriction
    final duration = _endDate!.difference(_startDate!).inDays + 1;
    if (duration > 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Leave request cannot exceed 3 days. Please select a shorter duration.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Check for overlapping leave requests
      final hasOverlap = await LeaveRequestService.hasOverlappingLeave(_startDate!, _endDate!);
      if (hasOverlap) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You already have a pending or approved leave request for these dates.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Submit leave request to database
      final requestId = await LeaveRequestService.submitLeaveRequest(
        fullName: _fullNameController.text.trim(),
        contactInfo: _contactInfoController.text.trim(),
        emergencyContact: _emergencyContactController.text.trim(),
        leaveType: _selectedLeaveType!,
        reason: _reasonController.text.trim(),
        startDate: _startDate!,
        endDate: _endDate!,
      );

      // Show success message with request ID
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Leave request submitted successfully!\nRequest ID: $requestId'),
          backgroundColor: const Color(0xFF00588e),
          duration: const Duration(seconds: 4),
        ),
      );

        // Save leave type for dialog before clearing form
        final leaveTypeForDialog = _selectedLeaveType;

        // Clear form after successful submission
        _emergencyContactController.clear();
        _reasonController.clear();
        _startDateController.clear();
        _endDateController.clear();
        setState(() {
          _selectedLeaveType = null;
          _startDate = null;
          _endDate = null;
        });

        // Show dialog with correct leave type
        _showSuccessDialog(requestId, leaveTypeForDialog);

    } catch (e) {
      print('Error submitting leave request: $e');
      
      String errorMessage;
      if (e.toString().contains('User not authenticated')) {
        errorMessage = 'Please log in to submit a leave request.';
      } else if (e.toString().contains('network')) {
        errorMessage = 'Network error. Please check your connection and try again.';
      } else {
        errorMessage = 'Failed to submit leave request. Please try again later.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _showSuccessDialog(String requestId, String? leaveType) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: const Color(0xFF00588e),
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text(
                'Success!',
                style: TextStyle(
                  color: Color(0xFF00588e),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your leave request has been submitted successfully and is now pending review.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Request Details:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00588e),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Request ID: $requestId'),
                    Text('Type: ${leaveType ?? 'N/A'}'),
                    Text('Status: Pending Review'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'You will be notified once your request has been reviewed.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'OK',
                style: TextStyle(
                  color: Color(0xFF00588e),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _validateDateRange() {
    if (_startDate != null && _endDate != null) {
      final duration = _endDate!.difference(_startDate!).inDays + 1;
      if (duration > 3) {
        _showMaxDaysExceededDialog();
        // Reset the end date
        setState(() {
          _endDate = null;
          _endDateController.clear();
        });
      }
    }
  }

  void _showMaxDaysExceededDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.warning,
                color: Colors.orange,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text(
                'Maximum Days Exceeded',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: const Text(
            'The maximum length of a leave request are only 3 days. Please choose another date.',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'OK',
                style: TextStyle(
                  color: Color(0xFF00588e),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}