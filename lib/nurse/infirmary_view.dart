import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class InfirmaryViewScreen extends StatefulWidget {
  const InfirmaryViewScreen({super.key});

  @override
  State<InfirmaryViewScreen> createState() => _InfirmaryViewScreenState();
}

class _InfirmaryViewScreenState extends State<InfirmaryViewScreen> {
  String selectedStatus = 'active'; // active, discharged, all
  String searchQuery = '';
  List<Map<String, dynamic>> allTransfers = [];
  List<Map<String, dynamic>> filteredTransfers = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchInfirmaryTransfers();
  }

  Future<void> fetchInfirmaryTransfers() async {
    setState(() => isLoading = true);
    try {
      Query query = FirebaseFirestore.instance.collection(
        'infirmary_transfers',
      );

      if (selectedStatus != 'all') {
        query = query.where('transfer_status', isEqualTo: selectedStatus);
      }

      final snapshot = await query
          .orderBy('transfer_date', descending: true)
          .get();

      allTransfers = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {'transfer_id': doc.id, ...data};
      }).toList();

      filterTransfers();
    } catch (e) {
      print('Error fetching infirmary transfers: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void filterTransfers() {
    List<Map<String, dynamic>> filtered = allTransfers;

    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      filtered = filtered.where((transfer) {
        final elderlyName = (transfer['elderly_name'] ?? '').toLowerCase();
        final nurseName = (transfer['nurse_name'] ?? '').toLowerCase();
        final reason = (transfer['transfer_reason'] ?? '').toLowerCase();
        final houseId = (transfer['from_house_id'] ?? '').toLowerCase();

        return elderlyName.contains(query) ||
            nurseName.contains(query) ||
            reason.contains(query) ||
            houseId.contains(query);
      }).toList();
    }

    setState(() {
      filteredTransfers = filtered;
    });
  }

  Future<void> updateTransferStatus(String transferId, String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('infirmary_transfers')
          .doc(transferId)
          .update({
            'transfer_status': newStatus,
            'updated_at': Timestamp.now(),
            'discharge_date': newStatus == 'discharged'
                ? Timestamp.now()
                : null,
          });

      // Refresh the list
      await fetchInfirmaryTransfers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == 'discharged'
                  ? 'Patient discharged from infirmary'
                  : 'Status updated successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error updating transfer status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating status: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void showStatusUpdateDialog(Map<String, dynamic> transfer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Update Status: ${transfer['elderly_name']}',
          style: const TextStyle(
            color: Color(0xFF00588E),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Discharge from Infirmary'),
              leading: const Icon(Icons.home, color: Colors.green),
              onTap: () {
                Navigator.pop(context);
                updateTransferStatus(transfer['transfer_id'], 'discharged');
              },
            ),
            if (transfer['transfer_status'] == 'discharged')
              ListTile(
                title: const Text('Return to Active'),
                leading: const Icon(
                  Icons.local_hospital,
                  color: Color(0xFF00588E),
                ),
                onTap: () {
                  Navigator.pop(context);
                  updateTransferStatus(transfer['transfer_id'], 'active');
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
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
                  // Back button and header
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Color(0xFF00588E),
                          size: 28,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Text(
                          "Infirmary Management",
                          style: TextStyle(
                            fontSize: 22,
                            color: Color(0xFF00588E),
                            fontWeight: FontWeight.bold,
                            fontFamily: "Poppins",
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 48), // Balance the back button
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Status filter
                  Container(
                    height: 45,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD8F4FF),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      children: [
                        _buildStatusButton("Pending", "pending"),
                        _buildStatusButton("Active", "active"),
                        _buildStatusButton("Discharged", "discharged"),
                        _buildStatusButton("All", "all"),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Search bar
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      hintText:
                          "Search by elderly name, nurse, reason, or house ID...",
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
                      filterTransfers();
                    },
                  ),

                  const SizedBox(height: 16),

                  // Transfers list
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : filteredTransfers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.local_hospital_outlined,
                                  size: 80,
                                  color: Colors.grey.withOpacity(0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  selectedStatus == 'pending'
                                      ? 'No pending transfer requests'
                                      : selectedStatus == 'active'
                                      ? 'No patients currently in infirmary'
                                      : selectedStatus == 'discharged'
                                      ? 'No discharged patients'
                                      : 'No infirmary transfers found',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: fetchInfirmaryTransfers,
                            child: ListView.builder(
                              itemCount: filteredTransfers.length,
                              itemBuilder: (context, index) {
                                final transfer = filteredTransfers[index];
                                final transferDate =
                                    transfer['transfer_date'] as Timestamp?;
                                final dischargeDate =
                                    transfer['discharge_date'] as Timestamp?;

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  elevation: 2,
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          transfer['transfer_status'] ==
                                              'active'
                                          ? const Color(0xFF00588E)
                                          : Colors.green,
                                      child: Icon(
                                        transfer['transfer_status'] == 'active'
                                            ? Icons.local_hospital
                                            : Icons.home,
                                        color: Colors.white,
                                      ),
                                    ),
                                    title: Text(
                                      transfer['elderly_name'] ?? 'Unknown',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'From: ${transfer['from_house_id'] ?? 'Unknown House'}',
                                        ),
                                        Text(
                                          'Nurse: ${transfer['nurse_name'] ?? 'Unknown'}',
                                        ),
                                        Text(
                                          'Reason: ${transfer['transfer_reason'] ?? 'No reason provided'}',
                                        ),
                                        if (transferDate != null)
                                          Text(
                                            'Transferred: ${DateFormat('MMM dd, yyyy HH:mm').format(transferDate.toDate())}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        if (dischargeDate != null)
                                          Text(
                                            'Discharged: ${DateFormat('MMM dd, yyyy HH:mm').format(dischargeDate.toDate())}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.green,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                transfer['transfer_status'] ==
                                                    'active'
                                                ? Colors.red.withOpacity(0.1)
                                                : Colors.green.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color:
                                                  transfer['transfer_status'] ==
                                                      'active'
                                                  ? Colors.red
                                                  : Colors.green,
                                            ),
                                          ),
                                          child: Text(
                                            transfer['transfer_status'] ==
                                                    'active'
                                                ? 'IN INFIRMARY'
                                                : 'DISCHARGED',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  transfer['transfer_status'] ==
                                                      'active'
                                                  ? Colors.red
                                                  : Colors.green,
                                            ),
                                          ),
                                        ),
                                        if (transfer['transfer_status'] ==
                                            'active')
                                          IconButton(
                                            icon: const Icon(Icons.more_vert),
                                            onPressed: () =>
                                                showStatusUpdateDialog(
                                                  transfer,
                                                ),
                                          ),
                                      ],
                                    ),
                                    isThreeLine: true,
                                    onTap: () =>
                                        showStatusUpdateDialog(transfer),
                                  ),
                                );
                              },
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

  Widget _buildStatusButton(String label, String value) {
    final isSelected = selectedStatus == value;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedStatus = value;
          });
          fetchInfirmaryTransfers();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00588E) : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
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
              fontSize: 12,
              color: isSelected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
