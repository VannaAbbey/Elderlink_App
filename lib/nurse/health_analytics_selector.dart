import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'health_analytics.dart';

class HealthAnalyticsSelectorScreen extends StatefulWidget {
  final String? nurseName;

  const HealthAnalyticsSelectorScreen({super.key, this.nurseName});

  @override
  State<HealthAnalyticsSelectorScreen> createState() =>
      _HealthAnalyticsSelectorScreenState();
}

class _HealthAnalyticsSelectorScreenState
    extends State<HealthAnalyticsSelectorScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _houses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHouses();
  }

  Future<void> _loadHouses() async {
    setState(() => _isLoading = true);

    try {
      final housesQuery = await _firestore
          .collection('house')
          .orderBy('house_id')
          .get();

      setState(() {
        _houses = housesQuery.docs
            .map(
              (doc) => {
                'house_id': doc.data()['house_id'] as String? ?? doc.id,
                'house_name': doc.data()['house_name'] as String? ?? 'Unknown',
                'description': doc.data()['description'] as String? ?? '',
              },
            )
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading houses: $e');
      setState(() => _isLoading = false);
    }
  }

  void _navigateToAnalytics(String houseId, String houseName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HealthAnalyticsScreen(
          houseId: houseId,
          nurseName: widget.nurseName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Health Analytics',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF00588E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _houses.isEmpty
          ? const Center(
              child: Text(
                'No houses available',
                style: TextStyle(fontSize: 16, fontFamily: 'Poppins'),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select a House',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                      color: Color(0xFF00588E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'View health analytics and trends for elderly residents',
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Poppins',
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _houses.length,
                      itemBuilder: (context, index) {
                        final house = _houses[index];
                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: const Color(0xFF00588E).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.home,
                                color: Color(0xFF00588E),
                                size: 30,
                              ),
                            ),
                            title: Text(
                              house['house_name'] ?? 'Unknown',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                fontFamily: 'Poppins',
                              ),
                            ),
                            subtitle:
                                house['description'] != null &&
                                    house['description'].toString().isNotEmpty
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      house['description'],
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'Poppins',
                                        color: Colors.grey,
                                      ),
                                    ),
                                  )
                                : null,
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              color: Color(0xFF00588E),
                              size: 20,
                            ),
                            onTap: () => _navigateToAnalytics(
                              house['house_id'],
                              house['house_name'],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
