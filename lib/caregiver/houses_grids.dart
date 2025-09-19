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
    print('DEBUG AliveProfilesGrid: About to show grid with ${profiles.length} items');
    
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
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
                (DateTime.now().month == birth.month && DateTime.now().day < birth.day)) {
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
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
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
                            errorWidget: (context, url, error) => Container(
                              width: 80,
                              height: 80,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/people_icon.png',
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            width: 80,
                            height: 80,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            child: ClipOval(
                              child: Image.asset(
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
    
    print('DEBUG DeceasedProfilesGrid: About to show grid with ${profiles.length} items');
    
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
        childAspectRatio: 0.85,
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
                (DateTime.now().month == birth.month && DateTime.now().day < birth.day)) {
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
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
                              errorWidget: (context, url, error) => Container(
                                width: 80,
                                height: 80,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/images/people_icon.png',
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              width: 80,
                              height: 80,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/people_icon.png',
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
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
