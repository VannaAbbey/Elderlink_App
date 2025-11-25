import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'elderly_profile.dart';
import 'infirmary_transfer_selection.dart';

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
          'elderly_causeOfDeath': data['elderly_causeOfDeath'] ?? '',
          'elderly_birthday': data['elderly_bday'] ?? data['birthdate'],
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
        final fullName = '${e['elderly_fname']} ${e['elderly_lname']}'
            .toLowerCase();
        final condition = (e['elderly_condition'] ?? '').toLowerCase();
        final diet = (e['elderly_dietNotes'] ?? '').toLowerCase();
        final mobility = (e['elderly_mobilityStatus'] ?? '').toLowerCase();
        final sex = (e['elderly_sex'] ?? '').toLowerCase();
        final causeOfDeath = (e['elderly_causeOfDeath'] ?? '').toLowerCase();

        return fullName.contains(query) ||
            condition.contains(query) ||
            diet.contains(query) ||
            mobility.contains(query) ||
            sex.contains(query) ||
            causeOfDeath.contains(query);
      }).toList();
    }

    if (sortOrder == 'A-Z') {
      filtered.sort(
        (a, b) => ('${a['elderly_fname']} ${a['elderly_lname']}').compareTo(
          '${b['elderly_fname']} ${b['elderly_lname']}',
        ),
      );
    } else {
      filtered.sort(
        (a, b) => ('${b['elderly_fname']} ${b['elderly_lname']}').compareTo(
          '${a['elderly_fname']} ${a['elderly_lname']}',
        ),
      );
    }

    setState(() {
      filteredElderly = filtered;
    });
  }

  bool _isBirthdayToday(dynamic birthday) {
    if (birthday == null) return false;

    DateTime birthDate;
    if (birthday is Timestamp) {
      birthDate = birthday.toDate();
    } else if (birthday is DateTime) {
      birthDate = birthday;
    } else {
      return false;
    }

    final now = DateTime.now();
    return birthDate.month == now.month && birthDate.day == now.day;
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
                      Image.asset(
                        houseImages[_getHouseIndex(widget.houseName)],
                        height: 70,
                        width: 70,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            "House of",
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF00588E),
                              fontWeight: FontWeight.bold,
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
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Status segmented control and Infirmary button
                  Row(
                    children: [
                      // Segmented control for Alive/Deceased
                      Expanded(
                        flex: 2,
                        child: Container(
                          height: 45,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD8F4FF),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Row(
                            children: [
                              _buildSegmentedButton("Alive", isLeft: true),
                              _buildSegmentedButton("Deceased", isLeft: false),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Infirmary Transfer button
                      Expanded(
                        flex: 1,
                        child: GestureDetector(
                          onTap: selectedStatus == 'Alive'
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          InfirmaryTransferSelectionScreen(
                                            houseId: widget.houseId,
                                            houseName: widget.houseName,
                                          ),
                                    ),
                                  );
                                }
                              : null,
                          child: Container(
                            height: 45,
                            decoration: BoxDecoration(
                              color: selectedStatus == 'Alive'
                                  ? const Color(0xFF00588E)
                                  : Colors.grey[300],
                              borderRadius: BorderRadius.circular(22.5),
                              boxShadow: selectedStatus == 'Alive'
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.local_hospital,
                                  color: selectedStatus == 'Alive'
                                      ? Colors.white
                                      : Colors.grey[600],
                                  size: 18,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "Infirmary",
                                  style: TextStyle(
                                    fontFamily: "Poppins",
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: selectedStatus == 'Alive'
                                        ? Colors.white
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

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
                          hintText:
                              "Search by Name, Condition, Mobility, or Cause of Death...",
                          hintStyle: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
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

                  Align(
                    alignment: Alignment.centerRight,
                    child: DropdownButton<String>(
                      value: sortOrder,
                      underline: const SizedBox(),
                      icon: const Icon(
                        Icons.arrow_upward,
                        color: Color(0xFF00588E),
                        size: 20,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'A-Z',
                          child: Text(
                            "Sorted A-Z",
                            style: TextStyle(color: Color(0xFF00588E)),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Z-A',
                          child: Text(
                            "Sorted Z-A",
                            style: TextStyle(color: Color(0xFF00588E)),
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

                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : filteredElderly.isEmpty
                        ? const Center(child: Text('No elderly found'))
                        : GridView.builder(
                            padding: EdgeInsets.zero,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  childAspectRatio: 0.75,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                            itemCount: filteredElderly.length,
                            itemBuilder: (context, index) {
                              final elderly = filteredElderly[index];
                              final imageUrl =
                                  (elderly['elderly_profilePic'] ?? '')
                                      .toString();
                              final fullName =
                                  '${elderly['elderly_fname']} ${elderly['elderly_lname']}';
                              final isBirthday = _isBirthdayToday(
                                elderly['elderly_birthday'],
                              );

                              return GestureDetector(
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
                                child: Stack(
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      height: double.infinity,
                                      decoration: BoxDecoration(
                                        color: selectedStatus == "Deceased"
                                            ? Colors.grey[300]
                                            : const Color(0xFFBFEAF2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.max,
                                          children: [
                                            const SizedBox(height: 15),
                                            ClipOval(
                                              child: ColorFiltered(
                                                colorFilter:
                                                    selectedStatus == "Deceased"
                                                    ? const ColorFilter.matrix([
                                                        0.2126,
                                                        0.7152,
                                                        0.0722,
                                                        0,
                                                        0,
                                                        0.2126,
                                                        0.7152,
                                                        0.0722,
                                                        0,
                                                        0,
                                                        0.2126,
                                                        0.7152,
                                                        0.0722,
                                                        0,
                                                        0,
                                                        0,
                                                        0,
                                                        0,
                                                        1,
                                                        0,
                                                      ])
                                                    : const ColorFilter.mode(
                                                        Colors.transparent,
                                                        BlendMode.multiply,
                                                      ),
                                                child: Image(
                                                  image: imageUrl.isNotEmpty
                                                      ? NetworkImage(imageUrl)
                                                      : const AssetImage(
                                                              'assets/images/people_icon.png',
                                                            )
                                                            as ImageProvider,
                                                  height: 100,
                                                  width: 100,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 20),
                                            Text(
                                              fullName,
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              selectedStatus == "Deceased"
                                                  ? (elderly['elderly_causeOfDeath'] ??
                                                            '')
                                                        .toString()
                                                  : (elderly['elderly_condition'] ??
                                                            '')
                                                        .toString(),
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (isBirthday)
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.pink,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.2,
                                                ),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.cake,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                  ],
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

  Widget _buildSegmentedButton(String label, {required bool isLeft}) {
    final bool isSelected = selectedStatus == label;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedStatus = label;
          });
          fetchElderly();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.all(4), // spacing inside outer capsule
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00588E) : Colors.transparent,
            borderRadius: BorderRadius.circular(
              30,
            ), // ✅ fully rounded highlight
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: "Poppins",
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
