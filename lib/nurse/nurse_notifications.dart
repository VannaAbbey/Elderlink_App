import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/nurse_services/nurse_notification_service.dart';
import '../models/cg_models/notification_model.dart';

class NurseNotificationsScreen extends StatefulWidget {
  const NurseNotificationsScreen({super.key});

  @override
  State<NurseNotificationsScreen> createState() =>
      _NurseNotificationsScreenState();
}

class _NurseNotificationsScreenState extends State<NurseNotificationsScreen> {
  final NurseNotificationService _notificationService =
      NurseNotificationService();
  String? _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Please login to view notifications')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(
                Icons.arrow_back,
                color: Color(0xFF22688E),
                size: 32,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Center(
                child: Text(
                  'Leave Notifications',
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF22688E),
                  ),
                ),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.filter_list,
                color: Color(0xFF22688E),
                size: 32,
              ),
              onSelected: (value) {
                setState(() {
                  _selectedFilter = value;
                });
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'All',
                  child: Text('All Leave Notifications'),
                ),
                const PopupMenuItem(
                  value: 'Leave Submitted',
                  child: Text('Leave Submitted'),
                ),
                const PopupMenuItem(
                  value: 'Leave Approved',
                  child: Text('Leave Approved'),
                ),
                const PopupMenuItem(
                  value: 'Leave Denied',
                  child: Text('Leave Denied'),
                ),
                const PopupMenuItem(
                  value: 'Leave Modified',
                  child: Text('Leave Modified'),
                ),
                const PopupMenuItem(
                  value: 'Leave Cancelled',
                  child: Text('Leave Cancelled'),
                ),
              ],
            ),
          ],
        ),
        toolbarHeight: 80,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/background1.png',
              fit: BoxFit.cover,
            ),
          ),
          Column(
            children: [
              // Filter bar
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      'Filter: ${_selectedFilter ?? 'All'}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF22688E),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        await _notificationService
                            .markAllLeaveNotificationsAsRead(currentUser.uid);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('All notifications marked as read'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(
                        Icons.done_all,
                        color: Color(0xFF22688E),
                      ),
                      label: const Text(
                        'Mark All Read',
                        style: TextStyle(color: Color(0xFF22688E)),
                      ),
                    ),
                  ],
                ),
              ),
              // Notifications list
              Expanded(
                child: StreamBuilder<List<NotificationModel>>(
                  stream: _getFilteredNotifications(currentUser.uid),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF22688E),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Error loading notifications',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              snapshot.error.toString(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    }

                    final notifications = snapshot.data ?? [];

                    if (notifications.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.notifications_none,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _selectedFilter == 'All'
                                  ? 'No leave notifications yet'
                                  : 'No ${_selectedFilter?.toLowerCase()} notifications',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Leave request notifications will appear here when submitted, approved, denied, or modified.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: notifications.length,
                      itemBuilder: (context, index) {
                        final notification = notifications[index];
                        return _buildNotificationCard(notification);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Stream<List<NotificationModel>> _getFilteredNotifications(String nurseId) {
    final allNotifications = _notificationService.getLeaveNotificationsStream(
      nurseId,
    );

    if (_selectedFilter == null || _selectedFilter == 'All') {
      return allNotifications;
    } else {
      // Filter by type
      NotificationType? type;
      switch (_selectedFilter) {
        case 'Leave Submitted':
          type = NotificationType.leaveSubmitted;
          break;
        case 'Leave Approved':
          type = NotificationType.leaveApproved;
          break;
        case 'Leave Denied':
          type = NotificationType.leaveDenied;
          break;
        case 'Leave Modified':
          type = NotificationType.leaveModified;
          break;
        case 'Leave Cancelled':
          type = NotificationType.leaveCancelled;
          break;
      }

      if (type != null) {
        return allNotifications.map(
          (notifications) => notifications
              .where((notification) => notification.type == type)
              .toList(),
        );
      }

      return allNotifications;
    }
  }

  Widget _buildNotificationCard(NotificationModel notification) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final timeFormat = DateFormat('h:mm a');

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white, size: 32),
      ),
      onDismissed: (direction) async {
        await _notificationService.deleteNotification(notification.id);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Notification deleted')));
        }
      },
      child: Card(
        color: notification.isRead
            ? const Color(0xFFF5F5F5)
            : const Color(0xFFE8F0FE),
        elevation: notification.isRead ? 2 : 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: () async {
            if (!notification.isRead) {
              await _notificationService.markNotificationAsRead(
                notification.id,
              );
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getTypeColor(notification.type),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        notification.type.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${dateFormat.format(notification.timestamp)} at ${timeFormat.format(notification.timestamp)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (!notification.isRead) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF22688E),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  notification.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: notification.isRead
                        ? Colors.grey[700]
                        : Colors.black,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  notification.message,
                  style: TextStyle(
                    fontSize: 14,
                    color: notification.isRead
                        ? Colors.grey[600]
                        : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getTypeColor(NotificationType type) {
    switch (type) {
      case NotificationType.leaveSubmitted:
        return Colors.indigo;
      case NotificationType.leaveApproved:
        return Colors.green;
      case NotificationType.leaveDenied:
        return Colors.red;
      case NotificationType.leaveModified:
        return Colors.orange;
      case NotificationType.leaveCancelled:
        return Colors.grey;
      default:
        return Colors.teal;
    }
  }
}
