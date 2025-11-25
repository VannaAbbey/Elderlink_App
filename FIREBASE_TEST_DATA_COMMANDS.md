# FIREBASE TEST DATA CREATION COMMANDS

## 🧪 Create Test Missed Vital (Use Firebase Console)

Once you navigate to the Missed Vitals tab and see the debug logs showing the nurse ID, use this data:

### Collection: `vitals`
### Document ID: `TEST_MISSED_VITAL_001` 

```json
{
  "house_id": "H001",
  "elderly_id": "TEST_E001",
  "assigned_nurse_id": "[REPLACE_WITH_ACTUAL_NURSE_ID_FROM_LOGS]",
  "status": "missed",
  "assigned_date": "2025-11-24", 
  "assigned_time": "08:00",
  "vital_type": "blood_pressure",
  "shift": "morning",
  "created_at": "2025-11-24T08:00:00Z",
  "missed_at": "2025-11-24T14:35:00Z"
}
```

### Collection: `elderly` 
### Document ID: `TEST_E001`

```json
{
  "elderly_fname": "Test",
  "elderly_lname": "Patient", 
  "house_id": "H001"
}
```

### Collection: `vital_activity_logs`
### Auto-generated Document ID

```json
{
  "house_id": "H001",
  "vital_id": "TEST_MISSED_VITAL_001",
  "elderly_id": "TEST_E001", 
  "nurse_id": "[REPLACE_WITH_ACTUAL_NURSE_ID_FROM_LOGS]",
  "nurse_name": "Test Nurse",
  "action_type": "missed_auto",
  "timestamp": "2025-11-24T14:35:00Z",
  "shift": "morning",
  "notes": "Test data for missed vital system validation"
}
```

## 📋 Quick Steps:

1. **Navigate to Missed Vitals tab** → Get nurse ID from debug logs
2. **Replace `[REPLACE_WITH_ACTUAL_NURSE_ID_FROM_LOGS]`** with the actual nurse ID
3. **Add the documents** to Firebase using the web console  
4. **Hot reload the app** or navigate away and back to Missed Vitals tab
5. **Verify** the test vital appears in the UI

## 🎯 Expected Result:

The missed vitals tab should show:
- ✅ Test Patient (Blood Pressure - Missed)  
- ✅ Assigned to: Test Nurse
- ✅ No errors in console
- ✅ Data loads properly

---
**🚀 First: Get the nurse ID from the app debug logs!**