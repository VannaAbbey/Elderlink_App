import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class RegisterProfileScreen extends StatefulWidget {
  const RegisterProfileScreen({super.key});

  @override
  State<RegisterProfileScreen> createState() => _RegisterProfileScreenState();
}

class _RegisterProfileScreenState extends State<RegisterProfileScreen> {
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreed = false;
  DateTime? _selectedDate;
  final TextEditingController _birthdayController = TextEditingController();

  Future<void> _pickDate() async {
    DateTime now = DateTime.now();
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _birthdayController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  InputDecoration customInput(
    String hint, {
    Widget? suffixIcon,
    TextEditingController? controller,
    bool readOnly = false,
    VoidCallback? onTap,
    TextInputType? keyboardType,
  }) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      suffixIcon: suffixIcon,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: Colors.black, width: 1.8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: Colors.black, width: 2.3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // ✅ Full Background Image
          Positioned.fill(
            child: Image.asset(
              'assets/images/background.png', // Replace with your path
              fit: BoxFit.cover,
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.1),
                  child: Column(
                    children: [
                      SizedBox(height: size.height * 0.06),

                      Image.asset(
                        'assets/images/logo.png',
                        height: size.height * 0.1,
                      ),
                      const SizedBox(height: 20),

                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Center(
                              child: Text(
                                'Complete \nYour Profile',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2D5260),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Center(
                              child: Text(
                                'Tell us something more \nabout yourself...',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                            const SizedBox(height: 25),

                            TextField(decoration: customInput('First Name')),
                            const SizedBox(height: 15),
                            TextField(decoration: customInput('Last Name')),
                            const SizedBox(height: 15),
                            TextField(
                              controller: _birthdayController,
                              readOnly: true,
                              onTap: _pickDate,
                              decoration: customInput(
                                'Birthday',
                                suffixIcon: const Icon(Icons.calendar_today),
                              ),
                            ),
                            const SizedBox(height: 15),
                            TextField(
                              keyboardType: TextInputType.phone,
                              decoration: customInput('Phone Number'),
                            ),
                            const SizedBox(height: 15),
                            TextField(
                              keyboardType: TextInputType.emailAddress,
                              decoration: customInput('Email'),
                            ),
                            const SizedBox(height: 15),
                            TextField(
                              obscureText: _obscurePassword,
                              decoration: customInput(
                                'Password',
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 15),
                            TextField(
                              obscureText: _obscureConfirm,
                              decoration: customInput(
                                'Confirm Password',
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscureConfirm = !_obscureConfirm;
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Checkbox(
                                    value: _agreed,
                                    activeColor: const Color(0xFF216386),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    onChanged: (value) {
                                      setState(() {
                                        _agreed = value!;
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  const Text.rich(
                                    TextSpan(
                                      text: 'Agree to the ',
                                      style: TextStyle(fontSize: 15),
                                      children: [
                                        TextSpan(
                                          text: 'Terms and Privacy',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF2D5260),
                                          ),
                                        ),
                                      ],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 10),

                            Center(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF216386),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 90,
                                  ),
                                ),
                                onPressed: _agreed
                                    ? () {
                                        // Handle register action
                                      }
                                    : null,
                                child: const Text(
                                  'Register',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            Center(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.pop(context);
                                },
                                child: RichText(
                                  textAlign: TextAlign.center,
                                  text: const TextSpan(
                                    text: 'Already registered? ',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 15,
                                      fontFamily: 'Poppins',
                                    ),
                                    children: [
                                      TextSpan(
                                        text: '\nLog in Here.',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Poppins',
                                          color: Color(0xFF2D5260),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: size.height * 0.06),
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
