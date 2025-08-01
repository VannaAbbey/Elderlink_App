import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class TextStyles {
  static const TextStyle header = TextStyle(
    fontSize: 33,
    fontWeight: FontWeight.w900,
    color: Color(0xFF142B35),
  );

  static const TextStyle logintext = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 30,
    color: Color(0xFF2D5260),
  );

  static const TextStyle subtext = TextStyle(
    fontSize: 16,
    color: Color(0xFF1E1E1A),
  );

  static const TextStyle buttontext = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 16,
    color: Colors.white,
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isPasswordVisible = false;
  bool isLoading = false;
  
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      _showErrorDialog('Please fill in all fields.');
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final userCredential = await _authService.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (userCredential != null && mounted) {
        // Get user data to determine role
        final userData = await _authService.getUserData(userCredential.user!.uid);
        
        if (userData != null) {
          final role = userData['role'] as String;
          
          // Navigate based on role
          if (role == 'caregiver') {
            Navigator.pushReplacementNamed(context, '/caregiver_home');
          } else if (role == 'nurse') {
            Navigator.pushReplacementNamed(context, '/nurse_home');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSocialLogin(String provider) async {
    // Development workaround for platform channel issues
    if (kDebugMode && provider != 'google') {
      _showErrorDialog('${provider.substring(0, 1).toUpperCase()}${provider.substring(1)} Sign-In is temporarily disabled in development. Please use Google Sign-In or email login.');
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      UserCredential? userCredential;
      
      switch (provider) {
        case 'google':
          userCredential = await _authService.signInWithGoogle();
          break;
        case 'facebook':
          userCredential = await _authService.signInWithFacebook();
          break;
        case 'apple':
          userCredential = await _authService.signInWithApple();
          break;
      }

      if (userCredential != null && mounted) {
        // Get user data to determine role
        final userData = await _authService.getUserData(userCredential.user!.uid);
        
        if (userData != null) {
          final role = userData['role'] as String;
          
          // Navigate based on role
          if (role == 'caregiver') {
            Navigator.pushReplacementNamed(context, '/caregiver_home');
          } else if (role == 'nurse') {
            Navigator.pushReplacementNamed(context, '/nurse_home');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString();
        
        // Provide more user friendly error messages
        if (errorMessage.contains('platform error') || errorMessage.contains('channel')) {
          errorMessage = 'Social login is currently unavailable. Please try email login or configure the platform settings.';
        } else if (errorMessage.contains('not supported')) {
          errorMessage = '${provider.substring(0, 1).toUpperCase()}${provider.substring(1)} Sign-In is not available on this device.';
        } else if (errorMessage.contains('not available')) {
          errorMessage = 'This sign-in method needs additional setup. Please use email login for now.';
        }
        
        _showErrorDialog(errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.asset(
              'assets/images/background.png', // <-- make sure this image exists
              fit: BoxFit.cover,
            ),
          ),

          // Foreground content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.1),
                  child: Column(
                    children: [
                      Image.asset('assets/images/logo.png', height: size.height * 0.1),
                      const SizedBox(height: 10),
                      const Text('ELDERLINK', style: TextStyles.header),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white, // optional transparency
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            const Text('Login', style: TextStyles.logintext),
                            const SizedBox(height: 8),
                            const Text(
                              'Continue your Elderly Care Journey, Sign in now!',
                              textAlign: TextAlign.center,
                              style: TextStyles.subtext,
                            ),
                            const SizedBox(height: 25),
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                hintText: 'Email',
                                filled: true,
                                fillColor: const Color(0xFFC1E5E9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(30),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 15),
                            TextField(
                              controller: _passwordController,
                              obscureText: !isPasswordVisible,
                              decoration: InputDecoration(
                                hintText: 'Password',
                                filled: true,
                                fillColor: const Color(0xFFC1E5E9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(30),
                                  borderSide: BorderSide.none,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                    color: Colors.black54,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      isPasswordVisible = !isPasswordVisible;
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 25),
                            Center(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1D5B78),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 95,
                                  ),
                                ),
                                onPressed: isLoading ? null : _handleLogin,
                                child: isLoading 
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Text('LOGIN', style: TextStyles.buttontext),
                              ),
                            ),
                            const SizedBox(height: 20),
                            GestureDetector(
                              onTap: () {
                                Navigator.pushNamed(context, '/forgot_pass');
                              },
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  color: Color(0xFF142B35),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text("Don't have an account?"),
                            GestureDetector(
                              onTap: () {
                                Navigator.pushNamed(context, '/register_choose_role');
                              },
                              child: const Text(
                                "Register Here.",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF142B35),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text('Or Continue With', style: TextStyle(fontFamily: 'Poppins')),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                GestureDetector(
                                  onTap: () => _handleSocialLogin('google'),
                                  child: Image.asset('assets/images/google.png', height: 47),
                                ),
                                GestureDetector(
                                  onTap: () => _handleSocialLogin('facebook'),
                                  child: Image.asset('assets/images/fb.png', height: 50),
                                ),
                                GestureDetector(
                                  onTap: () => _handleSocialLogin('apple'),
                                  child: Image.asset('assets/images/apple.png', height: 47),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
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
