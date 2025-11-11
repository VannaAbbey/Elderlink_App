# Attendance Check Implementation

## Overview
The attendance check system automatically prompts nurses and caregivers to mark their attendance when they arrive at their shift. The system includes **two-tier automatic checking**: foreground (when app is open) and **background (even when app is closed)**.

### 🆕 NEW: Background Attendance System
**Users are now automatically marked absent if they don't respond within 15 minutes of shift start, EVEN IF THEY HAVEN'T OPENED THE APP!**

Example: 1st shift starts at 6:00 AM → If no response by 6:15 AM → Automatically marked ABSENT

**See [BACKGROUND_ATTENDANCE_GUIDE.md](BACKGROUND_ATTENDANCE_GUIDE.md) for complete details.**

## Files

### Core Services
- **lib/services/attendance_check_service.dart** - Foreground attendance service (when app is open)
- **lib/services/background_attendance_service.dart** - ⭐ **NEW: Background service (always running)**

### Integration
- **lib/nurse/home.dart** - Attendance integrated in nurse home screen with periodic checks
- **lib/caregiver/home.dart** - Attendance integrated in caregiver home screen with periodic checks
- **lib/main.dart** - Background service initialization

## Features

### Foreground Features (When App is Open)
✅ **Auto-Display**: Dialog appears automatically at shift start (within 15-minute window)
✅ **Periodic Checking**: System checks every minute for shift start time - no refresh needed!
✅ **Background Monitoring**: Works even if app was opened before shift start time
✅ **15-Minute Timer**: Countdown timer shows time remaining to respond
✅ **Auto-Absent**: Automatically marks user as absent if no response after 15 minutes
✅ **Modal Dialog**: Cannot be dismissed - must answer Present or Absent
✅ **Shift Detection**: Automatically detects 1st (6AM-2PM), 2nd (2PM-10PM), or 3rd (10PM-6AM) shift
✅ **Firestore Integration**: Records attendance in `attendance` collection
✅ **Duplicate Prevention**: Won't show again if already marked for the day
✅ **Smart Cleanup**: Automatically stops checking after attendance is marked

### 🆕 Background Features (Always Running)
✅ **Independent Operation**: Runs even when app is completely closed
✅ **Automatic Absent Marking**: Marks users absent 15 minutes after shift start
✅ **All Users Covered**: Checks ALL scheduled nurses and caregivers
✅ **All Shifts Supported**: 1st (6AM), 2nd (2PM), 3rd (10PM) shifts
✅ **No App Required**: User doesn't need to open the app
✅ **System Enforcement**: Fair and automatic attendance policy
✅ **Audit Trail**: Records show "marked_by: system_background"
✅ **Efficient**: Runs every 15 minutes, minimal battery impact

## Shift Times & Auto-Absent Times

| Shift | Start Time | Auto-Absent Time | End Time |
|-------|-----------|------------------|----------|
| **1st Shift** | 6:00 AM | **6:15 AM** | 2:00 PM |
| **2nd Shift** | 2:00 PM | **2:15 PM** | 10:00 PM |
| **3rd Shift** | 10:00 PM | **10:15 PM** | 6:00 AM |

## Firestore Collections Used

### Reading
- `house_shift_assignments` - Check if user is scheduled today
- `attendance` - Check if already marked today
- `users` - Get user type and name

### Writing
- `attendance` - Record attendance (present/absent status)

### Attendance Record Schema
```dart
{
  'user_id': 'user_123',
  'user_type': 'nurse' or 'caregiver',
  'date': '2025-11-11',
  'shift': '1st' or '2nd' or '3rd',
  'is_present': true or false,
  'timestamp': ServerTimestamp,
  'reason': 'User marked' or 'Auto-marked absent...',
  'marked_by': 'user' or 'system' or 'system_background',
  'auto_marked': true (only for background marking)
}
```

## How It Works - Complete Flow

### Scenario 1: User Opens App Before Shift Start
```
5:50 AM  User opens app
         → Foreground service starts periodic checking (every 1 minute)
6:00 AM  Foreground service detects shift start
         → Shows attendance dialog
6:01 AM  User clicks "Present"
         → Records attendance to Firestore
         → Foreground checking stops
6:15 AM  Background service runs
         → Finds existing attendance record
         → Skips user (already marked)
```

### Scenario 2: User Opens App During 15-Min Window
```
6:05 AM  User opens app (5 minutes late)
         → Foreground service detects within shift window
         → Shows attendance dialog immediately
6:06 AM  User clicks "Present"
         → Records attendance
6:15 AM  Background service runs
         → Finds existing record
         → Skips user
```

### Scenario 3: User Doesn't Open App (NEW!)
```
6:00 AM  Shift starts
         → User hasn't opened app
         → No foreground service running
6:15 AM  Background service runs automatically
         → Checks all scheduled users
         → User has no attendance record
         → Calculates: 6:15 AM > (6:00 AM + 15 mins) ✓
         → **Automatically marks user as ABSENT**
         → Records to Firestore with:
           - is_present: false
           - marked_by: 'system_background'
           - reason: 'Auto-marked absent...'
6:20 AM  User opens app
         → Finds existing attendance record
         → No dialog shown (already marked absent)
```

### Scenario 4: User Opens App After 15 Minutes
```
6:00 AM  Shift starts (app not open)
6:15 AM  Background marks user as absent
6:25 AM  User opens app
         → Foreground service checks attendance
         → Finds record (marked absent)
         → No dialog shown
         → User sees they are marked absent
```

## Key Improvements

### Before (Manual Check Only)
- Attendance only checked when app first opened
- If app opened before shift start, user would miss the dialog
- Required closing and reopening app at shift time

### After (Automatic Periodic Checking)
- ✅ Checks every minute for shift start conditions
- ✅ Dialog appears automatically when shift time arrives
- ✅ Works even if app was already open
- ✅ No refresh or restart needed
- ✅ Automatically stops after attendance marked

## Testing Note

The `isScheduledToday()` method currently returns `true` to bypass schedule checking. To restore normal behavior:

1. Open `lib/services/attendance_check_service.dart`
2. Find line ~168 in `isScheduledToday()` method
3. Replace `return true;` with the actual Firestore check logic (commented out above it)

## Customization

To modify behavior, edit `lib/services/attendance_check_service.dart`:
- **Periodic check interval**: Line ~418 - `const Duration(minutes: 1)` - Change to check more/less frequently
- **Timer duration**: Line ~369 - `Timer(const Duration(minutes: 15), ...)` - Change auto-absent timeout
- **Shift times**: Lines ~70-109 - `getCurrentShift()` method
- **Time window**: Line ~133 - `const checkWindow = Duration(minutes: 15)` - Change attendance window
- **Dialog appearance**: Lines ~502-994 - `AttendanceCheckDialog` widget

## API Reference

### Starting Periodic Check
```dart
AttendanceCheckService.startPeriodicAttendanceCheck(
  context,
  () {
    // Callback when attendance is marked
    print('Attendance marked');
  },
);
```

### Stopping Periodic Check
```dart
AttendanceCheckService.stopPeriodicAttendanceCheck();
```

### Manual Check (Legacy - Not Recommended)
```dart
final scheduled = await AttendanceCheckService.isScheduledToday();
final atShiftStart = await AttendanceCheckService.isAtShiftStart();
final alreadyMarked = await AttendanceCheckService.hasMarkedAttendanceToday();

if (scheduled && atShiftStart && !alreadyMarked) {
  await AttendanceCheckService.showAttendanceDialog(
    context: context,
    onDismissed: () => print('Dialog dismissed'),
  );
}
```

## Lifecycle Management

The periodic checking automatically handles cleanup:
- ✅ Starts in `initState` of home screens
- ✅ Stops in `dispose` of home screens
- ✅ Stops automatically after attendance is marked
- ✅ Prevents memory leaks with proper timer cancellation

