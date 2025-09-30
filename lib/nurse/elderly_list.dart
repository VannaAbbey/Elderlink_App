import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'elderly_profile.dart';

class ElderlyListScreen extends StatefulWidget {
  final String houseId;
  final String houseName;

  const ElderlyListScreen({
    super.key,
    required this.houseId,
    required this.houseName,
  });

  @override
  State<ElderlyListScreen> createState() => _ElderlyListScreenState();
}

class _ElderlyListScreenState extends State<ElderlyListScreen> {
  List<Map<String, dynamic>> allElderly = [];
  List<Map<String, dynamic>> filteredElderly = [];
  String searchQuery = '';
  String sortOrder = 'A-Z';
  bool isLoading = true;
  String selectedStatus = 'Alive';

  final List<String> houseImages = [
    'assets/images/Sebastian_Logo.png',
    'assets/images/Emmanuel_Logo.png',
    'assets/images/Charbell_Logo.png',
    'assets/images/Rose_Logo.png',
    'assets/images/Gabriel_Logo.png',
  ];

  int _getHouseIndex(String houseName) {
    switch (houseName) {
      case "St. Sebastian":
        return 0;
      case "St. Emmanuel":
        return 1;
      case "St. Charbell":
        return 2;
      case "St. Rose of Lima":
        return 3;
      case "St. Gabriel":
        return 4;
      default:
        return 0;
    }
  }

  @override
  void initState() {
    super.initState();
    fetchElderly();
  }

  Future<void> fetchElderly() async {
  setState(() => isLoading = true);
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('elderly')
        .where('house_id', isEqualTo: widget.houseId)
        .where('elderly_status', isEqualTo: selectedStatus)
        .get();

    allElderly = snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'elderly_id': doc.id,
        'elderly_fname': data['elderly_fname'] ?? '',
        'elderly_lname': data['elderly_lname'] ?? '',
        'elderly_profilePic': data['elderly_profilePic'] ?? '',
        'elderly_status': data['elderly_status'] ?? 'Alive',
        'elderly_condition': data['elderly_condition'] ?? '',
        'elderly_dietNotes': data['elderly_dietNotes'] ?? '',
        'elderly_mobilityStatus': data['elderly_mobilityStatus'] ?? '',
        'elderly_sex': data['elderly_sex'] ?? '',
      };
    }).toList();

    filterElderly();
  } catch (e) {
    print('Error fetching elderly: $e');
  } finally {
    setState(() => isLoading = false);
  }
}

void filterElderly() {
  List<Map<String, dynamic>> filtered = allElderly;

  if (searchQuery.isNotEmpty) {
    final query = searchQuery.toLowerCase();

    filtered = filtered.where((e) {
      final fullName = '${e['elderly_fname']} ${e['elderly_lname']}'.toLowerCase();
      final condition = (e['elderly_condition'] ?? '').toLowerCase();
      final diet = (e['elderly_dietNotes'] ?? '').toLowerCase();
      final mobility = (e['elderly_mobilityStatus'] ?? '').toLowerCase();
      final sex = (e['elderly_sex'] ?? '').toLowerCase();

      return fullName.contains(query) ||
          condition.contains(query) ||
          diet.contains(query) ||
          mobility.contains(query) ||
          sex.contains(query);
    }).toList();
  }

  if (sortOrder == 'A-Z') {
    filtered.sort((a, b) =>
        ('${a['elderly_fname']} ${a['elderly_lname']}')
            .compareTo('${b['elderly_fname']} ${b['elderly_lname']}'));
  } else {
    filtered.sort((a, b) =>
        ('${b['elderly_fname']} ${b['elderly_lname']}')
            .compareTo('${a['elderly_fname']} ${a['elderly_lname']}'));
  }

  setState(() {
    filteredElderly = filtered;
  });
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ✅ Background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/background1.png',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // 🔙 Back button
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Color(0xFF00588E),
                        size: 28,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // House Image (left)
                      Image.asset(
                        houseImages[_getHouseIndex(widget.houseName)],
                        height: 70,
                        width: 70,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 12),

                      // Texts (right, centered)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment
                            .center, // ✅ center texts horizontally
                        children: [
                          Text(
                            "House of",
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFF00588E), // ✅ Blue color
                              fontWeight: FontWeight.bold, // ✅ Bold
                              fontFamily: "Poppins",
                            ),
                          ),
                          Text(
                            widget.houseName,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Color(0xFF00588E),
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center, // ✅ Center align text
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 🔘 Toggle Buttons (Alive / Deceased)
                  Row(
                    children: [
                      Expanded(child: _buildToggleButton("Alive")),
                      const SizedBox(width: 10),
                      Expanded(child: _buildToggleButton("Deceased")),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 🔎 Search bar
                  Align(
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.85,
                      child: TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.grey,
                          ),
                          hintText: "Search an Elderly...",
                          hintStyle: const TextStyle(
                            color: Colors.grey,
                            fontSize: 15,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFD8F4FF),
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
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.black,
                        ),
                        onChanged: (value) {
                          searchQuery = value;
                          filterElderly();
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Sort dropdown
                  Align(
                    alignment: Alignment.centerRight,
                    child: DropdownButton<String>(
                      value: sortOrder,
                      underline: const SizedBox(), // alisin underline
                      icon: const Icon(
                        Icons.arrow_drop_down,
                        color: Color(0xFF00588E),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'A-Z',
                          child: Text(
                            "Sort A-Z",
                            style: TextStyle(
                              color: Color(0xFF00588E),
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Z-A',
                          child: Text(
                            "Sort Z-A",
                            style: TextStyle(
                              color: Color(0xFF00588E),
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          sortOrder = value!;
                          filterElderly();
                        });
                      },
                    ),
                  ),

                  const SizedBox(height: 10),

                  // 👵 Elderly List
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : filteredElderly.isEmpty
                        ? const Center(child: Text('No elderly found'))
                        : ListView.builder(
                            itemCount: filteredElderly.length,
                            itemBuilder: (context, index) {
                              final elderly = filteredElderly[index];
                              final imageUrl = elderly['elderly_profilePic'];
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFBFEAF2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ElderlyProfile(
                                          elderlyId: elderly['elderly_id'],
                                        ),
                                      ),
                                    );
                                  },
                                  leading: CircleAvatar(
                                    radius: 25,
                                    backgroundColor: const Color(0xFF00588E),
                                    backgroundImage: imageUrl.isNotEmpty
                                        ? NetworkImage(imageUrl)
                                        : const AssetImage(
                                                'assets/images/people_icon.png',
                                              )
                                              as ImageProvider,
                                  ),
                                  title: Text(
                                    '${elderly['elderly_fname']} ${elderly['elderly_lname']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Custom Toggle Button
  Widget _buildToggleButton(String label) {
    final bool isSelected = selectedStatus == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedStatus = label;
        });
        fetchElderly(); // refresh list
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00588E) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
