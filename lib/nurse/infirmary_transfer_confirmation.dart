import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class InfirmaryTransferConfirmationScreen extends StatefulWidget {
  final String houseId;
  final String houseName;
  final List<Map<String, dynamic>> selectedElderly;

  const InfirmaryTransferConfirmationScreen({
    super.key,
    required this.houseId,
    required this.houseName,
    required this.selectedElderly,
  });

  @override
  State<InfirmaryTransferConfirmationScreen> createState() =>
      _InfirmaryTransferConfirmationScreenState();
}

class _InfirmaryTransferConfirmationScreenState
    extends State<InfirmaryTransferConfirmationScreen> {
  final TextEditingController _reasonController = TextEditingController();
  bool _isSubmitting = false;
  String? _nurseName;
  String? _nurseId;

  @override
  void initState() {
    super.initState();
    _loadNurseInfo();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadNurseInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data()!;
          setState(() {
            _nurseId = user.uid;
            _nurseName =
                '${userData['user_fname'] ?? ''} ${userData['user_lname'] ?? ''}'
                    .trim();
          });
        }
      }
    } catch (e) {
      print('Error loading nurse info: $e');
    }
  }

  Future<void> _submitTransfer() async {
    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide a reason for the transfer'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final transferTime = Timestamp.now();

      // Create transfer records for each selected elderly
      for (final elderly in widget.selectedElderly) {
        final transferDoc = FirebaseFirestore.instance
            .collection('infirmary_transfers')
            .doc();

        batch.set(transferDoc, {
          'transfer_id': transferDoc.id,
          'elderly_id': elderly['elderly_id'],
          'elderly_name':
              '${elderly['elderly_fname']} ${elderly['elderly_lname']}',
          'from_house_id': widget.houseId,
          'nurse_id': _nurseId,
          'nurse_name': _nurseName,
          'transfer_reason': _reasonController.text.trim(),
          'request_date': transferTime,
          'transfer_status':
              'pending', // pending, approved, rejected, active, discharged
          'created_at': transferTime,
          'updated_at': transferTime,
        });
      }

      await batch.commit();

      if (mounted) {
        // Show request sent dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text(
              'Request Sent to Admin',
              style: TextStyle(
                color: Color(0xFF00588E),
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.pending_actions,
                  color: Colors.orange,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  'Your request to transfer ${widget.selectedElderly.length} elderly to infirmary has been sent to admin.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Please wait for approval.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  // Pop all the way back to elderly list
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.of(context).pop(); // Close confirmation screen
                  Navigator.of(context).pop(); // Close selection screen
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF00588E),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('Error submitting transfer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
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

                    // Header
                    const Text(
                      "Confirm Infirmary Transfer",
                      style: TextStyle(
                        fontSize: 22,
                        color: Color(0xFF00588E),
                        fontWeight: FontWeight.bold,
                        fontFamily: "Poppins",
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Transfer summary card
                    Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.local_hospital,
                                  color: Color(0xFF00588E),
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  "Transfer Summary",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF00588E),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            Text(
                              "From: ${widget.houseId}",
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 4),

                            const Text(
                              "To: Infirmary",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),

                            Text(
                              "Nurse: ${_nurseName ?? 'Loading...'}",
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 4),

                            Text(
                              "Elderly Count: ${widget.selectedElderly.length}",
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Selected elderly list
                    SizedBox(
                      height: 300, // Fixed height for the elderly list
                      child: Card(
                        elevation: 4,
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: Color(0xFF00588E),
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                              child: const Text(
                                "Selected Elderly",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.all(8),
                                itemCount: widget.selectedElderly.length,
                                itemBuilder: (context, index) {
                                  final elderly = widget.selectedElderly[index];
                                  final imageUrl =
                                      (elderly['elderly_profilePic'] ?? '')
                                          .toString();
                                  final fullName =
                                      '${elderly['elderly_fname']} ${elderly['elderly_lname']}';

                                  return ListTile(
                                    leading: CircleAvatar(
                                      radius: 20,
                                      backgroundImage: imageUrl.isNotEmpty
                                          ? NetworkImage(imageUrl)
                                          : const AssetImage(
                                                  'assets/images/people_icon.png',
                                                )
                                                as ImageProvider,
                                    ),
                                    title: Text(
                                      fullName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
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
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Reason input
                    Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Transfer Reason",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00588E),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _reasonController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText:
                                    "Please provide the reason for transferring to infirmary...",
                                filled: true,
                                fillColor: const Color(0xFFD8F4FF),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF00588E),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF00588E),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Submit buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF00588E)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Text(
                              "Cancel",
                              style: TextStyle(
                                color: Color(0xFF00588E),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submitTransfer,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF00588E),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    "Confirm Transfer",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
