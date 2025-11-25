import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'vital_update_screen.dart';
import 'follow_up_vitals_selection.dart';
import 'notification_service.dart';

class UpcomingVitalsTab extends StatefulWidget {
  final String houseId;
  final String? nurseName;
  final DateTime? selectedDate;

  const UpcomingVitalsTab({
    super.key,
    required this.houseId,
    required this.nurseName,
    this.selectedDate,
  });

  @override
  State<UpcomingVitalsTab> createState() => _UpcomingVitalsTabState();
}

// ⚠️ IMPORTANT ARCHITECTURAL DECISION:
// This class NEVER deletes vital assignment records from the database.
// Instead, it updates their status to 'reassigned' or 'inactive' to preserve history.
// Changes in house_shift_assignments and elderly_assignments are reflected in vitals
// through status updates and field modifications, not record deletion.
// This ensures complete audit trail and prevents data loss.

class _UpcomingVitalsTabState extends State<UpcomingVitalsTab>
    with AutomaticKeepAliveClientMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  List<Map<String, dynamic>>? _upcomingVitals;
  bool _isNotAssignedToShift = false;
  // Simple in-memory cache per houseId
  static final Map<String, List<Map<String, dynamic>>> _houseVitalsCache = {};
  static final Map<String, DateTime> _houseVitalsCacheTime = {};
  late DateTime _selectedDate;

  // Real-time listeners for schedule/assignment changes
  StreamSubscription<QuerySnapshot>? _assignmentListener;
  StreamSubscription<QuerySnapshot>? _shiftListener;

  String _getCurrentShift() {
    final currentHour = DateTime.now().hour;
    if (currentHour >= 6 && currentHour < 14) return "1st";
    if (currentHour >= 14 && currentHour < 22) return "2nd";
    return "3rd";
  }

  Future<bool> _isNurseAssignedToCurrentShift(String nurseId) async {
    final currentShift = _getCurrentShift();
    final currentDay = _getCurrentDay();

    try {
      final shiftQuery = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .where('days_assigned', arrayContains: currentDay)
          .get();

      return shiftQuery.docs.isNotEmpty;
    } catch (e) {
      print('❌ Error checking shift assignment: $e');
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.selectedDate ?? DateTime.now();

    // 🚀 CRITICAL: Check cache IMMEDIATELY before first build to prevent "Unknown" flash
    final cacheKey = widget.houseId + (widget.nurseName ?? "");
    if (_houseVitalsCache.containsKey(cacheKey)) {
      print('⚡ initState: Loading from cache IMMEDIATELY for instant display!');
      _upcomingVitals = _houseVitalsCache[cacheKey];
      _isLoading = false; // Data already available
    } else {
      // 🔧 CRITICAL FIX: Initialize with empty list instead of null to prevent "Unknown" flash
      print('⚡ initState: No cache found - initializing with empty list');
      _upcomingVitals = [];
    }

    // Initialize real-time listeners for schedule/assignment changes
    _initializeListeners();
    // Prewarm nurse id lookup and start loading vitals
    _prewarm();
    // Schedule notifications for existing vital tasks
    _scheduleNotificationsForExistingVitals();
  }

  /// Initialize real-time listeners for auto-updates
  void _initializeListeners() async {
    try {
      final nurseId = await _getCachedNurseId();
      if (nurseId == null) {
        debugPrint('❌ Cannot initialize listeners: No nurse ID');
        return;
      }

      debugPrint(
        '🔄 Initializing vitals assignment listeners for nurse: $nurseId',
      );

      // Listen to elderly_assignments changes
      _assignmentListener = _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .snapshots()
          .listen((snapshot) {
            debugPrint(
              '🔔 Elderly assignments changed! Documents: ${snapshot.docs.length}',
            );
            // Clear cache and reload vitals when assignments change
            _houseVitalsCache.clear();
            _houseVitalsCacheTime.clear();
            // Reload in background even if not mounted - data will be cached
            _loadUpcomingVitals(forceRefresh: true);
          });

      // Listen to house_shift_assignments changes
      _shiftListener = _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .snapshots()
          .listen((snapshot) {
            debugPrint(
              '🔔 Shift assignments changed! Documents: ${snapshot.docs.length}',
            );
            // Clear cache and reload vitals when shift changes
            _houseVitalsCache.clear();
            _houseVitalsCacheTime.clear();
            // Reload in background even if not mounted - data will be cached
            _loadUpcomingVitals(forceRefresh: true);
          });

      debugPrint('✅ Vitals assignment listeners initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing vitals listeners: $e');
    }
  }

  /// Pre-fetch lightweight data to speed up first render
  void _prewarm() async {
    // Kick off nurse id lookup so it's cached before heavy queries
    _getCachedNurseId();
    // Start loading vitals (will use cached nurse id if available)
    _loadUpcomingVitals();
    // Preload all houses in background for instant house switching
    _preloadAllHouses();
  }

  /// Preload vitals data for all houses in the background
  /// This makes house switching instant with no loading delays
  void _preloadAllHouses() async {
    try {
      debugPrint('🚀 Starting background preload for all houses...');

      final nurseId = await _getCachedNurseId();
      if (nurseId == null) return;

      final currentShift = _getCurrentShift();
      final currentDay = _getCurrentDay();

      // Get all houses the nurse is assigned to
      final assignQuery = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: nurseId)
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: currentShift)
          .where('day', isEqualTo: currentDay)
          .get();

      if (assignQuery.docs.isEmpty) return;

      // Collect all unique house IDs
      final Set<String> houseIds = {};
      for (final doc in assignQuery.docs) {
        final data = doc.data();
        final houseIdList = data['house_id'];
        if (houseIdList is List) {
          houseIds.addAll(List<String>.from(houseIdList));
        } else if (houseIdList is String) {
          houseIds.add(houseIdList);
        }
      }

      debugPrint('📦 Found ${houseIds.length} houses to preload: $houseIds');

      // Preload vitals for each house in parallel (but not current house)
      final futures = <Future>[];
      for (final houseId in houseIds) {
        if (houseId == widget.houseId) continue; // Skip current house

        final cacheKey = houseId + (widget.nurseName ?? "");

        // Only preload if not already cached
        if (!_houseVitalsCache.containsKey(cacheKey)) {
          futures.add(
            _preloadHouseData(houseId, nurseId, currentShift, currentDay),
          );
        }
      }

      await Future.wait(futures);
      debugPrint('✅ Background preload completed for ${futures.length} houses');
    } catch (e) {
      debugPrint('❌ Error preloading houses: $e');
    }
  }

  /// Preload data for a specific house
  Future<void> _preloadHouseData(
    String houseId,
    String nurseId,
    String shift,
    String day,
  ) async {
    try {
      final cacheKey = houseId + (widget.nurseName ?? "");

      debugPrint('⚡ Preloading house: $houseId');

      // Get vitals for this house (same logic as _loadUpcomingVitals)
      final vitals = await _getUpcomingVitalsForHouse(
        houseId,
        nurseId,
        shift,
        day,
      );

      // Cache the data
      _houseVitalsCache[cacheKey] = vitals;
      _houseVitalsCacheTime[cacheKey] = DateTime.now();

      debugPrint('✅ Preloaded ${vitals.length} vitals for house: $houseId');
    } catch (e) {
      debugPrint('❌ Error preloading house $houseId: $e');
    }
  }

  /// Get upcoming vitals for a specific house (used by preloading)
  Future<List<Map<String, dynamic>>> _getUpcomingVitalsForHouse(
    String houseId,
    String nurseId,
    String shift,
    String day,
  ) async {
    // Quick check: does this nurse have any assignments for this house/shift/day?
    final quickCheck = await _firestore
        .collection('elderly_assignments')
        .where('user_id', isEqualTo: nurseId)
        .where('user_type', isEqualTo: 'nurse')
        .where('is_current', isEqualTo: true)
        .where('shift', isEqualTo: shift)
        .where('day', isEqualTo: day)
        .where('house_id', arrayContains: houseId)
        .limit(1)
        .get();

    if (quickCheck.docs.isEmpty) {
      return [];
    }

    // Get all assignments for this house
    final assignQuery = await _firestore
        .collection('elderly_assignments')
        .where('user_id', isEqualTo: nurseId)
        .where('user_type', isEqualTo: 'nurse')
        .where('is_current', isEqualTo: true)
        .where('shift', isEqualTo: shift)
        .where('day', isEqualTo: day)
        .where('house_id', arrayContains: houseId)
        .get();

    if (assignQuery.docs.isEmpty) return [];

    final assignData = assignQuery.docs.first.data();
    final elderlyIds = List<String>.from(assignData['elderly_ids'] ?? []);

    if (elderlyIds.isEmpty) return [];

    // Get pending vitals for these elderly
    final vitalsQuery = await _firestore
        .collection('vitals')
        .where('status', isEqualTo: 'pending')
        .where('elderly_id', whereIn: elderlyIds.take(10).toList())
        .get();

    final List<Map<String, dynamic>> vitals = [];
    for (final vitalDoc in vitalsQuery.docs) {
      final vitalData = vitalDoc.data();
      vitalData['vital_id'] = vitalDoc.id;
      vitals.add(vitalData);
    }

    return vitals;
  }

  // Schedule notifications for existing vital tasks
  Future<void> _scheduleNotificationsForExistingVitals() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      debugPrint('Scheduling notifications for existing vital tasks');
      debugPrint('Today: $today, Tomorrow: $tomorrow, Now: $now');

      // Get all vital tasks for the next 7 days
      final nextWeek = today.add(const Duration(days: 7));
      final query = await _firestore
          .collection('vitals')
          .where(
            'assigned_date',
            isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(today),
          )
          .where(
            'assigned_date',
            isLessThan: DateFormat('yyyy-MM-dd').format(nextWeek),
          )
          .where('status', isEqualTo: 'pending')
          .get();

      debugPrint('Found ${query.docs.length} vital tasks for the next 7 days');

      for (final doc in query.docs) {
        final vital = doc.data();
        final assignedDate = vital['assigned_date'] as String?;
        final shift = vital['shift'] as String?;
        final elderlyId = vital['elderly_id'] as String?;
        final houseId = vital['house_id'] as String?;

        if (assignedDate == null ||
            shift == null ||
            elderlyId == null ||
            houseId == null) {
          continue;
        }

        debugPrint(
          'Processing vital task: $elderlyId, date: $assignedDate, shift: $shift',
        );

        // Calculate notification time based on shift start
        DateTime? notificationTime = _getShiftStartTime(assignedDate, shift);
        if (notificationTime == null || !notificationTime.isAfter(now)) {
          debugPrint(
            'Skipping vital task - notification time in past or invalid',
          );
          continue;
        }

        // Get elderly name
        final elderlyDoc = await _firestore
            .collection('elderly')
            .doc(elderlyId)
            .get();
        final elderlyName = elderlyDoc.exists
            ? '${elderlyDoc.data()?['elderly_fname'] ?? ''} ${elderlyDoc.data()?['elderly_lname'] ?? ''}'
                  .trim()
            : 'Unknown';

        // Schedule notification at shift start time
        debugPrint(
          'Scheduling vital notification for $elderlyName at $notificationTime',
        );
        final notificationId = 'vital_${doc.id}'.hashCode;
        NotificationService.cancelNotification(notificationId);
        NotificationService.scheduleTaskNotification(
          id: notificationId,
          title: 'Vital Check Reminder',
          body: 'Time to check vitals for $elderlyName',
          dateTime: notificationTime,
        );
      }
    } catch (e) {
      debugPrint('Error scheduling notifications for existing vital tasks: $e');
    }
  }

  // Get shift start time
  DateTime? _getShiftStartTime(String dateString, String shift) {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(dateString);
      switch (shift) {
        case '1st':
          return DateTime(date.year, date.month, date.day, 6, 0); // 6:00 AM
        case '2nd':
          return DateTime(date.year, date.month, date.day, 14, 0); // 2:00 PM
        case '3rd':
          return DateTime(date.year, date.month, date.day, 22, 0); // 10:00 PM
        default:
          return null;
      }
    } catch (e) {
      debugPrint('Error parsing shift time: $e');
      return null;
    }
  }

  @override
  void dispose() {
    // Cancel listeners to prevent memory leaks
    _assignmentListener?.cancel();
    _shiftListener?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  void _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF00588E)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      // Reload vitals for the new date
      _loadUpcomingVitals(forceRefresh: true);
    }
  }

  Future<void> _loadUpcomingVitals({bool forceRefresh = false}) async {
    print(
      '🔄 _loadUpcomingVitals called with forceRefresh=$forceRefresh (mounted=$mounted)',
    );
    final cacheKey = widget.houseId + (widget.nurseName ?? "");

    // CHECK CACHE FIRST before showing any loading state
    if (_houseVitalsCache.containsKey(cacheKey) && !forceRefresh) {
      print('✅ Using cached data for $cacheKey - INSTANT display!');
      // Show cached data immediately if widget is mounted (NO loading state)
      if (mounted) {
        setState(() {
          _upcomingVitals = _houseVitalsCache[cacheKey]!;
          _isLoading = false;
        });
      }
      return;
    }

    // Only show loading indicator if no cache exists
    print('⚡ No cache found - fetching fresh vitals data...');
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    // Fetch fresh data in background (works even if widget is not mounted)
    try {
      // Use cached nurse id if available to speed up a quick existence check
      final nurseId = await _getCachedNurseId();
      if (nurseId == null) {
        // Update UI only if widget is mounted
        if (mounted) {
          setState(() {
            _upcomingVitals = [];
            _isLoading = false;
          });
        }
        return;
      }

      // ⚡ OPTIMIZATION: Parallelize nurse assignment check and quick vitals check
      final today = _getTodayDateString();
      final currentShift = _getCurrentShift();
      final currentDay = _getCurrentDay();

      // Run both checks in parallel to speed up the process
      final parallelChecks = await Future.wait([
        _isNurseAssignedToCurrentShift(nurseId),
        // Quick check for ANY pending vitals for today (ALL shifts)
        _firestore
            .collection('vitals')
            .where('assigned_date', isEqualTo: today)
            .where('status', isEqualTo: 'pending')
            .limit(1)
            .get(),
      ]);

      final isAssignedToShift = parallelChecks[0] as bool;
      final quickCheck = parallelChecks[1] as QuerySnapshot;

      if (!isAssignedToShift) {
        // Update cache and UI
        _houseVitalsCache[cacheKey] = [];
        _houseVitalsCacheTime[cacheKey] = DateTime.now();
        if (mounted) {
          setState(() {
            _isNotAssignedToShift = true;
            _upcomingVitals = [];
            _isLoading = false;
          });
        }
        return;
      }

      List<Map<String, dynamic>> vitals;

      if (quickCheck.docs.isEmpty) {
        // No assignments found in cache - fetch and ensure they exist
        print(
          '🔄 No cached assignments found - loading and ensuring assignments exist...',
        );
        vitals = await _ensureAssignmentsExistInBackground(
          nurseId,
          currentShift,
          currentDay,
          today,
        );
      } else {
        vitals = await _getUpcomingVitals();
      }

      // Cache data (happens in background)
      _houseVitalsCache[cacheKey] = vitals;
      _houseVitalsCacheTime[cacheKey] = DateTime.now();

      // Update UI only if widget is still mounted
      if (mounted) {
        setState(() {
          _upcomingVitals = vitals;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading upcoming vitals: $e');
      if (mounted) {
        setState(() {
          _upcomingVitals = [];
          _isLoading = false;
        });
      }
    }
    print('✅ _loadUpcomingVitals completed');
  }

  Future<void> _refreshVitals() async {
    print(
      '🔄 FORCE REFRESH: Starting complete refresh for house ${widget.houseId}',
    );

    // Clear ALL caches to ensure absolutely fresh data
    final cacheKey = widget.houseId + (widget.nurseName ?? "");
    print('🔄 Clearing cache for key: $cacheKey');
    _houseVitalsCache.clear();
    _houseVitalsCacheTime.clear();
    print('🗑️ ALL caches cleared');

    // Force complete reload without any caching
    print('🔄 Loading fresh data with forceRefresh=true');
    await _loadUpcomingVitals(forceRefresh: true);

    print('✅ Force refresh completed');
  }

  String _getCurrentDay() {
    final now = DateTime.now();
    final currentHour = now.hour;

    // For third shift (10pm-6am), if it's after midnight (0:00-5:59),
    // we need to look at the previous day's assignments
    if (currentHour >= 0 && currentHour < 6) {
      // It's after midnight during third shift, so get previous day
      final previousDay = now.subtract(Duration(days: 1));
      return DateFormat('EEEE').format(previousDay);
    }

    // For all other times, use current day
    return DateFormat('EEEE').format(now);
  }

  String _getTodayDateString() {
    final now = DateTime.now();
    final currentHour = now.hour;

    // For third shift (10pm-6am), if it's after midnight (0:00-5:59),
    // we need to use the previous day's date for assignments
    if (currentHour >= 0 && currentHour < 6) {
      // It's after midnight during third shift, so get previous day's date
      final previousDay = now.subtract(Duration(days: 1));
      return DateFormat('yyyy-MM-dd').format(previousDay);
    }

    // For all other times, use current date
    return DateFormat('yyyy-MM-dd').format(now);
  }

  // Check if we need to handle shift transition based on actual nurse change

  /// ⚡ OPTIMIZED: Get authenticated nurse ID directly from Firebase Auth
  Future<String?> _getCachedNurseId() async {
    // Use the authenticated user's UID directly for reliable nurse identification
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('No authenticated user found');
      return null;
    }
    return user.uid;
  }

  /// 🔧 UPDATED LOGIC: Get upcoming vitals with smart filtering
  ///
  /// NEW BEHAVIOR:
  /// 1. Only shows vitals for current nurse's shift
  /// 2. Excludes elderly who already had vitals completed TODAY by ANY shift
  /// 3. Prevents duplicate work across shifts
  /// 4. When nurse completes vital → disappears from their upcoming list
  /// 5. Subsequent shifts won't see elderly that previous shift already completed
  Future<List<Map<String, dynamic>>> _getUpcomingVitals() async {
    try {
      final currentShift = _getCurrentShift();
      final currentDay = _getCurrentDay();
      final today = _getTodayDateString();

      print(
        '⚡ OPTIMIZED: Fetching for nurse: ${widget.nurseName}, shift: $currentShift, day: $currentDay - House: "${widget.houseId}"',
      );

      // ⚡ OPTIMIZATION 1: Use cached nurse ID
      final nurseId = await _getCachedNurseId();
      if (nurseId == null) return [];

      print('✅ Nurse ID: $nurseId');

      // Get elderly assigned to all nurses (general assignments, not per shift)
      final elderlyToNurse = <String, String>{};
      final nurseAssignmentsQuery = await _firestore
          .collection('elderly_assignments')
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where(
            'house_id',
            arrayContains: widget.houseId,
          ) // 🔧 FIXED: Filter by house
          .where(
            'shift',
            isEqualTo: currentShift,
          ) // 🔧 FIXED: Filter by current shift
          .where(
            'day',
            isEqualTo: currentDay,
          ) // 🔧 FIXED: Filter by current day
          .get();

      print(
        '🔍 DEBUG: Found ${nurseAssignmentsQuery.docs.length} elderly_assignments documents',
      );

      for (final doc in nurseAssignmentsQuery.docs) {
        final data = doc.data();
        print('🔍 DEBUG: Assignment doc ${doc.id}: $data');
        final assignedNurseId = data['user_id'] as String;
        final elderlyIds = List<String>.from(data['elderly_ids'] ?? []);
        print('🔍 DEBUG: Nurse $assignedNurseId has elderly: $elderlyIds');
        for (final elderlyId in elderlyIds) {
          elderlyToNurse[elderlyId] = assignedNurseId;
        }
      }

      print(
        '✅ Found assignments for ${elderlyToNurse.length} elderly for all nurses',
      );

      // 🔧 MODIFIED: Get elderly assigned to CURRENT nurse only
      final currentNurseElderlyIds = <String>[];
      for (final entry in elderlyToNurse.entries) {
        if (entry.value == nurseId) {
          currentNurseElderlyIds.add(entry.key);
        }
      }

      print(
        '👥 Current nurse ($nurseId) is assigned to ${currentNurseElderlyIds.length} elderly: $currentNurseElderlyIds',
      );

      // If no elderly assigned to current nurse, return empty
      if (currentNurseElderlyIds.isEmpty) {
        print('ℹ️ No elderly assigned to current nurse');
        return [];
      }

      // ⚡ OPTIMIZATION: Batch fetch all elderly documents at once instead of individual fetches
      final elderlyDocs = await Future.wait(
        currentNurseElderlyIds.map(
          (id) => _firestore.collection('elderly').doc(id).get(),
        ),
      );

      // Build elderly data map and filter by current house
      final elderlyInCurrentHouse = <String>[];
      final elderlyDataMap = <String, Map<String, dynamic>>{};

      for (final doc in elderlyDocs) {
        if (doc.exists) {
          final elderlyData = doc.data()!;
          final elderlyId = doc.id;
          final elderlyHouseId = elderlyData['house_id'];

          elderlyDataMap[elderlyId] = elderlyData;

          // Only log if elderly is in different house (reduce noise)
          if (elderlyHouseId == widget.houseId) {
            elderlyInCurrentHouse.add(elderlyId);
          }
        }
      }

      print(
        '🏠 Elderly in current house: ${elderlyInCurrentHouse.length} out of ${currentNurseElderlyIds.length}',
      );

      // If no elderly in current house, return empty
      if (elderlyInCurrentHouse.isEmpty) {
        print('ℹ️ No elderly assigned to current nurse in this house');
        return [];
      }

      // Use only elderly in current house
      final filteredElderlyIds = elderlyInCurrentHouse;

      // 🔧 SMART FILTERING: First check which elderly already had vitals completed today by ANY shift
      final completedTodayElderlyIds = <String>{};

      // Get all completed vitals for today to exclude from pending list
      final completedTodayQuery = await _firestore
          .collection('vitals')
          .where('house_id', isEqualTo: widget.houseId)
          .where('assigned_date', isEqualTo: today)
          .where('status', isEqualTo: 'completed')
          .where('elderly_id', whereIn: filteredElderlyIds.take(30).toList())
          .get();

      for (final doc in completedTodayQuery.docs) {
        final data = doc.data();
        final elderlyId = data['elderly_id'] as String?;
        if (elderlyId != null) {
          completedTodayElderlyIds.add(elderlyId);
        }
      }

      // Filter out elderly who already completed vitals today
      final elderlyNeedingVitals = filteredElderlyIds
          .where((elderlyId) => !completedTodayElderlyIds.contains(elderlyId))
          .toList();

      print(
        '🔍 Filtered elderly: ${filteredElderlyIds.length} assigned, ${completedTodayElderlyIds.length} already completed today, ${elderlyNeedingVitals.length} still need vitals',
      );
      print('📋 Completed today elderly IDs: $completedTodayElderlyIds');
      print('📋 Elderly still needing vitals: $elderlyNeedingVitals');

      if (elderlyNeedingVitals.isEmpty) {
        print('✅ All elderly already have completed vitals today');
        return [];
      }

      // 🔧 OPTIMIZED: Query for pending vitals for CURRENT nurse's elderly only (in current house)
      // Use Firestore's full whereIn limit of 30 items instead of 10
      final vitalsQuery = await _firestore
          .collection('vitals')
          .where('house_id', isEqualTo: widget.houseId)
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: currentShift)
          .where('status', isEqualTo: 'pending')
          .where(
            'elderly_id',
            whereIn: elderlyNeedingVitals.take(30).toList(),
          ) // Firestore whereIn limit is 30
          .get();

      // Handle Firestore whereIn limit (30 items max) by chunking if needed
      final allVitals = <QueryDocumentSnapshot>[];
      allVitals.addAll(vitalsQuery.docs);

      // Handle completed elderly in chunks too if needed
      if (filteredElderlyIds.length > 30) {
        for (var i = 30; i < filteredElderlyIds.length; i += 30) {
          final chunk = filteredElderlyIds.skip(i).take(30).toList();
          if (chunk.isNotEmpty) {
            final chunkCompletedQuery = await _firestore
                .collection('vitals')
                .where('house_id', isEqualTo: widget.houseId)
                .where('assigned_date', isEqualTo: today)
                .where('status', isEqualTo: 'completed')
                .where('elderly_id', whereIn: chunk)
                .get();

            for (final doc in chunkCompletedQuery.docs) {
              final data = doc.data();
              final elderlyId = data['elderly_id'] as String?;
              if (elderlyId != null) {
                completedTodayElderlyIds.add(elderlyId);
              }
            }
          }
        }

        // Re-filter with all completed elderly IDs
        final elderlyNeedingVitalsChunked = filteredElderlyIds
            .where((elderlyId) => !completedTodayElderlyIds.contains(elderlyId))
            .toList();

        // If we have more than 30 elderly needing vitals, query in chunks
        if (elderlyNeedingVitalsChunked.length > 30) {
          for (var i = 30; i < elderlyNeedingVitalsChunked.length; i += 30) {
            final chunk = elderlyNeedingVitalsChunked.skip(i).take(30).toList();
            if (chunk.isNotEmpty) {
              final chunkQuery = await _firestore
                  .collection('vitals')
                  .where('house_id', isEqualTo: widget.houseId)
                  .where('assigned_date', isEqualTo: today)
                  .where('shift', isEqualTo: currentShift)
                  .where('status', isEqualTo: 'pending')
                  .where('elderly_id', whereIn: chunk)
                  .get();
              allVitals.addAll(chunkQuery.docs);
            }
          }
        }
      }

      print(
        '⚡ Found ${allVitals.length} pending vital assignments for current nurse\'s elderly',
      );

      // Debug: Check status of returned vitals and filter out any completed ones
      int completedCount = 0;
      int pendingCount = 0;
      for (final doc in allVitals) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue; // Skip if data is null
        final status = data['status'];
        if (status == 'completed') {
          completedCount++;
          print(
            '   ❌ COMPLETED Vital ${doc.id}: status=$status, elderly=${data['elderly_id']} - SHOULD NOT BE HERE!',
          );
        } else if (status == 'pending') {
          pendingCount++;
          print(
            '   ✅ PENDING Vital ${doc.id}: status=$status, elderly=${data['elderly_id']}',
          );
        } else {
          print(
            '   ⚠️ OTHER Vital ${doc.id}: status=$status, elderly=${data['elderly_id']}',
          );
        }
      }

      print(
        '📊 Query results: $pendingCount pending, $completedCount completed',
      );

      // Filter out any completed vitals that somehow got through the query
      final filteredVitals = allVitals.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        return data != null && data['status'] == 'pending';
      }).toList();

      if (filteredVitals.length != allVitals.length) {
        print(
          '🧹 Filtered out ${allVitals.length - filteredVitals.length} completed vitals from results',
        );
      }

      // Process vitals assignments for current nurse only
      final upcomingVitals = <Map<String, dynamic>>[];
      final seenElderlyIds = <String>{};

      // ⚡ OPTIMIZATION: Collect all unique nurse IDs that need name lookup
      final nurseIdsToFetch = <String>{};
      for (final vitalDoc in filteredVitals) {
        final vitalData = vitalDoc.data() as Map<String, dynamic>;
        final assignedNurseId = vitalData['assigned_nurse_id'];
        final inheritedNurseId = vitalData['inherited_from_nurse_id'];
        if (assignedNurseId != null) nurseIdsToFetch.add(assignedNurseId);
        if (inheritedNurseId != null) nurseIdsToFetch.add(inheritedNurseId);
      }

      // Batch fetch all nurse documents
      final nurseDocs = await Future.wait(
        nurseIdsToFetch.map(
          (id) => _firestore.collection('users').doc(id).get(),
        ),
      );

      // Create nurse data map for quick lookup
      final nurseDataMap = <String, Map<String, dynamic>>{};
      for (final doc in nurseDocs) {
        if (doc.exists && doc.data() != null) {
          nurseDataMap[doc.id] = Map<String, dynamic>.from(doc.data()!);
        }
      }

      // Reset seenElderlyIds for final processing
      seenElderlyIds.clear();

      for (final vitalDoc in filteredVitals) {
        final vitalData = vitalDoc.data() as Map<String, dynamic>?;
        if (vitalData == null) continue; // Skip if data is null
        final elderlyId = vitalData['elderly_id'];

        // 🔧 MODIFIED: No need to filter by nurse since we already filtered by elderly assigned to current nurse
        if (!seenElderlyIds.contains(elderlyId)) {
          seenElderlyIds.add(elderlyId);

          // Get elderly details from our batched data
          final elderlyData = elderlyDataMap[elderlyId];
          if (elderlyData == null) continue;

          final elderlyName =
              '${elderlyData['elderly_fname'] ?? ''} ${elderlyData['elderly_lname'] ?? ''}'
                  .trim();
          if (elderlyName.isEmpty) continue;

          // Get assigned nurse name from batched nurse data
          final assignedNurseId = vitalData['assigned_nurse_id'];
          String assignedNurseName = 'Unknown Nurse';
          if (assignedNurseId != null &&
              nurseDataMap.containsKey(assignedNurseId)) {
            final nurseData = nurseDataMap[assignedNurseId]!;
            assignedNurseName =
                '${nurseData['user_fname'] ?? ''} ${nurseData['user_lname'] ?? ''}'
                    .trim();
          }

          // Get original nurse name for inherited assignments
          String originalNurseName = assignedNurseName;
          final inheritedNurseId = vitalData['inherited_from_nurse_id'];
          if (inheritedNurseId != null &&
              nurseDataMap.containsKey(inheritedNurseId)) {
            final inheritedNurseData = nurseDataMap[inheritedNurseId]!;
            originalNurseName =
                '${inheritedNurseData['user_fname'] ?? ''} ${inheritedNurseData['user_lname'] ?? ''}'
                    .trim();
          }

          upcomingVitals.add({
            'assignment_id': vitalDoc.id,
            'elderly_id': elderlyId,
            'elderly_name': elderlyName,
            'assigned_nurse_id': assignedNurseId,
            'assigned_nurse_name': assignedNurseName,
            'house_id': vitalData['house_id'],
            'shift': vitalData['shift'],
            'assigned_date': vitalData['assigned_date'],
            'status': vitalData['status'],
            'blood_pressure': vitalData['blood_pressure'],
            'pulse_rate': vitalData['pulse_rate'],
            'oxygen_saturation': vitalData['oxygen_saturation'],
            'temperature': vitalData['temperature'],
            'respiratory_rate': vitalData['respiratory_rate'],
            'vital_remarks': vitalData['vital_remarks'],
            'completed_at': vitalData['completed_at'],
            'updated_by_nurse_id': vitalData['updated_by_nurse_id'],
            'updated_by_nurse_name': null, // Can be fetched if needed
            'original_nurse': originalNurseName,
          });
        }
      }

      // Sort by elderly name
      upcomingVitals.sort((a, b) {
        return (a['elderly_name'] as String).compareTo(
          b['elderly_name'] as String,
        );
      });

      print(
        '⚡ Returning ${upcomingVitals.length} elderly assignments for current nurse',
      );
      return upcomingVitals;
    } catch (e) {
      print('❌ Error getting upcoming vitals: $e');
      return [];
    }
  }

  /// ⚡ BACKGROUND: Ensure assignments exist for ALL shifts and ALL houses and return the vitals list
  Future<List<Map<String, dynamic>>> _ensureAssignmentsExistInBackground(
    String nurseId,
    String currentShift,
    String currentDay,
    String today,
  ) async {
    try {
      print(
        '🔄 Background: Ensuring assignments exist for ALL shifts and ALL houses...',
      );

      // Get ALL elderly assignments for ALL shifts and ALL houses (not just current house)
      final allAssignmentsQuery = await _firestore
          .collection('elderly_assignments')
          .where('is_current', isEqualTo: true)
          .where('day', isEqualTo: currentDay)
          .get(); // 🔧 REMOVED: No house filter - get ALL houses

      final elderlyToNurseByShift =
          <String, Map<String, String>>{}; // shift -> {elderlyId -> nurseId}

      for (final doc in allAssignmentsQuery.docs) {
        final data = doc.data();
        final nurseId = data['user_id'] as String;
        final shift = data['shift'] as String;
        final elderlyIds = List<String>.from(data['elderly_ids'] ?? []);

        if (!elderlyToNurseByShift.containsKey(shift)) {
          elderlyToNurseByShift[shift] = <String, String>{};
        }

        for (final elderlyId in elderlyIds) {
          elderlyToNurseByShift[shift]![elderlyId] = nurseId;
        }
      }

      print(
        '✅ Found assignments for ${elderlyToNurseByShift.length} shifts across all houses',
      );

      // Ensure assignments exist for ALL shifts
      for (final entry in elderlyToNurseByShift.entries) {
        final shift = entry.key;
        final elderlyToNurse = entry.value;
        if (elderlyToNurse.isNotEmpty) {
          print(
            '🔄 Checking/ensuring assignments for shift: $shift (${elderlyToNurse.length} elderly)',
          );
          await _ensureAllAssignmentsExistForAllHouses(
            shift,
            currentDay,
            today,
          );
        }
      }

      print(
        '✅ Background assignment check/sync completed for ALL shifts and ALL houses',
      );

      // Now fetch the vitals for current shift only
      return await _getUpcomingVitals();
    } catch (e) {
      print('❌ Error ensuring assignments exist: $e');
      return [];
    }
  }

  Future<void> _updateVitals(Map<String, dynamic> elderlyInfo) async {
    print('🔄 Navigating to update vitals for: ${elderlyInfo['elderly_name']}');
    print('🏥 Assignment ID being passed: ${elderlyInfo['assignment_id']}');
    print('👴 Elderly ID: ${elderlyInfo['elderly_id']}');

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VitalUpdateScreen(
          assignmentId: elderlyInfo['assignment_id'],
          elderlyId: elderlyInfo['elderly_id'],
          elderlyName: elderlyInfo['elderly_name'],
          nurseName: widget.nurseName,
          houseId: widget.houseId,
        ),
      ),
    );

    // Refresh the list if vitals were updated (removes from upcoming)
    if (result == true && mounted) {
      print('✅ Vitals updated successfully, refreshing upcoming list...');

      // 🔴 BADGE FIX: Clear all caches to ensure immediate red badge update
      _houseVitalsCache.clear();
      _houseVitalsCacheTime.clear();

      await _refreshVitals();

      // 🔴 BADGE FIX: Force widget rebuild to trigger badge count stream update
      if (mounted) {
        setState(() {
          // This will cause the StreamBuilder in vital_monitoring.dart to rebuild
          // and refresh the red badge count immediately
        });
      }

      print('✅ Upcoming list refresh completed with badge update');
      // Optionally: trigger a callback/event to update completed tab if needed
    } else {
      print('ℹ️ Vitals update cancelled or failed, no refresh needed');
    }
  }

  // 🆕 FOLLOW-UP VITALS: Show selection screen for follow-up recordings
  Future<void> _showFollowUpVitalsSelection() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FollowUpVitalsSelectionScreen(
          nurseName: widget.nurseName,
          houseId: widget.houseId,
        ),
      ),
    );

    // Refresh the list if follow-up vitals were recorded
    if (result == true && mounted) {
      await _refreshVitals();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    print(
      '🏗️ UpcomingVitalsTab build() called with houseId: ${widget.houseId}',
    );

    // 🔧 CRITICAL FIX: Since _upcomingVitals is now always initialized (never null),
    // we only show loading spinner when _isLoading is true
    final upcomingVitals = _upcomingVitals ?? [];

    // Check if nurse is not assigned to current shift
    if (_isNotAssignedToShift) {
      return Center(
        child: Container(
          padding: EdgeInsets.all(20),
          margin: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'You are not scheduled for the current shift',
                style: TextStyle(
                  fontSize: 18,
                  color: Color.fromARGB(255, 170, 171, 171),
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'Please check your schedule or contact your supervisor.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color.fromARGB(255, 124, 124, 124),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Always show loading spinner if _isLoading is true
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00588E)),
            ),
            SizedBox(height: 16),
            Text(
              'Loading vitals...',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF00588E),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // Show empty state if no assignments
    if (upcomingVitals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_outline, size: 48, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              'No upcoming vitals',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'All vitals are up to date',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    // Filter out completed vitals for UI display (additional safety check)
    final pendingVitals = upcomingVitals
        .where((vital) => vital['status'] == 'pending')
        .toList();

    return Column(
      children: [
        // Date Picker Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.white,
          child: Row(
            children: [
              const Text(
                'Date: ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF00588E),
                ),
              ),
              Text(
                DateFormat('MMM. d, yyyy').format(_selectedDate),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(
                  Icons.calendar_today,
                  color: Color(0xFF00588E),
                ),
                onPressed: () => _selectDate(context),
              ),
            ],
          ),
        ),
        // Main Content
        Expanded(
          child: Stack(
            children: [
              if (_isLoading)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF00588E),
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Loading vitals...',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF00588E),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              else
                // Vitals List
                pendingVitals.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(height: 24),
                            Icon(
                              Icons.favorite_outline,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No upcoming vitals',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'All vitals are up to date',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _refreshVitals,
                        child: ListView.builder(
                          padding: EdgeInsets.only(bottom: 80),
                          itemCount: pendingVitals.length,
                          itemBuilder: (context, index) {
                            final elderlyInfo = pendingVitals[index];

                            // 🔧 SAFETY CHECK: Skip rendering if elderly_name is missing or "Unknown"
                            final elderlyName =
                                elderlyInfo['elderly_name'] as String?;
                            if (elderlyName == null ||
                                elderlyName.isEmpty ||
                                elderlyName == 'Unknown') {
                              return SizedBox.shrink(); // Skip this item completely
                            }

                            final lastVital =
                                elderlyInfo['last_vital']
                                    as Map<String, dynamic>?;

                            return Card(
                              margin: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              color: const Color(0xFFE6F3FA),
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Elderly Name
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: const Color(
                                            0xFF00588E,
                                          ),
                                          child:
                                              elderlyInfo['elderly_profilePic']
                                                      ?.isNotEmpty ==
                                                  true
                                              ? ClipOval(
                                                  child: Image.network(
                                                    elderlyInfo['elderly_profilePic'],
                                                    fit: BoxFit.cover,
                                                  ),
                                                )
                                              : Icon(
                                                  Icons.person,
                                                  color: Colors.white,
                                                ),
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            elderlyName, // Use validated elderlyName
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF00588E),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 12),

                                    // Status and Tap to Update
                                    GestureDetector(
                                      onTap: () => _updateVitals(elderlyInfo),
                                      child: Container(
                                        padding: EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color:
                                                elderlyInfo['status'] ==
                                                    'missed'
                                                ? Colors.red
                                                : Colors.orange,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          color: Colors.white,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              elderlyInfo['status'] == 'missed'
                                                  ? Icons.warning
                                                  : Icons.pending_actions,
                                              color:
                                                  elderlyInfo['status'] ==
                                                      'missed'
                                                  ? Colors.red
                                                  : Colors.orange,
                                              size: 24,
                                            ),
                                            SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding:
                                                            EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              elderlyInfo['is_inherited'] ==
                                                                  true
                                                              ? Colors.blue
                                                              : Colors.orange,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          elderlyInfo['is_inherited'] ==
                                                                  true
                                                              ? 'INHERITED'
                                                              : 'PENDING',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          elderlyInfo['is_inherited'] ==
                                                                  true
                                                              ? 'From Previous Shift'
                                                              : 'Not Updated Today',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 14,
                                                            color:
                                                                elderlyInfo['is_inherited'] ==
                                                                    true
                                                                ? Colors.blue
                                                                : Colors.orange,
                                                          ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  SizedBox(height: 4),
                                                  // Split the inherited info into separate lines to prevent overflow
                                                  if (elderlyInfo['is_inherited'] ==
                                                      true) ...[
                                                    Text(
                                                      'Originally: ${elderlyInfo['original_nurse']}',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey[700],
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    Text(
                                                      '${elderlyInfo['inherited_from_shift']} shift - Tap to complete',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey[700],
                                                      ),
                                                    ),
                                                  ] else
                                                    Text(
                                                      'Tap to update vital signs for ${_getTodayDateString()}',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey[700],
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                              Icons.arrow_forward_ios,
                                              color:
                                                  elderlyInfo['is_inherited'] ==
                                                      true
                                                  ? Colors.blue
                                                  : Colors.orange,
                                              size: 16,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    // Last vital info if available
                                    if (lastVital != null) ...[
                                      SizedBox(height: 12),
                                      Text(
                                        'Last recorded vitals:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Container(
                                        padding: EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey.withOpacity(0.3),
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          // UI-only change: make last vitals container white
                                          color: Colors.white,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    'BP: ${lastVital['blood_pressure'] ?? 'N/A'}',
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Text(
                                                    'Pulse: ${lastVital['pulse_rate'] ?? 'N/A'}',
                                                  ),
                                                ),
                                              ],
                                            ),
                                            SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    'O₂: ${lastVital['o2_sat'] ?? 'N/A'}%',
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Text(
                                                    'Temp: ${lastVital['temperature'] ?? 'N/A'}°C',
                                                  ),
                                                ),
                                              ],
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'RR: ${lastVital['respiratory_rate'] ?? 'N/A'}',
                                            ),
                                            if (lastVital['vital_record_at'] !=
                                                null)
                                              Text(
                                                'Recorded: ${DateFormat('MMM dd, yyyy HH:mm').format((lastVital['vital_record_at'] as Timestamp).toDate())}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              if (!_isLoading)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton.extended(
                    onPressed: _showFollowUpVitalsSelection,
                    backgroundColor: Color(0xFF00588E),
                    foregroundColor: Colors.white,
                    icon: Icon(Icons.add_circle_outline),
                    label: Text(
                      'Follow-up',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    heroTag: "followup_vitals_fab",
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _ensureAllAssignmentsExistForAllHouses(
    String shift,
    String currentDay,
    String today,
  ) async {
    try {
      print('🔍 Checking ALL nurse assignments across ALL houses...');

      // Get elderly assigned to ALL nurses across ALL houses for this shift
      final nurseAssignmentsQuery = await _firestore
          .collection('elderly_assignments')
          .where('user_type', isEqualTo: 'nurse')
          .where('is_current', isEqualTo: true)
          .where('shift', isEqualTo: shift)
          .where('day', isEqualTo: currentDay)
          .get();

      final elderlyToProcess = <String, String>{}; // elderlyId -> nurseId

      for (final assignDoc in nurseAssignmentsQuery.docs) {
        final data = assignDoc.data();
        final assignedNurseId = data['user_id'] as String;
        final elderlyIds = List<String>.from(data['elderly_ids'] ?? []);
        for (final elderlyId in elderlyIds) {
          elderlyToProcess[elderlyId] = assignedNurseId;
        }
      }

      print(
        '📋 Found ${elderlyToProcess.length} elderly assignments for all nurses across all houses',
      );

      // 🔧 NEW: Check if schedule changed by comparing with existing vitals
      print('🔍 Checking if nurse schedule has changed...');
      final existingVitalsQuery = await _firestore
          .collection('vitals')
          .where('assigned_date', isEqualTo: today)
          .where('shift', isEqualTo: shift)
          .where('status', isEqualTo: 'pending')
          .get();

      // Build map of existing vitals: elderlyId -> nurseId
      final existingVitalsMap = <String, String>{};
      for (final doc in existingVitalsQuery.docs) {
        final data = doc.data();
        final elderlyId = data['elderly_id'] as String?;
        final nurseId = data['assigned_nurse_id'] as String?;
        if (elderlyId != null && nurseId != null) {
          existingVitalsMap[elderlyId] = nurseId;
        }
      }

      // Check if schedule has changed
      bool scheduleChanged = false;
      final vitalsToDelete = <String>[]; // Document IDs to delete

      // Check for mismatches or missing assignments
      for (final entry in elderlyToProcess.entries) {
        final elderlyId = entry.key;
        final newNurseId = entry.value;
        final existingNurseId = existingVitalsMap[elderlyId];

        if (existingNurseId != null && existingNurseId != newNurseId) {
          // Nurse assignment changed for this elderly
          scheduleChanged = true;
          print(
            '🔄 Schedule changed for elderly $elderlyId: $existingNurseId → $newNurseId',
          );
        }
      }

      // Check for vitals that should be removed (elderly no longer assigned)
      for (final doc in existingVitalsQuery.docs) {
        final data = doc.data();
        final elderlyId = data['elderly_id'] as String?;
        if (elderlyId != null && !elderlyToProcess.containsKey(elderlyId)) {
          scheduleChanged = true;
          vitalsToDelete.add(doc.id);
          print(
            '🗑️ Elderly $elderlyId no longer assigned - marking for deletion',
          );
        }
      }

      // If schedule changed, delete old pending vitals and create new ones
      if (scheduleChanged || existingVitalsQuery.docs.isEmpty) {
        print('🔄 Schedule changed or no vitals exist - resetting vitals...');

        // Delete all pending vitals for this shift/day
        final batch = _firestore.batch();
        for (final doc in existingVitalsQuery.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        print('✅ Deleted ${existingVitalsQuery.docs.length} old vitals');
      } else {
        print('✅ No schedule changes detected - keeping existing vitals');
        return; // No need to create new vitals
      }

      // 🔧 NEW: Create new vitals for all assigned elderly
      print('➕ Creating new vitals for ${elderlyToProcess.length} elderly...');
      int createdCount = 0;

      for (final entry in elderlyToProcess.entries) {
        final elderlyId = entry.key;
        final assignedNurseId = entry.value;

        // Fetch elderly details to get house information
        final elderlyDoc = await _firestore
            .collection('elderly')
            .doc(elderlyId)
            .get();

        if (!elderlyDoc.exists) {
          print('⚠️ Elderly document not found: $elderlyId');
          continue;
        }

        final elderlyData = elderlyDoc.data()!;

        // Only process alive elderly
        if (elderlyData['elderly_status'] != 'Alive') {
          print(
            '⏭️ Skipping elderly $elderlyId - status is ${elderlyData['elderly_status']}',
          );
          continue;
        }

        final elderlyName =
            '${elderlyData['elderly_fname'] ?? ''} ${elderlyData['elderly_lname'] ?? ''}'
                .trim();
        final elderlyHouseId = elderlyData['house_id'];

        // 🔧 NEW LOGIC: Check if vitals were already completed today for THIS SPECIFIC SHIFT
        // This allows multiple shifts to have assignments, but prevents duplicate assignments per shift
        final completedThisShiftQuery = await _firestore
            .collection('vitals')
            .where('elderly_id', isEqualTo: elderlyId)
            .where('assigned_date', isEqualTo: today)
            .where('shift', isEqualTo: shift) // 🔧 FIXED: Check specific shift
            .where('status', isEqualTo: 'completed')
            .limit(1)
            .get();

        if (completedThisShiftQuery.docs.isNotEmpty) {
          print(
            '⏭️ Skipping assignment creation for: $elderlyName - vitals already completed for $shift shift today',
          );
          continue; // Skip creating new assignment for THIS shift only
        }

        print(
          '➕ Creating vital assignment for: $elderlyName (House: $elderlyHouseId, Nurse: $assignedNurseId)',
        );

        await _firestore.collection('vitals').add({
          // 🔧 ASSIGNMENT FIELDS (required)
          'elderly_id': elderlyId,
          'assigned_nurse_id': assignedNurseId,
          'house_id': elderlyHouseId, // Use the elderly's actual house_id
          'shift': shift,
          'assigned_date': today,
          'status': 'pending',
          'created_at': FieldValue.serverTimestamp(),

          // 🔧 ULTRA CLEAN: Only essential vital fields (null until recorded)
          'blood_pressure': null,
          'pulse_rate': null,
          'oxygen_saturation': null,
          'temperature': null,
          'respiratory_rate': null,

          // ✅ Single completion timestamp (null until completed)
          'completed_at': null,

          // ✅ Minimal tracking (null until updated)
          'updated_by_nurse_id': null,
        });
        createdCount++;
        print('✅ Created vital assignment for: $elderlyName');

        // Schedule notification for the new vital task
        final notificationTime = _getShiftStartTime(today, shift);
        if (notificationTime != null &&
            notificationTime.isAfter(DateTime.now())) {
          final notificationId = 'vital_${elderlyId}_${today}_$shift'.hashCode;
          NotificationService.cancelNotification(notificationId);
          NotificationService.scheduleTaskNotification(
            id: notificationId,
            title: 'Vital Check Reminder',
            body: 'Time to check vitals for $elderlyName',
            dateTime: notificationTime,
          );
          print(
            '✅ Scheduled notification for vital task: $elderlyName at $notificationTime',
          );
        }
      }

      print('✅ Created $createdCount new vital assignments for ALL houses');

      print('✅ All assignments verified and created for ALL houses');
    } catch (e) {
      print('❌ Error ensuring assignments exist for all houses: $e');
    }
  }
}
