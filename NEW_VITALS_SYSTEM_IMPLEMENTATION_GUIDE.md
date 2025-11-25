# 🏥 NEW VITALS SYSTEM - COMPLETE IMPLEMENTATION GUIDE

## ✅ COMPLETED: Backend Cloud Functions

### 1. Removed Old Functions
- ❌ **Deleted**: `checkPendingVitalsReminder` (old vitals reminder system)
- ❌ **Deleted**: `markPendingVitalsAsMissedAtShiftEnd` (old shift transition logic)

### 2. New Cloud Functions Implemented

#### **`autoCreateVitalsDaily`** (runs every 5 minutes at midnight)
- **Purpose**: Auto-creates `vitals_daily` documents for all active elderly at day start
- **Trigger**: 12:00 AM - 12:30 AM Philippines time daily
- **Logic**:
  ```javascript
  For each active elderly:
    1. Generate vitals_id = elderlyId_YYYY-MM-DD
    2. Check if vitals_daily already exists
    3. If not exists, create with:
       - All vital_values = null
       - All shift_status = pending
       - any_completed = false
       - any_missed = false
  ```

#### **`markShiftVitalsAsMissed`** (runs every 5 minutes)
- **Purpose**: Auto-marks pending shifts as missed at shift end times
- **Trigger**: At 6:00 AM, 2:00 PM, 10:00 PM (±30 min buffer)
- **Logic**:
  ```javascript
  At shift transition:
    1. Get all vitals_daily for today
    2. Check shift_status[ended_shift]
    3. If status == 'pending':
       - Update to 'missed'
       - Set any_missed = true
       - Create vitals_activity_logs entry with action_type = 'shift_missed'
  ```

---

## 📊 DATABASE STRUCTURE

### **vitals_daily** Collection
```javascript
{
  "vitals_id": "iOrhx802kPDggjSvnEp5_20251125",
  "elderly_id": "iOrhx802kPDggjSvnEp5",
  "elderly_name": "Oscary Martinez",
  "assigned_date": "2025-11-25",              // YYYY-MM-DD
  "house_id": "H005",
  "created_at": Timestamp,
  "created_by": "system",
  "vital_values": {
     "blood_pressure": null,
     "temperature": null,
     "pulse_rate": null,
     "oxygen_saturation": null,
     "respiratory_rate": null,
     "notes": null,
     "last_updated_at": null,
     "last_updated_by": null
  },
  "shift_status": {
     "1st": { 
       "status": "pending",           // pending | completed | missed
       "completed_by": null,          // nurse_id when completed
       "completed_at": null,          // Timestamp when completed
       "missed_reason": null          // string when missed
     },
     "2nd": { "status": "pending", "completed_by": null, "completed_at": null, "missed_reason": null },
     "3rd": { "status": "pending", "completed_by": null, "completed_at": null, "missed_reason": null }
  },
  "any_completed": false,
  "any_missed": false,
  "updated_at": null
}
```

### **vitals_activity_logs** Collection
```javascript
{
  "activity_id": "uuid",
  "vitals_id": "iOrhx802kPDggjSvnEp5_20251125",
  "elderly_id": "iOrhx802kPDggjSvnEp5",
  "elderly_name": "Oscary Martinez",
  "assigned_date": "2025-11-25",
  "action_type": "vitals_update | shift_completed | shift_missed | assignment_changed | vitals_followup",
  "shift": "1st",
  "nurse_id": "4ESO1bhOfgR9mMxipojs58rDpQ03",
  "nurse_name": "Ellie Laforteza",
  "old_value": { /* partial snapshot */ },
  "new_value": { /* partial snapshot */ },
  "remarks": "follow-up: temp rose to 38.5",
  "timestamp": Timestamp
}
```

---

## 🔄 FRONTEND IMPLEMENTATION REQUIRED

### **Files Requiring Updates**:

#### 1. **lib/nurse/vital_upcoming.dart** - Pending Tab
**Current**: Reads from `vitals` collection with `status == 'pending'`
**Required Changes**:
```dart
// Query vitals_daily instead
Stream<QuerySnapshot> _getPendingVitals() {
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final currentShift = _getCurrentShift(); // Returns "1st", "2nd", or "3rd"
  
  return _firestore
      .collection('vitals_daily')
      .where('house_id', isEqualTo: widget.houseId)
      .where('assigned_date', isEqualTo: today)
      .snapshots()
      .map((snapshot) {
    // Filter by shift_status in code
    return snapshot.docs.where((doc) {
      final data = doc.data();
      final shiftStatus = data['shift_status'][currentShift];
      return shiftStatus['status'] == 'pending';
    }).toList();
  });
}
```

#### 2. **lib/nurse/vital_completed.dart** - Completed Tab
**Current**: Reads from `vitals` collection with `status == 'completed'`
**Required Changes**:
```dart
Stream<QuerySnapshot> _getCompletedVitals() {
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final currentShift = _getCurrentShift();
  
  return _firestore
      .collection('vitals_daily')
      .where('house_id', isEqualTo: widget.houseId)
      .where('assigned_date', isEqualTo: today)
      .where('any_completed', isEqualTo: true) // Quick filter
      .snapshots()
      .map((snapshot) {
    return snapshot.docs.where((doc) {
      final data = doc.data();
      final shiftStatus = data['shift_status'][currentShift];
      return shiftStatus['status'] == 'completed';
    }).toList();
  });
}

// Display completed_by and completed_at from shift_status
String getCompletedInfo(Map<String, dynamic> vital, String shift) {
  final shiftData = vital['shift_status'][shift];
  final completedAt = (shiftData['completed_at'] as Timestamp?)?.toDate();
  final completedBy = shiftData['completed_by'];
  
  return 'Completed by: $completedBy at ${DateFormat('h:mm a').format(completedAt!)}';
}
```

#### 3. **lib/nurse/vital_missed.dart** - Missed Tab
**Current**: Reads from `vitals` collection with `status == 'missed'`
**Required Changes**:
```dart
Stream<QuerySnapshot> _getMissedVitals() {
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final currentShift = _getCurrentShift();
  
  return _firestore
      .collection('vitals_daily')
      .where('house_id', isEqualTo: widget.houseId)
      .where('assigned_date', isEqualTo: today)
      .where('any_missed', isEqualTo: true) // Quick filter
      .snapshots()
      .map((snapshot) {
    return snapshot.docs.where((doc) {
      final data = doc.data();
      final shiftStatus = data['shift_status'][currentShift];
      return shiftStatus['status'] == 'missed';
    }).toList();
  });
}

// Display missed_reason from shift_status
String getMissedReason(Map<String, dynamic> vital, String shift) {
  final shiftData = vital['shift_status'][shift];
  return shiftData['missed_reason'] ?? 'No reason provided';
}
```

#### 4. **lib/nurse/vital_update_screen.dart** - Update Vitals
**Current**: Updates `vitals` collection single document
**Required Changes**:
```dart
Future<void> _saveVitals() async {
  final vitalsId = '${widget.elderlyId}_${_getTodayDate()}';
  final currentShift = _getCurrentShift();
  final nurseId = FirebaseAuth.instance.currentUser!.uid;
  final nurseName = FirebaseAuth.instance.currentUser!.displayName ?? 'Unknown';
  
  // Check if this is first entry or follow-up
  final vitalDoc = await _firestore.collection('vitals_daily').doc(vitalsId).get();
  final isFollowUp = vitalDoc.data()?['vital_values']['last_updated_at'] != null;
  
  final vitalValues = {
    'blood_pressure': _bloodPressureController.text,
    'temperature': _temperatureController.text,
    'pulse_rate': _pulseRateController.text,
    'oxygen_saturation': _o2SatController.text,
    'respiratory_rate': _respiratoryRateController.text,
    'notes': _notesController.text,
    'last_updated_at': FieldValue.serverTimestamp(),
    'last_updated_by': nurseId,
  };
  
  // Update vitals_daily
  await _firestore.collection('vitals_daily').doc(vitalsId).update({
    'vital_values': vitalValues,
    'shift_status.$currentShift': {
      'status': 'completed',
      'completed_by': nurseId,
      'completed_at': FieldValue.serverTimestamp(),
      'missed_reason': null,
    },
    'any_completed': true,
    'updated_at': FieldValue.serverTimestamp(),
  });
  
  // Log activity
  await logVitalAction(
    vitalsId: vitalsId,
    elderlyId: widget.elderlyId,
    elderlyName: widget.elderlyName,
    assignedDate: _getTodayDate(),
    actionType: isFollowUp ? 'vitals_followup' : 'shift_completed',
    shift: currentShift,
    nurseId: nurseId,
    nurseName: nurseName,
    oldValue: {},
    newValue: vitalValues,
    remarks: isFollowUp ? 'Follow-up vitals update' : 'Initial shift completion',
  );
}
```

#### 5. **lib/nurse/vital_logger.dart** ✅ ALREADY UPDATED
Updated to use new activity log structure with proper fields.

#### 6. **lib/nurse/vital_monitoring_details.dart**
**Required Changes**:
- Read from `vitals_daily` to show current day's vitals
- Display shift completion status per shift
- Show last vital_values when opening screen

#### 7. **lib/nurse/activity_logs.dart**
**Required Changes**:
- Read from `vitals_activity_logs` collection
- Display action_type properly: `vitals_update`, `shift_completed`, `shift_missed`, `vitals_followup`
- Show shift-specific information

---

## 🎯 KEY BEHAVIORS

### **Shift Status Independence**
- Each shift (1st, 2nd, 3rd) has independent status
- Completing 1st shift doesn't affect 2nd or 3rd
- Missing 1st shift doesn't affect 2nd or 3rd

### **Follow-up Vitals**
- Nurses can update vitals in subsequent shifts
- Creates `vitals_followup` activity log
- Updates `vital_values.last_updated_at` and `last_updated_by`
- Does NOT change shift_status of previous shifts

### **Daily Reset**
- New `vitals_daily` created at midnight
- Previous day's data archived in `vitals_activity_logs`
- UI shows only current day's vitals

### **Real-time Schedule Changes**
- When `house_shift_assignments` or `elderly_assignments` change:
  - New elderly appear in Pending tab automatically
  - Removed elderly disappear from all tabs
  - Activity logs remain intact for audit trail

---

## 📋 FIRESTORE INDEXES REQUIRED

### **vitals_daily**
```json
{
  "collectionGroup": "vitals_daily",
  "queryScope": "COLLECTION",
  "fields": [
    {"fieldPath": "house_id", "order": "ASCENDING"},
    {"fieldPath": "assigned_date", "order": "ASCENDING"},
    {"fieldPath": "any_completed", "order": "ASCENDING"}
  ]
},
{
  "collectionGroup": "vitals_daily",
  "queryScope": "COLLECTION",
  "fields": [
    {"fieldPath": "house_id", "order": "ASCENDING"},
    {"fieldPath": "assigned_date", "order": "ASCENDING"},
    {"fieldPath": "any_missed", "order": "ASCENDING"}
  ]
}
```

### **vitals_activity_logs**
```json
{
  "collectionGroup": "vitals_activity_logs",
  "queryScope": "COLLECTION",
  "fields": [
    {"fieldPath": "elderly_id", "order": "ASCENDING"},
    {"fieldPath": "assigned_date", "order": "ASCENDING"},
    {"fieldPath": "timestamp", "order": "DESCENDING"}
  ]
},
{
  "collectionGroup": "vitals_activity_logs",
  "queryScope": "COLLECTION",
  "fields": [
    {"fieldPath": "vitals_id", "order": "ASCENDING"},
    {"fieldPath": "timestamp", "order": "DESCENDING"}
  ]
}
```

---

## 🚀 DEPLOYMENT STEPS

### 1. Deploy Cloud Functions
```bash
cd functions
firebase deploy --only functions:autoCreateVitalsDaily,functions:markShiftVitalsAsMissed
```

### 2. Create Firestore Indexes
```bash
firebase deploy --only firestore:indexes
```

### 3. Update Frontend Files
- Follow the implementation guide above for each file
- Test each tab independently
- Verify shift transitions work correctly

### 4. Migration (Optional)
If you have existing `vitals` collection data, you can migrate it to the new structure, but it's optional since the system auto-creates new documents daily.

---

## ✅ TESTING CHECKLIST

- [ ] Cloud Functions deployed successfully
- [ ] vitals_daily auto-created at midnight
- [ ] Pending vitals show in Pending tab
- [ ] Completing vitals moves to Completed tab
- [ ] Missed vitals show in Missed tab at shift end
- [ ] Follow-up vitals update vital_values
- [ ] Activity logs created for all actions
- [ ] UI maintains existing layout
- [ ] Real-time updates work with schedule changes

---

## 📝 NOTES

- **Frontend layout preserved**: All UI components remain unchanged
- **Backend logic replaced**: Old vitals system completely removed
- **New structure benefits**: 
  - ✅ Single document per elderly per day
  - ✅ Independent shift tracking
  - ✅ Complete audit trail
  - ✅ Real-time sync with assignments
  - ✅ Follow-up capability
  - ✅ Daily auto-reset

---

**Status**: Backend ✅ Complete | Frontend ⏳ Pending Implementation
**Updated**: November 25, 2025
