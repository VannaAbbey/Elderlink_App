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
        };
      }).toList();

      _applyFilters();
    } catch (e) {
      debugPrint('Error fetching elderly: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _applyFilters() {
    var filtered = allElderly;

    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      filtered = filtered.where((e) {
        final fullName = ('${e['elderly_fname']} ${e['elderly_lname']}').toLowerCase();
        final condition = (e['elderly_condition'] ?? '').toString().toLowerCase();
        return fullName.contains(q) || condition.contains(q);
      }).toList();
    }

    if (sortOrder == 'A-Z') {
      filtered.sort((a, b) => ('${a['elderly_fname']} ${a['elderly_lname']}')
          .toLowerCase()
          .compareTo(('${b['elderly_fname']} ${b['elderly_lname']}').toLowerCase()));
    } else {
      filtered.sort((a, b) => ('${b['elderly_fname']} ${b['elderly_lname']}')
          .toLowerCase()
          .compareTo(('${a['elderly_fname']} ${a['elderly_lname']}').toLowerCase()));
    }

    setState(() => filteredElderly = List<Map<String, dynamic>>.from(filtered));
  }

  @override
  Widget build(BuildContext context) {
    final houseIndex = _getHouseIndex(widget.houseName);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF00588E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Elderly List'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(houseImages[houseIndex], height: 70, width: 70, fit: BoxFit.contain),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      const Text('House of', style: TextStyle(fontSize: 16, color: Color(0xFF00588E), fontWeight: FontWeight.bold)),
                      Text(widget.houseName, style: const TextStyle(fontSize: 20, color: Color(0xFF00588E), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(child: _buildToggleButton('Alive')),
                  const SizedBox(width: 8),
                  Expanded(child: _buildToggleButton('Deceased')),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        hintText: 'Search...',
                        filled: true,
                        fillColor: const Color(0xFFD8F4FF),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                      onChanged: (v) {
                        searchQuery = v;
                        _applyFilters();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: sortOrder,
                    items: const [DropdownMenuItem(value: 'A-Z', child: Text('A-Z')), DropdownMenuItem(value: 'Z-A', child: Text('Z-A'))],
                    onChanged: (v) {
                      sortOrder = v ?? 'A-Z';
                      _applyFilters();
                    },
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredElderly.isEmpty
                        ? const Center(child: Text('No elderly found'))
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.72,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                            ),
                            itemCount: filteredElderly.length,
                            itemBuilder: (context, i) {
                              final e = filteredElderly[i];
                              final fullName = '${e['elderly_fname'] ?? ''} ${e['elderly_lname'] ?? ''}';
                              final imageUrl = (e['elderly_profilePic'] ?? '').toString();
                              final status = (e['elderly_status'] ?? selectedStatus).toString().toLowerCase();
                              final isDeceased = status == 'deceased';

                              return GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ElderlyProfile(elderlyId: e['elderly_id']))),
                                child: Card(
                                  color: isDeceased ? Colors.grey.shade400 : const Color(0xFFBFEAF2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 2,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(height: 8),
                                      Container(
                                        width: 88,
                                        height: 88,
                                        decoration: const BoxDecoration(shape: BoxShape.circle),
                                        child: ClipOval(
                                          child: imageUrl.isNotEmpty
                                              ? (isDeceased
                                                  ? ColorFiltered(
                                                      colorFilter: const ColorFilter.matrix(<double>[
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
                                                        1,
                                                        0,
                                                      ]),
                                                      child: Image.network(imageUrl, fit: BoxFit.cover),
                                                    )
                                                  : Image.network(imageUrl, fit: BoxFit.cover))
                                              : Image.asset('assets/images/people_icon.png', fit: BoxFit.cover),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        child: Text(fullName, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(height: 6),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        child: Text((e['elderly_condition'] ?? '').toString(), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                      ),
                                    ],
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
    );
  }

  Widget _buildToggleButton(String status) {
    final selected = selectedStatus.toLowerCase() == status.toLowerCase();
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? const Color(0xFF00588E) : Colors.white,
        foregroundColor: selected ? Colors.white : const Color(0xFF00588E),
        side: const BorderSide(color: Color(0xFF00588E)),
      ),
      onPressed: () {
        setState(() {
          selectedStatus = status;
          fetchElderly();
        });
      },
      child: Text(status),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'elderly_profile.dart';

/// Clean, single-file implementation for the nurse elderly list.
/// - 2-column portrait GridView
/// - Circular avatar (88x88) with breathing padding
/// - Living card color: const Color(0xFFBFEAF2)
/// - Deceased: desaturated/grayscale avatar and gray card
/// - Truncated text to avoid overflow

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
        };
      }).toList();

      _applyFilters();
    } catch (e) {
      debugPrint('Error fetching elderly: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _applyFilters() {
    var filtered = allElderly;

    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      filtered = filtered.where((e) {
        final fullName = ('${e['elderly_fname']} ${e['elderly_lname']}').toLowerCase();
        final condition = (e['elderly_condition'] ?? '').toString().toLowerCase();
        return fullName.contains(q) || condition.contains(q);
      }).toList();
    }

    if (sortOrder == 'A-Z') {
      filtered.sort((a, b) => ('${a['elderly_fname']} ${a['elderly_lname']}')
          .toLowerCase()
          .compareTo(('${b['elderly_fname']} ${b['elderly_lname']}').toLowerCase()));
    } else {
      filtered.sort((a, b) => ('${b['elderly_fname']} ${b['elderly_lname']}')
          .toLowerCase()
          .compareTo(('${a['elderly_fname']} ${a['elderly_lname']}').toLowerCase()));
    }

    setState(() => filteredElderly = List<Map<String, dynamic>>.from(filtered));
  }

  @override
  Widget build(BuildContext context) {
    final houseIndex = _getHouseIndex(widget.houseName);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF00588E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Elderly List'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(houseImages[houseIndex], height: 70, width: 70, fit: BoxFit.contain),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      const Text('House of', style: TextStyle(fontSize: 16, color: Color(0xFF00588E), fontWeight: FontWeight.bold)),
                      Text(widget.houseName, style: const TextStyle(fontSize: 20, color: Color(0xFF00588E), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(child: _buildToggleButton('Alive')),
                  const SizedBox(width: 8),
                  Expanded(child: _buildToggleButton('Deceased')),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        hintText: 'Search...',
                        filled: true,
                        fillColor: const Color(0xFFD8F4FF),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                      onChanged: (v) {
                        searchQuery = v;
                        _applyFilters();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: sortOrder,
                    items: const [DropdownMenuItem(value: 'A-Z', child: Text('A-Z')), DropdownMenuItem(value: 'Z-A', child: Text('Z-A'))],
                    onChanged: (v) {
                      sortOrder = v ?? 'A-Z';
                      _applyFilters();
                    },
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredElderly.isEmpty
                        ? const Center(child: Text('No elderly found'))
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.72,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                            ),
                            itemCount: filteredElderly.length,
                            itemBuilder: (context, i) {
                              final e = filteredElderly[i];
                              final fullName = '${e['elderly_fname'] ?? ''} ${e['elderly_lname'] ?? ''}';
                              final imageUrl = (e['elderly_profilePic'] ?? '').toString();
                              final status = (e['elderly_status'] ?? selectedStatus).toString().toLowerCase();
                              final isDeceased = status == 'deceased';

                              return GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ElderlyProfile(elderlyId: e['elderly_id']))),
                                child: Card(
                                  color: isDeceased ? Colors.grey.shade400 : const Color(0xFFBFEAF2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 2,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(height: 8),
                                      Container(
                                        width: 88,
                                        height: 88,
                                        decoration: const BoxDecoration(shape: BoxShape.circle),
                                        child: ClipOval(
                                          child: imageUrl.isNotEmpty
                                              ? (isDeceased
                                                  ? ColorFiltered(
                                                      colorFilter: const ColorFilter.matrix(<double>[
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
                                                        1,
                                                        0,
                                                      ]),
                                                      child: Image.network(imageUrl, fit: BoxFit.cover),
                                                    )
                                                  : Image.network(imageUrl, fit: BoxFit.cover))
                                              : Image.asset('assets/images/people_icon.png', fit: BoxFit.cover),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        child: Text(fullName, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(height: 6),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        child: Text((e['elderly_condition'] ?? '').toString(), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                      ),
                                    ],
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
    );
  }

  Widget _buildToggleButton(String status) {
    final selected = selectedStatus.toLowerCase() == status.toLowerCase();
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? const Color(0xFF00588E) : Colors.white,
        foregroundColor: selected ? Colors.white : const Color(0xFF00588E),
        side: const BorderSide(color: Color(0xFF00588E)),
      ),
      onPressed: () {
        setState(() {
          selectedStatus = status;
          fetchElderly();
        });
      },
      child: Text(status),
    );
  }
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
        };
      }).toList();

      _applyFilters();
    } catch (e) {
      debugPrint('Error fetching elderly: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _applyFilters() {
    var filtered = allElderly;

    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      filtered = filtered.where((e) {
        final fullName = ('${e['elderly_fname']} ${e['elderly_lname']}').toLowerCase();
        final condition = (e['elderly_condition'] ?? '').toString().toLowerCase();
        return fullName.contains(q) || condition.contains(q);
      }).toList();
    }

    if (sortOrder == 'A-Z') {
      filtered.sort((a, b) => ('${a['elderly_fname']} ${a['elderly_lname']}')
          .toLowerCase()
          .compareTo(('${b['elderly_fname']} ${b['elderly_lname']}').toLowerCase()));
    } else {
      filtered.sort((a, b) => ('${b['elderly_fname']} ${b['elderly_lname']}')
          .toLowerCase()
          .compareTo(('${a['elderly_fname']} ${a['elderly_lname']}').toLowerCase()));
    }

    setState(() => filteredElderly = List<Map<String, dynamic>>.from(filtered));
  }

  @override
  Widget build(BuildContext context) {
    final houseIndex = _getHouseIndex(widget.houseName);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF00588E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Elderly List'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(houseImages[houseIndex], height: 70, width: 70, fit: BoxFit.contain),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      const Text('House of', style: TextStyle(fontSize: 16, color: Color(0xFF00588E), fontWeight: FontWeight.bold)),
                      Text(widget.houseName, style: const TextStyle(fontSize: 20, color: Color(0xFF00588E), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(child: _buildToggleButton('Alive')),
                  const SizedBox(width: 8),
                  Expanded(child: _buildToggleButton('Deceased')),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        hintText: 'Search...',
                        filled: true,
                        fillColor: const Color(0xFFD8F4FF),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                      onChanged: (v) {
                        searchQuery = v;
                        _applyFilters();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: sortOrder,
                    items: const [DropdownMenuItem(value: 'A-Z', child: Text('A-Z')), DropdownMenuItem(value: 'Z-A', child: Text('Z-A'))],
                    onChanged: (v) {
                      sortOrder = v ?? 'A-Z';
                      _applyFilters();
                    },
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredElderly.isEmpty
                        ? const Center(child: Text('No elderly found'))
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.72,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                            ),
                            itemCount: filteredElderly.length,
                            itemBuilder: (context, i) {
                              final e = filteredElderly[i];
                              final fullName = '${e['elderly_fname'] ?? ''} ${e['elderly_lname'] ?? ''}';
                              final imageUrl = (e['elderly_profilePic'] ?? '').toString();
                              final status = (e['elderly_status'] ?? selectedStatus).toString().toLowerCase();
                              final isDeceased = status == 'deceased';

                              return GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ElderlyProfile(elderlyId: e['elderly_id']))),
                                child: Card(
                                  color: isDeceased ? Colors.grey.shade400 : const Color(0xFFBFEAF2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 2,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(height: 8),
                                      Container(
                                        width: 88,
                                        height: 88,
                                        decoration: const BoxDecoration(shape: BoxShape.circle),
                                        child: ClipOval(
                                          child: imageUrl.isNotEmpty
                                              ? (isDeceased
                                                  ? ColorFiltered(
                                                      colorFilter: const ColorFilter.matrix(<double>[
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
                                                        1,
                                                        0,
                                                      ]),
                                                      child: Image.network(imageUrl, fit: BoxFit.cover),
                                                    )
                                                  : Image.network(imageUrl, fit: BoxFit.cover))
                                              : Image.asset('assets/images/people_icon.png', fit: BoxFit.cover),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        child: Text(fullName, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(height: 6),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        child: Text((e['elderly_condition'] ?? '').toString(), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                      ),
                                    ],
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
    );
  }

  Widget _buildToggleButton(String status) {
    final selected = selectedStatus.toLowerCase() == status.toLowerCase();
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? const Color(0xFF00588E) : Colors.white,
        foregroundColor: selected ? Colors.white : const Color(0xFF00588E),
        side: const BorderSide(color: Color(0xFF00588E)),
      ),
      onPressed: () {
        setState(() {
          selectedStatus = status;
          fetchElderly();
        });
      },
      child: Text(status),
    );
  }
}
        ),
        onPressed: () {
          setState(() {
            selectedStatus = status;
            fetchElderly();
          });
        },
        child: Text(status),
      );
    }
  }
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
                                                                          1,
                                                                          0,
                                                                        ]),
                                                                        child: Image.network(imageUrl, fit = BoxFit.cover),
                                                                      )
                                                                    : Image.network(imageUrl, fit = BoxFit.cover))
                                                                : Image.asset('assets/images/people_icon.png', fit = BoxFit.cover),
                                                          ),
                                                        ),
                                                        SizedBox(height = 8),
                                                        Padding(
                                                          padding = const EdgeInsets.symmetric(horizontal: 8.0),
                                                          child = Text(fullName, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                                                        ),
                                                        SizedBox(height = 6),
                                                        Padding(
                                                          padding = const EdgeInsets.symmetric(horizontal: 8.0),
                                                          child = Text((e['elderly_condition'] ?? '').toString(), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                                        ),
                                                      ],
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
                      );
                    }

                    Widget _buildToggleButton(String status) {
                      final selected = selectedStatus.toLowerCase() == status.toLowerCase();
                      return ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selected ? const Color(0xFF00588E) : Colors.white,
                          foregroundColor: selected ? Colors.white : const Color(0xFF00588E),
                          side: const BorderSide(color: Color(0xFF00588E)),
                        ),
                        onPressed: () {
                          setState(() {
                            selectedStatus = status;
                            fetchElderly();
                          });
                        },
                        child: Text(status),
                      );
                    }
                  }
                  child: Text(status),
