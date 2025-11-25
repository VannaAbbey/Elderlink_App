// lib/nurse/medication_management_layout.dart
import 'package:flutter/material.dart';
import 'package:elderlink_app/services/ai_prescription_scanner_service.dart';
import 'medication_upcoming.dart';
import 'medication_completed.dart';
import 'medication_missed.dart';
import 'nurse_sidebar.dart';
import '../widgets/nurse_widgets/nurse_notification_icon_button.dart';
import 'package:image_picker/image_picker.dart';
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
      // Use maximum quality and resolution for better handwriting recognition
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100, // Maximum quality (0-100)
        maxWidth: 2400, // Higher resolution for text detail
        maxHeight: 2400,
        preferredCameraDevice:
            CameraDevice.rear, // Back camera is usually better
      );

      if (image == null) return;

      // Show loading dialog with System processing message
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  'System is analyzing prescription...\nExtracting medication details',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      );

      // Use AI-powered prescription scanner
      final aiScanner = AIPrescriptionScannerService();
      final extractedData = await aiScanner.scanPrescription(File(image.path));

      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      // Check if there's an error message
      if (extractedData.containsKey('error')) {
        final errorMsg = extractedData['error'] as String;
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('📸 Camera Tips'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(errorMsg),
                  const SizedBox(height: 16),
                  const Text(
                    '💡 Tips for better results:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('• Write clearly with DARK pen (black/blue)'),
                  const Text('• Use LARGE letters (at least 1cm tall)'),
                  const Text('• Take photo in BRIGHT light'),
                  const Text('• Hold camera STEADY and close'),
                  const Text('• Make sure text is IN FOCUS'),
                  const Text('• Write on WHITE paper for best contrast'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Try Again'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Show confidence level if available
      final confidence = extractedData['confidence'] ?? 0.0;
      print(
        'System Extraction Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
      );

      // Show the add medication dialog with AI-extracted data
      if (context.mounted) {
        _showScannedMedicationDialog(context, extractedData);
      }
    } catch (e) {
      // Close loading dialog if open
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning prescription: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

    // Get AI confidence score
    final confidence = extractedData['confidence'] as double? ?? 0.0;
    final confidencePercent = (confidence * 100).toStringAsFixed(0);

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
                      "Scanned Medication",
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
                const SizedBox(height: 8),

                // AI Confidence Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: confidence >= 0.7
                        ? Colors.green.shade50
                        : confidence >= 0.4
                        ? Colors.orange.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: confidence >= 0.7
                          ? Colors.green
                          : confidence >= 0.4
                          ? Colors.orange
                          : Colors.red,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        confidence >= 0.7
                            ? Icons.check_circle
                            : confidence >= 0.4
                            ? Icons.info
                            : Icons.warning,
                        size: 16,
                        color: confidence >= 0.7
                            ? Colors.green
                            : confidence >= 0.4
                            ? Colors.orange
                            : Colors.red,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'System Confidence: $confidencePercent%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: confidence >= 0.7
                              ? Colors.green.shade700
                              : confidence >= 0.4
                              ? Colors.orange.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '🤖 System has scanned the prescription. Please review and complete the details:',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                  textAlign: TextAlign.center,
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
                    hintText: "e.g., Daily, Once, Every 3 days, Every 4 days",
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
                          const NurseNotificationIconButton(),
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
