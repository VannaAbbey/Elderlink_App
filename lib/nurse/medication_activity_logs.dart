import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class MedicationActivityLogsScreen extends StatefulWidget {
  const MedicationActivityLogsScreen({super.key});

  @override
  State<MedicationActivityLogsScreen> createState() =>
      _MedicationActivityLogsScreenState();
}

class _MedicationActivityLogsScreenState
    extends State<MedicationActivityLogsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime selectedDate = DateTime.now();

  String buildLogText(Map<String, dynamic> log) {
    final action = (log['action_type'] ?? "").toString().toLowerCase();
    final nurseName = log['nurse_name'] ?? "Unknown Nurse";
    final newValue = log['new_value'] ?? {};
    final medicationName = newValue['medication_name'] ?? "medication";
    final elderlyName = log['elderly_name'] ?? "an elderly";

    if (action == "add") {
      return "Nurse $nurseName added $medicationName for $elderlyName's Medication.";
    } else if (action == "edit") {
      return "The medication details of $elderlyName were modified by Nurse $nurseName.";
    } else {
      return "$action by Nurse $nurseName for $elderlyName.";
    }
  }

  Color getCardColor(String actionType) {
    final action = actionType.toLowerCase();
    if (action == "add") return Colors.yellow.shade200;
    if (action == "edit") return Colors.orange.shade200;
    return Colors.white;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
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
            child: Column(
              children: [
                // Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Color(0xFF00588E),
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        "Activity Logs",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00588E),
                        ),
                      ),
                      const Spacer(),
                      Opacity(
                        opacity: 0,
                        child: IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.arrow_back),
                        ),
                      ),
                    ],
                  ),
                ),

                // Date selector (icon only)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Text(
                        "Date: ${DateFormat.yMMMd().format(selectedDate)}",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _pickDate,
                        icon: const Icon(
                          Icons.calendar_today,
                          color: Color(0xFF00588E),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection("medication_logs")
                        .where(
                          "timestamp",
                          isGreaterThanOrEqualTo: DateTime(selectedDate.year,
                              selectedDate.month, selectedDate.day, 0, 0),
                        )
                        .where(
                          "timestamp",
                          isLessThanOrEqualTo: DateTime(selectedDate.year,
                              selectedDate.month, selectedDate.day, 23, 59, 59),
                        )
                        .orderBy("timestamp", descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(child: Text("Error: ${snapshot.error}"));
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text("No logs available"));
                      }

                      final logs = snapshot.data!.docs;

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 12),
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          final logData =
                              logs[index].data() as Map<String, dynamic>? ?? {};
                          final timestamp =
                              (logData['timestamp'] as Timestamp?)?.toDate() ??
                                  DateTime.now();
                          final logText = buildLogText(logData);
                          final actionType =
                              (logData['action_type'] ?? "").toString();

                          final formattedTime =
                              DateFormat.jm().format(timestamp);

                          return Card(
                            color: getCardColor(actionType),
                            margin: const EdgeInsets.symmetric(
                                vertical: 6.0, horizontal: 8.0),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 16),
                              title: Text(logText),
                              subtitle: Text(
                                "Elderly ID: ${logData['elderly_id'] ?? 'unknown'}\nDate: ${DateFormat.yMMMd().format(timestamp)}",
                              ),
                              trailing: Text(formattedTime),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                // Extra bottom spacing
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
