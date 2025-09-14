import 'package:elderlink_app/nurse/emergency.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home.dart';
import 'medication_management.dart';
import 'incident_report.dart';

class VitalMonitoringScreen extends StatefulWidget {
  const VitalMonitoringScreen({super.key});

  @override
  State<VitalMonitoringScreen> createState() => _VitalMonitoringScreenState();
}

class _VitalMonitoringScreenState extends State<VitalMonitoringScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _search = '';

  final Map<String, String> houseDescriptions = const {
    'St. Sebastian': 'Females with Psychological Needs',
    'St. Emmanuel': 'Females that are Bedridden',
    'St. Charbell': 'Males that are Bedridden',
    'St. Rose': 'Females that are Abled',
    'St. Gabriel': 'Males that are Abled',
  };

  Future<List<Map<String, dynamic>>> fetchHouses() async {
    final snap = await _firestore.collection('house').get();
    final list = snap.docs.map((d) => d.data()).toList();
    list.sort(
      (a, b) => (a['house_id'] ?? '').toString().compareTo(
        (b['house_id'] ?? '').toString(),
      ),
    );
    return list;
  }

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
                    children: const [
                      Icon(
                        Icons.monitor_heart,
                        color: Color(0xFF00588E),
                        size: 38,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Vital Signs Monitoring',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF00588E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Search for house
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search house...',
                      filled: true,
                      fillColor: const Color(0xFFD8F4FF),
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
                    onChanged: (v) =>
                        setState(() => _search = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 24),

                  // Houses
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

                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: fetchHouses(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting)
                        return const Center(child: CircularProgressIndicator());
                      if (!snap.hasData || snap.data!.isEmpty)
                        return const Text('No houses found.');
                      final houses = snap.data!.where((h) {
                        final name = (h['house_name'] ?? '')
                            .toString()
                            .toLowerCase();
                        return _search.isEmpty || name.contains(_search);
                      }).toList();

                      return Column(
                        children: houses.map((house) {
                          final houseName = (house['house_name'] ?? '')
                              .toString();
                          final desc =
                              houseDescriptions[houseName] ??
                              'Elderly Care Facility';
                          final imageName = houseName
                              .replaceAll('St. ', '')
                              .replaceAll(' ', '');
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VitalElderlyListScreen(
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
                                    'assets/images/$imageName.png',
                                    width: 80,
                                    height: 80,
                                  ),
                                  const SizedBox(width: 15),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text(
                                          houseName,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF00588E),
                                          ),
                                        ),
                                        Text(desc, textAlign: TextAlign.center),
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
        ],
      ),
    );
  }
}

/// Screen 2: List elderly for selected house with SEARCH
class VitalElderlyListScreen extends StatefulWidget {
  final String houseId;
  final String houseName;
  const VitalElderlyListScreen({
    super.key,
    required this.houseId,
    required this.houseName,
  });

  @override
  State<VitalElderlyListScreen> createState() => _VitalElderlyListScreenState();
}

class _VitalElderlyListScreenState extends State<VitalElderlyListScreen> {
  String _search = '';

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
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search elderly...',
                      filled: true,
                      fillColor: const Color(0xFFD8F4FF),
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
                    onChanged: (value) =>
                        setState(() => _search = value.toLowerCase()),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('elderly')
                        .where('house_id', isEqualTo: widget.houseId)
                        .where('elderly_status', isEqualTo: 'Alive')
                        .snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final docs = snap.data!.docs.where((doc) {
                        final name =
                            '${doc['elderly_fname']} ${doc['elderly_lname']}'
                                .toLowerCase();
                        return _search.isEmpty || name.contains(_search);
                      }).toList();

                      if (docs.isEmpty) {
                        return const Center(child: Text('No elderly found.'));
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final e = docs[i];
                          final fullName =
                              '${e['elderly_fname']} ${e['elderly_lname']}';
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: NetworkImage(
                                  e['elderly_profilePic'] ?? '',
                                ),
                              ),
                              title: Text(fullName),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VitalDetailsScreen(
                                    elderlyId: e.id,
                                    elderlyName: fullName,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Screen 3: Vital details for selected elderly
class VitalDetailsScreen extends StatefulWidget {
  final String elderlyId;
  final String elderlyName;
  const VitalDetailsScreen({
    super.key,
    required this.elderlyId,
    required this.elderlyName,
  });

  @override
  State<VitalDetailsScreen> createState() => _VitalDetailsScreenState();
}

class _VitalDetailsScreenState extends State<VitalDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _data = {
    'blood_pressure': '',
    'temperature': '',
    'respiratory_rate': '',
    'pulse_rate': '',
    'o2_saturation': '',
    'remarks': '',
  };

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
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Color(0xFF00588E),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Text(
                    'Vital Sign Monitoring',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00588E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.elderlyName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Form(
                      key: _formKey,
                      child: ListView(
                        children: [
                          _field('Blood Pressure', 'blood_pressure'),
                          _field('Temperature', 'temperature'),
                          _field('Respiratory Rate', 'respiratory_rate'),
                          _field('Pulse Rate', 'pulse_rate'),
                          _field('O₂ Saturation', 'o2_saturation'),
                          _field('Remarks', 'remarks', maxLines: 3),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00588E),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _showConfirmDialog,
                            child: const Text('Forward Report'),
                          ),
                        ],
                      ),
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

  Widget _field(String label, String key, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(),
        ),
        onChanged: (v) => _data[key] = v,
      ),
    );
  }

  void _showConfirmDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        bool checked = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Confirm Submission'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Please confirm all data is correct before submitting.',
                  ),
                  Row(
                    children: [
                      Checkbox(
                        value: checked,
                        onChanged: (v) => setState(() => checked = v ?? false),
                      ),
                      const Expanded(
                        child: Text('I acknowledge all data is accurate.'),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: checked ? _submit : null,
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submit() async {
    final now = DateTime.now();
    final formattedDate =
        '${now.year}-${now.month}-${now.day} ${now.hour}:${now.minute}';

    await FirebaseFirestore.instance
        .collection('elderly')
        .doc(widget.elderlyId)
        .collection('vitals')
        .add({
          ..._data,
          'vital_record_at': FieldValue.serverTimestamp(),
          'recorded_at_string': formattedDate,
        });

    if (mounted) {
      Navigator.pop(context); // close dialog
      Navigator.pop(context); // back to elderly list
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vital report submitted.')));
    }
  }
}
