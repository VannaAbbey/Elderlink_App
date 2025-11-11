import 'package:flutter/material.dart';
import 'dart:async';
import '../../models/cg_models/nurse_cg_absence.dart';
import '../../models/cg_models/temporary_assignment.dart';
import '../../services/cg_services/absence_service.dart';

/// Provider to manage and track absence status for caregivers/nurses
class AbsenceProvider extends ChangeNotifier {
  NurseCgAbsence? _currentAbsence;
  List<TemporaryAssignment> _temporaryAssignments = [];
  List<String> _temporaryElderlyIds = [];
  bool _isLoading = false;
  String? _error;
  StreamSubscription<NurseCgAbsence?>? _absenceSubscription;
  StreamSubscription<List<TemporaryAssignment>>? _assignmentsSubscription;

  // Getters
  NurseCgAbsence? get currentAbsence => _currentAbsence;
  List<TemporaryAssignment> get temporaryAssignments => _temporaryAssignments;
  List<String> get temporaryElderlyIds => _temporaryElderlyIds;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  /// Check if the user is currently absent/on leave for today
  bool get isAbsentToday => _currentAbsence != null;
  
  /// Get the absence type (absent or leave)
  String? get absenceType => _currentAbsence?.absenceType;
  
  /// Check if user has temporary elderly assignments today
  bool get hasTemporaryAssignments => _temporaryAssignments.isNotEmpty;

  /// Initialize absence tracking for a specific user
  /// This sets up real-time listeners for absence and temporary assignments
  Future<void> initializeAbsenceTracking(String userId) async {
    print('🔧 Initializing absence tracking for user: $userId');
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Cancel any existing subscriptions
      await cancelAbsenceTracking();

      // Set up real-time listener for absence status
      _absenceSubscription = AbsenceService.listenToTodayAbsence(userId).listen(
        (absence) async {
          print('📡 Absence status update: ${absence?.toString() ?? 'No absence'}');
          
          final wasAbsent = _currentAbsence != null;
          final isAbsent = absence != null;
          
          // If absence is detected and it's new, auto-mark tasks
          if (isAbsent && !wasAbsent) {
            print('🔄 New absence detected, auto-marking tasks as incomplete...');
            await AbsenceService.autoMarkTasksForAbsence(
              userId,
              DateTime.now(),
              absence.absenceType,
            );
          }
          
          // If absence has ended (was absent, now not absent)
          if (wasAbsent && !isAbsent) {
            print('✅ Absence has ended - caregiver is now present');
          }
          
          _currentAbsence = absence;
          _error = null;
          notifyListeners();
        },
        onError: (error) {
          print('❌ Error listening to absence: $error');
          _error = 'Failed to check absence status: $error';
          notifyListeners();
        },
      );

      // Set up real-time listener for temporary assignments
      _assignmentsSubscription = AbsenceService.listenToTodayTemporaryAssignmentsTo(userId).listen(
        (assignments) {
          print('📡 Temporary assignments update: ${assignments.length} assignment(s)');
          _temporaryAssignments = assignments;
          
          // Extract all elderly IDs from assignments
          final elderlyIds = <String>{};
          for (final assignment in assignments) {
            elderlyIds.addAll(assignment.elderlyIds);
          }
          _temporaryElderlyIds = elderlyIds.toList();
          
          print('📋 Total temporary elderly: ${_temporaryElderlyIds.length}');
          notifyListeners();
        },
        onError: (error) {
          print('❌ Error listening to temporary assignments: $error');
          _error = 'Failed to load temporary assignments: $error';
          notifyListeners();
        },
      );

      _isLoading = false;
      notifyListeners();
      print('✅ Absence tracking initialized successfully');
    } catch (e) {
      print('❌ Error initializing absence tracking: $e');
      _error = 'Failed to initialize absence tracking: $e';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Check absence status without setting up listeners
  /// Useful for one-time checks
  Future<void> checkAbsenceStatus(String userId) async {
    print('🔍 Checking absence status for user: $userId');
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentAbsence = await AbsenceService.checkTodayAbsence(userId);
      
      if (_currentAbsence != null) {
        print('⚠️ User is ${_currentAbsence!.absenceType} today');
      } else {
        print('✅ User is not absent today');
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      print('❌ Error checking absence status: $e');
      _error = 'Failed to check absence status: $e';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Load temporary assignments for the current user
  Future<void> loadTemporaryAssignments(String userId) async {
    print('📋 Loading temporary assignments for user: $userId');
    
    try {
      _temporaryAssignments = await AbsenceService.getTodayTemporaryAssignmentsTo(userId);
      _temporaryElderlyIds = await AbsenceService.getTodayTemporaryElderlyIds(userId);
      
      print('✅ Loaded ${_temporaryAssignments.length} temporary assignments');
      print('✅ Total temporary elderly: ${_temporaryElderlyIds.length}');
      
      notifyListeners();
    } catch (e) {
      print('❌ Error loading temporary assignments: $e');
      _error = 'Failed to load temporary assignments: $e';
      notifyListeners();
    }
  }

  /// Cancel all absence tracking subscriptions
  Future<void> cancelAbsenceTracking() async {
    print('🛑 Cancelling absence tracking');
    
    await _absenceSubscription?.cancel();
    await _assignmentsSubscription?.cancel();
    
    _absenceSubscription = null;
    _assignmentsSubscription = null;
    
    print('✅ Absence tracking cancelled');
  }

  /// Refresh absence data manually
  Future<void> refreshAbsenceData(String userId) async {
    print('🔄 Refreshing absence data for user: $userId');
    
    _isLoading = true;
    notifyListeners();

    try {
      await checkAbsenceStatus(userId);
      await loadTemporaryAssignments(userId);
      
      _isLoading = false;
      notifyListeners();
      print('✅ Absence data refreshed');
    } catch (e) {
      print('❌ Error refreshing absence data: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear all absence data (for logout)
  void clearAbsenceData() {
    print('🧹 Clearing absence data');
    
    _currentAbsence = null;
    _temporaryAssignments = [];
    _temporaryElderlyIds = [];
    _error = null;
    _isLoading = false;
    
    notifyListeners();
  }

  /// Get user-friendly absence message
  String getAbsenceMessage() {
    if (_currentAbsence == null) {
      return 'You are on duty today';
    }

    final type = _currentAbsence!.absenceType == 'leave' ? 'on leave' : 'absent';
    return 'You are currently $type for today';
  }

  /// Check if user can access app functions today
  bool canAccessAppFunctions() {
    return !isAbsentToday;
  }

  @override
  void dispose() {
    cancelAbsenceTracking();
    super.dispose();
  }
}