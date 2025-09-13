import 'package:flutter/material.dart';
import 'medication_management.dart';
import 'vital_monitoring.dart';

class BottomNavbar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTap;

  const BottomNavbar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0XFFA5D4DC),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _navIcon(context, 'assets/images/homeIcon.png', 0),
            _navIcon(context, 'assets/images/addTaskIcon.png', 1),
            _navIcon(context, 'assets/images/emerIcon.png', 2),
            _navIcon(context, 'assets/images/incidentIcon.png', 3),
            _navIcon(context, 'assets/images/shiftIcon.png', 4),
          ],
        ),
      ),
    );
  }

  Widget _navIcon(BuildContext context, String assetPath, int index) {
    return GestureDetector(
      onTap: () {
        onTap(index); // parent handles navigation
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selectedIndex == index ? Colors.white : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Image.asset(
          assetPath,
          height: 38,
          width: 38,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
