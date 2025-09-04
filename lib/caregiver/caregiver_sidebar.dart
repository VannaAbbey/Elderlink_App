import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'edit_profile.dart';
import 'settings.dart';
import 'help_support.dart';

class CaregiverSidebar extends StatelessWidget {
  final VoidCallback onLogout;
  final bool isSidebarOpen;
  final VoidCallback toggleSidebar;
  final BuildContext parentContext;

  const CaregiverSidebar({
    required this.onLogout,
    required this.isSidebarOpen,
    required this.toggleSidebar,
    required this.parentContext,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!isSidebarOpen) return SizedBox.shrink();
    return Stack(
      children: [
        GestureDetector(
          onTap: toggleSidebar,
          child: Container(color: Colors.black54),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          child: Material(
            elevation: 5,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(10),
              bottomRight: Radius.circular(10),
            ),
            child: Container(
              width: 250,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 50),
                  Center(
                    child: Consumer<AuthProvider>(
                      builder: (context, authProvider, child) {
                        if (authProvider.userData == null) {
                          return const Text(
                            'Caregiver',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                              fontFamily: 'Poppins',
                            ),
                          );
                        }
                        final firstName = authProvider.userFirstName;
                        final displayName = (firstName.isEmpty || firstName == 'User') ? '' : firstName;
                        return Text(
                          displayName.isEmpty ? 'Caregiver' : 'Caregiver $displayName',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            fontFamily: 'Poppins',
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(Icons.edit, color: Color(0xFF00588e)),
                    title: Text('Edit Profile'),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(
                        parentContext,
                        MaterialPageRoute(builder: (context) => const EditProfile()),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.settings, color: Color(0xFF00588e)),
                    title: Text('Settings'),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(
                        parentContext,
                        MaterialPageRoute(builder: (context) => const Settings()),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.help, color: Color(0xFF00588e)),
                    title: Text('Help & Support'),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(
                        parentContext,
                        MaterialPageRoute(builder: (context) => const HelpSupport()),
                      );
                    },
                  ),
                  const Divider(),
                  const SizedBox(height: 20),
                  Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D5B78),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 60,
                        ),
                      ),
                      onPressed: onLogout,
                      child: const Text(
                        'LOGOUT',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
