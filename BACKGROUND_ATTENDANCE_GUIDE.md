# Background Attendance System - Complete Guide

## 🎯 Overview

The background attendance system **automatically marks users as absent** if they don't respond within 15 minutes of their shift start time, **even if they haven't opened the app**.

**SIMPLE EXPLANATION:**
- Shift starts at 6:00 AM → User has until 6:15 AM to mark attendance
- At 6:15 AM → System automatically checks all scheduled users
- No attendance record? → **MARKED ABSENT**
- Has attendance record? → Skip (user already marked present)
- **This happens for ALL users and ALL shifts automatically!**

### Key Features
- ✅ **Runs in background** - Works even when app is closed
- ✅ **15-minute deadline** - Marks absent EXACTLY at shift start + 15 minutes
- ✅ **All shifts supported** - 1st (6:00 AM), 2nd (2:00 PM), 3rd (10:00 PM)
- ✅ **All users** - Applies to all nurses and caregivers
- ✅ **No app required** - Doesn't need user to open app
- ✅ **System marking** - Records show "marked_by: system_background"

## 📋 How It Works

### Example: 1st Shift (6:00 AM - 2:00 PM)

**Timeline:**
```
6:00 AM  ➜ Shift starts
         ➜ Foreground service shows dialog (if app is open)
         ➜ Background service is monitoring
         ➜ User has 15 minutes to respond

6:15 AM  ➜ 15-MINUTE DEADLINE REACHED
         ➜ Background service runs periodic check
         ➜ Checks ALL users scheduled for 1st shift
         ➜ For each user:
            - Has attendance record? → Skip
            - No attendance record? → MARK ABSENT

6:30 AM  ➜ Background service runs again
         ➜ Users already marked → Skip

Every 15 minutes after, the service keeps checking
but skips users who are already marked.
```

**KEY POINT:** Background service runs **every 15 minutes**. When it runs at 6:15 AM (or shortly after), it checks if 15 minutes have passed since shift start. If yes, and user has no attendance record, it marks them ABSENT.

### All Shift Deadlines

| Shift | Start Time | Deadline (Start + 15min) | Status After Deadline |
|-------|-----------|-------------------------|----------------------|
| 1st Shift | 6:00 AM | **6:15 AM** | Marked ABSENT if no record |
| 2nd Shift | 2:00 PM | **2:15 PM** | Marked ABSENT if no record |
| 3rd Shift | 10:00 PM | **10:15 PM** | Marked ABSENT if no record |

## 🔄 System Architecture

### Two-Tier System

#### 1. **Foreground Service** (When App is Open)
- File: `lib/services/attendance_check_service.dart`
- Checks every minute while app is open
- Shows attendance dialog at shift start
- User can mark present/absent

#### 2. **Background Service** (Always Running)
- File: `lib/services/background_attendance_service.dart`
- Runs every 15 minutes via WorkManager
- Checks all scheduled users
- Automatically marks absent if no response
- Works independently of app state

## 🚀 Setup & Installation

### 1. Dependencies Already Installed
```yaml
workmanager: ^0.6.0  # Background task manager
```

### 2. Initialization (Already Done in main.dart)
```dart
await BackgroundAttendanceService.initialize();
```

### 3. Android Permissions (Already Configured)
- `WAKE_LOCK` - Keep device awake for checks
- `RECEIVE_BOOT_COMPLETED` - Restart service after reboot
- `FOREGROUND_SERVICE` - Run background tasks
- `INTERNET` - Access Firestore

## 📊 Database Schema

### Attendance Collection
```dart
{
  'user_id': 'user_123',
  'user_type': 'nurse' or 'caregiver',
  'date': '2025-11-11',  // yyyy-MM-dd format
  'shift': '1st' or '2nd' or '3rd',
  'is_present': false,  // true if present, false if absent
  'timestamp': Timestamp,
  'reason': 'Auto-marked absent by system - No response within 15 minutes of shift start',
  'marked_by': 'system_background',  // or 'user' or 'system'
  'auto_marked': true  // Flag for system auto-marking
}
```

## 🔍 How Background Service Works

### Check Logic (Every 15 Minutes)

1. **Determine Current Shift Window**
   ```dart
   If time is 6:15 AM - 2:00 PM  → Check 1st shift
   If time is 2:15 PM - 10:00 PM → Check 2nd shift
   If time is 10:15 PM - 6:00 AM → Check 3rd shift
   ```

2. **Query Scheduled Users**
   - Get all `house_shift_assignments` for current shift
   - Filter by `is_current: true`
   - Filter by shift `start_time`

3. **Check Each User**
   - Is user scheduled today? (check `days_assigned`)
   - Has user marked attendance? (query `attendance` collection)
   - Has 15 minutes passed since shift start?

4. **Mark Absent if Needed**
   - If no attendance record and 15+ minutes passed
   - Create attendance record with `is_present: false`
   - Add system reason and auto_marked flag

### Example Query Flow

```dart
// 1. Get users scheduled for 1st shift (6:00 AM)
house_shift_assignments
  .where('is_current', isEqualTo: true)
  .where('start_time', isEqualTo: '06:00')
  .get()

// 2. For each user, check if already marked
attendance
  .where('user_id', isEqualTo: userId)
  .where('date', isEqualTo: '2025-11-11')
  .where('shift', isEqualTo: '1st')
  .get()

// 3. If not marked and 15+ mins passed, mark absent
attendance.add({
  'user_id': userId,
  'is_present': false,
  'marked_by': 'system_background',
  'reason': 'Auto-marked absent...',
  ...
})
```

## 🧪 Testing

### Manual Testing

1. **Test Background Service Directly**
   ```dart
   // Add this in your test screen or debug menu
   await BackgroundAttendanceService.triggerManualCheck();
   ```

2. **Check Logs**
   ```
   🔄 BACKGROUND: Attendance check task started
   🔍 BACKGROUND: Checking at 2025-11-11 06:16:00
   📋 BACKGROUND: Checking shifts: [1st]
   📊 BACKGROUND: Found 5 assignments for 1st shift
   📝 BACKGROUND: Marked John Doe (user_123) as absent...
   ✅ BACKGROUND: Marked 2 users as absent for 1st shift
   ```

3. **Verify Database**
   - Open Firestore Console
   - Check `attendance` collection
   - Look for records with `marked_by: 'system_background'`

### Test Scenarios

#### Scenario 1: User Opens App Before Shift
```
5:50 AM - User opens app
6:00 AM - Foreground dialog appears
6:01 AM - User marks present
Result: ✅ Present (no background marking needed)
```

#### Scenario 2: User Opens App During 15-Min Window
```
6:05 AM - User opens app (5 mins after shift start)
6:05 AM - Foreground dialog appears immediately
6:06 AM - User marks present
Result: ✅ Present (no background marking needed)
```

#### Scenario 3: User Doesn't Open App
```
6:00 AM - Shift starts (app not opened)
6:15 AM - Background service runs
6:15 AM - System marks user as absent
Result: ❌ Absent (auto-marked by background)
```

#### Scenario 4: User Opens App After 15 Minutes
```
6:00 AM - Shift starts (app not opened)
6:15 AM - Background service marks absent
6:20 AM - User opens app
6:20 AM - No dialog (already marked absent)
Result: ❌ Absent (cannot change)
```

## 🛠️ Configuration

### Adjust Check Frequency

Edit `lib/services/background_attendance_service.dart`:

```dart
// Current: Every 15 minutes
await Workmanager().registerPeriodicTask(
  backgroundAttendanceTask,
  backgroundAttendanceTask,
  frequency: const Duration(minutes: 15),  // Change this
  ...
);
```

**Note:** Android minimum is 15 minutes for periodic tasks.

### Adjust Absent Timeout Window

Edit `lib/services/background_attendance_service.dart`:

```dart
// Check if 15 minutes have passed
final fifteenMinutesAfter = shiftStartTime.add(
  const Duration(minutes: 15),  // Change this
);
```

### Adjust Shift Times

Edit both:
- `lib/services/attendance_check_service.dart`
- `lib/services/background_attendance_service.dart`

```dart
// 1st Shift times
if (currentHour >= 6 && currentHour < 14) {  // Change these
  shiftsToCheck.add({
    'shift': '1st',
    'startTime': '06:00',  // Change this
    'endTime': '14:00',
  });
}
```

## 🔧 Troubleshooting

### Background Service Not Running

1. **Check Battery Optimization**
   - Go to Settings → Apps → Elderlink App
   - Battery → Unrestricted

2. **Check Permissions**
   - Settings → Apps → Elderlink App → Permissions
   - Ensure all required permissions granted

3. **Check Android Version**
   - Requires Android 6.0 (API 23) or higher

4. **Check Logs**
   ```dart
   print('🔧 Starting Background Attendance Service...');
   print('✅ Background Attendance Service started');
   ```

### Users Not Being Marked

1. **Verify Schedule Data**
   - Check `house_shift_assignments` collection
   - Ensure `is_current: true`
   - Ensure `days_assigned` contains correct day names

2. **Check Time Zones**
   - Ensure server time matches local time
   - Firestore timestamps use UTC

3. **Verify 15 Minutes Passed**
   - Background service only marks after 15+ minutes

## 📱 User Impact

### For Nurses/Caregivers

**Before:**
- Had to manually refresh app
- Could miss attendance if app wasn't opened
- Manual tracking by supervisors

**After:**
- ✅ Automatic attendance tracking
- ✅ Fair 15-minute response window
- ✅ No app opening required (but can still mark if opened)
- ✅ Clear absence records with reasons
- ⚠️ Must respond within 15 minutes or marked absent

### For Administrators

**Benefits:**
- ✅ Accurate attendance records
- ✅ No manual intervention needed
- ✅ Clear audit trail (marked_by field)
- ✅ Automatic enforcement of attendance policy
- ✅ Real-time attendance monitoring

## 🔐 Security & Privacy

- ✅ Only scheduled users are checked
- ✅ Records include reason for absence
- ✅ System marking clearly identified
- ✅ No personal data exposed
- ✅ Secure Firestore rules should be applied

## 📈 Performance

- Background service runs every 15 minutes
- Minimal battery impact
- Efficient Firestore queries (indexed fields)
- Only checks users scheduled for current shift
- Stops after marking to avoid duplicates

## 🚀 Production Deployment

### Before Launch:

1. **Test All Shift Times**
   - 1st shift: 6:00 AM
   - 2nd shift: 2:00 PM
   - 3rd shift: 10:00 PM

2. **Verify Database Structure**
   - `house_shift_assignments` populated
   - `days_assigned` format correct
   - User IDs match

3. **Test Background Service**
   - Install on multiple devices
   - Test with app closed
   - Test after device reboot

4. **Enable Production Mode**
   ```dart
   await Workmanager().initialize(
     callbackDispatcher,
     isInDebugMode: false,  // Set to false for production
   );
   ```

5. **Monitor Logs**
   - Check Firebase Console
   - Monitor attendance records
   - Watch for errors

### Post-Launch:

1. **Monitor First Week**
   - Check attendance records daily
   - Verify absent markings are correct
   - Collect user feedback

2. **Adjust If Needed**
   - Modify 15-minute window if required
   - Adjust check frequency
   - Update shift times

## 📞 Support

For issues or questions:
1. Check logs for error messages
2. Verify Firestore data structure
3. Test manual trigger function
4. Review Android permissions

## 🔄 Future Enhancements

Possible improvements:
- [ ] Push notifications before auto-absent
- [ ] Grace period warnings
- [ ] Manual override by supervisors
- [ ] Attendance reports
- [ ] Integration with payroll system
