import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

class ActivityReport {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Generate and share a PDF report of medication and vital activities
  Future<void> generateAndShareReport({
    required String houseId,
    required String nurseName,
    required BuildContext context,
  }) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CircularProgressIndicator()),
      );

      // Generate PDF document
      final pdf = pw.Document();

      // Get house name
      final houseDoc = await _firestore.collection('house').doc(houseId).get();
      String houseName = 'Unknown House';
      if (houseDoc.exists && houseDoc.data() != null) {
        houseName = houseDoc.data()!['house_name'] ?? 'Unknown House';
      }

      // Generate medication report
      await _generateMedicationReport(pdf, houseId, houseName);

      // Generate vitals report
      await _generateVitalsReport(pdf, houseId, houseName);

      // Save PDF to temporary file
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'activity_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      // Hide loading dialog
      Navigator.of(context).pop();

      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Activity Report - Medications and Vital Signs',
        subject: 'Elderlink Activity Report',
      );
    } catch (e) {
      // Hide loading dialog if still showing
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Show error dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Report Generation Failed'),
          content: Text('Failed to generate activity report: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  /// Generate medication report page
  Future<void> _generateMedicationReport(
    pw.Document pdf,
    String houseId,
    String houseName,
  ) async {
    // Get medication data grouped by shift
    final medicationData = await _getMedicationDataGroupedByShift(houseId);

    for (final shiftEntry in medicationData.entries) {
      final shift = shiftEntry.key;
      final shiftData = shiftEntry.value;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Container(
                  padding: pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue,
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Text(
                    '$houseName - $shift Shift',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
                pw.SizedBox(height: 20),

                // Medication Table
                pw.Text(
                  'Medication Administration Report',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),

                pw.Table(
                  border: pw.TableBorder.all(),
                  columnWidths: {
                    0: pw.FlexColumnWidth(2), // Nurse Name
                    1: pw.FlexColumnWidth(2), // Elderly Name
                    2: pw.FlexColumnWidth(2), // Medication Name
                    3: pw.FlexColumnWidth(1), // Take
                    4: pw.FlexColumnWidth(1), // Time
                    5: pw.FlexColumnWidth(1), // Status
                  },
                  children: [
                    // Table Header
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        pw.Container(
                          padding: pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Nurse Name',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Container(
                          padding: pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Elderly Name',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Container(
                          padding: pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Medication',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Container(
                          padding: pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Take',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Container(
                          padding: pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Time',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Container(
                          padding: pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Status',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                      ],
                    ),

                    // Table Data
                    ...shiftData.map(
                      (activity) => pw.TableRow(
                        children: [
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(activity['nurse_name'] ?? ''),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(activity['elderly_name'] ?? ''),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(activity['medication_name'] ?? ''),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(activity['take_ordinal'] ?? ''),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(activity['time'] ?? ''),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              activity['status'] ?? '',
                              style: pw.TextStyle(
                                color:
                                    (activity['status'] ?? '').toLowerCase() ==
                                        'comp.'
                                    ? PdfColors.green
                                    : PdfColors.red,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                pw.SizedBox(height: 20),
                pw.Text(
                  'Generated on: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
              ],
            );
          },
        ),
      );
    }
  }

  /// Generate vitals report page
  Future<void> _generateVitalsReport(
    pw.Document pdf,
    String houseId,
    String houseName,
  ) async {
    // Get vitals data grouped by shift
    final vitalsData = await _getVitalsDataGroupedByShift(houseId);

    for (final shiftEntry in vitalsData.entries) {
      final shift = shiftEntry.key;
      final shiftData = shiftEntry.value;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Container(
                  padding: pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.green,
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Text(
                    '$houseName - $shift Shift',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
                pw.SizedBox(height: 20),

                // Vitals Table
                pw.Text(
                  'Vital Signs Monitoring Report',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),

                pw.Table(
                  border: pw.TableBorder.all(),
                  columnWidths: {
                    0: pw.FlexColumnWidth(2), // Nurse Name
                    1: pw.FlexColumnWidth(2), // Elderly Name
                    2: pw.FlexColumnWidth(1.5), // Blood Pressure
                    3: pw.FlexColumnWidth(1), // Pulse Rate
                    4: pw.FlexColumnWidth(1), // O2
                    5: pw.FlexColumnWidth(1), // Temperature
                    6: pw.FlexColumnWidth(1), // Respiratory Rate
                    7: pw.FlexColumnWidth(1), // Status
                  },
                  children: [
                    // Table Header
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        pw.Container(
                          padding: pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Nurse Name',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Container(
                          padding: pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Elderly Name',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Container(
                          padding: pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Blood Pressure',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Container(
                          padding: pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Pulse',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Container(
                          padding: pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'O2',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Container(
                          padding: pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Temp',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Container(
                          padding: pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'RR',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Container(
                          padding: pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Status',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                      ],
                    ),

                    // Table Data
                    ...shiftData.map(
                      (activity) => pw.TableRow(
                        children: [
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(activity['nurse_name'] ?? ''),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(activity['elderly_name'] ?? ''),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(activity['blood_pressure'] ?? '-'),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              activity['pulse_rate'] != null
                                  ? '${activity['pulse_rate']} bpm'
                                  : '-',
                            ),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              activity['oxygen_saturation'] != null
                                  ? '${activity['oxygen_saturation']}%'
                                  : '-',
                            ),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              activity['temperature'] != null
                                  ? '${activity['temperature']}°C'
                                  : '-',
                            ),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(activity['respiratory_rate'] ?? '-'),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              activity['status'] ?? '',
                              style: pw.TextStyle(
                                color:
                                    (activity['status'] ?? '').toLowerCase() ==
                                        'comp.'
                                    ? PdfColors.green
                                    : PdfColors.red,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                pw.SizedBox(height: 20),
                pw.Text(
                  'Generated on: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
              ],
            );
          },
        ),
      );
    }
  }

  /// Get medication data grouped by shift
  Future<Map<String, List<Map<String, dynamic>>>>
  _getMedicationDataGroupedByShift(String houseId) async {
    final groupedData = <String, List<Map<String, dynamic>>>{};

    try {
      final querySnapshot = await _firestore
          .collection('medication_activity_logs')
          .where('house_id', isEqualTo: houseId)
          .get();

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final timestamp = data['timestamp'] as Timestamp?;
        if (timestamp == null) continue;

        final shift = data['shift'] ?? 'Unknown';
        if (!groupedData.containsKey(shift)) {
          groupedData[shift] = [];
        }

        final action = data['action'] ?? '';
        String status = 'Unknown';
        if (action == 'complete_take') {
          status = 'Comp.';
        } else if (action == 'miss_take') {
          status = 'Miss.';
        }

        // Convert take_ordinal (0th -> 1st, 1st -> 2nd, etc.)
        String takeOrdinal = data['take_ordinal'] ?? '';
        if (takeOrdinal.isNotEmpty) {
          // Extract number from ordinal (e.g., "0th" -> 0, "1st" -> 1)
          final numberMatch = RegExp(r'(\d+)').firstMatch(takeOrdinal);
          if (numberMatch != null) {
            final number =
                int.parse(numberMatch.group(1)!) +
                1; // Add 1 since array starts at 0
            takeOrdinal = _getOrdinalFromNumber(number);
          }
        }

        groupedData[shift]!.add({
          'nurse_name': data['nurse_name'] ?? 'Unknown',
          'elderly_name': data['elderly_name'] ?? 'Unknown',
          'medication_name': data['medication_name'] ?? 'Unknown',
          'take_ordinal': takeOrdinal,
          'time': DateFormat(
            'h:mm a',
          ).format(timestamp.toDate()), // 12-hour format with AM/PM
          'status': status,
        });
      }
    } catch (e) {
      print('Error getting medication activities: $e');
    }

    return groupedData;
  }

  /// Get vitals data grouped by shift
  Future<Map<String, List<Map<String, dynamic>>>> _getVitalsDataGroupedByShift(
    String houseId,
  ) async {
    final groupedData = <String, List<Map<String, dynamic>>>{};

    try {
      final querySnapshot = await _firestore
          .collection('vital_activity_logs')
          .where('house_id', isEqualTo: houseId)
          .get();

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final timestamp = data['timestamp'] as Timestamp?;
        if (timestamp == null) continue;

        final shift = data['shift'] ?? 'Unknown';
        if (!groupedData.containsKey(shift)) {
          groupedData[shift] = [];
        }

        final actionType = data['action_type'] ?? 'vital_recorded';
        final newValues = data['new_values'] as Map<String, dynamic>? ?? {};

        String status = 'Unknown';
        if (actionType.toLowerCase().contains('completed') ||
            actionType.toLowerCase().contains('recorded')) {
          status = 'Comp.';
        } else if (actionType.toLowerCase().contains('missed')) {
          status = 'Miss.';
        }

        groupedData[shift]!.add({
          'nurse_name': data['nurse_name'] ?? 'Unknown',
          'elderly_name': data['elderly_name'] ?? 'Unknown',
          'blood_pressure': newValues['blood_pressure'],
          'pulse_rate': newValues['pulse_rate'],
          'oxygen_saturation': newValues['oxygen_saturation'],
          'temperature': newValues['temperature'],
          'respiratory_rate': newValues['respiratory_rate'],
          'status': status,
        });
      }
    } catch (e) {
      print('Error getting vital activities: $e');
    }

    return groupedData;
  }

  /// Convert number to ordinal (1 -> 1st, 2 -> 2nd, etc.)
  String _getOrdinalFromNumber(int number) {
    if (number >= 11 && number <= 13) {
      return '${number}th';
    }
    switch (number % 10) {
      case 1:
        return '${number}st';
      case 2:
        return '${number}nd';
      case 3:
        return '${number}rd';
      default:
        return '${number}th';
    }
  }
}
