# Emergency Coverage Task Creation Implementation

## Overview
Implemented emergency coverage functionality for the task creation feature, similar to how temporary elderly assignments work in the absent feature. When a caregiver has emergency coverage assignments, tasks for those elderly can only be created with "Only once" frequency.

## Implementation Details

### File Modified
- `lib/caregiver/upcoming_tasks_screen.dart`

### Changes Made

#### 1. **Added Emergency Coverage Tracking Variable**
```dart
bool isEmergencyCoverage = false; // Track if selected elderly is from emergency coverage
```
- Tracks whether the currently selected elderly is from an emergency coverage assignment
- Works alongside `isTemporaryAssignment` flag

#### 2. **Enhanced Initial Elderly Check**
Updated the `WidgetsBinding.instance.addPostFrameCallback` to detect both temporary and emergency coverage elderly:

```dart
final isTemp = elderlyData['is_temporary_assignment'] == true;
final isEmergency = elderlyData['is_emergency_coverage'] == true;

if (isTemp != isTemporaryAssignment || isEmergency != isEmergencyCoverage) {
  setState(() {
    isTemporaryAssignment = isTemp;
    isEmergencyCoverage = isEmergency;
    if (isTemp || isEmergency) {
      selectedFrequency = 'Only once';
      selectedDate = DateTime.now();
      selectedRecurringStartDate = DateTime.now();
    }
  });
}
```

#### 3. **Updated Elderly Dropdown Visual Indicators**
Added red dot indicator for emergency coverage elderly (distinct from orange dot for temporary):

```dart
if (isEmergency)
  Container(
    width: 10,
    height: 10,
    margin: const EdgeInsets.only(left: 8),
    decoration: BoxDecoration(
      color: Colors.red,  // Red for emergency coverage
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1),
    ),
  )
else if (isTemporary)
  Container(
    width: 10,
    height: 10,
    margin: const EdgeInsets.only(left: 8),
    decoration: BoxDecoration(
      color: Colors.orange,  // Orange for temporary
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1),
    ),
  ),
```

**Visual Indicators:**
- 🔴 **Red dot** = Emergency coverage elderly
- 🟠 **Orange dot** = Temporary assignment elderly
- **No dot** = Regular assignment

#### 4. **Updated Elderly Selection Handler**
Enhanced `onChanged` callback to detect both temporary and emergency coverage:

```dart
onChanged: (value) {
  setState(() {
    selectedElderly = value;
    
    if (value != null) {
      final elderlyData = assignedElderly.firstWhere(
        (e) => e['elderly_id'] == value,
        orElse: () => {},
      );
      
      // Check both flags
      final isTemp = elderlyData['is_temporary_assignment'] == true;
      final isEmergency = elderlyData['is_emergency_coverage'] == true;
      
      isTemporaryAssignment = isTemp;
      isEmergencyCoverage = isEmergency;
      
      if (isTemp || isEmergency) {
        // Auto-set to "Only once" for temporary or emergency elderly
        selectedFrequency = 'Only once';
        selectedDate = DateTime.now();
        selectedRecurringStartDate = DateTime.now();
      }
    }
  });
}
```

#### 5. **Disabled Frequency Dropdown for Emergency Coverage**
Updated frequency dropdown to be disabled for BOTH temporary and emergency coverage:

```dart
Container(
  height: 40,
  decoration: BoxDecoration(
    color: (isTemporaryAssignment || isEmergencyCoverage) 
        ? const Color(0xFFE0E0E0)  // Grey/disabled
        : const Color(0xFFE6F3FA),  // Normal blue
    borderRadius: BorderRadius.circular(20),
  ),
  child: DropdownButtonHideUnderline(
    child: DropdownButton<String>(
      value: selectedFrequency,
      isExpanded: true,
      icon: Icon(
        Icons.arrow_drop_down, 
        color: (isTemporaryAssignment || isEmergencyCoverage) 
            ? Colors.grey 
            : const Color(0xFF22688E)
      ),
      items: frequencyList.map((freq) {
        return DropdownMenuItem<String>(
          value: freq,
          child: Text(
            freq,
            style: TextStyle(
              color: (isTemporaryAssignment || isEmergencyCoverage) 
                  ? Colors.grey 
                  : Colors.black,
            ),
          ),
        );
      }).toList(),
      onChanged: (isTemporaryAssignment || isEmergencyCoverage) 
          ? null  // Disabled
          : (value) {
              setState(() {
                selectedFrequency = value;
              });
            },
    ),
  ),
),
```

**UI Behavior:**
- When emergency coverage elderly is selected:
  - Frequency dropdown turns **grey** (disabled)
  - Frequency is locked to **"Only once"**
  - Cannot change to "Every Assigned Day" or "Custom"

#### 6. **Enhanced Assignment Type Detection in Date Picker**
Updated the "Every Assigned Day" date picker validation to check for emergency coverage:

```dart
for (var doc in tempAssignmentSnapshot.docs) {
  final tempData = doc.data();
  final assignmentType = tempData['assignment_type'] as String?;
  final tempElderlyIds = List<String>.from(tempData['elderly_ids'] ?? []);
  
  if (tempElderlyIds.contains(selectedElderly)) {
    elderlyAssignedDays.add(todayWeekday);
    
    // Check if this is emergency coverage or regular temporary assignment
    if (assignmentType == 'emergency_coverage' || 
        assignmentType == 'emergency redistribution') {
      isEmergencyCoverageAssignment = true;
      print('🚨 DEBUG: Found EMERGENCY COVERAGE: $selectedElderly from emergency coverage for today ($todayWeekday)');
    } else {
      isTemporaryAssignment = true;
      print('🔍 DEBUG: Found TEMPORARY assignment: $selectedElderly temporarily assigned for today ($todayWeekday)');
    }
    break;
  }
}
```

**Recognized Assignment Types:**
- `emergency_coverage`
- `emergency redistribution` (web terminology)
- `absence_coverage` (regular temporary assignment)

## User Experience Flow

### Scenario: Caregiver with Emergency Coverage

1. **Open Task Creation Dialog**
   - Elderly dropdown shows all assigned elderly
   - Emergency coverage elderly have a **red dot** 🔴
   - Temporary elderly have an **orange dot** 🟠

2. **Select Emergency Coverage Elderly**
   - Frequency dropdown automatically sets to **"Only once"**
   - Frequency dropdown becomes **disabled (greyed out)**
   - Date field defaults to **today**

3. **Attempt to Change Frequency**
   - Dropdown is **non-interactive** (disabled)
   - User cannot select "Every Assigned Day" or "Custom"
   - UI clearly indicates restriction with grey styling

4. **Task Creation**
   - Task can only be created for **today**
   - Task will **not recur**
   - Task follows emergency coverage duration

### Scenario: Regular Elderly Selection

1. **Select Regular Elderly (no dots)**
   - Frequency dropdown remains **enabled (blue)**
   - All frequency options available:
     - ✅ Only once
     - ✅ Every Assigned Day
     - ✅ Custom days

2. **Full Functionality**
   - Can create recurring tasks
   - Can select any assigned day
   - Normal task creation flow

## Testing Guidelines

### Test Case 1: Emergency Coverage Detection
1. Ensure temporary_assignments document exists with:
   - `assignment_type`: "emergency_coverage" or "emergency redistribution"
   - `to_user_id`: caregiver's ID
   - `elderly_ids`: array with elderly IDs
   - `date`: today's date
   - `status`: "active"

2. Open task creation dialog
3. Verify elderly from emergency coverage shows **red dot** 🔴
4. Select emergency elderly
5. Verify frequency is "Only once" and **greyed out**

### Test Case 2: Temporary Assignment (Non-Emergency)
1. Ensure temporary_assignments document exists with:
   - `assignment_type`: "absence_coverage"
   - Other fields same as above

2. Open task creation dialog
3. Verify elderly shows **orange dot** 🟠
4. Select temporary elderly
5. Verify frequency is "Only once" and **greyed out**

### Test Case 3: Regular Assignment
1. Select elderly with **no dot indicator**
2. Verify frequency dropdown is **enabled (blue)**
3. Verify all frequency options are selectable
4. Can create recurring tasks normally

### Test Case 4: Switching Between Elderly Types
1. Select emergency coverage elderly (red dot)
   - Verify frequency is disabled
2. Switch to regular elderly (no dot)
   - Verify frequency becomes enabled
3. Switch to temporary elderly (orange dot)
   - Verify frequency is disabled again
4. Switch back to emergency elderly
   - Verify frequency remains disabled

## Debug Logging

Added comprehensive debug logging:

```dart
print('🔍 DEBUG: Is temporary assignment = $isTemporaryAssignment');
print('🚨 DEBUG: Is emergency coverage = $isEmergencyCoverageAssignment');
print('🚨 DEBUG: Found EMERGENCY COVERAGE: $selectedElderly from emergency coverage for today');
```

**Log Symbols:**
- 🔍 = Regular debug info
- 🚨 = Emergency coverage related
- ✅ = Success/validation passed
- ❌ = Error/validation failed

## Integration Points

### Works With Existing Features
✅ **HouseService Integration**
   - Uses same `is_emergency_coverage` flag from HouseService
   - Consistent with home.dart and incident.dart implementations

✅ **AbsenceProvider Integration**
   - Reads emergency coverage status from provider
   - Responds to real-time changes

✅ **Temporary Assignment Logic**
   - Extends existing temporary assignment functionality
   - Emergency coverage is treated as a special type of temporary assignment

## Benefits

1. **Consistency**: Matches the UI/UX pattern from incident report feature
2. **Safety**: Prevents creating recurring tasks for temporary emergency assignments
3. **Clarity**: Visual indicators (red vs orange dots) clearly distinguish assignment types
4. **Flexibility**: System recognizes multiple assignment type names from different parts of the system

## Future Enhancements

Potential improvements:
- Add tooltip on hover over dots explaining what they mean
- Show assignment end date/time for temporary/emergency assignments
- Add bulk task creation restrictions for emergency coverage periods
- Display warning message when emergency coverage is active in task creation dialog

## Related Files
- `lib/caregiver/incident.dart` - Similar emergency coverage implementation
- `lib/caregiver/home.dart` - Emergency coverage banner display
- `lib/services/cg_services/house_service.dart` - Core emergency coverage logic
- `lib/providers/cg_providers/absence_provider.dart` - Emergency coverage state management

## Status
✅ **Implemented and Ready for Testing**

All changes have been applied and there are no compilation errors. The feature is ready for testing with actual emergency coverage scenarios.
