import 'package:flutter/material.dart';

class TextStyles {
  static const TextStyle buttontext = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 16,
    color: Colors.white,
  );
}

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

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
                          "Select which contain details to \nbe use to reset your password:",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, color: Colors.black),
                        ),
                      ),

                      SizedBox(height: screenHeight * 0.04),

                      // ✉️ Email
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.08),
                        child: Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                            side: const BorderSide(color: Colors.black87, width: 2),
                          ),
                          child: Container(
                            height: screenHeight * 0.12,
                            padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.15),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.email,
                                  size: screenHeight * 0.07,
                                  color: const Color(0xFF3D7795),
                                ),
                                SizedBox(width: screenWidth * 0.05),
                                Expanded(
                                  child: Text(
                                    'via Email\nAddress',
                                    style: TextStyle(
                                      fontSize: 20,
                                      color: const Color(0xFF3D7795),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: screenHeight * 0.025),

                      // 📞 Phone
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.08),
                        child: Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                            side: const BorderSide(color: Colors.black87, width: 2),
                          ),
                          child: Container(
                            height: screenHeight * 0.12,
                            padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.15),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.phone,
                                  size: screenHeight * 0.07,
                                  color: const Color(0xFF3D7795),
                                ),
                                SizedBox(width: screenWidth * 0.05),
                                Expanded(
                                  child: Text(
                                    'via Contact\nNumber',
                                    style: TextStyle(
                                      fontSize: 20,
                                      color: const Color(0xFF3D7795),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: screenHeight * 0.05),

                      // 🔙 Back Button
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
