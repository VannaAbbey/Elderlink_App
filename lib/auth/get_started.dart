import 'package:flutter/material.dart';
import 'package:elderlink_app/auth/login.dart';

class TextStyles {
  static const TextStyle header = TextStyle(
    fontFamily: 'Poppins',
    fontSize: 33,
    fontWeight: FontWeight.w900,
    color: Color(0xFF142B35),
  );

  static const TextStyle subtext = TextStyle(
    fontFamily: 'Poppins',
    color: Color(0xFF142B35),
  );
}

class GetStartedPage extends StatelessWidget {
  const GetStartedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.08),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: screenHeight * 0.10), // ✅ top padding for logo

                  // Logo & Title
                  Image.asset(
                    'assets/images/logo.png',
                    height: screenHeight * 0.10,
                  ),
                  const SizedBox(height: 4),
                  Text('ELDERLINK', style: TextStyles.header),

                  SizedBox(height: screenHeight * 0.015),

                  // Elderly image (✅ made a bit larger)
                  Image.asset(
                    'assets/images/elderly.png',
                    height: screenHeight * 0.35,
                  ),

                  SizedBox(height: screenHeight * 0.02),

                  Text('WELCOME !', style: TextStyles.header),
                  SizedBox(height: 8),
                  Text(
                    'Manage caregiving tasks\nWith ease and stay connected',
                    textAlign: TextAlign.center,
                    style: TextStyles.subtext.copyWith(
                      fontSize: screenWidth * 0.045,
                    ),
                  ),

                  SizedBox(height: screenHeight * 0.04),

                  // Get Started Button
                  SizedBox(
                    width: screenWidth * 0.7,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LoginScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          vertical: screenHeight * 0.014,
                        ),
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: Text(
                        'Get Started',
                        style: TextStyles.subtext.copyWith(
                          fontWeight: FontWeight.bold, fontSize: screenWidth * 0.045,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
