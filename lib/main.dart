import 'package:flutter/material.dart';
import '../auth/get_started.dart'; // make sure the path is correct
import '../auth/register_choose_role.dart';
import '../auth/forgot_pass.dart';


void main() {
  runApp(const MyApp());
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
      initialRoute: '/', // ✅ START HERE
      routes: {
        '/': (context) =>
            const GetStartedPage(), // ✅ This becomes the first screen
        '/register_choose_role': (context) => const RegisterChooseRoleScreen(),
        '/forgot_pass': (context) => const ForgotPasswordScreen(),
      },
    );
  }
}
