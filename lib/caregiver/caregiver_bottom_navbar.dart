import 'package:flutter/material.dart';

class CaregiverBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onNavTap;

  const CaregiverBottomNavBar({
    Key? key,
    required this.selectedIndex,
    required this.onNavTap,
  }) : super(key: key);

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
            _navIcon('assets/images/homeIcon.png', 0),
            _navIcon('assets/images/addTaskIcon.png', 1),
            _navIcon('assets/images/emerIcon.png', 2),
            _navIcon('assets/images/incidentIcon.png', 3),
            _navIcon('assets/images/shiftIcon.png', 4),
          ],
        ),
      ),
    );
  }

  Widget _navIcon(String assetPath, int index) {
    return GestureDetector(
      onTap: () => onNavTap(index),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selectedIndex == index
              ? const Color.fromARGB(255, 255, 255, 255)
              : Colors.transparent,
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
