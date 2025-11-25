import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'infirmary_transfer_confirmation.dart';

class InfirmaryTransferSelectionScreen extends StatefulWidget {
  final String houseId;
  final String houseName;

  const InfirmaryTransferSelectionScreen({
    super.key,
    required this.houseId,
    required this.houseName,
  });

  @override
  State<InfirmaryTransferSelectionScreen> createState() =>
      _InfirmaryTransferSelectionScreenState();
}

class _InfirmaryTransferSelectionScreenState
    extends State<InfirmaryTransferSelectionScreen> {
  List<Map<String, dynamic>> allElderly = [];
  List<Map<String, dynamic>> filteredElderly = [];
  Set<String> selectedElderlyIds = <String>{};
  String searchQuery = '';
  String sortOrder = 'A-Z';
  bool isLoading = true;

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
      // Only fetch alive elderly for infirmary transfer
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
          'elderly_condition': data['elderly_condition'] ?? '',
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
        final fullName = '${e['elderly_fname']} ${e['elderly_lname']}'
            .toLowerCase();
        return fullName.contains(query);
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

  void toggleElderlySelection(String elderlyId) {
    setState(() {
      if (selectedElderlyIds.contains(elderlyId)) {
        selectedElderlyIds.remove(elderlyId);
      } else {
        selectedElderlyIds.add(elderlyId);
      }
    });
  }

  void proceedToConfirmation() {
    if (selectedElderlyIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one elderly to transfer'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Get selected elderly details
    final selectedElderly = allElderly
        .where((elderly) => selectedElderlyIds.contains(elderly['elderly_id']))
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InfirmaryTransferConfirmationScreen(
          houseId: widget.houseId,
          houseName: widget.houseName,
          selectedElderly: selectedElderly,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background image
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
                  // Back button
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

                  // Header with house info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.local_hospital,
                        color: Color(0xFF00588E),
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        children: [
                          const Text(
                            "Infirmary Transfer",
                            style: TextStyle(
                              fontSize: 20,
                              color: Color(0xFF00588E),
                              fontWeight: FontWeight.bold,
                              fontFamily: "Poppins",
                            ),
                          ),
                          Text(
                            "Select elderly from ${widget.houseName}",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF00588E),
                              fontFamily: "Poppins",
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Search bar
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      hintText: "Search elderly by name...",
                      hintStyle: const TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFD8F4FF),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
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
                    onChanged: (value) {
                      searchQuery = value;
                      filterElderly();
                    },
                  ),

                  const SizedBox(height: 10),

                  // Sort dropdown and selection count
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Selection count
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: selectedElderlyIds.isNotEmpty
                              ? Color(0xFF00588E)
                              : Colors.grey,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "${selectedElderlyIds.length} selected",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      // Sort dropdown
                      DropdownButton<String>(
                        value: sortOrder,
                        underline: const SizedBox(),
                        icon: const Icon(Icons.sort, color: Color(0xFF00588E)),
                        items: const [
                          DropdownMenuItem(
                            value: 'A-Z',
                            child: Text(
                              "A-Z",
                              style: TextStyle(color: Color(0xFF00588E)),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'Z-A',
                            child: Text(
                              "Z-A",
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
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Elderly list
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : filteredElderly.isEmpty
                        ? const Center(child: Text('No elderly found'))
                        : ListView.builder(
                            itemCount: filteredElderly.length,
                            itemBuilder: (context, index) {
                              final elderly = filteredElderly[index];
                              final elderlyId = elderly['elderly_id'];
                              final isSelected = selectedElderlyIds.contains(
                                elderlyId,
                              );
                              final imageUrl =
                                  (elderly['elderly_profilePic'] ?? '')
                                      .toString();
                              final fullName =
                                  '${elderly['elderly_fname']} ${elderly['elderly_lname']}';

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                elevation: 2,
                                child: ListTile(
                                  leading: Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: 25,
                                        backgroundImage: imageUrl.isNotEmpty
                                            ? NetworkImage(imageUrl)
                                            : const AssetImage(
                                                    'assets/images/people_icon.png',
                                                  )
                                                  as ImageProvider,
                                      ),
                                      if (isSelected)
                                        Positioned(
                                          right: 0,
                                          top: 0,
                                          child: Container(
                                            width: 20,
                                            height: 20,
                                            decoration: BoxDecoration(
                                              color: Color(0xFF00588E),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 2,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.check,
                                              color: Colors.white,
                                              size: 12,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  title: Text(
                                    fullName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (elderly['elderly_condition']
                                              ?.isNotEmpty ==
                                          true)
                                        Text(
                                          'Condition: ${elderly['elderly_condition']}',
                                        ),
                                      if (elderly['elderly_mobilityStatus']
                                              ?.isNotEmpty ==
                                          true)
                                        Text(
                                          'Mobility: ${elderly['elderly_mobilityStatus']}',
                                        ),
                                    ],
                                  ),
                                  trailing: Checkbox(
                                    value: isSelected,
                                    activeColor: Color(0xFF00588E),
                                    onChanged: (value) {
                                      toggleElderlySelection(elderlyId);
                                    },
                                  ),
                                  onTap: () =>
                                      toggleElderlySelection(elderlyId),
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
      // Floating action button for confirmation
      floatingActionButton: selectedElderlyIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: proceedToConfirmation,
              backgroundColor: Color(0xFF00588E),
              icon: const Icon(Icons.arrow_forward, color: Colors.white),
              label: const Text(
                "Continue",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }
}
