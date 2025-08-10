import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

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
  
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      _showErrorDialog('Please fill in all fields.');
      return;
    }

    final success = await authProvider.signInWithEmailAndPassword(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );

    if (mounted) {
      if (success) {
        // Navigation is handled by AuthWrapper based on user role
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/caregiver_home', // This will be redirected by AuthWrapper
          (route) => false,
        );
      } else {
        _showErrorDialog(authProvider.error ?? 'Login failed. Please try again.');
      }
    }
  }

  Future<void> _handleSocialLogin(String provider) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // Development workaround for platform channel issues
    if (kDebugMode && provider != 'google') {
      _showErrorDialog('${provider.substring(0, 1).toUpperCase()}${provider.substring(1)} Sign-In is temporarily disabled in development. Please use Google Sign-In or email login.');
      return;
    }

    bool success = false;
    
    try {
      switch (provider) {
        case 'google':
          success = await authProvider.signInWithGoogle();
          break;
        case 'facebook':
          success = await authProvider.signInWithFacebook();
          break;
        case 'apple':
          success = await authProvider.signInWithApple();
          break;
      }

      if (mounted) {
        if (success) {
          // Navigation is handled by AuthWrapper based on user role
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/caregiver_home', // This will be redirected by AuthWrapper
            (route) => false,
          );
        } else {
          String errorMessage = authProvider.error ?? 'Social login failed. Please try again.';
          
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
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('An unexpected error occurred. Please try again.');
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
                            Consumer<AuthProvider>(
                              builder: (context, authProvider, child) {
                                return ElevatedButton(
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
                                  onPressed: authProvider.isLoading ? null : _handleLogin,
                                  child: authProvider.isLoading 
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Text('LOGIN', style: TextStyles.buttontext),
                                );
                              },
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
