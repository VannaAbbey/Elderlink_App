import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'notification_service.dart';
import '../../models/cg_models/notification_model.dart';

/// Service to listen for leave request status changes and create notifications
/// This service should be initialized when the app starts and run in the background
class LeaveNotificationListener {
  static final LeaveNotificationListener _instance = LeaveNotificationListener._internal();
  factory LeaveNotificationListener() => _instance;
  LeaveNotificationListener._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();
  
  StreamSubscription<QuerySnapshot>? _leaveRequestsSubscription;
  final Set<String> _processedRequests = {}; // Track processed requests to avoid duplicates
  bool _isInitialized = false;

  /// Initialize the listener for the current user's leave requests
  Future<void> initialize() async {
    if (_isInitialized) {
      print('📢 LeaveNotificationListener: Already initialized');
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      print('❌ LeaveNotificationListener: No authenticated user');
      return;
    }

    print('🔔 LeaveNotificationListener: Initializing for user ${currentUser.uid}');
    
    // Cancel any existing subscription
    await dispose();

    // Listen to leave requests for the current user
    // Note: Listening to both 'rejected' and 'denied' to handle different status values
    _leaveRequestsSubscription = _firestore
        .collection('leave_requests')
        .where('caregiver_id', isEqualTo: currentUser.uid)
        .where('status', whereIn: ['approved', 'rejected', 'denied']) // Listen to all decided statuses
        .snapshots()
        .listen(
          (snapshot) => _handleLeaveRequestChanges(snapshot, currentUser.uid),
          onError: (error) {
            print('❌ LeaveNotificationListener: Error listening to leave requests: $error');
          },
        );

    _isInitialized = true;
    print('✅ LeaveNotificationListener: Initialized successfully');
  }

  /// Handle changes in leave requests
  void _handleLeaveRequestChanges(QuerySnapshot snapshot, String userId) async {
    print('📡 LeaveNotificationListener: Received ${snapshot.docs.length} leave request updates');
    
    for (final change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
        final doc = change.doc;
        final requestId = doc.id;
        final data = doc.data() as Map<String, dynamic>?;
        
        if (data == null) continue;

        final status = data['status'] as String?;
        final reviewedAt = data['reviewed_at'] as Timestamp?;
        
        print('🔍 LeaveNotificationListener: Document change detected - Request ID: $requestId, Status: $status, Reviewed: ${reviewedAt != null}');
        
        // Skip if not yet reviewed
        if (reviewedAt == null) {
          print('⏭️ LeaveNotificationListener: Request $requestId not yet reviewed (reviewed_at is null), skipping');
          continue;
        }

        // Create unique key for this request status
        final processKey = '${requestId}_$status';
        
        // Skip if already processed in this session
        if (_processedRequests.contains(processKey)) {
          print('⏭️ LeaveNotificationListener: Request $requestId with status "$status" already processed in this session, skipping');
          continue;
        }

        // Check if notification was already sent for this leave request (stored in the leave request itself)
        final notificationSent = data['notification_sent'] as bool? ?? false;
        if (notificationSent) {
          print('⏭️ LeaveNotificationListener: Notification already sent for request $requestId (notification_sent=true), skipping');
          _processedRequests.add(processKey); // Mark as processed to avoid checking again
          continue;
        }

        // Additional check: If notification_sent field doesn't exist but notification exists in database
        // This handles migration for existing leave requests
        try {
          final existingNotification = await _firestore
              .collection('app_notifications')
              .where('user_id', isEqualTo: userId)
              .where('reference_id', isEqualTo: requestId)
              .where('reference_type', isEqualTo: 'leave_request')
              .limit(1)
              .get();

          if (existingNotification.docs.isNotEmpty) {
            print('⏭️ LeaveNotificationListener: Notification exists in database for request $requestId, marking as sent');
            // Mark the leave request as notified for future checks
            await _firestore.collection('leave_requests').doc(requestId).update({
              'notification_sent': true,
            });
            _processedRequests.add(processKey);
            continue;
          }
        } catch (e) {
          print('⚠️ LeaveNotificationListener: Error checking for existing notification: $e');
        }

        print('🔍 LeaveNotificationListener: Processing leave request $requestId with status: "$status"');
        
        // Mark as processed
        _processedRequests.add(processKey);
        
        // Create notification
        _createLeaveStatusNotification(
          requestId: requestId,
          userId: userId,
          data: data,
        );
      }
    }
  }

  /// Create a notification for leave status change
  Future<void> _createLeaveStatusNotification({
    required String requestId,
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final status = data['status'] as String?;
      final leaveType = data['leave_type'] as String? ?? 'Leave';
      final startDate = (data['start_date'] as Timestamp?)?.toDate();
      final endDate = (data['end_date'] as Timestamp?)?.toDate();
      final reviewerId = data['reviewed_by'] as String?;
      final reviewerComments = data['reviewer_comments'] as String?;
      
      // Format dates
      String leaveDates = '';
      if (startDate != null && endDate != null) {
        final dateFormat = DateFormat('MMM dd, yyyy');
        if (startDate.year == endDate.year && 
            startDate.month == endDate.month && 
            startDate.day == endDate.day) {
          leaveDates = dateFormat.format(startDate);
        } else {
          leaveDates = '${dateFormat.format(startDate)} - ${dateFormat.format(endDate)}';
        }
      }
      // Get reviewer name if available
      String? approverName;
      if (reviewerId != null) {
        try {
          final reviewerDoc = await _firestore.collection('users').doc(reviewerId).get();
          if (reviewerDoc.exists) {
            final reviewerData = reviewerDoc.data();
            final fname = reviewerData?['user_fname'] ?? '';
            final lname = reviewerData?['user_lname'] ?? '';
            approverName = '$fname $lname'.trim();
            if (approverName.isEmpty) {
              approverName = null;
            }
          }
        } catch (e) {
          print('⚠️ LeaveNotificationListener: Error fetching reviewer name: $e');
        }
      }

      NotificationType notificationType;

      if (status?.toLowerCase() == 'approved') {
        notificationType = NotificationType.leaveApproved;
        print('✅ LeaveNotificationListener: Creating APPROVED notification');
      } else if (status?.toLowerCase() == 'rejected' || status?.toLowerCase() == 'denied') {
        notificationType = NotificationType.leaveDenied;
        print('❌ LeaveNotificationListener: Creating DENIED notification (status: "$status")');
        if (reviewerComments != null && reviewerComments.isNotEmpty) {
          print('💬 LeaveNotificationListener: Reviewer comments: "$reviewerComments"');
        } else {
          print('⚠️ LeaveNotificationListener: No reviewer comments provided');
        }
      } else {
        print('⏭️ LeaveNotificationListener: Unknown status: "$status", skipping notification');
        return;
      }

      print('📬 LeaveNotificationListener: Creating notification for request $requestId with type: ${notificationType.toString()}');
      
      // Create notification using the dedicated leave notification method
      await _notificationService.createLeaveNotification(
        userId: userId,
        userType: 'caregiver',
        leaveRequestId: requestId,
        type: notificationType,
        leaveDates: leaveDates,
        leaveType: leaveType,
        approverName: approverName,
        reviewerComments: reviewerComments,
        priority: NotificationPriority.high,
      );

      // Mark the leave request as notified so we don't send duplicate notifications
      await _firestore.collection('leave_requests').doc(requestId).update({
        'notification_sent': true,
      });

      print('✅ LeaveNotificationListener: Notification created successfully for request $requestId');
      print('✅ LeaveNotificationListener: Marked leave request as notified (notification_sent=true)');
    } catch (e, stackTrace) {
      print('❌ LeaveNotificationListener: Error creating notification: $e');
      print('❌ Stack trace: $stackTrace');
      // Remove from processed set so it can be retried
      _processedRequests.remove('${requestId}_${data['status']}');
    }
  }

  /// Dispose of the listener
  Future<void> dispose() async {
    print('🛑 LeaveNotificationListener: Disposing');
    await _leaveRequestsSubscription?.cancel();
    _leaveRequestsSubscription = null;
    _isInitialized = false;
    // Don't clear processed requests - keep them across reinitializations
  }

  /// Reset processed requests (use carefully, mainly for testing)
  void resetProcessedRequests() {
    print('🔄 LeaveNotificationListener: Resetting processed requests');
    _processedRequests.clear();
  }
}
