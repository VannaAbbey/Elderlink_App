import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/nurse_services/nurse_notification_service.dart';
import '../../nurse/nurse_notifications.dart';

class NurseNotificationIconButton extends StatelessWidget {
  const NurseNotificationIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return Container(); // Don't show notification icon if not logged in
    }

    final notificationService = NurseNotificationService();

    return StreamBuilder<int>(
      stream: notificationService.getUnreadLeaveNotificationsCount(
        currentUser.uid,
      ),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;

        return Stack(
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications,
                color: Color(0xFF22688E),
                size: 32,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NurseNotificationsScreen(),
                  ),
                );
              },
            ),
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
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
