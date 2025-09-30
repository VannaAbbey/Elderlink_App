import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_profile.dart';
import '../auth/login.dart';
import 'medication_management_layout.dart'; // Import layout widgets

/// --- Medication Management Screen ---
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

  final Map<String, String> houseDescriptions = const {
    'St. Sebastian': 'Females with Psychological Needs',
    'St. Emmanuel': 'Females that are Bedridden',
    'St. Charbell': 'Males that are Bedridden',
    'St. Rose of Lima': 'Females that are Abled',
    'St. Gabriel': 'Males that are Abled',
  };

  @override
  void initState() {
    super.initState();
    _loadNurseData();
  }

  Future<void> _loadNurseData() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final firstName = doc['user_fname'] ?? '';
        final lastName = doc['user_lname'] ?? '';
        setState(() {
          nurseName = '$firstName $lastName'.trim();
        });

        // Also update FirebaseAuth displayName to use later in medication updates
        if ((user.displayName ?? '').isEmpty) {
          await user.updateDisplayName('$firstName $lastName'.trim());
        }
      } else {
        setState(() => nurseName = null);
      }
    }
  } catch (e) {
    print("❌ Error loading nurse data: $e");
    setState(() => nurseName = null);
  }
}



  void toggleSidebar() => setState(() => isSidebarOpen = !isSidebarOpen);

  Future<List<Map<String, dynamic>>> fetchHouses() async {
    final snap = await _firestore.collection('house').get();
    final list = snap.docs.map((d) => d.data()).toList();
    list.sort((a, b) =>
        (a['house_id'] ?? '').toString().compareTo((b['house_id'] ?? '').toString()));
    return list;
  }

  Future<void> _handleLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MedicationManagementLayout(
      search: _search,
      onSearchChanged: (v) => setState(() => _search = v),
      toggleSidebar: toggleSidebar,
      isSidebarOpen: isSidebarOpen,
      nurseName: nurseName,
      houseDescriptions: houseDescriptions,
      fetchHouses: fetchHouses,
      handleLogout: _handleLogout,
    );
  }
}

/// --- Elderly List Screen ---
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

    filtered.sort((a, b) {
      final nameA = '${a['elderly_fname']} ${a['elderly_lname']}';
      final nameB = '${b['elderly_fname']} ${b['elderly_lname']}';
      return sortOrder == 'A-Z'
          ? nameA.compareTo(nameB)
          : nameB.compareTo(nameA);
    });

    setState(() => filteredElderly = filtered);
  }

  @override
  Widget build(BuildContext context) {
    return MedicationElderlyListLayout(
      houseId: widget.houseId, 
      houseName: widget.houseName,
      filteredElderly: filteredElderly,
      isLoading: isLoading,
      searchQuery: searchQuery,
      onSearchChanged: (v) {
        searchQuery = v;
        filterElderly();
      },
      sortOrder: sortOrder,
      onSortChanged: (v) {
        sortOrder = v;
        filterElderly();
      },
    );
  }
}

/// --- Medication Details Screen ---
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
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _loading = true;
  List<MedItem> _meds = [];

  @override
  void initState() {
    super.initState();
    _loadMeds();
  }

  Future<void> _loadMeds() async {
    try {
      final snapshot = await _firestore
          .collection('medication')
          .where('elderly_id', isEqualTo: widget.elderlyId)
          .get();

      _meds = snapshot.docs.map((d) {
        final data = d.data();
        DateTime? date;
        final rawDate = data['medication_date_time'];
        if (rawDate is Timestamp) date = rawDate.toDate();

        return MedItem(
          docId: d.id,
          medName: data['medication_name'] ?? '',
          dosage: data['medication_dosage'] ?? '',
          frequency: data['medication_frequency'] ?? '',
          date: date,
          status: data['medication_status'] ?? 'Pending',
        );
      }).toList();
    } catch (e) {
      print('❌ Error loading medications: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveUpdates() async {
  // Get current nurse's UID
  final user = _auth.currentUser;
  String nurseName = 'Unknown Nurse';

  if (user != null) {
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (doc.exists) {
  final firstName = doc['user_fname'] ?? '';
  final lastName = doc['user_lname'] ?? '';
  nurseName = '$firstName $lastName'.trim();
}
  }

  final result = await showDialog<_ConfirmResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ConfirmDialog(nurseName: nurseName),
  );

  if (result == null || !result.confirmed) return;

  try {
    final batch = _firestore.batch();
    final medsCol = _firestore.collection('medication');

    for (final m in _meds) {
      if (m.docId.isEmpty) {
        final newDoc = medsCol.doc();
        batch.set(newDoc, {
          'elderly_id': widget.elderlyId,
          'medication_name': m.medName,
          'medication_dosage': m.dosage,
          'medication_frequency': m.frequency,
          'medication_date_time': m.date != null ? Timestamp.fromDate(m.date!) : null,
          'medication_status': m.status,
          'reporting_nurse': nurseName,
          'last_updated_at': FieldValue.serverTimestamp(),
          'last_update_note': result.description,
        });
      } else if (m.statusChanged) {
        batch.update(medsCol.doc(m.docId), {
          'medication_status': m.status,
          'reporting_nurse': nurseName,
          'last_updated_at': FieldValue.serverTimestamp(),
          'last_update_note': result.description,
        });
      }
    }

    await batch.commit();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Medication updates saved successfully.')),
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
    return MedicationDetailsLayout(
      elderlyName: widget.elderlyName,
      meds: _meds,
      loading: _loading,
      onSave: _saveUpdates,
    );
  }
}

/// --- Helper Classes ---
class MedItem {
  String docId; // empty if newly added
  String medName;
  String dosage;
  String frequency;
  final DateTime? date;
  String status;
  bool statusChanged = false;

  MedItem({
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
  final String nurseName;
  const _ConfirmDialog({required this.nurseName});

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
          Row(
            children: [
              Expanded(child: Text("Reporting Nurse: ${widget.nurseName}")),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: "Description / Notes",
            ),
          ),
          const SizedBox(height: 12),
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
          onPressed: _agree
              ? () => Navigator.pop(
                  context, _ConfirmResult(true, _descCtrl.text.trim()))
              : null,
          child: const Text("Confirm"),
        ),
      ],
    );
  }
}

------------------------------------------------------layout widgets------------------------------------------------------
import 'package:flutter/material.dart';
import 'medication_management.dart';
import 'edit_profile.dart';
import 'package:intl/intl.dart';

/// Layout for MedicationManagementScreen
class MedicationManagementLayout extends StatelessWidget {
  final String search;
  final Function(String) onSearchChanged;
  final VoidCallback toggleSidebar;
  final bool isSidebarOpen;
  final String? nurseName;
  final Map<String, String> houseDescriptions;
  final Future<List<Map<String, dynamic>>> Function() fetchHouses;
  final Future<void> Function() handleLogout;

  const MedicationManagementLayout({
    super.key,
    required this.search,
    required this.onSearchChanged,
    required this.toggleSidebar,
    required this.isSidebarOpen,
    required this.nurseName,
    required this.houseDescriptions,
    required this.fetchHouses,
    required this.handleLogout,
  });

  @override
  Widget build(BuildContext context) {
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
              child: ListView(
                children: [
                  // Header
                  Row(
                    children: [
                      GestureDetector(
                        onTap: toggleSidebar,
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
                    style: const TextStyle(fontSize: 18, color: Colors.black),
                    onChanged: onSearchChanged,
                  ),
                  const SizedBox(height: 24),
                  // Houses header
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
                        return search.isEmpty ||
                            name.contains(search.toLowerCase());
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
                          final imagePath =
                              'assets/images/${imageName}_Logo.png';
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
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
          if (isSidebarOpen)
            _SidebarOverlay(
              nurseName: nurseName,
              toggleSidebar: toggleSidebar,
              handleLogout: handleLogout,
            ),
        ],
      ),
    );
  }
}

/// Sidebar overlay
class _SidebarOverlay extends StatelessWidget {
  final String? nurseName;
  final VoidCallback toggleSidebar;
  final Future<void> Function() handleLogout;

  const _SidebarOverlay({
    required this.nurseName,
    required this.toggleSidebar,
    required this.handleLogout,
  });

  @override
  Widget build(BuildContext context) {
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
                        MaterialPageRoute(builder: (_) => const EditProfile()),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.settings,
                      color: Color(0xFF00588E),
                    ),
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
                      onPressed: handleLogout,
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

/// --- Medication Elderly List Layout ---
class MedicationElderlyListLayout extends StatelessWidget {
  final String houseId;
  final String houseName;
  final List<Map<String, dynamic>> filteredElderly;
  final bool isLoading;
  final String searchQuery;
  final Function(String?) onSearchChanged;
  final String? sortOrder;
  final Function(String?) onSortChanged;
  final Function(String elderlyId, String elderlyName) onElderlyTap;

  const MedicationElderlyListLayout({
    super.key,
    required this.houseId,
    required this.houseName,
    required this.filteredElderly,
    required this.isLoading,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.sortOrder,
    required this.onSortChanged,
    required this.onElderlyTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Medications - $houseName"),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: "Search Elderly",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => onSearchChanged(v),
            ),
          ),

          // Sort Dropdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: DropdownButtonFormField<String>(
              value: sortOrder,
              decoration: const InputDecoration(
                labelText: "Sort Order",
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: "asc", child: Text("Ascending")),
                DropdownMenuItem(value: "desc", child: Text("Descending")),
              ],
              onChanged: onSortChanged,
            ),
          ),

          // Elderly List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredElderly.isEmpty
                    ? const Center(child: Text("No elderly found"))
                    : ListView.builder(
                        itemCount: filteredElderly.length,
                        itemBuilder: (context, index) {
                          final elderly = filteredElderly[index];
                          return Card(
                            child: ListTile(
                              title: Text(elderly["name"] ?? "Unnamed"),
                              subtitle: Text("Age: ${elderly["age"] ?? "N/A"}"),
                              trailing: const Icon(Icons.arrow_forward_ios),
                              onTap: () => onElderlyTap(
                                elderly["id"],
                                elderly["name"] ?? "Unnamed",
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// --- Medication Details Layout ---
class MedicationDetailsLayout extends StatefulWidget {
  final String elderlyName;
  final List<MedItem> meds;
  final bool loading;
  final VoidCallback onSave;

  const MedicationDetailsLayout({
    super.key,
    required this.elderlyName,
    required this.meds,
    required this.loading,
    required this.onSave,
  });

  @override
  State<MedicationDetailsLayout> createState() => _MedicationDetailsLayoutState();
}

class _MedicationDetailsLayoutState extends State<MedicationDetailsLayout> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Medication Details - ${widget.elderlyName}'),
      ),
      body: widget.loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: widget.meds.length,
                    itemBuilder: (context, index) {
                      final med = widget.meds[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    med.medName,
                                    style: const TextStyle(
                                        fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () {
                                      setState(() {
                                        widget.meds.removeAt(index);
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('Dosage: ${med.dosage}'),
                              Text('Frequency: ${med.frequency}'),
                              if (med.date != null)
                                Text(
                                  'Date: ${DateFormat('yyyy-MM-dd HH:mm').format(med.date!)}',
                                ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Text('Status: '),
                                  DropdownButton<String>(
                                    value: ['Pending', 'Taken', 'Missed'].contains(med.status)
                                        ? med.status
                                        : 'Pending',
                                    items: ['Pending', 'Taken', 'Missed']
                                        .map((status) => DropdownMenuItem(
                                              value: status,
                                              child: Text(status),
                                            ))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val == null) return;
                                      setState(() {
                                        med.status = val;
                                        med.statusChanged = true;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add Medication'),
                        onPressed: () async {
                          final newMed = await _showAddMedicationDialog(context);
                          if (newMed != null) {
                            setState(() {
                              widget.meds.add(newMed);
                            });
                          }
                        },
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text('Submit Updates'),
                        onPressed: widget.onSave,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<MedItem?> _showAddMedicationDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final dosageCtrl = TextEditingController();
    final freqCtrl = TextEditingController();
    DateTime? selectedDate;

    return showDialog<MedItem>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Medication'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Medication Name')),
                    TextField(controller: dosageCtrl, decoration: const InputDecoration(labelText: 'Dosage')),
                    TextField(controller: freqCtrl, decoration: const InputDecoration(labelText: 'Frequency')),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(selectedDate == null
                            ? 'Select Date & Time'
                            : DateFormat('yyyy-MM-dd HH:mm').format(selectedDate!)),
                        IconButton(
                          icon: const Icon(Icons.calendar_today),
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (date != null) {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.now(),
                              );
                              if (time != null) {
                                setDialogState(() {
                                  selectedDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                                });
                              }
                            }
                          },
                        )
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty || dosageCtrl.text.trim().isEmpty || freqCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
                      return;
                    }
                    final med = MedItem(
                      docId: '',
                      medName: nameCtrl.text.trim(),
                      dosage: dosageCtrl.text.trim(),
                      frequency: freqCtrl.text.trim(),
                      date: selectedDate,
                      status: 'Pending',
                    );
                    Navigator.pop(ctx, med);
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
