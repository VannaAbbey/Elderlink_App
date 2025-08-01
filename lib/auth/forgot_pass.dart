import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class TextStyles {
  static const TextStyle buttontext = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 16,
    color: Colors.white,
  );
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    if (_emailController.text.trim().isEmpty) {
      _showDialog('Error', 'Please enter your email address.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.resetPassword(email: _emailController.text.trim());
      if (mounted) {
        _showDialog(
          'Success', 
          'Password reset email sent! Please check your inbox.',
          isSuccess: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _showDialog('Error', e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showDialog(String title, String message, {bool isSuccess = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (isSuccess) {
                Navigator.pop(context); // Go back to login screen
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final screenWidth = size.width;
    final screenHeight = size.height;

    return Scaffold(
      body: Stack(
        children: [
          // 🔹 Background
          SizedBox(
            height: screenHeight,
            width: screenWidth,
            child: Image.asset(
              'assets/images/background.png',
              fit: BoxFit.cover,
            ),
          ),

          // 🔹 Foreground Content
          SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: screenHeight - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: screenHeight * 0.04,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      SizedBox(height: screenHeight * 0.04),

                      // 🔒 Icon
                      Image.asset(
                        'assets/images/lockIcon.png',
                        height: screenHeight * 0.1,
                        width: screenHeight * 0.1,
                      ),

                      SizedBox(height: screenHeight * 0.03),

                      // 🔤 Header
                      Text(
                        "Forgot\nPassword?",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: screenWidth * 0.075,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF142B35),
                        ),
                      ),

                      SizedBox(height: screenHeight * 0.02),

                      // 📝 Subtext
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.1),
                        child: const Text(
                          "Enter your email address and we'll send you a password reset link:",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, color: Colors.black),
                        ),
                      ),

                      SizedBox(height: screenHeight * 0.04),

                      // ✉️ Email Input
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.08),
                        child: TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: 'Enter your email address',
                            filled: true,
                            fillColor: const Color(0xFFC1E5E9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: const Icon(Icons.email, color: Colors.black54),
                          ),
                        ),
                      ),

                      SizedBox(height: screenHeight * 0.04),

                      // � Send Reset Email Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1D5B78),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: screenWidth * 0.20,
                            vertical: screenHeight * 0.015,
                          ),
                        ),
                        onPressed: _isLoading ? null : _handleResetPassword,
                        child: _isLoading 
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'SEND RESET EMAIL',
                              style: TextStyles.buttontext,
                            ),
                      ),

                      SizedBox(height: screenHeight * 0.02),

                      // 🔙 Back Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: screenWidth * 0.20,
                            vertical: screenHeight * 0.015,
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: const Text(
                          'BACK TO LOGIN',
                          style: TextStyles.buttontext,
                        ),
                      ),

                      SizedBox(height: screenHeight * 0.04),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
