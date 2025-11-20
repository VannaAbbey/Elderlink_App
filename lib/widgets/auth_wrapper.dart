import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/cg_providers/absence_provider.dart';
import '../services/cg_services/leave_notification_listener.dart';
import '../services/cg_services/missed_task_monitor_service.dart';
import '../services/medication_missed_monitor_service.dart';
import '../auth/get_started.dart';
import '../caregiver/home.dart';
import '../nurse/home.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _absenceInitialized = false;
  bool _leaveListenerInitialized = false;
  bool _missedTaskMonitorInitialized = false;
  bool _emergencyListenerInitialized = false;

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, AbsenceProvider>(
      builder: (context, authProvider, absenceProvider, child) {
        // If user is not authenticated, show get started page
        if (!authProvider.isAuthenticated) {
          _absenceInitialized = false; // Reset flag on logout
          _leaveListenerInitialized = false; // Reset leave listener flag
          _missedTaskMonitorInitialized =
              false; // Reset missed task monitor flag

          // Stop all background services on logout
          MissedTaskMonitorService().stopMonitoring();
          LeaveNotificationListener().dispose();

          return const GetStartedPage();
        }

        // If user is authenticated but userData is null, show minimal loading
        if (authProvider.userData == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Initialize absence tracking once user data is loaded
        final userId = authProvider.currentUser?.uid;
        if (userId != null && !_absenceInitialized) {
          _absenceInitialized = true;
          // Initialize absence tracking in the background
          WidgetsBinding.instance.addPostFrameCallback((_) {
            absenceProvider.initializeAbsenceTracking(userId);
          });
        }

        // User is authenticated, has data - navigate based on role
        // (Removed absence blocking - absent caregivers can now access the app with limited functionality)
        final userRole = authProvider.userRole;

        // Initialize emergency listener for nurses
        if (userId != null &&
            !_emergencyListenerInitialized &&
            userRole == 'nurse') {
          _emergencyListenerInitialized = true;
          // Initialize emergency listener in the background
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Import the main.dart file to access the listener method
            // Since we can't directly call it, we'll need to trigger it differently
            // For now, let's trigger a rebuild of MyApp or find another way
          });
        }

        // Initialize medication missed monitor for nurses
        if (userId != null && userRole == 'nurse') {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            print(
              '🔄 Initializing MedicationMissedMonitorService for nurse: $userId',
            );
            if (!MedicationMissedMonitorService().isRunning) {
              print('▶️ Starting MedicationMissedMonitorService...');
              await MedicationMissedMonitorService().start();
              print('✅ MedicationMissedMonitorService started successfully');
            } else {
              print('ℹ️ MedicationMissedMonitorService already running');
            }
          });
        }

        // Initialize or restart missed task monitor for caregivers
        if (userId != null &&
            !_missedTaskMonitorInitialized &&
            userRole == 'caregiver') {
          _missedTaskMonitorInitialized = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!MissedTaskMonitorService().isMonitoring) {
              await MissedTaskMonitorService().startMonitoring();
            }
          });
        }

        // Initialize leave notification listener for caregivers and nurses
        if (userId != null &&
            !_leaveListenerInitialized &&
            (userRole == 'caregiver' || userRole == 'nurse')) {
          _leaveListenerInitialized = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            print(
              '🔔 Initializing LeaveNotificationListener for $userRole: $userId',
            );
            await LeaveNotificationListener().initialize();
            print('✅ LeaveNotificationListener initialized successfully');
          });
        }

        switch (userRole) {
          case 'administrator':
            return const CaregiverHomeScreen();
          case 'nurse':
            return const NurseHomeScreen();
          case 'caregiver':
          default:
            return const CaregiverHomeScreen();
        }
      },
    );
  }
}
