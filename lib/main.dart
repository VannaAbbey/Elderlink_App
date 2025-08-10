import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'widgets/auth_wrapper.dart';
import 'auth/get_started.dart'; 
import 'auth/login.dart';
import 'auth/register_choose_role.dart';
import 'auth/forgot_pass.dart';
import 'auth/register_success.dart';
import 'caregiver/home.dart';
import 'nurse/home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully');
  } catch (e) {
    print('Firebase initialization failed: $e');
    // Continue without Firebase for now
  }
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ElderLink',
      theme: ThemeData(
        fontFamily: 'Poppins',
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 15), // Default size ng body text
        ),
        colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFFA5D4DC)),
        inputDecorationTheme: InputDecorationTheme(
          contentPadding: EdgeInsets.symmetric(vertical: 2, horizontal: 20),
          filled: true,
          fillColor: Color(0xFFC1E5E9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(30)),
            borderSide: BorderSide.none,
          ),
          hintStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
      routes: {
        '/get_started': (context) => const GetStartedPage(),
        '/login': (context) => const LoginScreen(),
        '/register_choose_role': (context) => const RegisterChooseRoleScreen(),
        '/forgot_pass': (context) => const ForgotPasswordScreen(),
        '/register_success': (context) => const RegisterSuccessScreen(),
        '/caregiver_home': (context) => const CaregiverHomeScreen(),
        '/nurse_home': (context) => const NurseHomeScreen(),
      },
    );
  }
}
