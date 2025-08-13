import 'package:flutter/material.dart';
import 'register_complete_profile.dart';

class TextStyles {
  static const TextStyle header = TextStyle(
    fontSize: 33,
    fontWeight: FontWeight.w900,
    color: Color(0xFF142B35),
  );

  static const TextStyle registertext = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 30,
    color: Color(0xFF2D5260),
  );

  static const TextStyle roletext = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: Color(0xFF1E1E1A),
  );

  static const TextStyle buttontext = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 16,
    color: Colors.white,
  );
}

class RegisterChooseRoleScreen extends StatefulWidget {
  const RegisterChooseRoleScreen({super.key});

  @override
  State<RegisterChooseRoleScreen> createState() =>
      _RegisterChooseRoleScreenState();
}

class _RegisterChooseRoleScreenState extends State<RegisterChooseRoleScreen> {
  String? selectedRole;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // ✅ Background Image
          Positioned.fill(
            child: Image.asset(
              'assets/images/background.png',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.08),
                  child: Column(
                    children: [
                      const SizedBox(height: 20), // ✅ Top padding above logo
                      Image.asset(
                        'assets/images/logo.png',
                        height: size.height * 0.11,
                      ),
                      const SizedBox(height: 10),
                      const Text('ELDERLINK', style: TextStyles.header),
                      const SizedBox(height: 20),

                      // ✅ Register Box
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            const Text('Register',
                                style: TextStyles.registertext),
                            const SizedBox(height: 8),
                            const Text(
                              'Select Your Role',
                              textAlign: TextAlign.center,
                              style: TextStyles.roletext,
                            ),
                            const SizedBox(height: 25),

                            RoleCard(
                              imagePath: 'assets/images/caregiver.png',
                              title: 'Caregiver',
                              description:
                                  'Implements care tasks, tracks progress, and assists the elderly.',
                              isSelected: selectedRole == 'caregiver',
                              onTap: () {
                                setState(() {
                                  selectedRole = 'caregiver';
                                });
                              },
                            ),
                            const SizedBox(height: 25),
                            RoleCard(
                              imagePath: 'assets/images/nurse.png',
                              title: 'Nurse',
                              description:
                                  'Provides expert health guidance, oversight, and health assessments.',
                              isSelected: selectedRole == 'nurse',
                              onTap: () {
                                setState(() {
                                  selectedRole = 'nurse';
                                });
                              },
                            ),
                            const SizedBox(height: 25),

                            ElevatedButton(
                              onPressed: selectedRole != null ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => RegisterProfileScreen(
                                      selectedRole: selectedRole!,
                                    ),
                                  ),
                                );
                              } : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: selectedRole != null 
                                  ? const Color(0xFF1D5B78) 
                                  : Colors.grey,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 60,
                                  vertical: 12,
                                ),
                                child: Text(
                                  "SUBMIT",
                                  style: TextStyles.buttontext,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
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

class RoleCard extends StatelessWidget {
  final String imagePath;
  final String title;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const RoleCard({
    required this.imagePath,
    required this.title,
    required this.description,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? const Color(0xFF1D5B78) : const Color(0xFF00588E),
            width: isSelected ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: isSelected 
              ? [
                  const Color(0xFF1D5B78).withValues(alpha: 0.2),
                  const Color(0xFFA5D4DC),
                  const Color.fromARGB(255, 225, 242, 244)
                ]
              : [
                  const Color(0xFFA5D4DC),
                  const Color.fromARGB(255, 225, 242, 244),
                  const Color.fromARGB(255, 241, 245, 246)
                ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                imagePath,
                width: 110, // ✅ Slightly larger
                height: 110,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.check_circle,
                          color: Color(0xFF1D5B78),
                          size: 24,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 13),
                    textAlign: TextAlign.center,
                    softWrap: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
