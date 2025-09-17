import 'package:flutter/material.dart';
import 'houses_grids.dart';

class HousesScreen extends StatelessWidget {
  const HousesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> aliveProfiles = [
      {'name': 'Lola Ada'},
      {'name': 'Lola Andrea'},
      {'name': 'Lola Celia'},
      {'name': 'Lola Lisa'},
      {'name': 'Lola Maria'},
      {'name': 'Lola Rosa'},
    ];
    final List<Map<String, String>> deceasedProfiles = [
      {'name': 'Lolo Juan'},
      {'name': 'Lola Remedios'},
      {'name': 'Lolo Pedro'},
      {'name': 'Lola Teresa'},
    ];

    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/background1.png',
            fit: BoxFit.cover,
          ),
        ),
        _HousesTabScaffold(
          aliveProfiles: aliveProfiles,
          deceasedProfiles: deceasedProfiles,
        ),
      ],
    );
  }
}


class _HousesTabScaffold extends StatefulWidget {
  final List<Map<String, String>> aliveProfiles;
  final List<Map<String, String>> deceasedProfiles;
  const _HousesTabScaffold({
    required this.aliveProfiles,
    required this.deceasedProfiles,
  });

  @override
  State<_HousesTabScaffold> createState() => _HousesTabScaffoldState();
}

class _HousesTabScaffoldState extends State<_HousesTabScaffold> {
  int selectedTab = 0; // 0 = Alive, 1 = Deceased

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: const Color(0x00FFFFFF),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '',
          style: TextStyle(
            color: Color(0xFF00588e),
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF00588e)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.home,
                        size: 50,
                        color: Color(0xFF00588E),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: const [
                          Text(
                            'House of',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00588e),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 2),
                          Text(
                            'St. Sebastian',
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00588e),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Container(
                    decoration: BoxDecoration(
                      color: Color(0xFFD8F4FF), // Light blue background for tab row
                      borderRadius: BorderRadius.circular(32),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() => selectedTab = 0);
                            },
                            child: Container(
                              height: 38,
                              decoration: BoxDecoration(
                                color: selectedTab == 0
                                    ? Color(0xFF2368A2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(32),
                              ),
                              child: Center(
                                child: Text(
                                  'Alive',
                                  style: TextStyle(
                                    color: selectedTab == 0
                                        ? Colors.white
                                        : Color(0xFF2368A2),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    decoration: TextDecoration.none,
                                    decorationColor: Colors.white,
                                    decorationThickness: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() => selectedTab = 1);
                            },
                            child: Container(
                              height: 38,
                              decoration: BoxDecoration(
                                color: selectedTab == 1
                                    ? Color(0xFF2368A2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(32),
                              ),
                              child: Center(
                                child: Text(
                                  'Deceased',
                                  style: TextStyle(
                                    color: selectedTab == 1
                                        ? Colors.white
                                        : Colors.black,
                                    fontWeight: FontWeight.normal,
                                    fontSize: 18,
                                    decoration: TextDecoration.none,
                                    decorationColor: Colors.white,
                                    decorationThickness: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      hintText: 'Search an Elderly...',
                      hintStyle: const TextStyle(
                        color: Colors.grey,
                        fontSize: 15,
                      ),
                      filled: true,
                      fillColor: Color(0xFFD8F4FF),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 9,
                        horizontal: 14,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFF00588E),
                          width: 1.5,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFF00588E),
                          width: 2,
                        ),
                      ),
                    ),
                    style: const TextStyle(fontSize: 18, color: Colors.black),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: const [
                      Text(
                        'Click to Sort',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF00588e),
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.sort, color: Color(0xFF00588e)),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: selectedTab == 0
                    ? AliveProfilesGrid(profiles: widget.aliveProfiles)
                    : DeceasedProfilesGrid(profiles: widget.deceasedProfiles),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
