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
        // Show loading indicator while checking authentication state
        if (authProvider.isLoading && authProvider.currentUser == null) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // If user is authenticated, navigate to appropriate home screen
        if (authProvider.isAuthenticated) {
          // Wait for user data to load before deciding which home screen
          if (authProvider.userData == null) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          // Navigate based on user role
          final userRole = authProvider.userRole;
          if (userRole == 'nurse') {
            return const NurseHomeScreen();
          } else {
            return const CaregiverHomeScreen();
          }
        }

        // If user is not authenticated, show get started page
        return const GetStartedPage();
      },
    );
  }
}
