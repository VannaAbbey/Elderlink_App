import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_profile.dart';
import '../auth/login.dart';

class MedicationManagementScreen extends StatefulWidget {
  const MedicationManagementScreen({super.key});

  @override
  State<MedicationManagementScreen> createState() =>
      _MedicationManagementScreenState();
}

class _MedicationManagementScreenState
    extends State<MedicationManagementScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _search = '';
  String? nurseName;


  bool isSidebarOpen = false;

  @override
void initState() {
  super.initState();
  _loadNurseData();
}

Future<void> _loadNurseData() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        setState(() {
          nurseName = doc['user_fname'] ?? '';
        });
      } else {
        setState(() {
          nurseName = null;
        });
      }
    }
  } catch (e) {
    print("❌ Error loading nurse data: $e");
    setState(() => nurseName = null);
  }
}

  void toggleSidebar() {
    setState(() => isSidebarOpen = !isSidebarOpen);
  }

  final Map<String, String> houseDescriptions = const {
    'St. Sebastian': 'Females with Psychological Needs',
    'St. Emmanuel': 'Females that are Bedridden',
    'St. Charbell': 'Males that are Bedridden',
    'St. Rose of Lima': 'Females that are Abled',
    'St. Gabriel': 'Males that are Abled',
  };

  Future<List<Map<String, dynamic>>> fetchHouses() async {
    final snap = await _firestore.collection('house').get();
    final list = snap.docs.map((d) => d.data()).toList();
    // sort by house_id for stable order
    list.sort(
      (a, b) => (a['house_id'] ?? '').toString().compareTo(
        (b['house_id'] ?? '').toString(),
      ),
    );
    return list;
  }

  Future<void> _handleLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        ), // Replace with your login screen
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    }
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

          // Main content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  // Header
                  Row(
                    children: [
                      GestureDetector(
                        onTap: toggleSidebar, // Open/close sidebar
                        child: const Icon(
                          Icons.menu,
                          size: 30,
                          color: Color(0xFF00588E),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Medication Management',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF00588E),
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.notifications,
                        size: 30,
                        color: Color(0xFF00588E),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Search bar
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      hintText: "Search house...",
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 15),
                      filled: true,
                      fillColor: const Color(0xFFD8F4FF),
                      contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
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
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 24),

                  // Elderly Houses header
                  Row(
                    children: const [
                      Icon(Icons.home, color: Color(0xFF00588E), size: 45),
                      SizedBox(width: 8),
                      Text(
                        'Elderly Houses',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Houses list
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: fetchHouses(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: 24),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      if (!snap.hasData || snap.data!.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text('No houses available.'),
                        );
                      }

                      final houses = snap.data!.where((h) {
                        final name = (h['house_name'] ?? '')
                            .toString()
                            .toLowerCase();
                        return _search.isEmpty || name.contains(_search);
                      }).toList();

                      if (houses.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text('No matching houses.'),
                        );
                      }

                      return Column(
                        children: houses.map((house) {
                          final houseName = (house['house_name'] ?? '')
                              .toString();
                          final imageName = houseName
                              .replaceAll('St. ', '')
                              .replaceAll(' ', '');
                          final imagePath = 'assets/images/${imageName}_Logo.png';
                          final desc =
                              houseDescriptions[houseName] ??
                              'Elderly Care Facility';

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MedicationElderlyListScreen(
                                    houseId: (house['house_id'] ?? '')
                                        .toString(),
                                    houseName: houseName,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: const Color(0XFFE7EFFF),
                              ),
                              child: Row(
  children: [
    Image.asset(
      imagePath,
      width: 80,
      height: 80,
      errorBuilder: (context, error, stackTrace) {
        return Image.asset(
          'assets/images/Rose_Logo.png',
          width: 80,
          height: 80,
        );
      },
    ),
    const SizedBox(width: 15),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            houseName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00588E),
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    ),
  ],
),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Sidebar overlay
          if (isSidebarOpen) _buildSidebarOverlay(),
        ],
      ),
    );
  }

  // Sidebar item helper
  Widget _sidebarItem(IconData icon, String title, {VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF00588e)),
      title: Text(title),
      onTap: onTap ?? () {},
    );
  }

  // Sidebar overlay
  Widget _buildSidebarOverlay() {
    return Stack(
      children: [
        GestureDetector(
          onTap: toggleSidebar,
          child: Container(color: Colors.black54),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          child: Material(
            elevation: 5,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(10),
              bottomRight: Radius.circular(10),
            ),
            child: Container(
              width: 250,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Colors.white),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 50),
                  Text(
                    nurseName != null && nurseName!.isNotEmpty
                        ? 'Nurse $nurseName'
                        : 'No name found',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.edit, color: Color(0xFF00588E)),
                    title: const Text("Edit Profile"),
                    onTap: () {
                      toggleSidebar();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EditProfile(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings, color: Color(0xFF00588E)),
                    title: const Text("Settings"),
                    onTap: toggleSidebar,
                  ),
                  ListTile(
                    leading: const Icon(Icons.help, color: Color(0xFF00588E)),
                    title: const Text("Help & Support"),
                    onTap: toggleSidebar,
                  ),
                  const Divider(),
                  const SizedBox(height: 20),
                  Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D5B78),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 60,
                        ),
                      ),
                      onPressed: _handleLogout,
                      child: const Text(
                        'LOGOUT',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Elderly list for a specific house (similar style to your elderly_list.dart),
/// but navigates to MedicationDetailsScreen on tap.
class MedicationElderlyListScreen extends StatefulWidget {
  final String houseId;
  final String houseName;

  const MedicationElderlyListScreen({
    super.key,
    required this.houseId,
    required this.houseName,
  });

  @override
  State<MedicationElderlyListScreen> createState() =>
      _MedicationElderlyListScreenState();
}

class _MedicationElderlyListScreenState
    extends State<MedicationElderlyListScreen> {
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
        };
      }).toList();

      filterElderly();
    } catch (e) {
      // ignore: avoid_print
      print('Error fetching elderly: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void filterElderly() {
    List<Map<String, dynamic>> filtered = List.from(allElderly);

    if (searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (e) => ('${e['elderly_fname']} ${e['elderly_lname']}')
                .toLowerCase()
                .contains(searchQuery.toLowerCase()),
          )
          .toList();
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

    setState(() => filteredElderly = filtered);
  }
  

  @override
  Widget build(BuildContext context) {
    String logoImage =
        'assets/images/${widget.houseName.replaceAll('St. ', '').trim()}_Logo.png';

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
                    onChanged: (v) {
                      searchQuery = v;
                      filterElderly();
                    },
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DropdownButton<String>(
                      value: sortOrder,
                      items: const ['A-Z', 'Z-A']
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
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
                              final imageUrl =
                                  elderly['elderly_profilePic'] as String? ??
                                  '';
                              final fullName =
                                  '${elderly['elderly_fname']} ${elderly['elderly_lname']}';
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
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
                                        builder: (_) => MedicationDetailsScreen(
                                          elderlyId: elderly['elderly_id'],
                                          elderlyName: fullName,
                                        ),
                                      ),
                                    );
                                  },
                                  leading: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFF00588E),
                                    ),
                                    child: ClipOval(
                                      child: imageUrl.isNotEmpty
                                          ? Image.network(
                                              imageUrl,
                                              fit: BoxFit.cover,
                                            )
                                          : Image.asset(
                                              'assets/images/people_icon.png',
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                  ),
                                  title: Text(
                                    fullName,
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
}

/// Medication details for a specific elderly.
/// Displays list of medications and allows updating STATUS per medication.
/// Clicking "Save Updated Data" opens a confirmation dialog requiring
/// a description and a checkbox before submitting the updates.
class MedicationDetailsScreen extends StatefulWidget {
  final String elderlyId;
  final String elderlyName;

  const MedicationDetailsScreen({
    super.key,
    required this.elderlyId,
    required this.elderlyName,
  });

  @override
  State<MedicationDetailsScreen> createState() =>
      _MedicationDetailsScreenState();
}

class _MedicationDetailsScreenState extends State<MedicationDetailsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loading = true;
  List<_MedItem> _meds = [];

  @override
  void initState() {
    super.initState();
    _loadMeds();
  }

  Future<void> _loadMeds() async {
    try {
      final q = await _firestore
          .collection('medication')
          .where('elderly_id', isEqualTo: widget.elderlyId)
          .get();

      _meds = q.docs.map((d) {
        final data = d.data();
        final String medName = (data['medication_name'] ?? '').toString();
        final String dosage = (data['medication_dosage'] ?? '').toString();
        final String frequency = (data['medication_frequency'] ?? '').toString();
        final String status =
            (data['medication_status'] ?? 'Pending').toString();

        DateTime? date;
        final rawDate = data['medication_date_time'];
        if (rawDate is Timestamp) {
          date = rawDate.toDate();
        }

        return _MedItem(
          docId: d.id,
          medName: medName,
          dosage: dosage,
          frequency: frequency,
          date: date,
          status: status,
        );
      }).toList();
    } catch (e) {
      print('❌ Error loading medications: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveUpdatesWithConfirm() async {
    final result = await showDialog<_ConfirmResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ConfirmDialog(),
    );

    if (result == null || !result.confirmed) return;

    try {
      final batch = _firestore.batch();
      final medsCol = _firestore.collection('medication');

      for (final m in _meds.where((x) => x.statusChanged)) {
        batch.update(medsCol.doc(m.docId), {
          'medication_status': m.status,
          'last_updated_at': FieldValue.serverTimestamp(),
          'last_update_note': result.description,
        });
      }

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medication statuses updated.')),
      );

      setState(() {
        for (final m in _meds) {
          m.markCommitted();
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to update: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Medications of ${widget.elderlyName}"),
        backgroundColor: const Color(0xFF00588E),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _meds.isEmpty
              ? const Center(child: Text("No medications found."))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final m in _meds)
                      Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text(m.medName),
                          subtitle: Text(
                              "Dosage: ${m.dosage}\nFrequency: ${m.frequency}\nDate: ${m.date != null ? m.date.toString() : 'N/A'}"),
                          trailing: DropdownButton<String>(
                            value: m.status,
                            items: const [
                              DropdownMenuItem(
                                  value: 'Pending', child: Text("Pending")),
                              DropdownMenuItem(
                                  value: 'Given', child: Text("Given")),
                              DropdownMenuItem(
                                  value: 'Missed', child: Text("Missed")),
                            ],
                            onChanged: (val) {
                              setState(() {
                                m.status = val ?? 'Pending';
                                m.statusChanged = true;
                              });
                            },
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _saveUpdatesWithConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00588E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 20),
                      ),
                      child: const Text("Save Updated Data"),
                    ),
                  ],
                ),
    );
  }
}

/// --- Helper Classes ---
class _MedItem {
  final String docId;
  final String medName;
  final String dosage;
  final String frequency;
  final DateTime? date;
  String status;
  bool statusChanged = false;

  _MedItem({
    required this.docId,
    required this.medName,
    required this.dosage,
    required this.frequency,
    required this.date,
    required this.status,
  });

  void markCommitted() => statusChanged = false;
}

class _ConfirmResult {
  final bool confirmed;
  final String description;

  _ConfirmResult(this.confirmed, this.description);
}

class _ConfirmDialog extends StatefulWidget {
  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  final TextEditingController _descCtrl = TextEditingController();
  bool _agree = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Confirm Update"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: "Description / Notes",
            ),
          ),
          CheckboxListTile(
            value: _agree,
            onChanged: (v) => setState(() => _agree = v ?? false),
            title: const Text("I confirm these medication updates."),
          ),
        ],
      ),
      actions: [
        TextButton(
          child: const Text("Cancel"),
          onPressed: () => Navigator.pop(context),
        ),
        ElevatedButton(
          child: const Text("Confirm"),
          onPressed: _agree
              ? () => Navigator.pop(
                  context, _ConfirmResult(true, _descCtrl.text.trim()))
              : null,
        ),
      ],
    );
  }
}



