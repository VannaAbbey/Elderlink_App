import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'elderly_detail_screen.dart';

// Widget for Alive profiles grid
class AliveProfilesGrid extends StatelessWidget {
  final List<Map<String, dynamic>> profiles;
  const AliveProfilesGrid({super.key, required this.profiles});

  @override
  Widget build(BuildContext context) {
    print('DEBUG AliveProfilesGrid: Received ${profiles.length} profiles');

    // Debug: Print details of each profile to check is_temporary_assignment flag
    for (int i = 0; i < profiles.length; i++) {
      final profile = profiles[i];
      print(
        'DEBUG AliveProfilesGrid: Profile $i - Name: ${profile['name']}, is_temporary_assignment: ${profile['is_temporary_assignment']}',
      );
    }

    print(
      'DEBUG AliveProfilesGrid: About to show grid with ${profiles.length} items',
    );

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.0,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: profiles.length,
      itemBuilder: (context, index) {
        final profile = profiles[index];
        final profilePic = profile['profile_pic'] as String?;
        final birthdate = profile['birthdate'];

        // Calculate age if birthdate is available
        int? age;
        if (birthdate != null) {
          try {
            DateTime birth;
            if (birthdate is String) {
              birth = DateTime.parse(birthdate);
            } else {
              birth = birthdate;
            }
            age = DateTime.now().year - birth.year;
            if (DateTime.now().month < birth.month ||
                (DateTime.now().month == birth.month &&
                    DateTime.now().day < birth.day)) {
              age--;
            }
          } catch (e) {
            age = null;
          }
        }

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ElderlyDetailScreen(elderlyData: profile),
              ),
            );
          },
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            color: Color(0xFFC1E5E9),
            elevation: 2,
            child: Stack(
              children: [
                // Main content - positioned to fill the card
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: ClipOval(
                            child: profilePic != null && profilePic.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: profilePic,
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      width: 80,
                                      height: 80,
                                      color: Colors.grey[300],
                                      child: const Icon(
                                        Icons.person,
                                        color: Colors.grey,
                                        size: 40,
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        Image.asset(
                                          'assets/images/people_icon.png',
                                          width: 80,
                                          height: 80,
                                          fit: BoxFit.cover,
                                        ),
                                  )
                                : Image.asset(
                                    'assets/images/people_icon.png',
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          profile['name'] ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF00588e),
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (age != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Age: $age',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF00588e),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Temporary assignment indicator - orange dot in top right
                if (profile['is_temporary_assignment'] == true) ...[
                  // Debug print
                  Builder(
                    builder: (context) {
                      print(
                        '🟠🟠🟠 RENDERING ORANGE DOT for ${profile['name']}',
                      );
                      return const SizedBox.shrink();
                    },
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// Widget for Deceased profiles grid
class DeceasedProfilesGrid extends StatelessWidget {
  final List<Map<String, dynamic>> profiles;
  const DeceasedProfilesGrid({super.key, required this.profiles});

  @override
  Widget build(BuildContext context) {
    print('DEBUG DeceasedProfilesGrid: Received ${profiles.length} profiles');
    for (int i = 0; i < profiles.length; i++) {
      print('DEBUG DeceasedProfilesGrid: Profile $i - ${profiles[i]}');
    }

    print(
      'DEBUG DeceasedProfilesGrid: About to show grid with ${profiles.length} items',
    );

    if (profiles.isEmpty) {
      print('DEBUG DeceasedProfilesGrid: Showing empty state');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: Colors.grey.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'No deceased elderly in this house.',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.0,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: profiles.length,
      itemBuilder: (context, index) {
        final profile = profiles[index];
        final profilePic = profile['profile_pic'] as String?;
        final birthdate = profile['birthdate'];

        // Calculate age if birthdate is available
        int? age;
        if (birthdate != null) {
          try {
            DateTime birth;
            if (birthdate is String) {
              birth = DateTime.parse(birthdate);
            } else {
              birth = birthdate;
            }
            age = DateTime.now().year - birth.year;
            if (DateTime.now().month < birth.month ||
                (DateTime.now().month == birth.month &&
                    DateTime.now().day < birth.day)) {
              age--;
            }
          } catch (e) {
            age = null;
          }
        }

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ElderlyDetailScreen(elderlyData: profile),
              ),
            );
          },
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            color: Color(0xFFB0B0B0), // Different color for deceased
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: ClipOval(
                      child: ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          Colors.grey,
                          BlendMode.saturation,
                        ),
                        child: profilePic != null && profilePic.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: profilePic,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  width: 80,
                                  height: 80,
                                  color: Colors.grey[300],
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.grey,
                                    size: 40,
                                  ),
                                ),
                                errorWidget: (context, url, error) =>
                                    Image.asset(
                                      'assets/images/people_icon.png',
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                    ),
                              )
                            : Image.asset(
                                'assets/images/people_icon.png',
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile['name'] ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF7A7A7A), // Muted color for deceased
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (age != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Age: $age',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7A7A7A),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
