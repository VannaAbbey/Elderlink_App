# 🧪 Testing Auto-Absent Marking System

## What You're Testing

**Goal:** Verify that nurses are automatically marked ABSENT at 2:15 PM (15 minutes after 2:00 PM shift start), **EVEN IF THEY DON'T OPEN THE APP**.

## Test Scenario

### Setup
- User: A nurse scheduled for **2nd shift** (2:00 PM - 10:00 PM)
- Date: Today (Tuesday, November 11, 2025)
- Shift Start: **2:00 PM**
- Absent Deadline: **2:15 PM**

### Timeline
```
2:00 PM  ➜ 2nd shift starts
         ➜ Background service is monitoring
         ➜ 15-minute grace period begins

2:15 PM  ➜ DEADLINE REACHED
         ➜ Background service checks:
            - Is it 15+ minutes after 2:00 PM? YES
            - Does nurse have attendance record? NO
            - Action: MARK ABSENT

3:06 PM  ➜ Nurse opens app for first time
         ➜ Manual background check triggers
         ➜ Should find existing ABSENT record from 2:15 PM
```

## What Should Happen

### When App Reopens at 3:06 PM:

1. **Manual background check triggers** (within 10 seconds of app opening)
2. **Background service logs:**
   ```
   🔧 BACKGROUND: Manual check triggered
   🔄 BACKGROUND: Attendance check task started
   🔄 BACKGROUND: Firebase initialized in background isolate
   🔍 BACKGROUND: Checking at 15:06
   ✅ BACKGROUND: 2nd shift past 15-min window (2:15 PM+)
   📋 BACKGROUND: Processing shifts: [2nd]
   🔍 BACKGROUND: Checking 2nd shift on Tuesday
   📊 BACKGROUND: Found X assignments for 2nd shift
   📝 BACKGROUND: Marked [Nurse Name] (user_id) as absent for 2nd shift on 2025-11-11
   ✅ BACKGROUND: Marked X users as absent for 2nd shift
   ✅ BACKGROUND: Attendance check task completed
   ```

3. **Foreground check logs:**
   ```
   🔍 ATTENDANCE: Checking shift start at 2025-11-11 15:06:XX
   🔍 ATTENDANCE: Shift starts at 2025-11-11 14:00:00.000
   🔍 ATTENDANCE: Time difference: 66 minutes
   🔍 ATTENDANCE: Within window: false
   ```

4. **No attendance dialog shows** (because already marked absent)

## Checking the Database

### Go to Firestore Console → `attendance` collection

Look for a document with:
```json
{
  "user_id": "rllE7tS4uegLyCQvHu9liJvZmgS2", // Olivia Baustista
  "user_type": "nurse",
  "date": "2025-11-11",
  "shift": "2nd",
  "is_present": false,  // ← ABSENT!
  "timestamp": "2025-11-11T14:15:XX.XXXZ",  // ← Around 2:15 PM
  "reason": "Auto-marked absent by system - No response within 15 minutes of shift start",
  "marked_by": "system_background",  // ← Marked by background service!
  "auto_marked": true
}
```

## What Logs to Look For

### In Flutter Logs (when app reopens):

**Good Signs ✅:**
```
✅ NURSE: Manual background check completed
🔄 BACKGROUND: Attendance check task started
🔄 BACKGROUND: Firebase initialized in background isolate
✅ BACKGROUND: 2nd shift past 15-min window (2:15 PM+)
📝 BACKGROUND: Marked [Name] as absent for 2nd shift
```

**Bad Signs ❌:**
```
❌ BACKGROUND: Error in attendance check task: ...
❌ BACKGROUND: Failed to initialize Firebase
❌ NURSE: Manual background check failed: ...
```

## Current Issue (From Your Logs)

Your logs show:
```
🔍 ATTENDANCE: Time difference: 66 minutes
🔍 ATTENDANCE: Within window: false
```

This means:
- ✅ System correctly detected it's 66 minutes past shift start
- ✅ System correctly determined it's outside the 15-minute window
- ❌ BUT no "BACKGROUND" logs showing the absent marking happened

**Why?**
The background service wasn't running before! The fixes I made should enable it now.

## How to Test NOW

### Option 1: Close and Reopen App
1. **Close the app completely** (swipe away from recent apps)
2. **Wait 5 seconds**
3. **Reopen the app**
4. **Watch the logs** - you should see:
   - "Manual background check triggered"
   - Background service checking 2nd shift
   - User being marked absent
5. **Check Firestore** - attendance record should appear

### Option 2: Wait for Next Background Run
The background service runs automatically every 15 minutes:
- Next run times: 3:15 PM, 3:30 PM, 3:45 PM, etc.
- At next run, it will mark any users who are past their deadline

## What Was Fixed

1. **Added Firebase initialization** in background callback with proper options
2. **Added manual trigger** when app opens (catches missed absent markings)
3. **Enabled debug mode** to see background service logs
4. **Firebase.initializeApp()** now uses `DefaultFirebaseOptions.currentPlatform`

## Expected Behavior After Fix

**Scenario A: User Never Opens App**
```
2:00 PM  - Shift starts (app closed)
2:15 PM  - Background service runs automatically
         - Marks user ABSENT
         - User never knows!
3:00 PM  - User still hasn't opened app
         - Database shows ABSENT record from 2:15 PM
```

**Scenario B: User Opens App After Deadline (Your Case)**
```
2:00 PM  - Shift starts (app closed)
2:15 PM  - Background service might have run (marks absent)
3:06 PM  - User opens app
         - Manual check triggers immediately
         - If not already marked: marks absent now
         - If already marked: skips (already done)
```

**Scenario C: User Opens App On Time**
```
2:00 PM  - Shift starts
2:05 PM  - User opens app
         - Foreground dialog shows immediately
         - User marks PRESENT
2:15 PM  - Background service runs
         - Finds existing record
         - Skips user (already marked present)
```

## Next Steps

1. ✅ Close and reopen the app
2. ✅ Check logs for "BACKGROUND" messages
3. ✅ Check Firestore for attendance record
4. ✅ If no record: Check error messages
5. ✅ Report back what you see!

## Important Notes

- Background service needs **internet connection**
- First run after app restart: 10 seconds delay
- Periodic runs: Every 15 minutes
- Android may delay tasks by a few minutes (battery optimization)
- System must have `house_shift_assignments` data properly configured

## Questions to Answer

After testing, please check:
1. ✅ Do you see "BACKGROUND" logs?
2. ✅ Is there an attendance record in Firestore?
3. ✅ What is the timestamp of the record?
4. ✅ What is marked_by field? (should be "system_background")
5. ✅ Any error messages?
