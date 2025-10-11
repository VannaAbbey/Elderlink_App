import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'cg_services/notification_service.dart';
import '../models/cg_models/notification_model.dart';

class LeaveRequestService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final NotificationService _notificationService = NotificationService();

  /// Submits a leave request to the database
  static Future<String> submitLeaveRequest({
    required String fullName,
    required String contactInfo,
    required String emergencyContact,
    required String leaveType,
    required String reason,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      print('🔍 Submitting leave request with data:');
      print('   - Full Name: $fullName');
      print('   - Contact Info: $contactInfo');
      print('   - Emergency Contact: $emergencyContact');
      print('   - Leave Type: $leaveType');
      print('   - Reason: $reason');
      print('   - Start Date: $startDate');
      print('   - End Date: $endDate');

      // Get current user ID
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Calculate leave duration in days
      final duration = endDate.difference(startDate).inDays + 1;

      // Create leave request data
      final leaveRequestData = {
        'leave_request_id': '', // Will be updated with document ID
        'caregiver_id': currentUser.uid,
        'caregiver_email': currentUser.email ?? '',
        'full_name': fullName.trim(),
        'contact_info': contactInfo.trim(),
        'emergency_contact': emergencyContact.trim(),
        'leave_type': leaveType,
        'reason': reason.trim(),
        'start_date': Timestamp.fromDate(startDate),
        'end_date': Timestamp.fromDate(endDate),
        'duration_days': duration,
        'status': 'pending', // pending, approved, rejected
        'submitted_at': FieldValue.serverTimestamp(),
        'reviewed_at': null,
        'reviewed_by': null,
        'reviewer_comments': null,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Add the document to Firestore
      final docRef = await _firestore.collection('leave_requests').add(leaveRequestData);
      
      // Update the document with its own ID
      await docRef.update({
        'leave_request_id': docRef.id,
        'updated_at': FieldValue.serverTimestamp(),
      });

      print('✅ Leave request submitted successfully with ID: ${docRef.id}');
      
      return docRef.id;
    } catch (e) {
      print('❌ Error submitting leave request: $e');
      rethrow;
    }
  }

  /// Gets all leave requests for the current user
  static Stream<List<Map<String, dynamic>>> getUserLeaveRequests() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('leave_requests')
        .where('caregiver_id', isEqualTo: currentUser.uid)
        .orderBy('submitted_at', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // Include document ID
        return data;
      }).toList();
    });
  }

  /// Gets a specific leave request by ID
  static Future<Map<String, dynamic>?> getLeaveRequestById(String requestId) async {
    try {
      final doc = await _firestore.collection('leave_requests').doc(requestId).get();
      if (doc.exists) {
        final data = doc.data();
        if (data == null) return null;
        data['id'] = doc.id;
        return data;
      }
      return null;
    } catch (e) {
      print('❌ Error fetching leave request: $e');
      rethrow;
    }
  }

  /// Updates a leave request (for status updates by admins)
  static Future<void> updateLeaveRequestStatus({
    required String requestId,
    required String status, // 'approved' or 'rejected'
    required String reviewerId,
    String? reviewerComments,
  }) async {
    try {
      // First, get the leave request data to extract caregiver info
      final leaveRequestDoc = await _firestore.collection('leave_requests').doc(requestId).get();
      
      if (!leaveRequestDoc.exists) {
        throw Exception('Leave request not found');
      }
      
      final leaveData = leaveRequestDoc.data()!;
      final caregiverId = leaveData['caregiver_id'] as String;
      final leaveType = leaveData['leave_type'] as String? ?? 'Leave';
      final startDate = (leaveData['start_date'] as Timestamp?)?.toDate();
      final endDate = (leaveData['end_date'] as Timestamp?)?.toDate();
      
      // Update the leave request status
      await _firestore.collection('leave_requests').doc(requestId).update({
        'status': status,
        'reviewed_at': FieldValue.serverTimestamp(),
        'reviewed_by': reviewerId,
        'reviewer_comments': reviewerComments ?? '',
        'updated_at': FieldValue.serverTimestamp(),
      });

      print('✅ Leave request $requestId status updated to: $status');
      
      // Create notification for the caregiver
      String notificationTitle;
      String notificationMessage;
      NotificationType notificationType;
      
      if (status.toLowerCase() == 'approved') {
        notificationTitle = 'Leave Request Approved';
        notificationMessage = 'Your $leaveType request';
        if (startDate != null && endDate != null) {
          final dateFormat = DateFormat('MMM dd, yyyy');
          notificationMessage += ' from ${dateFormat.format(startDate)} to ${dateFormat.format(endDate)}';
        }
        notificationMessage += ' has been approved.';
        if (reviewerComments != null && reviewerComments.isNotEmpty) {
          notificationMessage += '\n\nReviewer\'s comment: $reviewerComments';
        }
        notificationType = NotificationType.leaveApproved;
      } else {
        notificationTitle = 'Leave Request Denied';
        notificationMessage = 'Your $leaveType request';
        if (startDate != null && endDate != null) {
          final dateFormat = DateFormat('MMM dd, yyyy');
          notificationMessage += ' from ${dateFormat.format(startDate)} to ${dateFormat.format(endDate)}';
        }
        notificationMessage += ' has been denied.';
        if (reviewerComments != null && reviewerComments.isNotEmpty) {
          notificationMessage += '\n\nReason: $reviewerComments';
        } else {
          notificationMessage += ' Please contact your supervisor for more details.';
        }
        notificationType = NotificationType.leaveDenied;
      }
      
      // Send notification to the caregiver
      await _notificationService.createNotification(
        title: notificationTitle,
        message: notificationMessage,
        userId: caregiverId,
        userType: 'caregiver',
        type: notificationType,
        referenceId: requestId,
        referenceType: 'leave_request',
        priority: NotificationPriority.high,
        category: 'Leave Management',
        metadata: {
          'leave_type': leaveType,
          'status': status,
          'reviewed_by': reviewerId,
          'reviewer_comments': reviewerComments ?? '',
        },
      );
      
      print('✅ Notification sent to caregiver for leave request $status');
    } catch (e) {
      print('❌ Error updating leave request status: $e');
      rethrow;
    }
  }

  /// Gets all leave requests for admin review
  static Stream<List<Map<String, dynamic>>> getAllLeaveRequests() {
    return _firestore
        .collection('leave_requests')
        .orderBy('submitted_at', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  /// Gets leave requests by status
  static Stream<List<Map<String, dynamic>>> getLeaveRequestsByStatus(String status) {
    return _firestore
        .collection('leave_requests')
        .where('status', isEqualTo: status)
        .orderBy('submitted_at', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  /// Gets pending leave requests count for the current user
  static Future<int> getPendingLeaveCount() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return 0;
    }

    try {
      final snapshot = await _firestore
          .collection('leave_requests')
          .where('caregiver_id', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'pending')
          .get();
      
      return snapshot.docs.length;
    } catch (e) {
      print('❌ Error getting pending leave count: $e');
      return 0;
    }
  }

  /// Validates leave request dates
  static bool validateLeaveDates(DateTime startDate, DateTime endDate) {
    // Start date cannot be in the past (allow today)
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final startDateOnly = DateTime(startDate.year, startDate.month, startDate.day);
    
    if (startDateOnly.isBefore(todayOnly)) {
      return false;
    }

    // End date must be after or equal to start date
    if (endDate.isBefore(startDate)) {
      return false;
    }

    return true;
  }

  /// Checks for overlapping leave requests
  static Future<bool> hasOverlappingLeave(DateTime startDate, DateTime endDate) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return false;
    }

    try {
      // Get all approved leave requests for the current user
      final snapshot = await _firestore
          .collection('leave_requests')
          .where('caregiver_id', isEqualTo: currentUser.uid)
          .where('status', whereIn: ['pending', 'approved'])
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final existingStart = (data['start_date'] as Timestamp).toDate();
        final existingEnd = (data['end_date'] as Timestamp).toDate();

        // Check for overlap
        if (!(endDate.isBefore(existingStart) || startDate.isAfter(existingEnd))) {
          return true; // Overlap found
        }
      }

      return false; // No overlap
    } catch (e) {
      print('❌ Error checking for overlapping leave: $e');
      return false; // Assume no overlap on error
    }
  }
}