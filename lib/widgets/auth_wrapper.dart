import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../auth/get_started.dart';
import '../caregiver/home.dart';
import '../nurse/home.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        print('DEBUG: AuthWrapper build - isAuthenticated: ${authProvider.isAuthenticated}, userData: ${authProvider.userData != null}');
        
        // If user is not authenticated, show get started page
        if (!authProvider.isAuthenticated) {
          print('DEBUG: User not authenticated, showing GetStartedPage');
          return const GetStartedPage();
        }

        // If user is authenticated but userData is null, show minimal loading
        if (authProvider.userData == null) {
          print('DEBUG: User authenticated but no userData, showing minimal loading');
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // User is authenticated and has data, navigate based on role
        final userRole = authProvider.userRole;
        print('DEBUG: User authenticated with role: $userRole');
        
        switch (userRole) {
          case 'administrator':
            print('DEBUG: Navigating to CaregiverHomeScreen (admin)');
            return const CaregiverHomeScreen();
          case 'nurse':
            print('DEBUG: Navigating to NurseHomeScreen');
            return const NurseHomeScreen();
          case 'caregiver':
          default:
            print('DEBUG: Navigating to CaregiverHomeScreen (default)');
            return const CaregiverHomeScreen();
        }
      },
    );
  }
}
