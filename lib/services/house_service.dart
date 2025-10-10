import 'package:cloud_firestore/cloud_firestore.dart';


class HouseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>?> getAssignedHouseForCaregiver(String caregiverId) async {
    final assignSnapshot = await _firestore
        .collection('house_shift_assignments')
        .where('user_id', isEqualTo: caregiverId)
        .where('user_type', isEqualTo: 'caregiver')
        .limit(1)
        .get();
    if (assignSnapshot.docs.isEmpty) return null;
    
    final assignData = assignSnapshot.docs.first.data();
    final houseId = assignData['house_id'] as String?;
    
    if (houseId == null) return null;
    
    final houseSnapshot = await _firestore
        .collection('house')
        .where('house_id', isEqualTo: houseId)
        .limit(1)
        .get();
    if (houseSnapshot.docs.isEmpty) return null;
    return houseSnapshot.docs.first.data();
  }

  Future<List<Map<String, dynamic>>> getAssignedElderlyForCaregiver(String caregiverId) async {
    try {
      print('DEBUG HouseService: Getting assigned elderly for caregiver $caregiverId');
      
      // ENHANCED APPROACH: First try to get specific elderly assignments, 
      // then fallback to house-based approach if needed
      // HYBRID APPROACH: Try elderly_assignments first, then fall back to house-based approach
      print('DEBUG HouseService: Querying elderly_assignments for caregiver $caregiverId...');
      final elderlyAssignSnapshot = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .get();
      
      print('DEBUG HouseService: Found ${elderlyAssignSnapshot.docs.length} elderly_assignments documents');
      
      // Get house information for context (needed for both approaches)
      print('DEBUG HouseService: Querying house_shift_assignments for caregiver $caregiverId...');
      final caregiverHouseSnapshot = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .limit(1)
          .get();
      
      if (caregiverHouseSnapshot.docs.isEmpty) {
        print('DEBUG HouseService: ❌ No house assignment found for caregiver $caregiverId');
        return [];
      }
      
      final caregiverHouseData = caregiverHouseSnapshot.docs.first.data();
      print('DEBUG HouseService: Caregiver house assignment data: $caregiverHouseData');
      
      final houseId = caregiverHouseData['house_id'] as String?;
      if (houseId == null) {
        print('DEBUG HouseService: No house_id found in assignment');
        return [];
      }
      
      print('DEBUG HouseService: Caregiver assigned to house: $houseId');
      
      final houseSnapshot = await _firestore
          .collection('house')
          .where('house_id', isEqualTo: houseId)
          .limit(1)
          .get();
      
      String? houseName;
      if (houseSnapshot.docs.isNotEmpty) {
        final houseData = houseSnapshot.docs.first.data();
        houseName = houseData['house_name'] as String?;
        print('DEBUG HouseService: House name: $houseName');
      }

      List<Map<String, dynamic>> result = [];

      if (elderlyAssignSnapshot.docs.isNotEmpty) {
        // APPROACH 1: Use specific elderly assignments from array structure
        print('DEBUG HouseService: Using specific elderly assignments from arrays');
        
        // Collect unique elderly IDs and their assigned days from arrays
        Map<String, Set<String>> elderlyDaysMap = {};
        
        for (var doc in elderlyAssignSnapshot.docs) {
          final assignData = doc.data();
          final day = assignData['day'] as String?;
          final elderlyIds = List<String>.from(assignData['elderly_ids'] ?? []);
          
          print('DEBUG HouseService: Assignment for $day with ${elderlyIds.length} elderly: $elderlyIds');
          
          if (day != null && elderlyIds.isNotEmpty) {
            for (String elderlyId in elderlyIds) {
              elderlyDaysMap.putIfAbsent(elderlyId, () => <String>{}).add(day);
              print('DEBUG HouseService: Elderly $elderlyId assigned on $day');
            }
          }
        }

        if (elderlyDaysMap.isNotEmpty) {
          print('DEBUG HouseService: Using specific assignments for ${elderlyDaysMap.length} unique elderly');

          // Fetch elderly details for the assigned elderly only
          final elderlyIdsList = elderlyDaysMap.keys.toList();
          for (int i = 0; i < elderlyIdsList.length; i += 30) {
            final chunk = elderlyIdsList.skip(i).take(30).toList();
            final elderlySnapshot = await _firestore
                .collection('elderly')
                .where(FieldPath.documentId, whereIn: chunk)
                .where('elderly_status', isEqualTo: 'Alive')
                .get();

            for (var elderlyDoc in elderlySnapshot.docs) {
              final elderlyData = elderlyDoc.data();
              final elderlyId = elderlyDoc.id;
              final assignedDays = elderlyDaysMap[elderlyId]?.toList() ?? [];
              
              result.add(_buildElderlyRecord(elderlyData, elderlyId, assignedDays, houseName));
              print('DEBUG HouseService: Added specifically assigned elderly: ${elderlyData['elderly_fname']} (ID: $elderlyId, days: $assignedDays)');
            }
          }
        }
      }
      
      if (result.isEmpty) {
        // APPROACH 2: Intelligent fallback - show elderly in house who are NOT specifically assigned to other caregivers
        print('DEBUG HouseService: No specific elderly assignments found, using intelligent house-based approach for house $houseId');
        
        // First, get all elderly who ARE specifically assigned to OTHER caregivers
        print('DEBUG HouseService: Checking for other caregivers assignments...');
        final otherCaregiversAssignments = await _firestore
            .collection('elderly_assignments')
            .get(); // Get ALL assignments, then filter in code
        
        print('DEBUG HouseService: Found ${otherCaregiversAssignments.docs.length} total assignments');
        
        Set<String> elderlyAssignedToOthers = {};
        for (var doc in otherCaregiversAssignments.docs) {
          final assignData = doc.data();
          final assignmentCaregiverId = assignData['user_id'] as String?;
          final assignmentUserType = assignData['user_type'] as String?;
          final elderlyIds = List<String>.from(assignData['elderly_ids'] ?? []);
          
          // Only include assignments for OTHER caregivers
          if (assignmentCaregiverId != null && assignmentUserType == 'caregiver' && assignmentCaregiverId != caregiverId) {
            elderlyAssignedToOthers.addAll(elderlyIds);
            print('DEBUG HouseService: Elderly ${elderlyIds.join(', ')} assigned to caregiver $assignmentCaregiverId (not us)');
          }
        }
        
        print('DEBUG HouseService: Total elderly assigned to other caregivers: ${elderlyAssignedToOthers.length}');
        if (elderlyAssignedToOthers.isNotEmpty) {
          print('DEBUG HouseService: Elderly IDs assigned to others: ${elderlyAssignedToOthers.toList()}');
        }
        
        final caregiverAssignData = caregiverHouseSnapshot.docs.first.data();
        final defaultDaysAssigned = List<String>.from(caregiverAssignData['days_assigned'] ?? []);
        
        print('DEBUG HouseService: Fetching all elderly in house $houseId...');
        final elderlySnapshot = await _firestore
            .collection('elderly')
            .where('house_id', isEqualTo: houseId)
            .where('elderly_status', isEqualTo: 'Alive')
            .get();

        print('DEBUG HouseService: Found ${elderlySnapshot.docs.length} elderly in house $houseId');

        for (var elderlyDoc in elderlySnapshot.docs) {
          final elderlyData = elderlyDoc.data();
          final elderlyId = elderlyDoc.id;
          
          print('DEBUG HouseService: Checking elderly ${elderlyData['elderly_fname']} (ID: $elderlyId)');
          
          // Only include elderly who are NOT specifically assigned to other caregivers
          if (!elderlyAssignedToOthers.contains(elderlyId)) {
            result.add(_buildElderlyRecord(elderlyData, elderlyId, defaultDaysAssigned, houseName));
            print('DEBUG HouseService: ✅ Added unassigned elderly: ${elderlyData['elderly_fname']} (ID: $elderlyId)');
          } else {
            print('DEBUG HouseService: ❌ Skipped elderly assigned to other caregiver: ${elderlyData['elderly_fname']} (ID: $elderlyId)');
          }
        }
        
        print('DEBUG HouseService: Fallback approach added ${result.length} elderly to result');
      }

      print('DEBUG HouseService: Returning ${result.length} elderly records');
      return result;
      
    } catch (e) {
      print('DEBUG HouseService: Error in getAssignedElderlyForCaregiver: $e');
      return [];
    }
  }

  // Helper method to build elderly record consistently
  Map<String, dynamic> _buildElderlyRecord(Map<String, dynamic> elderlyData, String elderlyId, List<String> daysAssigned, String? houseName) {
    // Construct name field for consistency with grid display
    String constructedName = '';
    if (elderlyData['elderly_fname'] != null || elderlyData['elderly_lname'] != null) {
      constructedName = '${elderlyData['elderly_fname'] ?? ''} ${elderlyData['elderly_lname'] ?? ''}'.trim();
    } else if (elderlyData['name'] != null) {
      constructedName = elderlyData['name'].toString();
    }

    final profilePicUrl = elderlyData['elderly_profilePic'] ?? elderlyData['profile_pic'] ?? '';

    final elderlyRecord = <String, dynamic>{
      'elderly_id': elderlyId,
      'days_assigned': daysAssigned,
      'assign_id': '', // Default assignment ID
      'elderly_status': elderlyData['elderly_status'] as String? ?? 'Alive',
      'name': constructedName.isNotEmpty ? constructedName : 'Name not available',
      'house_name': houseName ?? 'Unknown House',
      // Add birthdate field mapping for consistency
      'birthdate': elderlyData['elderly_bday'] ?? elderlyData['birthdate'],
      // Add profile picture field mapping - use elderly_profilePic from database
      'profile_pic': profilePicUrl,
    };
    
    // Add all other elderly data
    elderlyRecord.addAll(elderlyData);
    
    return elderlyRecord;
  }

  Future<List<Map<String, dynamic>>> getAssignedElderlyForCaregiverDay(String caregiverId, String day) async {
    try {
      print('DEBUG HouseService: Starting getAssignedElderlyForCaregiverDay for caregiver $caregiverId on $day');
      
      // HYBRID APPROACH: Try elderly_assignments first, then fall back to house-based approach
      final elderlyAssignSnapshot = await _firestore
          .collection('elderly_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .where('day', isEqualTo: day)
          .get();
      
      // Get house information for context (needed for both approaches)
      final caregiverHouseSnapshot = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .limit(1)
          .get();
      
      if (caregiverHouseSnapshot.docs.isEmpty) {
        print('DEBUG HouseService: No house assignment found for caregiver $caregiverId');
        return [];
      }
      
      final caregiverAssignData = caregiverHouseSnapshot.docs.first.data();
      final houseId = caregiverAssignData['house_id'] as String?;
      final caregiverDaysAssigned = List<String>.from(caregiverAssignData['days_assigned'] ?? []);
      
      if (houseId == null) {
        print('DEBUG HouseService: No house_id found in assignment');
        return [];
      }
      
      // Check if caregiver is assigned on the requested day
      if (!caregiverDaysAssigned.contains(day)) {
        print('DEBUG HouseService: Caregiver not assigned on $day (assigned days: $caregiverDaysAssigned)');
        return [];
      }
      
      final houseSnapshot = await _firestore
          .collection('house')
          .where('house_id', isEqualTo: houseId)
          .limit(1)
          .get();
      
      String? houseName;
      if (houseSnapshot.docs.isNotEmpty) {
        final houseData = houseSnapshot.docs.first.data();
        houseName = houseData['house_name'] as String?;
      }

      List<Map<String, dynamic>> result = [];

      if (elderlyAssignSnapshot.docs.isNotEmpty) {
        // APPROACH 1: Use specific elderly assignments for this day from arrays
        print('DEBUG HouseService: Using specific elderly assignments from arrays for $day');
        
        // Collect elderly IDs assigned on this specific day from arrays
        Set<String> assignedElderlyIds = {};
        
        for (var doc in elderlyAssignSnapshot.docs) {
          final assignData = doc.data();
          final elderlyIds = List<String>.from(assignData['elderly_ids'] ?? []);
          
          print('DEBUG HouseService: Found ${elderlyIds.length} elderly assigned on $day: $elderlyIds');
          assignedElderlyIds.addAll(elderlyIds);
        }

        if (assignedElderlyIds.isNotEmpty) {
          print('DEBUG HouseService: Using specific assignments for ${assignedElderlyIds.length} elderly on $day');

          // Fetch elderly details for the assigned elderly only
          final elderlyIdsList = assignedElderlyIds.toList();
          for (int i = 0; i < elderlyIdsList.length; i += 30) {
            final chunk = elderlyIdsList.skip(i).take(30).toList();
            final elderlySnapshot = await _firestore
                .collection('elderly')
                .where(FieldPath.documentId, whereIn: chunk)
                .where('elderly_status', isEqualTo: 'Alive')
                .get();

            for (var elderlyDoc in elderlySnapshot.docs) {
              final elderlyData = elderlyDoc.data();
              final elderlyId = elderlyDoc.id;
              
              result.add(_buildElderlyRecord(elderlyData, elderlyId, [day], houseName));
              print('DEBUG HouseService: Added specifically assigned elderly for $day: ${elderlyData['elderly_fname']} (ID: $elderlyId)');
            }
          }
        }
      }
      
      if (result.isEmpty) {
        // APPROACH 2: Intelligent fallback - show elderly in house who are NOT specifically assigned to other caregivers on this day
        print('DEBUG HouseService: No specific elderly assignments found for $day, using intelligent house-based approach for house $houseId');
        
        // First, get all elderly who ARE specifically assigned to OTHER caregivers on this day
        print('DEBUG HouseService: Checking for other caregivers assignments on $day...');
        final otherCaregiversAssignments = await _firestore
            .collection('elderly_assignments')
            .where('day', isEqualTo: day)
            .get(); // Get ALL assignments for this day, then filter in code
        
        print('DEBUG HouseService: Found ${otherCaregiversAssignments.docs.length} total assignments on $day');
        
        Set<String> elderlyAssignedToOthersOnDay = {};
        for (var doc in otherCaregiversAssignments.docs) {
          final assignData = doc.data();
          final assignmentCaregiverId = assignData['user_id'] as String?;
          final assignmentUserType = assignData['user_type'] as String?;
          final elderlyIds = List<String>.from(assignData['elderly_ids'] ?? []);
          
          // Only include assignments for OTHER caregivers
          if (assignmentCaregiverId != null && assignmentUserType == 'caregiver' && assignmentCaregiverId != caregiverId) {
            elderlyAssignedToOthersOnDay.addAll(elderlyIds);
            print('DEBUG HouseService: Elderly ${elderlyIds.join(', ')} assigned to caregiver $assignmentCaregiverId on $day (not us)');
          }
        }
        
        print('DEBUG HouseService: Total elderly assigned to other caregivers on $day: ${elderlyAssignedToOthersOnDay.length}');
        if (elderlyAssignedToOthersOnDay.isNotEmpty) {
          print('DEBUG HouseService: Elderly IDs assigned to others on $day: ${elderlyAssignedToOthersOnDay.toList()}');
        }
        
        print('DEBUG HouseService: Fetching all elderly in house $houseId for $day...');
        final elderlySnapshot = await _firestore
            .collection('elderly')
            .where('house_id', isEqualTo: houseId)
            .where('elderly_status', isEqualTo: 'Alive')
            .get();

        print('DEBUG HouseService: Found ${elderlySnapshot.docs.length} elderly in house $houseId for $day');

        for (var elderlyDoc in elderlySnapshot.docs) {
          final elderlyData = elderlyDoc.data();
          final elderlyId = elderlyDoc.id;
          
          print('DEBUG HouseService: Checking elderly ${elderlyData['elderly_fname']} (ID: $elderlyId) for $day');
          
          // Only include elderly who are NOT specifically assigned to other caregivers on this day
          if (!elderlyAssignedToOthersOnDay.contains(elderlyId)) {
            result.add(_buildElderlyRecord(elderlyData, elderlyId, [day], houseName));
            print('DEBUG HouseService: ✅ Added unassigned elderly for $day: ${elderlyData['elderly_fname']} (ID: $elderlyId)');
          } else {
            print('DEBUG HouseService: ❌ Skipped elderly assigned to other caregiver on $day: ${elderlyData['elderly_fname']} (ID: $elderlyId)');
          }
        }
        
        print('DEBUG HouseService: Fallback approach added ${result.length} elderly for $day');
      }

      print('DEBUG HouseService: Returning ${result.length} elderly records for day $day');
      return result;
      
    } catch (e) {
      print('DEBUG HouseService: Error in getAssignedElderlyForCaregiverDay: $e');
      return [];
    }
  }

  /// Get all deceased elderly in the caregiver's assigned house
  Future<List<Map<String, dynamic>>> getDeceasedElderlyInHouse(String caregiverId) async {
    try {
      // Get house assignment
      final assignSnapshot = await _firestore
          .collection('house_shift_assignments')
          .where('user_id', isEqualTo: caregiverId)
          .where('user_type', isEqualTo: 'caregiver')
          .limit(1)
          .get();
      
      if (assignSnapshot.docs.isEmpty) {
        print('DEBUG HouseService: No house assignment found for caregiver');
        return [];
      }
      
      final assignData = assignSnapshot.docs.first.data();
      final houseId = assignData['house_id'] as String?;
      
      if (houseId == null) {
        print('DEBUG HouseService: No house_id found in assignment');
        return [];
      }
      
      print('DEBUG HouseService: Getting deceased elderly for house: $houseId');

      // Get house information first
      final houseSnapshot = await _firestore
          .collection('house')
          .where('house_id', isEqualTo: houseId)
          .limit(1)
          .get();
      
      String? houseName;
      if (houseSnapshot.docs.isNotEmpty) {
        final houseData = houseSnapshot.docs.first.data();
        houseName = houseData['house_name'] as String?;
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
