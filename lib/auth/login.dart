import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
                                onPressed: () {},
                                child: const Text('LOGIN', style: TextStyles.buttontext),
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
                                  onTap: () async {
                                    final url = Uri.parse('https://accounts.google.com/');
                                    if (await canLaunchUrl(url)) {
                                      await launchUrl(url);
                                    }
                                  },
                                  child: Image.asset('assets/images/google.png', height: 47),
                                ),
                                GestureDetector(
                                  onTap: () async {
                                    final url = Uri.parse('https://facebook.com/login/');
                                    if (await canLaunchUrl(url)) {
                                      await launchUrl(url);
                                    }
                                  },
                                  child: Image.asset('assets/images/fb.png', height: 50),
                                ),
                                GestureDetector(
                                  onTap: () async {
                                    final url = Uri.parse('https://appleid.apple.com/');
                                    if (await canLaunchUrl(url)) {
                                      await launchUrl(url);
                                    }
                                  },
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
