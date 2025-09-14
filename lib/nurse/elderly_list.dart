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

  @override
  void initState() {
    super.initState();
    fetchElderly();
  }

  Future<void> fetchElderly() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('elderly')
          .where('house_id', isEqualTo: widget.houseId)
          .where('elderly_status', isEqualTo: 'Alive')
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
          'elderly_mobilityStatus': data['elderly_mobilityStatus'] ?? 'Independent',
          'elderly_sex': data['elderly_sex'] ?? 'Female',
          'elderly_bday': data['elderly_bday'] ?? '',
          'elderly_age': data['elderly_age'] ?? '',
          'house_id': data['house_id'] ?? '',
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
      filtered = filtered
          .where((e) =>
              ('${e['elderly_fname']} ${e['elderly_lname']}')
                  .toLowerCase()
                  .contains(searchQuery.toLowerCase()))
          .toList();
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
    String logoImage =
        'assets/images/${widget.houseName.replaceAll('St. ', '').trim()}.png';

    return Scaffold(
      body: Stack(
        children: [
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
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Color(0xFF00588E),
                        size: 30,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(logoImage, height: 50),
                      const SizedBox(width: 10),
                      Text(
                        'House of ${widget.houseName}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Color(0xFF00588E),
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search elderly name...',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (value) {
                      searchQuery = value;
                      filterElderly();
                    },
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DropdownButton<String>(
                      value: sortOrder,
                      items: ['A-Z', 'Z-A']
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          sortOrder = value!;
                          filterElderly();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
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
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color.fromARGB(
                                        255,
                                        191,
                                        234,
                                        242,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ListTile(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ElderlyProfile(
                                                elderlyId: elderly['elderly_id']),
                                          ),
                                        );
                                      },
                                      leading: Container(
                                        width: 50,
                                        height: 50,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color(0xFF00588E)
                                        ),
                                        child: ClipOval(
                                          child: imageUrl.isNotEmpty
                                              ? Image.network(
                                                  imageUrl,
                                                  fit: BoxFit.cover,
                                                )
                                              : Image.asset(
                                                  'assets/images/profile.png',
                                                  fit: BoxFit.cover,
                                                ),
                                        ),
                                      ),
                                      title: Text(
                                        '${elderly['elderly_fname']} ${elderly['elderly_lname']}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
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
}
