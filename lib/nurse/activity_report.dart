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
      final houseQuery = await _firestore
          .collection('house')
          .where('house_id', isEqualTo: houseId)
          .limit(1)
          .get();
      String houseName = 'Unknown House';
      if (houseQuery.docs.isNotEmpty) {
        final houseData = houseQuery.docs.first.data();
        print('House doc data: $houseData');
        houseName = houseData['house_name'] ?? 'Unknown House';
        print('House name retrieved: $houseName');
      } else {
        print('No house document found with house_id: $houseId');
      }

      // Generate medication report
      await _generateMedicationReport(pdf);

      // Generate vitals report
      await _generateVitalsReport(pdf);

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
  Future<void> _generateMedicationReport(pw.Document pdf) async {
    // Get medication data grouped by house and shift
    final medicationData = await _getMedicationDataGroupedByHouseAndShift();

    for (final houseEntry in medicationData.entries) {
      final houseId = houseEntry.key;
      final houseShifts = houseEntry.value;

      // Get house name
      String houseName = 'Unknown House';
      try {
        final houseQuery = await _firestore
            .collection('house')
            .where('house_id', isEqualTo: houseId)
            .limit(1)
            .get();
        if (houseQuery.docs.isNotEmpty) {
          final houseData = houseQuery.docs.first.data();
          houseName = houseData['house_name'] ?? 'Unknown House';
        }
      } catch (e) {
        print('Error getting house name for $houseId: $e');
      }

      for (final shiftEntry in houseShifts.entries) {
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
                    width: double.infinity,
                    padding: pw.EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 5,
                    ),
                    margin: pw.EdgeInsets.only(bottom: 10),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(
                        0xFFE3F2FD,
                      ), // Light blue background
                      borderRadius: pw.BorderRadius.circular(0),
                    ),
                    child: pw.Text(
                      '$houseName - $shift Shift',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
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
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              'Elderly Name',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              'Medication',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              'Take',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              'Time',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              'Status',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
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
                              child: pw.Text(activity['take'] ?? ''),
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
                                      (activity['status'] ?? '')
                                              .toLowerCase() ==
                                          'comp.'
                                      ? PdfColors.green
                                      : PdfColors.red,
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 10,
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
  }

  /// Get vitals data grouped by house and shift
  Future<Map<String, Map<String, List<Map<String, dynamic>>>>>
  _getVitalsDataGroupedByHouseAndShift() async {
    final groupedData = <String, Map<String, List<Map<String, dynamic>>>>{};

    try {
      final querySnapshot = await _firestore
          .collection('vital_activity_logs')
          .get();

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final timestamp = data['timestamp'] as Timestamp?;
        if (timestamp == null) continue;

        final houseId = data['house_id'] ?? 'Unknown';
        final shift = data['shift'] ?? 'Unknown';

        if (!groupedData.containsKey(houseId)) {
          groupedData[houseId] = <String, List<Map<String, dynamic>>>{};
        }

        if (!groupedData[houseId]!.containsKey(shift)) {
          groupedData[houseId]![shift] = <Map<String, dynamic>>[];
        }

        final actionType = data['action_type'] ?? 'vital_recorded';
        final newValues = data['new_values'] as Map<String, dynamic>? ?? {};

        // Get nurse name and elderly name
        String nurseName = 'Unknown';
        String elderlyName = 'Unknown';

        try {
          final nurseId = data['nurse_id'] as String?;
          final elderlyId = data['elderly_id'] as String?;

          // Get nurse name
          if (nurseId != null) {
            final nurseDoc = await _firestore
                .collection('users')
                .doc(nurseId)
                .get();
            if (nurseDoc.exists) {
              final nurseData = nurseDoc.data();
              nurseName =
                  '${nurseData?['user_fname'] ?? ''} ${nurseData?['user_lname'] ?? ''}'
                      .trim();
              if (nurseName.isEmpty) nurseName = 'Unknown';
            }
          }

          // Get elderly name
          if (elderlyId != null) {
            final elderlyDoc = await _firestore
                .collection('elderly')
                .doc(elderlyId)
                .get();
            if (elderlyDoc.exists) {
              final elderlyData = elderlyDoc.data();
              elderlyName =
                  '${elderlyData?['elderly_fname'] ?? ''} ${elderlyData?['elderly_lname'] ?? ''}'
                      .trim();
              if (elderlyName.isEmpty) elderlyName = 'Unknown';
            }
          }
        } catch (e) {
          print('Error fetching names for vitals: $e');
        }

        String status = 'Unknown';
        if (actionType == 'completed' ||
            actionType == 'vital_completed' ||
            actionType == 'vitals_completed' ||
            actionType == 'vital_recorded') {
          status = 'Comp.';
        } else if (actionType == 'missed' || actionType == 'vital_missed') {
          status = 'Miss.';
        } else if (actionType == 'pending' || actionType == 'vital_pending') {
          status = 'Pending';
        }

        groupedData[houseId]![shift]!.add({
          'nurse_name': nurseName,
          'elderly_name': elderlyName,
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

  /// Generate vitals report page
  Future<void> _generateVitalsReport(pw.Document pdf) async {
    // Get vitals data grouped by house and shift
    final vitalsData = await _getVitalsDataGroupedByHouseAndShift();

    for (final houseEntry in vitalsData.entries) {
      final houseId = houseEntry.key;
      final houseShifts = houseEntry.value;

      // Get house name
      String houseName = 'Unknown House';
      try {
        final houseQuery = await _firestore
            .collection('house')
            .where('house_id', isEqualTo: houseId)
            .limit(1)
            .get();
        if (houseQuery.docs.isNotEmpty) {
          final houseData = houseQuery.docs.first.data();
          houseName = houseData['house_name'] ?? 'Unknown House';
        }
      } catch (e) {
        print('Error getting house name for $houseId: $e');
      }

      for (final shiftEntry in houseShifts.entries) {
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
                    width: double.infinity,
                    padding: pw.EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 5,
                    ),
                    margin: pw.EdgeInsets.only(bottom: 10),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(
                        0xFFE3F2FD,
                      ), // Light blue background
                      borderRadius: pw.BorderRadius.circular(0),
                    ),
                    child: pw.Text(
                      '$houseName - $shift Shift',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
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
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              'Elderly Name',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              'Blood Pressure',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              'Pulse',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              'O2',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              'Temp',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              'RR',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Container(
                            padding: pw.EdgeInsets.all(5),
                            child: pw.Text(
                              'Status',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
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
                              child: pw.Text(
                                activity['respiratory_rate'] ?? '-',
                              ),
                            ),
                            pw.Container(
                              padding: pw.EdgeInsets.all(5),
                              child: pw.Text(
                                activity['status'] ?? '',
                                style: pw.TextStyle(
                                  color: () {
                                    final status = (activity['status'] ?? '')
                                        .toLowerCase();
                                    if (status == 'comp.') {
                                      return PdfColors.green;
                                    }
                                    if (status == 'pending') {
                                      return PdfColors.orange;
                                    }
                                    return PdfColors.red;
                                  }(),
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 8,
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
  }

  /// Get medication data grouped by house and shift
  Future<Map<String, Map<String, List<Map<String, dynamic>>>>>
  _getMedicationDataGroupedByHouseAndShift() async {
    final groupedData = <String, Map<String, List<Map<String, dynamic>>>>{};

    try {
      final querySnapshot = await _firestore
          .collection('medication_activity_logs')
          .get();

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final timestamp = data['timestamp'] as Timestamp?;
        if (timestamp == null) continue;

        final houseId = data['house_id'] ?? 'Unknown';
        final shift = data['shift'] ?? 'Unknown';

        if (!groupedData.containsKey(houseId)) {
          groupedData[houseId] = <String, List<Map<String, dynamic>>>{};
        }

        if (!groupedData[houseId]!.containsKey(shift)) {
          groupedData[houseId]![shift] = <Map<String, dynamic>>[];
        }

        final action = data['action'] ?? '';

        // Get the actual status from medication_takes collection
        String status = 'Unknown';
        final medicationId = data['medication_id'] as String?;
        final takeNumber = data['take_number'] as int?;

        if (medicationId != null && takeNumber != null) {
          try {
            final takeQuery = await _firestore
                .collection('medication_takes')
                .where('medication_id', isEqualTo: medicationId)
                .where('take_number', isEqualTo: takeNumber)
                .limit(1)
                .get();

            if (takeQuery.docs.isNotEmpty) {
              final takeData = takeQuery.docs.first.data();
              final takeStatus = takeData['status'] as String?;
              if (takeStatus == 'completed') {
                status = 'Comp.';
              } else if (takeStatus == 'missed') {
                status = 'Miss.';
              } else if (takeStatus == 'pending') {
                status = 'Pending';
              }
            }
          } catch (e) {
            print(
              'Error getting take status for medication $medicationId, take $takeNumber: $e',
            );
          }
        } else {
          // Fallback to action-based status if take data not available
          if (action == 'complete_take' || action == 'take_completed') {
            status = 'Comp.';
          } else if (action == 'miss_take' || action == 'take_missed') {
            status = 'Miss.';
          }
        }

        // Get take data
        String takeOrdinal = data['take_ordinal'] ?? '';
        if (takeOrdinal.isEmpty) {
          final takeNumber = data['take_number'] as int?;
          if (takeNumber != null) {
            takeOrdinal = _getOrdinalFromNumber(takeNumber);
          }
        }

        groupedData[houseId]![shift]!.add({
          'nurse_name': data['nurse_name'] ?? 'Unknown',
          'elderly_name': data['elderly_name'] ?? 'Unknown',
          'medication_name': data['medication_name'] ?? 'Unknown',
          'take': takeOrdinal,
          'take_number': takeNumber,
          'time': DateFormat(
            'h:mm a',
          ).format(timestamp.toDate()), // 12-hour format with AM/PM
          'status': status,
        });
      }
    } catch (e) {
      print('Error getting medication activities: $e');
    }

    // Sort each house/shift's data by take number (1st take first)
    for (final houseId in groupedData.keys) {
      for (final shift in groupedData[houseId]!.keys) {
        groupedData[houseId]![shift]!.sort((a, b) {
          final aTakeNumber = a['take_number'] as int? ?? 999;
          final bTakeNumber = b['take_number'] as int? ?? 999;
          return aTakeNumber.compareTo(bTakeNumber);
        });
      }
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
