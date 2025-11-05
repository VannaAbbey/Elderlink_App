# Attendance Check Implementation

## Overview
The attendance check system automatically prompts nurses and caregivers to mark their attendance when they arrive at their shift.

## Files

### Core Service
- **lib/services/attendance_check_service.dart** - Main attendance service with all functionality

### Integration
- **lib/nurse/home.dart** - Attendance integrated in nurse home screen
- **lib/caregiver/home.dart** - Attendance integrated in caregiver home screen

## Features

✅ **Auto-Display**: Dialog appears automatically at shift start (within 15-minute window)
✅ **15-Minute Timer**: Countdown timer shows time remaining to respond
✅ **Auto-Absent**: Automatically marks user as absent if no response after 15 minutes
✅ **Modal Dialog**: Cannot be dismissed - must answer Present or Absent
✅ **Shift Detection**: Automatically detects 1st (6AM-2PM), 2nd (2PM-10PM), or 3rd (10PM-6AM) shift
✅ **Firestore Integration**: Records attendance in `attendance` collection
✅ **Duplicate Prevention**: Won't show again if already marked for the day

## Firestore Collections Used

### Reading
- `house_shift_assignments` - Check if user is scheduled today
- `attendance` - Check if already marked today

### Writing
- `attendance` - Record attendance (present/absent status)

## How It Works

1. When nurse/caregiver opens the app, `_checkAndShowAttendance()` is called
2. Service checks:
   - Is user scheduled to work today?
   - Is it within 15 minutes of shift start?
   - Have they already marked attendance?
3. If all conditions met, shows modal dialog with countdown
4. User clicks Present or Absent button
5. Attendance recorded to Firestore
6. Timer cancelled

## Testing Note

The `isScheduledToday()` method currently returns `true` to bypass schedule checking. To restore normal behavior:

1. Open `lib/services/attendance_check_service.dart`
2. Find line ~158 in `isScheduledToday()` method
3. Replace `return true;` with the actual Firestore check logic (commented out above it)

## Customization

To modify behavior, edit `lib/services/attendance_check_service.dart`:
- **Timer duration**: Line ~188 - `Timer(const Duration(minutes: 15), ...)`
- **Shift times**: Lines ~70-109 - `getCurrentShift()` method
- **Time window**: Line ~133 - `const checkWindow = Duration(minutes: 15)`
- **Dialog appearance**: Lines ~309-658 - `AttendanceCheckDialog` widget
