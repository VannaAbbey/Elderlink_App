import 'package:cloud_firestore/cloud_firestore.dart';


class HouseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>?> getAssignedHouseForCaregiver(String caregiverId) async {
    final assignSnapshot = await _firestore
        .collection('cg_house_assign')
        .where('caregiver_id', isEqualTo: caregiverId)
        .limit(1)
        .get();
    if (assignSnapshot.docs.isEmpty) return null;
    final houseId = assignSnapshot.docs.first.data()['house_id'] as String;
    final houseSnapshot = await _firestore
        .collection('house')
        .where('house_id', isEqualTo: houseId)
        .limit(1)
        .get();
    if (houseSnapshot.docs.isEmpty) return null;
    return houseSnapshot.docs.first.data();
  }

  Future<List<Map<String, dynamic>>> getAssignedElderlyForCaregiver(String caregiverId) async {
    // Get house assignment
    final assignSnapshot = await _firestore
        .collection('cg_house_assign')
        .where('caregiver_id', isEqualTo: caregiverId)
        .limit(1)
        .get();
    if (assignSnapshot.docs.isEmpty) return [];
    
    final houseId = assignSnapshot.docs.first.data()['house_id'] as String;

    // Get house information
    final houseSnapshot = await _firestore
        .collection('house')
        .where('house_id', isEqualTo: houseId)
        .limit(1)
        .get();
    
    String? houseName;
    if (houseSnapshot.docs.isNotEmpty) {
      houseName = houseSnapshot.docs.first.data()['house_name'] as String?;
    }

    // Get elderly assignments for caregiver
    final elderlyAssignSnapshot = await _firestore
        .collection('elderly_caregiver_assign')
        .where('caregiver_id', isEqualTo: caregiverId)
        .get();
    
    final elderlyIds = elderlyAssignSnapshot.docs.map((doc) => doc.data()['elderly_id'] as String).toList();
    if (elderlyIds.isEmpty) return [];

    print('DEBUG HouseService: Found ${elderlyIds.length} elderly IDs for caregiver (before deduplication)');
    
    // Remove duplicates from elderly IDs to prevent duplicate records
    final uniqueElderlyIds = elderlyIds.toSet().toList();
    print('DEBUG HouseService: After deduplication: ${uniqueElderlyIds.length} unique elderly IDs');

    // Firestore has a limit of 30 elements for 'whereIn' queries
    // Split uniqueElderlyIds into chunks of 30 and make multiple queries
    List<QuerySnapshot> elderlySnapshots = [];
    
    for (int i = 0; i < uniqueElderlyIds.length; i += 30) {
      final chunk = uniqueElderlyIds.skip(i).take(30).toList();
      print('DEBUG HouseService: Querying chunk ${(i ~/ 30) + 1} with ${chunk.length} IDs');
      
      final chunkSnapshot = await _firestore
          .collection('elderly')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      
      elderlySnapshots.add(chunkSnapshot);
    }

    // Filter by house_id and return with assignment data
    List<Map<String, dynamic>> result = [];
    Set<String> processedElderlyIds = {}; // Track processed elderly to avoid duplicates
    
    // Process all chunks
    for (var elderlySnapshot in elderlySnapshots) {
      for (var elderlyDoc in elderlySnapshot.docs) {
        final elderlyId = elderlyDoc.id;
        
        // Skip if we've already processed this elderly
        if (processedElderlyIds.contains(elderlyId)) {
          continue;
        }
        
        final elderlyData = elderlyDoc.data() as Map<String, dynamic>?;
        final elderlyHouseId = elderlyData?['house_id'] as String? ?? '';
        
        if (elderlyHouseId == houseId) {
          // Find the assignment data for this elderly
          final assignmentDoc = elderlyAssignSnapshot.docs
              .firstWhere((doc) => doc.data()['elderly_id'] == elderlyId);
          final assignmentData = assignmentDoc.data();
          
          // Construct name field for consistency with grid display
          String constructedName = '';
          if (elderlyData?['elderly_fname'] != null || elderlyData?['elderly_lname'] != null) {
            constructedName = '${elderlyData?['elderly_fname'] ?? ''} ${elderlyData?['elderly_lname'] ?? ''}'.trim();
          } else if (elderlyData?['name'] != null) {
            constructedName = elderlyData?['name'].toString() ?? '';
          }

          final profilePicUrl = elderlyData?['elderly_profilePic'] ?? elderlyData?['profile_pic'] ?? '';
          print('DEBUG HouseService: Profile pic for $constructedName: elderly_profilePic=${elderlyData?['elderly_profilePic']}, profile_pic=${elderlyData?['profile_pic']}, final=$profilePicUrl');

          final elderlyRecord = <String, dynamic>{
            'elderly_id': elderlyId,
            'days_assigned': assignmentData['days_assigned'] ?? [],
            'assign_id': assignmentData['assign_id'] ?? '',
            // Ensure elderly_status defaults to 'Alive' to match database format
            'elderly_status': elderlyData?['elderly_status'] as String? ?? 'Alive',
            'name': constructedName.isNotEmpty ? constructedName : 'Name not available',
            'house_name': houseName ?? 'Unknown House',
            // Add birthdate field mapping for consistency
            'birthdate': elderlyData?['elderly_bday'] ?? elderlyData?['birthdate'],
            // Add profile picture field mapping - use elderly_profilePic from database
            'profile_pic': profilePicUrl,
          };
          
          // Add all other elderly data
          if (elderlyData != null) {
            elderlyRecord.addAll(elderlyData);
          }
          
          result.add(elderlyRecord);
          processedElderlyIds.add(elderlyId); // Mark as processed
        }
      }
    }

    print('DEBUG HouseService: Returning ${result.length} elderly records after filtering by house_id');

    return result;
  }

  Future<List<Map<String, dynamic>>> getAssignedElderlyForCaregiverDay(String caregiverId, String day) async {
    try {
      // Use the same proven approach as upcoming_tasks_screen
      // Query for assignments based on day - try both approaches for compatibility
      QuerySnapshot assignSnapshot;
      
      // First, try querying by individual day field (if it exists)
      try {
        assignSnapshot = await _firestore
            .collection('elderly_caregiver_assign')
            .where('caregiver_id', isEqualTo: caregiverId)
            .where('day', isEqualTo: day)
            .get();
      } catch (e) {
        // If that fails, get all assignments and filter by days_assigned array
        assignSnapshot = await _firestore
            .collection('elderly_caregiver_assign')
            .where('caregiver_id', isEqualTo: caregiverId)
            .get();
      }

      List<QueryDocumentSnapshot> relevantAssignments;
      
      if (assignSnapshot.docs.isNotEmpty && assignSnapshot.docs.first.data().toString().contains('day')) {
        // Use direct query results if day field exists
        relevantAssignments = assignSnapshot.docs;
        print('DEBUG HouseService: Using direct day field query - found ${relevantAssignments.length} assignments');
      } else {
        // Filter by days_assigned array
        relevantAssignments = assignSnapshot.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final daysAssigned = List<String>.from(data['days_assigned'] ?? []);
          return daysAssigned.contains(day);
        }).toList();
        print('DEBUG HouseService: Using days_assigned array filtering - found ${relevantAssignments.length} assignments for $day');
      }

      if (relevantAssignments.isEmpty) {
        print('DEBUG HouseService: No elderly assigned for day $day');
        return [];
      }

      // Get unique elderly IDs from filtered assignments
      final elderlyIds = relevantAssignments
          .map((doc) => (doc.data() as Map<String, dynamic>)['elderly_id'] as String)
          .toSet() // Remove duplicates
          .toList();

      print('DEBUG HouseService: Found ${elderlyIds.length} unique elderly IDs for day $day');

      // Get house assignment to filter by house
      final houseAssignSnapshot = await _firestore
          .collection('cg_house_assign')
          .where('caregiver_id', isEqualTo: caregiverId)
          .limit(1)
          .get();
      
      if (houseAssignSnapshot.docs.isEmpty) {
        print('DEBUG HouseService: No house assignment found for caregiver');
        return [];
      }
      
      final houseId = houseAssignSnapshot.docs.first.data()['house_id'] as String;

      // Get house information
      final houseSnapshot = await _firestore
          .collection('house')
          .where('house_id', isEqualTo: houseId)
          .limit(1)
          .get();
      
      String? houseName;
      if (houseSnapshot.docs.isNotEmpty) {
        houseName = houseSnapshot.docs.first.data()['house_name'] as String?;
      }

      // Fetch elderly details in chunks of 30 (Firestore limit)
      List<QuerySnapshot> elderlySnapshots = [];
      
      for (int i = 0; i < elderlyIds.length; i += 30) {
        final chunk = elderlyIds.skip(i).take(30).toList();
        print('DEBUG HouseService: Querying elderly chunk ${(i ~/ 30) + 1} with ${chunk.length} IDs');
        
        final chunkSnapshot = await _firestore
            .collection('elderly')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        elderlySnapshots.add(chunkSnapshot);
      }

      // Build result with proper day filtering
      List<Map<String, dynamic>> result = [];
      Set<String> processedElderlyIds = {}; // Track processed elderly to avoid duplicates

      for (var elderlySnapshot in elderlySnapshots) {
        for (var elderlyDoc in elderlySnapshot.docs) {
          final elderlyId = elderlyDoc.id;
          
          // Skip if already processed
          if (processedElderlyIds.contains(elderlyId)) {
            continue;
          }
          
          final elderlyData = elderlyDoc.data() as Map<String, dynamic>?;
          final elderlyHouseId = elderlyData?['house_id'] as String? ?? '';
          
          // Only include elderly from the same house
          if (elderlyHouseId == houseId) {
            // Find the assignment data for this elderly
            final assignmentDoc = relevantAssignments
                .firstWhere((doc) => (doc.data() as Map<String, dynamic>)['elderly_id'] == elderlyId);
            final assignmentData = assignmentDoc.data() as Map<String, dynamic>;
            
            // Construct name field for consistency with grid display
            String constructedName = '';
            if (elderlyData?['elderly_fname'] != null || elderlyData?['elderly_lname'] != null) {
              constructedName = '${elderlyData?['elderly_fname'] ?? ''} ${elderlyData?['elderly_lname'] ?? ''}'.trim();
            } else if (elderlyData?['name'] != null) {
              constructedName = elderlyData?['name'].toString() ?? '';
            }

            final elderlyRecord = <String, dynamic>{
              'elderly_id': elderlyId,
              'days_assigned': assignmentData['days_assigned'] ?? [],
              'assign_id': assignmentData['assign_id'] ?? '',
              'elderly_status': elderlyData?['elderly_status'] as String? ?? 'Alive',
              'name': constructedName.isNotEmpty ? constructedName : 'Name not available',
              'house_name': houseName ?? 'Unknown House',
              // Add birthdate field mapping for consistency
              'birthdate': elderlyData?['elderly_bday'] ?? elderlyData?['birthdate'],
              // Add profile picture field mapping - use elderly_profilePic from database
              'profile_pic': elderlyData?['elderly_profilePic'] ?? elderlyData?['profile_pic'] ?? '',
            };
            
            // Add all other elderly data
            if (elderlyData != null) {
              elderlyRecord.addAll(elderlyData);
            }
            
            result.add(elderlyRecord);
            processedElderlyIds.add(elderlyId);
          }
        }
      }

      print('DEBUG HouseService: Returning ${result.length} elderly records for day $day after house filtering');
      return result;
      
    } catch (e) {
      print('DEBUG HouseService: Error in getAssignedElderlyForCaregiverDay: $e');
      // Fallback to showing all elderly if day filtering fails
      print('DEBUG HouseService: Falling back to showing all assigned elderly');
      return await getAssignedElderlyForCaregiver(caregiverId);
    }
  }

  /// Get all deceased elderly in the caregiver's assigned house
  Future<List<Map<String, dynamic>>> getDeceasedElderlyInHouse(String caregiverId) async {
    try {
      // Get house assignment
      final assignSnapshot = await _firestore
          .collection('cg_house_assign')
          .where('caregiver_id', isEqualTo: caregiverId)
          .limit(1)
          .get();
      
      if (assignSnapshot.docs.isEmpty) {
        print('DEBUG HouseService: No house assignment found for caregiver');
        return [];
      }
      
      final houseId = assignSnapshot.docs.first.data()['house_id'] as String;
      print('DEBUG HouseService: Getting deceased elderly for house: $houseId');

      // Get house information first
      final houseSnapshot = await _firestore
          .collection('house')
          .where('house_id', isEqualTo: houseId)
          .limit(1)
          .get();
      
      String? houseName;
      if (houseSnapshot.docs.isNotEmpty) {
        houseName = houseSnapshot.docs.first.data()['house_name'] as String?;
      }

      // Get all elderly in the house with deceased status
      final elderlySnapshot = await _firestore
          .collection('elderly')
          .where('house_id', isEqualTo: houseId)
          .where('elderly_status', isEqualTo: 'Deceased')
          .get();

      List<Map<String, dynamic>> result = [];
      
      for (var elderlyDoc in elderlySnapshot.docs) {
        final elderlyData = elderlyDoc.data();
        print('DEBUG HouseService: Deceased elderly data: $elderlyData');
        
        // Construct name field for consistency with grid display
        String constructedName = '';
        if (elderlyData['elderly_fname'] != null || elderlyData['elderly_lname'] != null) {
          constructedName = '${elderlyData['elderly_fname'] ?? ''} ${elderlyData['elderly_lname'] ?? ''}'.trim();
        } else if (elderlyData['name'] != null) {
          constructedName = elderlyData['name'].toString();
        }
        
        final profilePicUrl = elderlyData['elderly_profilePic'] ?? elderlyData['profile_pic'] ?? '';
        print('DEBUG HouseService: Profile pic for $constructedName: elderly_profilePic=${elderlyData['elderly_profilePic']}, profile_pic=${elderlyData['profile_pic']}, final=$profilePicUrl');

        final elderlyRecord = <String, dynamic>{
          'elderly_id': elderlyDoc.id,
          'elderly_status': 'Deceased',
          'house_name': houseName ?? 'Unknown House',
          'name': constructedName.isNotEmpty ? constructedName : 'Name not available',
          // Add birthdate field mapping for consistency
          'birthdate': elderlyData['elderly_bday'] ?? elderlyData['birthdate'],
          // Add profile picture field mapping - use elderly_profilePic from database
          'profile_pic': profilePicUrl,
          // Add all other elderly data
          ...elderlyData,
        };
        result.add(elderlyRecord);
        
        print('DEBUG HouseService: Final elderly record: $elderlyRecord');
      }

      print('DEBUG HouseService: Found ${result.length} deceased elderly in house');
      return result;
      
    } catch (e) {
      print('DEBUG HouseService: Error getting deceased elderly: $e');
      return [];
    }
  }

  /// Sort elderly list by first name alphabetically
  /// [elderly] - List of elderly maps to sort
  /// [ascending] - true for A-Z, false for Z-A
  static List<Map<String, dynamic>> sortElderlyByFirstName(
    List<Map<String, dynamic>> elderly, 
    {bool ascending = true}
  ) {
    final sortedList = List<Map<String, dynamic>>.from(elderly);
    
    sortedList.sort((a, b) {
      final nameA = (a['elderly_fname'] as String? ?? '').toLowerCase();
      final nameB = (b['elderly_fname'] as String? ?? '').toLowerCase();
      
      return ascending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
    });
    
    print('DEBUG HouseService: Sorted ${sortedList.length} elderly by first name (ascending: $ascending)');
    return sortedList;
  }
}
