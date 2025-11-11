import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'caregiver_sidebar.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../providers/cg_providers/absence_provider.dart';
import 'shift_logs.dart';
import '../services/cg_services/caregiver_shift_log_service.dart';
import '../services/cg_services/additional_log_service.dart';
import '../widgets/cg_widgets/notification_icon_button.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ShiftScreen extends StatefulWidget {
  final VoidCallback? onResetToHome;
  
  const ShiftScreen({super.key, this.onResetToHome});
  
  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  DateTime selectedDate = DateTime.now();
  final ScrollController _additionalLogsScrollController = ScrollController();
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    // Check absence status after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAbsenceStatus();
      // Set up listener for absence status changes
      _setupAbsenceListener();
    });
  }
  
  void _setupAbsenceListener() {
    print('👂 [Shift] Setting up absence listener');
    // Listen to absence provider changes
    final absenceProvider = Provider.of<AbsenceProvider>(context, listen: false);
    absenceProvider.addListener(_onAbsenceStatusChanged);
    print('✅ [Shift] Absence listener attached');
  }
  
  void _onAbsenceStatusChanged() {
    print('🔔 [Shift] Absence status changed callback fired');
    print('   mounted: $mounted, _dialogShown: $_dialogShown');
    
    if (!mounted) {
      print('⚠️ [Shift] Widget not mounted, ignoring');
      return;
    }
    
    final absenceProvider = Provider.of<AbsenceProvider>(context, listen: false);
    print('   isAbsentToday: ${absenceProvider.isAbsentToday}');
    print('   absenceType: ${absenceProvider.absenceType}');
    
    // If caregiver becomes absent and dialog not yet shown
    if (absenceProvider.isAbsentToday && !_dialogShown) {
      print('✅ [Shift] Will show absence dialog');
      _dialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          print('📱 [Shift] Showing absence dialog now');
          _showAbsenceDialog(context, absenceProvider.absenceType ?? 'absent');
        } else {
          print('⚠️ [Shift] Widget unmounted before showing dialog');
        }
      });
    }
    
    // If caregiver is no longer absent, reset dialog flag
    if (!absenceProvider.isAbsentToday && _dialogShown) {
      print('✅ [Shift] Resetting dialog flag (no longer absent)');
      _dialogShown = false;
    }
  }

  void _checkAbsenceStatus() {
    if (_dialogShown) return;
    
    final absenceProvider = Provider.of<AbsenceProvider>(context, listen: false);
    if (absenceProvider.isAbsentToday) {
      _dialogShown = true;
      _showAbsenceDialog(context, absenceProvider.absenceType ?? 'absent');
    }
  }

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

  void _showAdditionalLogModal(BuildContext context) async {
    // Load existing content for today's log
    final existingContent = await AdditionalLogService.getCurrentDayAdditionalLog();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        TextEditingController controller = TextEditingController(text: existingContent);
        bool acknowledged = false;
        bool isLoading = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                width: 340,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16.0),
                              child: Text(
                                'Additional Log',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF22688E),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 25, color: Colors.red),
                              onPressed: () {
                                _showClearConfirmationDialog(ctx, controller);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 25, color: Color(0xFF22688E)),
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(),
                    Container(
                      margin: const EdgeInsets.all(5),
                      child: TextField(
                        controller: controller,
                        maxLines: 10,
                        style: const TextStyle(fontSize: 16),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Type additional handover log here.',
                          hintStyle: TextStyle(fontStyle: FontStyle.italic, fontSize: 15),
                          isDense: true,
                          contentPadding: EdgeInsets.all(12)
                        ),
                        onChanged: (_) {
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: acknowledged,
                          activeColor: const Color(0xFF00588e),
                          onChanged: (val) {
                            setState(() {
                              acknowledged = val ?? false;
                            });
                          },
                        ),
                        Expanded(
                          child: Text(
                            'I acknowledge and accept full responsibility that the information that I provided is accurate and complete.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: (controller.text.trim().isNotEmpty && acknowledged && !isLoading)
                            ? () async {
                                setState(() {
                                  isLoading = true;
                                });
                                
                                try {
                                  await AdditionalLogService.saveAdditionalLog(controller.text.trim());
                                  if (ctx.mounted) {
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Additional log saved successfully!'),
                                        backgroundColor: Color(0xFF22688E),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error saving log: $e'),
                                        backgroundColor: Colors.red,
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                } finally {
                                  if (ctx.mounted) {
                                    setState(() {
                                      isLoading = false;
                                    });
                                  }
                                }
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (controller.text.trim().isNotEmpty && acknowledged && !isLoading)
                              ? Color(0xFF22688E)
                              : Colors.grey,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(32),
                          ),
                          elevation: 4,
                        ),
                        child: isLoading 
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Submit',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
  // End of dialog
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showClearConfirmationDialog(BuildContext parentContext, TextEditingController controller) {
    bool confirmClear = false;
    
    showDialog(
      context: parentContext,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: const Text(
                'Clear Additional Log',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF22688E),
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Are you sure that you want to clear all the additional log that you\'ve written so far?',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: confirmClear,
                        activeColor: const Color(0xFF22688E),
                        onChanged: (value) {
                          setState(() {
                            confirmClear = value ?? false;
                          });
                        },
                      ),
                      const Expanded(
                        child: Text(
                          'I confirm that I want to clear the additional log.',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: confirmClear
                      ? () async {
                          try {
                            // Clear the text field
                            controller.clear();
                            
                            // Soft delete the additional log from database
                            await AdditionalLogService.deleteAdditionalLog(DateTime.now());
                            
                            Navigator.of(ctx).pop(); // Close confirmation dialog
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Additional log cleared successfully!'),
                                backgroundColor: Color(0xFF22688E),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error clearing log: $e'),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: confirmClear ? Colors.red : Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Clear',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 7)),
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
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  bool isSidebarOpen = false;
  void toggleSidebar() => setState(() => isSidebarOpen = !isSidebarOpen);

  @override
  void dispose() {
    // Remove listener to prevent memory leaks
    try {
      final absenceProvider = Provider.of<AbsenceProvider>(context, listen: false);
      absenceProvider.removeListener(_onAbsenceStatusChanged);
    } catch (e) {
      // Context might be invalid during disposal, ignore
    }
    _additionalLogsScrollController.dispose();
    super.dispose();
  }

  /// Gets shift logs (tasks, emergency alerts, incident reports) for the current authenticated caregiver only
  Stream<List<Map<String, dynamic>>> _getCurrentCaregiverShiftLogs(DateTime date) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Return empty stream if no user is authenticated
      return Stream.value([]);
    }
    
    print('🔍 Getting shift logs for current caregiver: ${user.uid} on date: $date');
    return CaregiverShiftLogService.getShiftLogsForCaregiverAndDate(user.uid, date);
  }

  /// Gets additional logs for the current authenticated caregiver only
  Stream<String> _getCurrentCaregiverAdditionalLog(DateTime date) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Return empty stream if no user is authenticated
      return Stream.value('');
    }
    
    print('🔍 Getting additional logs for current caregiver: ${user.uid} on date: $date');
    return AdditionalLogService.getAdditionalLogForDate(date);
  }

  @override
  Widget build(BuildContext context) {
    Future<void> handleLogout() async {
      final authProvider = Provider.of<app_auth.AuthProvider>(context, listen: false);
      await authProvider.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/get_started',
          (route) => false,
        );
      }
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
            const SizedBox(height: 16), // Add space above AppBar
            Expanded(
              child: Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  backgroundColor: const Color(0x00FFFFFF),
                  surfaceTintColor: Colors.white,
                  scrolledUnderElevation: 0,
                  elevation: 0,
                  title: const Text('Shift Handover',
                      style: TextStyle(
                          color: Color(0xFF00588e),
                          fontWeight: FontWeight.bold)),
                  centerTitle: true,
                  leading: IconButton(
                    icon: const Icon(Icons.menu, color: Color(0xFF00588e)),
                    onPressed: toggleSidebar,
                  ),
                  actions: [
                    NotificationIconButton(
                      iconColor: Color(0xFF00588e),
                      iconSize: 35,
                    ),
                  ],
                ),
                body: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            // SizedBox for Task Summary Section:
                            SizedBox(
                              width: double.infinity,
                              height: 350,
                              child: Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                color: const Color(0xFFB3E0E8),
                                elevation: 2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Center(
                                              child: Column(
                                                children: [
                                                  Text(
                                                    _formattedDate(selectedDate),
                                                    style: const TextStyle(
                                                      fontSize: 20,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFF00588e),
                                                    ),
                                                  ),
                                                  Text(
                                                    'Shift Logs for Selected Date',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Color(0xFF00588e),
                                                      fontStyle: FontStyle.italic,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () => _selectDate(context),
                                            child: const Icon(Icons.calendar_today, color: Color(0xFF00588e), size: 28),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      const Divider(thickness: 1, color: Color(0xFF00588e)),
                                      const SizedBox(height: 9),
                                      // Task summary row - Real-time data from Firebase (filtered by current caregiver)
                                      Expanded(
                                        child: SingleChildScrollView(
                                          child: StreamBuilder<List<Map<String, dynamic>>>(
                                            stream: _getCurrentCaregiverShiftLogs(selectedDate),
                                            builder: (context, snapshot) {
                                              if (snapshot.connectionState == ConnectionState.waiting) {
                                                return const Center(
                                                  child: CircularProgressIndicator(
                                                    color: Color(0xFF00588e),
                                                  ),
                                                );
                                              }
                                              
                                              if (snapshot.hasError) {
                                                return Center(
                                                  child: Text(
                                                    'Error loading shift logs: ${snapshot.error}',
                                                    style: const TextStyle(color: Colors.red),
                                                  ),
                                                );
                                              }
                                              
                                              final shiftLogs = snapshot.data ?? [];
                                              
                                              if (shiftLogs.isEmpty) {
                                                return const Center(
                                                  child: Text(
                                                    'No shift logs to be recorded.',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontStyle: FontStyle.italic,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                );
                                              }
                                              
                                              return Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: shiftLogs.asMap().entries.map((entry) {
                                                  final index = entry.key;
                                                  final log = entry.value;
                                                  
                                                  final completionTime = CaregiverShiftLogService.formatCompletionTime(
                                                    log['completion_time'] as Timestamp?,
                                                  );
                                                  
                                                  final logMessage = CaregiverShiftLogService.formatLogMessage(log);
                                                  
                                                  final description = CaregiverShiftLogService.getLogDescription(log);
                                                  
                                                  return Column(
                                                    children: [
                                                      _taskSummaryRow(
                                                        time: completionTime,
                                                        text: logMessage,
                                                        reason: description,
                                                      ),
                                                      if (index < shiftLogs.length - 1) 
                                                        const SizedBox(height: 10),
                                                    ],
                                                  );
                                                }).toList(),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // SizedBox for Additional Logs Section:
                            SizedBox(
                              width: double.infinity,
                              height: 150,
                              child: Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                                color: const Color(0xFFB3E0E8),
                                elevation: 2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Additional Logs:',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF00588e),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Divider(thickness: 1, color: Color(0xFF00588e)),
                                      const SizedBox(height: 8),
                                      Expanded(
                                        child: StreamBuilder<String>(
                                          stream: _getCurrentCaregiverAdditionalLog(selectedDate),
                                          builder: (context, snapshot) {
                                            if (snapshot.connectionState == ConnectionState.waiting) {
                                              return const Center(
                                                child: CircularProgressIndicator(
                                                  color: Color(0xFF00588e),
                                                  strokeWidth: 2,
                                                ),
                                              );
                                            }
                                            
                                            if (snapshot.hasError) {
                                              return Text(
                                                'Error loading additional log: ${snapshot.error}',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.red,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              );
                                            }
                                            
                                            final additionalLogContent = snapshot.data ?? '';
                                            
                                            if (additionalLogContent.isEmpty) {
                                              return const Center(
                                                child: Text(
                                                  'No additional notes for this date.',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.grey,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              );
                                            }                                            
                                            return Directionality(
                                              textDirection: TextDirection.ltr,
                                              child: Scrollbar(
                                                controller: _additionalLogsScrollController,
                                                child: SingleChildScrollView(
                                                  controller: _additionalLogsScrollController,
                                                  scrollDirection: Axis.vertical,
                                                  child: Align(
                                                    alignment: Alignment.topLeft,
                                                    child: Text(
                                                      additionalLogContent,
                                                      textDirection: TextDirection.ltr,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontStyle: FontStyle.italic,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16, left: 32, right: 32, top: 8),
                      child: Column(
                        children: [
                          // Write Additional Log Button
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () async {
                                // Check if caregiver is on duty before allowing access to Write Additional Log
                                final isOnDuty = await _isCaregiverOnDuty();
                                if (!isOnDuty) {
                                  _showNotOnDutyToastForAdditionalLog();
                                  return;
                                }

                                _showAdditionalLogModal(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF22688E),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(32),
                                ),
                                elevation: 4,
                              ),
                              child: const Text(
                                'Write Additional Log',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 15),

                          // View Shift Logs Button
                          SizedBox(
                            width: 200,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () async {
                                // Check if caregiver is on duty before allowing access to Shift Logs
                                final isOnDuty = await _isCaregiverOnDuty();
                                if (!isOnDuty) {
                                  _showNotOnDutyToast();
                                  return;
                                }

                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const ShiftLogsScreen(),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF22688E),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(32),
                                ),
                                elevation: 4,
                              ),
                              child: const Text(
                                'Shift Logs',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
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

    String _formattedDate(DateTime date) {
      return '${_monthName(date.month)} ${date.day}, ${date.year}';
    }

    String _monthName(int month) {
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return months[month - 1];
    }

    Widget _taskSummaryRow({required String time, required String text, String? reason}) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Icon(Icons.circle, color: Colors.red, size: 12),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 16, color: Colors.black),
                    children: [
                      TextSpan(
                        text: '$time : ',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: text),
                    ],
                  ),
                ),
                if (reason != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 0, top: 2),
                    child: Text(
                      reason,
                      style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    /// Validates if the caregiver is currently on duty
    /// Returns true if on duty, false otherwise
    Future<bool> _isCaregiverOnDuty() async {
      try {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) {
          print('🔴 SHIFT: No user logged in');
          return false;
        }

        final caregiverId = currentUser.uid;
        final now = DateTime.now();
        
        print('🔍 SHIFT: Checking duty for $caregiverId at ${now.toString()}');

        // Get caregiver's house assignment
        final houseSnapshot = await FirebaseFirestore.instance
            .collection('house_shift_assignments')
            .where('user_id', isEqualTo: caregiverId)
            .where('user_type', isEqualTo: 'caregiver')
            .where('is_current', isEqualTo: true)
            .limit(1)
            .get();

        print('🔍 SHIFT: Found ${houseSnapshot.docs.length} house assignments');

        if (houseSnapshot.docs.isEmpty) {
          print('🔴 SHIFT: No valid house assignment found');
          return false;
        }

        final houseData = houseSnapshot.docs.first.data();
        final daysAssigned = List<String>.from(houseData['days_assigned'] ?? []);
        
        // Get dates from nested schedule_period object
        final schedulePeriod = houseData['schedule_period'] as Map<String, dynamic>?;
        
        if (schedulePeriod == null) {
          print('🔴 SHIFT: schedule_period is null!');
          return false;
        }
        
        final startDateTimestamp = schedulePeriod['start_date'] as Timestamp?;
        final endDateTimestamp = schedulePeriod['end_date'] as Timestamp?;
        
        if (startDateTimestamp == null || endDateTimestamp == null) {
          print('🔴 SHIFT: start_date or end_date is null in schedule_period!');
          return false;
        }
        
        final startDate = startDateTimestamp.toDate();
        final endDate = endDateTimestamp.toDate();

        // Normalize dates to compare only date parts (ignore time)
        final nowDate = DateTime(now.year, now.month, now.day);
        final normalizedStartDate = DateTime(startDate.year, startDate.month, startDate.day);
        final normalizedEndDate = DateTime(endDate.year, endDate.month, endDate.day);

        print('🔍 SHIFT: ========== HOUSE ASSIGNMENT DATA ==========');
        print('🔍 SHIFT: Days assigned: $daysAssigned');
        print('🔍 SHIFT: Start date: ${startDate.toString()}');
        print('🔍 SHIFT: End date: ${endDate.toString()}');
        print('🔍 SHIFT: Current date/time: ${now.toString()}');
        print('🔍 SHIFT: nowDate.isBefore(normalizedStartDate): ${nowDate.isBefore(normalizedStartDate)}');
        print('🔍 SHIFT: nowDate.isAfter(normalizedEndDate): ${nowDate.isAfter(normalizedEndDate)}');
        print('🔍 SHIFT: ==================================================');

        // Check if current date is within assignment period
        if (nowDate.isBefore(normalizedStartDate) || nowDate.isAfter(normalizedEndDate)) {
          print('🔴 SHIFT: Current date outside assignment period');
          return false;
        }

        // Check if current time is within shift hours
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
          dayToCheck = _getDayName(previousDay.weekday);
          print('🌙 SHIFT: Overnight end period - checking previous day: $dayToCheck');
        } else {
          // Regular shift or "start period" of overnight shift or after shift ends
          dayToCheck = _getDayName(now.weekday);
          print('☀️ SHIFT: Regular/overnight start - checking current day: $dayToCheck');
        }

        print('🔍 SHIFT: Shift times: $startHour:${startMinute.toString().padLeft(2, '0')} - $endHour:${endMinute.toString().padLeft(2, '0')}');
        print('🔍 SHIFT: Is overnight: $isOvernightShift');
        print('🔍 SHIFT: Day to check: $dayToCheck');

        // Check if the determined day is an assigned day
        if (!daysAssigned.contains(dayToCheck)) {
          print('🔴 SHIFT: Day $dayToCheck not in assigned days');
          return false;
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

        // Handle overnight shifts (e.g., 22:00 - 06:00)
        if (calculatedShiftEnd.isBefore(calculatedShiftStart)) {
          if (now.isBefore(calculatedShiftEnd)) {
            calculatedShiftStart = calculatedShiftStart.subtract(const Duration(days: 1));
          } else {
            calculatedShiftEnd = calculatedShiftEnd.add(const Duration(days: 1));
          }
        }

        final isWithinShift = !(now.isBefore(calculatedShiftStart) || now.isAfter(calculatedShiftEnd));

        print('🔍 SHIFT: ========== SHIFT TIME VALIDATION ==========');
        print('🔍 SHIFT: Start time from DB: $startTime');
        print('🔍 SHIFT: End time from DB: $endTime');
        print('🔍 SHIFT: Parsed start hour:minute: $startHour:$startMinute');
        print('🔍 SHIFT: Parsed end hour:minute: $endHour:$endMinute');
        print('🔍 SHIFT: Shift start: $calculatedShiftStart');
        print('🔍 SHIFT: Shift end: $calculatedShiftEnd');
        print('🔍 SHIFT: Current time (now): $now');
        print('🔍 SHIFT: now.isBefore(calculatedShiftStart): ${now.isBefore(calculatedShiftStart)}');
        print('🔍 SHIFT: now.isAfter(calculatedShiftEnd): ${now.isAfter(calculatedShiftEnd)}');
        print('🔍 SHIFT: Within shift: $isWithinShift');
        print('🔍 SHIFT: ===========================================');

        return isWithinShift;
      } catch (e) {
        print('🔴 SHIFT Error checking duty status: $e');
        return false;
      }
    }

    /// Shows a dialog message for when caregiver is not on duty
    void _showNotOnDutyDialog(String title, String message) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
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

    /// Shows a dialog message for when caregiver is not on duty for shift logs
    void _showNotOnDutyToast() {
      _showNotOnDutyDialog(
        'Unable to access shift logs',
        'You are currently not allowed to access the shift logs right now.'
      );
    }

    /// Shows a dialog message for when caregiver is not on duty for additional logs
    void _showNotOnDutyToastForAdditionalLog() {
      _showNotOnDutyDialog(
        'Unable to add additional logs',
        'You are currently not allowed to write any additional logs right now.'
      );
    }

    /// Helper function to get day name from weekday number
    String _getDayName(int weekday) {
      switch (weekday) {
        case DateTime.monday:
          return 'Monday';
        case DateTime.tuesday:
          return 'Tuesday';
        case DateTime.wednesday:
          return 'Wednesday';
        case DateTime.thursday:
          return 'Thursday';
        case DateTime.friday:
          return 'Friday';
        case DateTime.saturday:
          return 'Saturday';
        case DateTime.sunday:
          return 'Sunday';
        default:
          return '';
      }
    }
}