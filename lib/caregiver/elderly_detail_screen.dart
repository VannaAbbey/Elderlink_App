import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ElderlyDetailScreen extends StatelessWidget {
  final Map<String, dynamic> elderlyData;

  const ElderlyDetailScreen({super.key, required this.elderlyData});

  @override
  Widget build(BuildContext context) {
    print('DEBUG ElderlyDetailScreen: Received elderly data: $elderlyData');
    print('DEBUG ElderlyDetailScreen: Available keys: ${elderlyData.keys.toList()}');
    
    final profilePic = elderlyData['profile_pic'] as String?;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/background1.png',
              fit: BoxFit.cover,
            ),
          ),
          // Content
          SafeArea(
            child: Column(
              children: [
                // Custom App Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Color(0xFF00588e), size: 28),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Expanded(
                        child: Text(
                          'Elderly Information',
                          style: TextStyle(
                            color: Color(0xFF00588e),
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 48), // Balance the back button
                    ],
                  ),
                ),
                // Main Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Profile Picture
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(80),
                            child: profilePic != null && profilePic.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: profilePic,
                                    width: 160,
                                    height: 160,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      width: 160,
                                      height: 160,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[300],
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.person,
                                        color: Colors.grey,
                                        size: 80,
                                      ),
                                    ),
                                    errorWidget: (context, url, error) => Container(
                                      width: 160,
                                      height: 160,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                      ),
                                      child: ClipOval(
                                        child: Image.asset(
                                          'assets/images/people_icon.png',
                                          width: 160,
                                          height: 160,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 160,
                                    height: 160,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                    child: ClipOval(
                                      child: Image.asset(
                                        'assets/images/people_icon.png',
                                        width: 160,
                                        height: 160,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Name
                        Text(
                          _getElderlyName(),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00588e),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        
                        // Information Cards - Different fields for Alive vs Deceased
                        ..._buildInformationCards(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildInformationCards() {
    final status = elderlyData['elderly_status'] ?? elderlyData['status'];
    final isAlive = status == 'Alive' || status == 'alive';
    
    List<Widget> cards = [];
    
    // Common fields for both alive and deceased
    cards.addAll([
      // Testing field - will be removed upon deployment
      _buildInfoCard(
        icon: Icons.fingerprint,
        title: 'Elderly ID (Testing)',
        content: elderlyData['elderly_id'] ?? 'Not specified',
      ),
      const SizedBox(height: 16),
      
      _buildInfoCard(
        icon: Icons.person,
        title: 'Full Name',
        content: _getElderlyName(),
      ),
      const SizedBox(height: 16),
      
      _buildInfoCard(
        icon: Icons.cake,
        title: 'Birthday',
        content: (elderlyData['elderly_bday'] ?? elderlyData['birthdate']) != null 
            ? _formatDate(elderlyData['elderly_bday'] ?? elderlyData['birthdate'])
            : 'Not specified',
      ),
      const SizedBox(height: 16),
      
      _buildInfoCard(
        icon: Icons.wc,
        title: 'Gender',
        content: elderlyData['elderly_sex'] ?? elderlyData['sex'] ?? elderlyData['gender'] ?? 'Not specified',
      ),
      const SizedBox(height: 16),
    ]);
    
    if (isAlive) {
      // Additional fields for alive elderly
      cards.addAll([
        _buildInfoCard(
          icon: Icons.numbers,
          title: 'Age',
          content: elderlyData['elderly_age']?.toString() ?? 'Not specified',
        ),
        const SizedBox(height: 16),
        
        _buildInfoCard(
          icon: Icons.home,
          title: 'House Allocation',
          content: elderlyData['house_name'] ?? 'Not specified',
        ),
        const SizedBox(height: 16),
        
        _buildInfoCard(
          icon: Icons.accessible,
          title: 'Mobility Status',
          content: elderlyData['elderly_mobilityStatus'] ?? 'Not specified',
        ),
        const SizedBox(height: 16),
        
        _buildInfoCard(
          icon: Icons.restaurant,
          title: 'Dietary Notes',
          content: elderlyData['elderly_dietNotes'] ?? 'Not specified',
        ),
        const SizedBox(height: 16),
        
        _buildInfoCard(
          icon: Icons.health_and_safety,
          title: 'Health Condition',
          content: elderlyData['elderly_condition'] ?? 'Not specified',
        ),
      ]);
    } else {
      // Additional fields for deceased elderly
      cards.addAll([
        _buildInfoCard(
          icon: Icons.home_outlined,
          title: 'Former House Allocation',
          content: elderlyData['house_name'] ?? 'Not specified',
        ),
        const SizedBox(height: 16),
        
        _buildInfoCard(
          icon: Icons.health_and_safety,
          title: 'Health Condition',
          content: elderlyData['elderly_condition'] ?? 'Not specified',
        ),
        const SizedBox(height: 16),
        
        _buildInfoCard(
          icon: Icons.warning,
          title: 'Cause of Death',
          content: elderlyData['elderly_causeDeath'] ?? 'Not specified',
        ),
        const SizedBox(height: 16),
        
        _buildInfoCard(
          icon: Icons.calendar_today,
          title: 'Date of Passing',
          content: elderlyData['elderly_deathDate'] != null 
              ? _formatDate(elderlyData['elderly_deathDate'])
              : 'Not specified',
        ),
      ]);
    }
    
    return cards;
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFD8F4FF),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: const Color(0xFF00588e).withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00588e).withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: const Color(0xFF00588e),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF00588e).withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF00588e),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'Not specified';
    
    try {
      DateTime dateTime;
      if (date is String) {
        dateTime = DateTime.parse(date);
      } else if (date is DateTime) {
        dateTime = date;
      } else if (date is Timestamp) {
        // Handle Firestore Timestamp directly
        dateTime = date.toDate();
      } else if (date.toString().contains('Timestamp')) {
        // Handle Firestore Timestamp as string representation
        final timestampRegex = RegExp(r'seconds=(-?\d+)');
        final match = timestampRegex.firstMatch(date.toString());
        if (match != null) {
          final seconds = int.parse(match.group(1)!);
          dateTime = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
        } else {
          return 'Not specified';
        }
      } else {
        print('DEBUG: Unknown date type: ${date.runtimeType} - $date');
        return 'Not specified';
      }
      
      // Format as "Month Day, Year" (e.g., "August 6, 2003")
      final months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      
      final monthName = months[dateTime.month - 1];
      return '$monthName ${dateTime.day}, ${dateTime.year}';
    } catch (e) {
      print('DEBUG: Error formatting date $date: $e');
      return 'Not specified';
    }
  }

  String _getElderlyName() {
    // Try different possible field combinations for name
    if (elderlyData['name'] != null && elderlyData['name'].toString().trim().isNotEmpty) {
      return elderlyData['name'].toString().trim();
    }
    
    // Try fname + lname combination
    final fname = elderlyData['elderly_fname']?.toString() ?? '';
    final lname = elderlyData['elderly_lname']?.toString() ?? '';
    final fullName = '$fname $lname'.trim();
    
    if (fullName.isNotEmpty) {
      return fullName;
    }
    
    // Try other possible field names
    final firstName = elderlyData['first_name']?.toString() ?? '';
    final lastName = elderlyData['last_name']?.toString() ?? '';
    final altFullName = '$firstName $lastName'.trim();
    
    if (altFullName.isNotEmpty) {
      return altFullName;
    }
    
    return 'Name not specified';
  }
}