import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart' as app_auth;
import 'edit_profile.dart';
import 'leave_form.dart';
import 'health_analytics_selector.dart';
import 'activity_logs.dart';
import 'infirmary_view.dart';

class NurseSidebar extends StatelessWidget {
  final bool isSidebarOpen;
  final VoidCallback toggleSidebar;
  final BuildContext parentContext;

  const NurseSidebar({
    required this.isSidebarOpen,
    required this.toggleSidebar,
    required this.parentContext,
    super.key,
  });

  Future<void> _handleLogout() async {
    final authProvider = Provider.of<app_auth.AuthProvider>(
      parentContext,
      listen: false,
    );
    await authProvider.signOut();
    if (parentContext.mounted) {
      Navigator.pushNamedAndRemoveUntil(
        parentContext,
        '/get_started',
        (route) => false,
      );
    }
  }

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
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 50),
                  Center(
                    child: Consumer<app_auth.AuthProvider>(
                      builder: (context, authProvider, child) {
                        final firstName = authProvider.userFirstName;
                        final displayName =
                            (firstName.isEmpty || firstName == 'User')
                            ? ''
                            : firstName;
                        return Text(
                          displayName.isEmpty ? 'Nurse' : 'Nurse $displayName',
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
                    leading: Icon(Icons.edit, color: Color(0xFF00588E)),
                    title: Text('Edit Profile'),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(
                        parentContext,
                        MaterialPageRoute(
                          builder: (context) => const EditProfile(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.analytics, color: Color(0xFF00588E)),
                    title: Text('Health Analytics'),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(
                        parentContext,
                        MaterialPageRoute(
                          builder: (context) => HealthAnalyticsSelectorScreen(
                            nurseName: Provider.of<app_auth.AuthProvider>(
                              parentContext,
                              listen: false,
                            ).userFirstName,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.local_hospital,
                      color: Color(0xFF00588E),
                    ),
                    title: Text('Infirmary Management'),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(
                        parentContext,
                        MaterialPageRoute(
                          builder: (context) => const InfirmaryViewScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.request_page, color: Color(0xFF00588E)),
                    title: Text('Request Leave'),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(
                        parentContext,
                        MaterialPageRoute(
                          builder: (context) => const LeaveForm(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.history, color: Color(0xFF00588E)),
                    title: Text('Activity Logs'),
                    onTap: () {
                      toggleSidebar();
                      // Import will be added at the top
                      Navigator.push(
                        parentContext,
                        MaterialPageRoute(
                          builder: (context) => ActivityLogsScreen(
                            houseId: 'H001', // Default house
                            nurseName: Provider.of<app_auth.AuthProvider>(
                              parentContext,
                              listen: false,
                            ).userFirstName,
                          ),
                        ),
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
                      onPressed: _handleLogout,
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
