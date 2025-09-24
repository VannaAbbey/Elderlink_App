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
        // If user is not authenticated, show get started page
        if (!authProvider.isAuthenticated) {
          return const GetStartedPage();
        }

        // If user is authenticated but userData is null, show minimal loading
        if (authProvider.userData == null) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // User is authenticated and has data, navigate based on role
        final userRole = authProvider.userRole;
        
        switch (userRole) {
          case 'administrator':
            return const CaregiverHomeScreen();
          case 'nurse':
            return const NurseHomeScreen();
          case 'caregiver':
          default:
            return const CaregiverHomeScreen();
        }
      },
    );
  }
}
