import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import '../main.dart'; // For EmergencyService

class EmergencyScreenModal extends StatelessWidget {
  final String alertId;
  final String alertDescription;
  final String alertTimestamp;
  final String houseName;
  final String caregiverName;
  final String emergencyType;
  final String additionalInfo;

  const EmergencyScreenModal({
    super.key,
    required this.alertId,
    required this.alertDescription,
    required this.alertTimestamp,
    required this.houseName,
    required this.caregiverName,
    required this.emergencyType,
    required this.additionalInfo,
  });

  @override
  Widget build(BuildContext context) {
    // Compose description: ignore literal 'no description'
    String fullDescription = '';
    final desc = alertDescription.trim();
    if (desc.isNotEmpty && desc.toLowerCase() != 'no description') {
      fullDescription = desc;
    }

    // Append only emergencyType value (no label) if not already present
    if (emergencyType.isNotEmpty) {
      final contains = fullDescription.toLowerCase().contains(
        emergencyType.toLowerCase(),
      );
      if (!contains) {
        if (fullDescription.isNotEmpty) {
          fullDescription += '\n\n$emergencyType';
        } else {
          fullDescription = emergencyType;
        }
      }
    }

    // Parse date/time from the incoming string robustly
    String datePart = alertTimestamp.trim();
    String timePart = '';

    // Prefer ' at ' split
    final atSplit = alertTimestamp.split(
      RegExp(r'\s+at\s+', caseSensitive: false),
    );
    if (atSplit.length >= 2) {
      datePart = atSplit[0].trim();
      timePart = atSplit.sublist(1).join(' at ').trim();
    } else if (alertTimestamp.contains('T')) {
      final parts = alertTimestamp.split('T');
      datePart = parts[0].trim();
      timePart = parts.length > 1 ? parts[1].trim() : '';
    } else {
      final tm = RegExp(
        r'(\d{1,2}:\d{2}(?::\d{2})?\s*[APMapm]{2})',
      ).firstMatch(alertTimestamp);
      if (tm != null) {
        timePart = tm.group(0) ?? '';
        datePart = alertTimestamp
            .replaceFirst(timePart, '')
            .replaceAll(RegExp(r'UTC.*', caseSensitive: false), '')
            .trim();
      }
    }

    // Cleanup
    timePart = timePart
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'UTC.*', caseSensitive: false), '')
        .trim();

    // Format date
    String formattedDate = datePart;
    final dateFormats = [
      DateFormat('MMMM d, yyyy'),
      DateFormat('MM/dd/yyyy'),
      DateFormat('yyyy-MM-dd'),
    ];
    for (final df in dateFormats) {
      try {
        final d = df.parse(datePart);
        // Format date with comma between day and year (e.g. "Oct. 9, 2025")
        formattedDate = DateFormat('MMM. d, yyyy').format(d);
        break;
      } catch (_) {
        // try next
      }
    }

    // Format time to 'h:mm a' if possible
    String timeStr = timePart;
    if (timePart.isNotEmpty) {
      try {
        final t = DateFormat('h:mm:ss a').parse(timePart);
        // Format without a space before AM/PM (e.g. "9:14PM") for compact UI
        timeStr = DateFormat('h:mma').format(t);
      } catch (_) {
        try {
          final t = DateFormat('h:mm a').parse(timePart);
          timeStr = DateFormat('h:mma').format(t);
        } catch (_) {
          // leave raw
          timeStr = timePart;
        }
      }
    }

    // Keep date and time on a single line for UI: "Oct. 9 2025 | 9:14PM"
    final dateTimeValue = timeStr.isNotEmpty
        ? '$formattedDate | $timeStr'
        : formattedDate;

    // Dialog width: up to 600px or 90% of screen width
    final double dialogWidth = min(
      600,
      MediaQuery.of(context).size.width * 0.9,
    );

    return AlertDialog(
      backgroundColor: Colors.white,
      title: Column(
        children: const [
          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 50),
          SizedBox(height: 5),
          Text(
            'Emergency Alert',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF00588e),
              fontSize: 25,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),

            // House
            _InfoRow(icon: Icons.home, label: 'House', value: houseName),
            const SizedBox(height: 5),

            // Date & Time
            _InfoRow(
              icon: Icons.calendar_today,
              label: 'Date & Time',
              value: dateTimeValue,
              forceValueOnNewLine: true,
            ),
            const SizedBox(height: 5),

            // Reporting Caregiver (force value to next row)
            _InfoRow(
              icon: Icons.person,
              label: 'Reporting Caregiver',
              value: caregiverName,
              forceValueOnNewLine: true,
            ),
            const SizedBox(height: 10),

            // Description label + blue box
            Row(
              children: const [
                Icon(Icons.description, color: Color(0xFF00588e), size: 25),
                SizedBox(width: 8),
                Text(
                  'Description:',
                  style: TextStyle(
                    color: Color(0xFF00588e),
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 205, 227, 246),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                fullDescription.isNotEmpty ? fullDescription : 'No description',
                textAlign: TextAlign.justify,
                style: const TextStyle(color: Colors.black, fontSize: 16),
              ),
            ),
            const SizedBox(height: 10),

            // Additional Info (only show if not empty)
            if (additionalInfo.isNotEmpty) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.info, color: Color(0xFF00588e), size: 25),
                      SizedBox(width: 8),
                      Text(
                        'Additional Information:',
                        style: TextStyle(
                          color: Color(0xFF00588e),
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 205, 227, 246),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      additionalInfo,
                      textAlign: TextAlign.justify,
                      style: const TextStyle(color: Colors.black, fontSize: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00588e),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
          ),
          onPressed: () async {
            try {
              await FirebaseFirestore.instance
                  .collection('emergency_alert')
                  .doc(alertId)
                  .update({'alert_viewed': true});
            } catch (e) {
              // ignore
            }

            EmergencyService.stopAlarm();
            Navigator.of(context).pop();
          },
          child: const Text(
            'Mark as Viewed',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

// Custom widget for House / Date / Caregiver rows
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool forceValueOnNewLine;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.forceValueOnNewLine = false,
  });

  @override
  Widget build(BuildContext context) {
    // Split value into lines so the first line stays next to the label and
    // any additional lines (like time) appear below, aligned under the value.
    final lines = value.split('\n');
    final firstLine = lines.isNotEmpty ? lines.first : '';
    final remaining = lines.length > 1 ? lines.sublist(1) : <String>[];

    const labelStyle = TextStyle(
      color: Color(0xFF00588e),
      fontWeight: FontWeight.w600,
      fontSize: 16,
    );

    // If the caller wants the value forced to the next row, render the
    // label on its own line and then the value lines below (left-aligned).
    if (forceValueOnNewLine) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF00588e), size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label on its own row
                IntrinsicWidth(child: Text('$label:', style: labelStyle)),
                const SizedBox(height: 6),
                // Value lines below
                for (final line in lines) ...[
                  Text(
                    line,
                    style: const TextStyle(color: Colors.black, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF00588e), size: 28),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Keep label intrinsic-width so it only uses the space it needs
              IntrinsicWidth(child: Text('$label:', style: labelStyle)),
              const SizedBox(width: 6),
              // Value column: first line next to label, remaining lines below
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      firstLine,
                      style: const TextStyle(color: Colors.black, fontSize: 16),
                    ),
                    for (final line in remaining) ...[
                      const SizedBox(height: 4),
                      Text(
                        line,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
