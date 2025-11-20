# Firebase Cloud Functions Setup for Background Notifications

This guide explains how to set up Firebase Cloud Functions to send push notifications even when the app is closed.

## Prerequisites

1. Install Node.js (v18 or higher)
2. Install Firebase CLI: `npm install -g firebase-tools`
3. Login to Firebase: `firebase login`

## Setup Steps

### 1. Initialize Firebase Functions

```bash
cd C:\Users\Vanna\Elderlink_App
firebase init functions
```

Select:
- Choose JavaScript or TypeScript
- Install dependencies with npm

### 2. Create Cloud Function

Edit `functions/index.js` (or `index.ts` if TypeScript):

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// Send notification when emergency alert is created
exports.sendEmergencyNotification = functions.firestore
  .document('emergency_alert/{alertId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const nurseIds = data.user_id_nu || [];
    
    const emergencyType = data.emergency_type || 'Emergency';
    const houseName = data.house_name || 'Unknown House';
    const description = data.additional_info || '';
    
    const title = '🚨 Emergency Alert';
    const body = `${emergencyType} at ${houseName}${description ? ' - ' + description : ''}`;
    
    // Get FCM tokens for all nurses
    const tokenPromises = nurseIds.map(nurseId =>
      admin.firestore().collection('fcm_tokens').doc(nurseId).get()
    );
    
    const tokenDocs = await Promise.all(tokenPromises);
    const tokens = tokenDocs
      .filter(doc => doc.exists && doc.data().token)
      .map(doc => doc.data().token);
    
    if (tokens.length === 0) {
      console.log('No FCM tokens found');
      return null;
    }
    
    // Send notification to all tokens
    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        type: 'emergency',
        alertId: context.params.alertId,
        house_name: houseName,
        emergency_type: emergencyType,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      tokens: tokens,
    };
    
    try {
      const response = await admin.messaging().sendMulticast(message);
      console.log(`Successfully sent ${response.successCount} notifications`);
      if (response.failureCount > 0) {
        console.log(`Failed to send ${response.failureCount} notifications`);
      }
      return response;
    } catch (error) {
      console.error('Error sending notification:', error);
      return null;
    }
  });

// Send notification when incident report is created
exports.sendIncidentNotification = functions.firestore
  .document('incident_report/{incidentId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const nurseIds = data.assigned_nurse_ids || [];
    
    const incidentType = data.incident_type || 'Incident';
    const elderlyName = data.elderly_name || 'an elderly resident';
    const description = data.incident_description || '';
    
    const title = '⚠️ Incident Report';
    const body = `${incidentType} involving ${elderlyName}${description ? ' - ' + description : ''}`;
    
    // Get FCM tokens for all assigned nurses
    const tokenPromises = nurseIds.map(nurseId =>
      admin.firestore().collection('fcm_tokens').doc(nurseId).get()
    );
    
    const tokenDocs = await Promise.all(tokenPromises);
    const tokens = tokenDocs
      .filter(doc => doc.exists && doc.data().token)
      .map(doc => doc.data().token);
    
    if (tokens.length === 0) {
      console.log('No FCM tokens found');
      return null;
    }
    
    // Send notification to all tokens
    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        type: 'incident',
        incidentId: context.params.incidentId,
        elderly_name: elderlyName,
        incident_type: incidentType,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      tokens: tokens,
    };
    
    try {
      const response = await admin.messaging().sendMulticast(message);
      console.log(`Successfully sent ${response.successCount} notifications`);
      if (response.failureCount > 0) {
        console.log(`Failed to send ${response.failureCount} notifications`);
      }
      return response;
    } catch (error) {
      console.error('Error sending notification:', error);
      return null;
    }
  });
```

### 3. Install Dependencies

```bash
cd functions
npm install firebase-admin firebase-functions
```

### 4. Deploy Cloud Functions

```bash
firebase deploy --only functions
```

## Testing

1. Create an emergency alert from the caregiver app
2. Check if nurses receive notifications even when app is closed/killed
3. Check Firebase Functions logs: `firebase functions:log`

## Troubleshooting

- **No notifications received**: Check FCM tokens are saved in `fcm_tokens` collection
- **Function errors**: Check logs with `firebase functions:log`
- **Token errors**: Make sure users have granted notification permissions

## Important Notes

- Cloud Functions are triggered automatically when documents are created
- Notifications will be sent even if the app is completely closed
- Make sure to test on a real device (not emulator) for best results
- FCM tokens are automatically managed by the NotificationService in the app

