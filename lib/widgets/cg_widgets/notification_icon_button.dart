import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/cg_services/notification_service.dart';
import '../../caregiver/notifications.dart';

/// A reusable notification icon button with red dot indicator for unread notifications
class NotificationIconButton extends StatelessWidget {
  final Color iconColor;
  final double iconSize;

  const NotificationIconButton({
    super.key,
    this.iconColor = const Color(0xFF00588e),
    this.iconSize = 35,
  });

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    
    if (currentUser == null) {
      // Return a disabled icon if no user is logged in
      return IconButton(
        icon: Icon(Icons.notifications, color: iconColor, size: iconSize),
        onPressed: null,
      );
    }

    return StreamBuilder<int>(
      stream: NotificationService().getUnreadNotificationsCount(currentUser.uid),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;
        
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: Icon(Icons.notifications, color: iconColor, size: iconSize),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const NotificationsScreen(),
                  ),
                );
              },
            ),
            // Red dot indicator for unread notifications
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}