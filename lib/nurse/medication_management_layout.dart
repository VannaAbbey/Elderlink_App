// lib/nurse/medication_management_layout.dart
import 'package:flutter/material.dart';
import 'medication_upcoming.dart';
import 'medication_completed.dart';
import 'medication_missed.dart';
import 'nurse_sidebar.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';

class MedicationManagementLayout extends StatefulWidget {
  final String search;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback toggleSidebar;
  final bool isSidebarOpen;
  final String? nurseName;
  final Map<String, String> houseDescriptions;
  final Future<List<Map<String, dynamic>>> Function() fetchHouses;
  final Future<List<Map<String, dynamic>>> Function(String houseId)
  fetchElderlies;
  final String? selectedHouseId;
  final ValueChanged<String?> onHouseSelected;
  final VoidCallback? onBellPressed;
  final ScrollController tabScrollController;
  final void Function(int index, List<Map<String, dynamic>> houses)
  scrollToCenter;

  const MedicationManagementLayout({
    super.key,
    required this.search,
    required this.onSearchChanged,
    required this.toggleSidebar,
    required this.isSidebarOpen,
    required this.nurseName,
    required this.houseDescriptions,
    required this.fetchHouses,
    required this.fetchElderlies,
    required this.selectedHouseId,
    required this.onHouseSelected,
    this.onBellPressed,
    required this.tabScrollController,
    required this.scrollToCenter,
  });

  @override
  State<MedicationManagementLayout> createState() =>
      _MedicationManagementLayoutState();
}

class _MedicationManagementLayoutState extends State<MedicationManagementLayout>
    with TickerProviderStateMixin {
  final Map<String, int> _houseCounts = {};
  late TabController _medicationTabController;
  int _selectedMedicationTabIndex = 0;
  List<Map<String, dynamic>> _elderlyList = [];
  String? _selectedElderlyId;

  Widget _buildUpcomingTabWithCount(Map<String, dynamic> house, bool selected) {
    final count = _houseCounts[house['house_id']] ?? 0;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Text(
          'Upcoming',
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF00588e),
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        if (count > 0)
          Positioned(
            right: -8,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _medicationTabController = TabController(length: 3, vsync: this);
    _medicationTabController.addListener(_handleTabChange);
    // Initialize the selected index
    _selectedMedicationTabIndex = _medicationTabController.index;
  }

  @override
  void dispose() {
    _medicationTabController.removeListener(_handleTabChange);
    _medicationTabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    // Use addPostFrameCallback to ensure UI updates immediately after the frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _selectedMedicationTabIndex != _medicationTabController.index) {
        setState(() {
          _selectedMedicationTabIndex = _medicationTabController.index;
        });
      }
    });
  }

  Future<void> _scanPrescription(BuildContext context) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.camera);

      if (image == null) return;

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Processing prescription...'),
            ],
          ),
        ),
      );

      // Process the image with ML Kit
      final inputImage = InputImage.fromFile(File(image.path));
      final textRecognizer = TextRecognizer();
      final recognisedText = await textRecognizer.processImage(inputImage);

      // Close loading dialog
      Navigator.of(context).pop();

      // Parse the extracted text
      final extractedData = _parsePrescriptionText(recognisedText.text);

      // Show the add medication dialog with pre-filled data
      _showScannedMedicationDialog(context, extractedData);
    } catch (e) {
      // Close loading dialog if open
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error scanning prescription: $e')),
      );
    }
  }

  String _extractMedicationName(String lowerText) {
    // List of potential medication names with confidence scores
    final candidates = <Map<String, dynamic>>[];

    // Common medication name patterns with different confidence levels
    final patterns = [
      // High confidence: Explicit labels
      {
        'pattern': RegExp(
          r'(?:medication|drug|medicine|med)[:.\s]*([^\n\r]{3,50})',
          caseSensitive: false,
        ),
        'confidence': 0.95,
        'type': 'explicit_label',
      },
      {
        'pattern': RegExp(
          r'(?:name|drug name)[:.\s]*([^\n\r]{3,50})',
          caseSensitive: false,
        ),
        'confidence': 0.95,
        'type': 'name_label',
      },
      {
        'pattern': RegExp(r'rx[:.\s]*([^\n\r]{3,50})', caseSensitive: false),
        'confidence': 0.9,
        'type': 'rx_label',
      },

      // Medium-high confidence: Common medication structures with specific patterns
      {
        'pattern': RegExp(
          r'\b([A-Z][a-z]{3,}(?:\s+[A-Z][a-z]{3,})+(?:\s+dihydrochloride|hydrochloride|sulfate|acetate|citrate|succinate|tartrate|phosphate|chloride|oxide)?)\b',
          caseSensitive: false,
        ),
        'confidence': 0.85,
        'type': 'complex_medication',
      },
      {
        'pattern': RegExp(
          r'^([A-Z][a-z]{2,}\s+[A-Z][a-z]{2,}(?:\s+[A-Z][a-z]{2,})*)',
          multiLine: true,
        ),
        'confidence': 0.8,
        'type': 'capitalized_start',
      },

      // Medium confidence: Common medication suffixes with full names
      {
        'pattern': RegExp(
          r'\b([A-Z][a-z]{2,}(?:acin|adol|afen|aine|arin|avir|azol|bital|cin|cillin|cycline|dazole|dipine|done|fen|fenac|fibrate|fil|formin|fungin|glitazone|ide|ipine|iramine|lamide|last|line|lol|mab|micin|mide|mustine|nazole|olol|onide|oprazole|oxin|perazine|pril|quine|ridone|sartan|semide|setron|statin|sulf|terol|thiazide|tidine|triptan|vastatin|vir|vudine|zine|zolid))\b',
          caseSensitive: false,
        ),
        'confidence': 0.7,
        'type': 'medication_suffix',
      },

      // Lower confidence: Generic patterns (but improved)
      {
        'pattern': RegExp(
          r'\b([A-Z][a-z]{4,}(?:\s+[A-Z][a-z]{3,})*)\b',
          caseSensitive: false,
        ),
        'confidence': 0.5,
        'type': 'generic_pattern',
      },
    ];

    // Extract candidates from all patterns
    for (final patternData in patterns) {
      final pattern = patternData['pattern'] as RegExp;
      final confidence = patternData['confidence'] as double;
      final type = patternData['type'] as String;

      final matches = pattern.allMatches(lowerText);
      for (final match in matches) {
        if (match.groupCount >= 1) {
          final candidate = match.group(1)!.trim();

          // Skip if too short or contains numbers/digits (likely dosage)
          if (candidate.length < 3 || RegExp(r'\d').hasMatch(candidate)) {
            continue;
          }

          // Skip common non-medication words
          final skipWords = [
            'take',
            'with',
            'food',
            'water',
            'daily',
            'weekly',
            'monthly',
            'morning',
            'afternoon',
            'evening',
            'night',
            'before',
            'after',
            'meals',
            'breakfast',
            'lunch',
            'dinner',
            'bedtime',
            'hours',
            'minutes',
            'times',
            'days',
            'weeks',
            'months',
            'tablets',
            'capsules',
            'pills',
            'drops',
            'injection',
            'cream',
            'ointment',
            'solution',
            'suspension',
            'syrup',
            'powder',
            'doctor',
            'patient',
            'prescription',
            'pharmacy',
            'directions',
            'refills',
            'quantity',
            'dispense',
            'sig',
            'label',
            'notes',
            'date',
            'signature',
            'tablet',
            'coated',
            'enteric',
            'sustained',
            'release',
            'extended',
            'immediate',
            'film',
            'sugar',
            'chewable',
            'oral',
            'topical',
            'nasal',
            'inhalation',
            'rectal',
            'vaginal',
            'ophthalmic',
            'otic',
            'transdermal',
            'injectable',
            'intravenous',
            'intramuscular',
            'subcutaneous',
            'epidural',
            'spinal',
            'dose',
            'doses',
            'amount',
            'strength',
            'concentration',
            'volume',
            'weight',
            'each',
            'every',
            'as',
            'needed',
            'prn',
            'and',
            'or',
            'for',
            'the',
            'use',
            'only',
            'disp',
            'refill',
            'no',
            'substitutions',
            'generic',
            'brand',
            'may',
            'cause',
            'drowsiness',
            'dizziness',
            'nausea',
            'headache',
            'consult',
            'physician',
            'pharmacist',
            'if',
            'you',
            'have',
            'questions',
            'about',
            'this',
            'medication',
            'call',
            'your',
            'healthcare',
            'provider',
            'store',
            'at',
            'room',
            'temperature',
            'protect',
            'from',
            'light',
            'keep',
            'out',
            'of',
            'reach',
            'children',
            'poison',
            'control',
            'emergency',
            'number',
          ];

          // Skip if candidate contains any skip words
          if (skipWords.any((word) => candidate.toLowerCase().contains(word))) {
            continue;
          }

          // Skip if candidate is just a single common word
          final commonSingleWords = [
            'aspirin',
            'ibuprofen',
            'acetaminophen',
            'tylenol',
            'advil',
            'motrin',
            'aleve',
            'naproxen',
            'vitamin',
            'supplement',
            'ointment',
            'cream',
            'gel',
            'lotion',
            'spray',
            'drops',
            'syrup',
            'elixir',
            'tincture',
            'extract',
            'powder',
            'granules',
          ];

          if (candidate.split(' ').length == 1 &&
              commonSingleWords.contains(candidate.toLowerCase())) {
            continue;
          }

          // Calculate adjusted confidence based on various factors
          double adjustedConfidence = confidence;

          // Boost confidence for certain patterns
          if (candidate.contains(' ')) {
            adjustedConfidence += 0.15; // Multi-word names
          }
          if (candidate.length > 8) adjustedConfidence += 0.1; // Longer names
          if (candidate.length > 15) {
            adjustedConfidence += 0.05; // Very long names
          }
          if (RegExp(r'[A-Z]').hasMatch(candidate)) {
            adjustedConfidence += 0.05; // Proper capitalization
          }
          if (candidate.contains('hydrochloride') ||
              candidate.contains('dihydrochloride')) {
            adjustedConfidence += 0.2; // Common medication salt forms
          }
          if (candidate.split(' ').length >= 2) {
            adjustedConfidence += 0.1; // Multi-word
          }

          // Reduce confidence for very generic or short words
          if (candidate.length <= 5) adjustedConfidence -= 0.3;
          if (candidate.length <= 8) adjustedConfidence -= 0.1;

          // Additional penalty for candidates that look like instructions
          if (candidate.toLowerCase().startsWith('take') ||
              candidate.toLowerCase().startsWith('give') ||
              candidate.toLowerCase().contains('times a day') ||
              candidate.toLowerCase().contains('by mouth')) {
            adjustedConfidence -= 0.5;
          }

          candidates.add({
            'name': candidate,
            'confidence': adjustedConfidence.clamp(0.0, 1.0),
            'type': type,
            'position': match.start,
          });
        }
      }
    }

    // Sort candidates by confidence (highest first), then by position (earliest first)
    candidates.sort((a, b) {
      final confCompare = (b['confidence'] as double).compareTo(
        a['confidence'] as double,
      );
      if (confCompare != 0) return confCompare;
      return (a['position'] as int).compareTo(b['position'] as int);
    });

    // Debug logging (remove in production)
    if (candidates.isNotEmpty) {
      print('Medication candidates found:');
      for (var candidate in candidates.take(3)) {
        print(
          '  ${candidate['name']} (confidence: ${candidate['confidence']}, type: ${candidate['type']})',
        );
      }
    }

    // Return the highest confidence candidate, or empty string if none found
    return candidates.isNotEmpty ? candidates.first['name'] as String : '';
  }

  Map<String, dynamic> _parsePrescriptionText(String text) {
    // Initialize default values
    String medicationName = '';
    String dosage = '';
    String repeatInterval = 'Daily'; // Default to daily
    String numberOfIntakes = ''; // e.g., "7 days", "30 tablets"
    List<TimeOfDay> times = [];

    // Convert to lowercase for easier matching
    final lowerText = text.toLowerCase();

    // Enhanced medication name detection with intelligent scoring
    medicationName = _extractMedicationName(lowerText);

    // Dosage patterns - improved
    final dosagePatterns = [
      RegExp(
        r'(?:dosage|dose|amount|strength):\s*([^\n\r]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'(\d+(?:\.\d+)?\s*(?:mg|g|ml|mcg|units?|tablets?|capsules?|pills?))',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:take|give)\s+(\d+(?:\.\d+)?\s*(?:mg|g|ml|mcg|units?|tablets?|capsules?|pills?))',
        caseSensitive: false,
      ),
    ];

    for (final pattern in dosagePatterns) {
      final match = pattern.firstMatch(lowerText);
      if (match != null && match.groupCount >= 1) {
        dosage = match.group(1)!.trim();
        break;
      }
    }

    // Repeat interval patterns
    final intervalPatterns = [
      RegExp(r'(?:every|q)\s*(\d+)\s*(?:hours?|hrs?)', caseSensitive: false),
      RegExp(
        r'(?:twice|three\s+times|four\s+times)\s+(?:a|daily|day)',
        caseSensitive: false,
      ),
      RegExp(r'(?:bid|tid|qid|qd)', caseSensitive: false),
      RegExp(r'(?:daily|once\s+daily|every\s+day)', caseSensitive: false),
      RegExp(r'(?:weekly|every\s+week)', caseSensitive: false),
      RegExp(r'(?:monthly|every\s+month)', caseSensitive: false),
    ];

    for (final pattern in intervalPatterns) {
      final match = pattern.firstMatch(lowerText);
      if (match != null) {
        if (pattern.pattern.contains('hours') ||
            pattern.pattern.contains('hrs')) {
          final hours = match.group(1);
          repeatInterval = 'Every $hours hours';
        } else if (pattern.pattern.contains('bid')) {
          repeatInterval = 'Twice daily';
        } else if (pattern.pattern.contains('tid')) {
          repeatInterval = 'Three times daily';
        } else if (pattern.pattern.contains('qid')) {
          repeatInterval = 'Four times daily';
        } else if (pattern.pattern.contains('qd')) {
          repeatInterval = 'Once daily';
        } else if (pattern.pattern.contains('twice')) {
          repeatInterval = 'Twice daily';
        } else if (pattern.pattern.contains('three times')) {
          repeatInterval = 'Three times daily';
        } else if (pattern.pattern.contains('four times')) {
          repeatInterval = 'Four times daily';
        } else if (pattern.pattern.contains('daily')) {
          repeatInterval = 'Daily';
        } else if (pattern.pattern.contains('weekly')) {
          repeatInterval = 'Weekly';
        } else if (pattern.pattern.contains('monthly')) {
          repeatInterval = 'Monthly';
        }
        break;
      }
    }

    // Number of intakes patterns (duration or quantity)
    final intakePatterns = [
      RegExp(
        r'(?:for|duration|course|period)(?:\s+of)?\s*(\d+)\s*(?:days?|weeks?|months?)',
        caseSensitive: false,
      ),
      RegExp(
        r'(\d+)\s*(?:tablets?|capsules?|pills?|doses?)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:quantity|qty|total)(?:\s*[:.]?\s*)(\d+)',
        caseSensitive: false,
      ),
      RegExp(
        r'(\d+)\s*(?:days?|weeks?|months?)\s+(?:supply|course)',
        caseSensitive: false,
      ),
    ];

    for (final pattern in intakePatterns) {
      final match = pattern.firstMatch(lowerText);
      if (match != null && match.groupCount >= 1) {
        final value = match.group(1)!;
        if (pattern.pattern.contains('days?')) {
          numberOfIntakes = '$value days';
        } else if (pattern.pattern.contains('weeks?')) {
          numberOfIntakes = '$value weeks';
        } else if (pattern.pattern.contains('months?')) {
          numberOfIntakes = '$value months';
        } else if (pattern.pattern.contains(
          'tablets?|capsules?|pills?|doses?',
        )) {
          numberOfIntakes = '$value tablets';
        } else {
          numberOfIntakes = match.group(0)!;
        }
        break;
      }
    }

    // Time patterns - improved
    final timePatterns = [
      RegExp(
        r'(\d{1,2}):(\d{2})\s*(?:am|pm|a\.m\.|p\.m\.)?',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:at|time)\s*(\d{1,2}):(\d{2})\s*(?:am|pm|a\.m\.|p\.m\.)?',
        caseSensitive: false,
      ),
      RegExp(r'(?:time|times?|frequency):\s*([^\n\r]+)', caseSensitive: false),
    ];

    for (final pattern in timePatterns) {
      final matches = pattern.allMatches(lowerText);
      for (final match in matches) {
        if (match.groupCount >= 2 && match.group(1) != null) {
          final hour = int.tryParse(match.group(1)!);
          final minute = int.tryParse(match.group(2) ?? '0');
          if (hour != null && minute != null && hour >= 0 && hour <= 23) {
            times.add(TimeOfDay(hour: hour, minute: minute));
          }
        }
      }
    }

    // If no specific times found, try to infer common frequencies
    if (times.isEmpty) {
      if (lowerText.contains('twice') ||
          lowerText.contains('2x') ||
          lowerText.contains('bid')) {
        times.addAll([
          const TimeOfDay(hour: 9, minute: 0),
          const TimeOfDay(hour: 21, minute: 0),
        ]);
      } else if (lowerText.contains('three') ||
          lowerText.contains('3x') ||
          lowerText.contains('tid')) {
        times.addAll([
          const TimeOfDay(hour: 9, minute: 0),
          const TimeOfDay(hour: 14, minute: 0),
          const TimeOfDay(hour: 21, minute: 0),
        ]);
      } else if (lowerText.contains('four') ||
          lowerText.contains('4x') ||
          lowerText.contains('qid')) {
        times.addAll([
          const TimeOfDay(hour: 9, minute: 0),
          const TimeOfDay(hour: 12, minute: 0),
          const TimeOfDay(hour: 17, minute: 0),
          const TimeOfDay(hour: 21, minute: 0),
        ]);
      } else {
        // Default to once daily at 9 AM
        times.add(const TimeOfDay(hour: 9, minute: 0));
      }
    }

    return {
      'medicationName': medicationName,
      'dosage': dosage,
      'repeatInterval': repeatInterval,
      'numberOfIntakes': numberOfIntakes,
      'times': times,
    };
  }

  void _showScannedMedicationDialog(
    BuildContext context,
    Map<String, dynamic> extractedData,
  ) async {
    // Fetch elderly list for the current house
    if (widget.selectedHouseId != null) {
      try {
        _elderlyList = await widget.fetchElderlies(widget.selectedHouseId!);
      } catch (e) {
        _elderlyList = [];
      }
    }

    final TextEditingController nameController = TextEditingController(
      text: extractedData['medicationName'],
    );
    final TextEditingController dosageController = TextEditingController(
      text: extractedData['dosage'],
    );
    final TextEditingController repeatIntervalController =
        TextEditingController(text: extractedData['repeatInterval']);
    final TextEditingController numberOfIntakesController =
        TextEditingController(text: extractedData['numberOfIntakes']);
    List<TimeOfDay> medTimes = List.from(extractedData['times']);
    String? selectedElderlyId = _selectedElderlyId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Add Scanned Medication",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00588E),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Please review and adjust the scanned information:',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 12),

                // Elderly Selection Dropdown
                DropdownButtonFormField<String>(
                  value: selectedElderlyId,
                  decoration: const InputDecoration(
                    labelText: "Select Elderly *",
                    border: OutlineInputBorder(),
                  ),
                  items: _elderlyList.map((elderly) {
                    return DropdownMenuItem<String>(
                      value: elderly['elderly_id'],
                      child: Text(elderly['name'] ?? 'Unknown'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedElderlyId = value);
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please select an elderly';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: "Medication Name *",
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter medication name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: dosageController,
                  decoration: const InputDecoration(
                    labelText: "Dosage *",
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter dosage';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: repeatIntervalController,
                  decoration: const InputDecoration(
                    labelText: "Repeat Interval",
                    border: OutlineInputBorder(),
                    hintText: "e.g., Daily, Twice daily, Every 8 hours",
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: numberOfIntakesController,
                  decoration: const InputDecoration(
                    labelText: "Number of Intakes/Duration",
                    border: OutlineInputBorder(),
                    hintText: "e.g., 7 days, 30 tablets",
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Medication Times:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Column(
                  children: [
                    for (int i = 0; i < medTimes.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Text("Take ${i + 1}:"),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  final TimeOfDay? picked =
                                      await showTimePicker(
                                        context: context,
                                        initialTime: medTimes[i],
                                      );
                                  if (picked != null) {
                                    setState(() => medTimes[i] = picked);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(medTimes[i].format(context)),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  setState(() => medTimes.removeAt(i)),
                              icon: const Icon(Icons.delete, color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => medTimes.add(const TimeOfDay(hour: 9, minute: 0)),
                    ),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text(
                      "Add Time",
                      style: TextStyle(color: Colors.white),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFF00588E),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      // Validate required fields
                      if (selectedElderlyId == null ||
                          selectedElderlyId!.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please select an elderly'),
                          ),
                        );
                        return;
                      }
                      if (nameController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter medication name'),
                          ),
                        );
                        return;
                      }
                      if (dosageController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter dosage')),
                        );
                        return;
                      }

                      // Here you would save the medication data
                      // For now, just show a success message
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Medication "${nameController.text}" added successfully for selected elderly!',
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00588E),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: const Text(
                      "Save Medication",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Get stream for upcoming medications count
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/background1.png',
              fit: BoxFit.cover,
            ),
          ),

          // Main Content
          SafeArea(
            child: Column(
              children: [
                // Header Row
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: widget.toggleSidebar,
                        child: const Icon(
                          Icons.menu,
                          size: 30,
                          color: Color(0xFF00588E),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Medication Management",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF00588E),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.camera_alt,
                              color: Color(0xFF00588E),
                            ),
                            iconSize: 30,
                            onPressed: () => _scanPrescription(context),
                            tooltip: 'Scan Prescription',
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.notifications,
                              color: Color(0xFF00588E),
                            ),
                            iconSize: 30,
                            onPressed: widget.onBellPressed,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: widget.fetchHouses(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final houses = snapshot.data!;
                      return DefaultTabController(
                        length: houses.length,
                        child: RefreshIndicator(
                          onRefresh: () async {
                            // Trigger refresh by rebuilding the widget
                            setState(() {});
                          },
                          child: Column(
                            children: [
                              // 🩶 House Tabs — fixed divider + auto-scroll center
                              Stack(
                                children: [
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      height: 1,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                  SingleChildScrollView(
                                    controller: widget.tabScrollController,
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    child: Transform.translate(
                                      offset: const Offset(-32, 0),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minWidth:
                                              MediaQuery.of(
                                                context,
                                              ).size.width +
                                              64, // extended right side
                                        ),
                                        child: Material(
                                          color: Colors.white,
                                          child: TabBar(
                                            isScrollable: true,
                                            labelColor: const Color(0xFF00588E),
                                            unselectedLabelColor: Colors.grey,
                                            indicator:
                                                const UnderlineTabIndicator(
                                                  borderSide: BorderSide(
                                                    color: Color(0xFF00588E),
                                                    width: 3,
                                                  ),
                                                  insets: EdgeInsets.symmetric(
                                                    horizontal: -20,
                                                  ),
                                                ),
                                            labelPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 20,
                                                ),
                                            physics:
                                                const BouncingScrollPhysics(),
                                            onTap: (index) {
                                              WidgetsBinding.instance
                                                  .addPostFrameCallback((_) {
                                                    widget.scrollToCenter(
                                                      index,
                                                      snapshot.data!,
                                                    );
                                                  });
                                            },
                                            tabs: houses.map((house) {
                                              return Tab(
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                      child: Image.asset(
                                                        'assets/houses_img/${house['house_name']}.png',
                                                        width: 24,
                                                        height: 24,
                                                        errorBuilder:
                                                            (
                                                              context,
                                                              error,
                                                              stackTrace,
                                                            ) {
                                                              return const Icon(
                                                                Icons.home,
                                                              );
                                                            },
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      house['house_name'] ?? '',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              // House Content
                              Expanded(
                                child: TabBarView(
                                  children: houses.map((house) {
                                    return Column(
                                      children: [
                                        // Medication Status Tabs - Copy layout from caregiver add_task.dart
                                        Container(
                                          width: double.infinity,
                                          color: const Color(0xFFE6F3FA),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                            horizontal: 16,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceEvenly,
                                            children: List.generate(3, (index) {
                                              final bool selected =
                                                  _selectedMedicationTabIndex ==
                                                  index;
                                              final List<String> tabLabels = [
                                                'Upcoming',
                                                'Completed',
                                                'Missed',
                                              ];
                                              return Expanded(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 4.0,
                                                      ),
                                                  child: GestureDetector(
                                                    onTap: () {
                                                      setState(() {
                                                        _selectedMedicationTabIndex =
                                                            index;
                                                      });
                                                      _medicationTabController
                                                          .animateTo(
                                                            index,
                                                            duration:
                                                                Duration.zero,
                                                          );
                                                    },
                                                    child: Container(
                                                      constraints:
                                                          BoxConstraints(
                                                            minWidth: 120,
                                                          ),
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 8,
                                                          ),
                                                      decoration: selected
                                                          ? BoxDecoration(
                                                              color:
                                                                  const Color(
                                                                    0xFF00588e,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    20,
                                                                  ),
                                                            )
                                                          : null,
                                                      child: index == 0
                                                          ? _buildUpcomingTabWithCount(
                                                              house,
                                                              selected,
                                                            )
                                                          : Text(
                                                              tabLabels[index],
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                color: selected
                                                                    ? Colors
                                                                          .white
                                                                    : const Color(
                                                                        0xFF00588e,
                                                                      ),
                                                                fontWeight:
                                                                    selected
                                                                    ? FontWeight
                                                                          .bold
                                                                    : FontWeight
                                                                          .normal,
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }),
                                          ),
                                        ), // Medication Content
                                        Expanded(
                                          child: TabBarView(
                                            controller:
                                                _medicationTabController,
                                            physics: const PageScrollPhysics(),
                                            children: [
                                              UpcomingMedicationsTab(
                                                houseId: house['house_id'],
                                                nurseName: widget.nurseName,
                                                onCountChanged: (count) {
                                                  setState(() {
                                                    _houseCounts[house['house_id']] =
                                                        count;
                                                  });
                                                },
                                              ),
                                              CompletedMedicationsTab(
                                                houseId: house['house_id'],
                                                nurseName: widget.nurseName,
                                              ),
                                              MissedMedicationsTab(
                                                houseId: house['house_id'],
                                                nurseName: widget.nurseName,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Sidebar overlay
          if (widget.isSidebarOpen)
            NurseSidebar(
              isSidebarOpen: widget.isSidebarOpen,
              toggleSidebar: widget.toggleSidebar,
              parentContext: context,
            ),
        ],
      ),
    );
  }
}
