# Attendance Check Implementation

## Overview
The attendance check system automatically prompts nurses and caregivers to mark their attendance when they arrive at their shift. **The system now includes automatic periodic checking**, so the attendance dialog will appear automatically at the scheduled time even if the app is already open.

## Files

### Core Service
- **lib/services/attendance_check_service.dart** - Main attendance service with all functionality

### Integration
- **lib/nurse/home.dart** - Attendance integrated in nurse home screen with periodic checks
- **lib/caregiver/home.dart** - Attendance integrated in caregiver home screen with periodic checks

## Features

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

## Firestore Collections Used

### Reading
- `house_shift_assignments` - Check if user is scheduled today
- `attendance` - Check if already marked today

### Writing
- `attendance` - Record attendance (present/absent status)

## How It Works

### Initialization (On App Start)
1. When nurse/caregiver opens the app, `startPeriodicAttendanceCheck()` is called in `initState`
2. This starts a timer that checks attendance conditions **every minute**
3. Timer automatically stops when attendance is marked or when screen is disposed

### Periodic Checking (Every Minute)
1. System checks:
   - Is user scheduled to work today?
   - Is it within 15 minutes of shift start?
   - Have they already marked attendance?
2. If all conditions are met, shows modal dialog with countdown
3. Dialog persists until user responds or 15 minutes elapse

### User Response
1. User clicks Present or Absent button
2. Attendance recorded to Firestore
3. Timer cancelled and periodic checking stops
4. Dialog won't appear again for this shift

### Auto-Absent (No Response)
1. If no response after 15 minutes, automatically marks as absent
2. Shows notification that they were marked absent
3. Records reason: "Auto-marked absent - no response within 15 minutes"

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

