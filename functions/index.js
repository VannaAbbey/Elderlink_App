const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {setGlobalOptions} = require('firebase-functions/v2');
const admin = require('firebase-admin');
admin.initializeApp();

// Set region for all functions
setGlobalOptions({region: 'asia-southeast1'});

// Send notification when emergency alert is created
exports.sendEmergencyNotification = onDocumentCreated(
  'emergency_alert/{alertId}',
  async (event) => {
    const data = event.data.data();
    const alertId = event.params.alertId;
    const nurseIds = data.user_id_nu || [];
    
    const emergencyType = data.emergency_type || 'Emergency';
    const houseName = data.house_name || 'Unknown House';
    const description = data.additional_info || '';
    
    const title = '🚨 Emergency Alert';
    const body = `${emergencyType} at ${houseName}${description ? ' - ' + description : ''}`;
    
    console.log(`Emergency alert created: ${emergencyType} at ${houseName}`);
    console.log(`Notifying ${nurseIds.length} nurses`);
    
    // Get FCM tokens for all nurses
    const tokenPromises = nurseIds.map(nurseId =>
      admin.firestore().collection('fcm_tokens').doc(nurseId).get()
    );
    
    const tokenDocs = await Promise.all(tokenPromises);
    const tokens = tokenDocs
      .filter(doc => doc.exists && doc.data().token)
      .map(doc => doc.data().token);
    
    if (tokens.length === 0) {
      console.log('No FCM tokens found for nurses');
      return null;
    }
    
    console.log(`Found ${tokens.length} FCM tokens`);
    
    // Send notification to all tokens
    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        type: 'emergency',
        alertId: alertId,
        house_name: houseName,
        emergency_type: emergencyType,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'emergency_channel',
          priority: 'max',
          sound: 'default',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            contentAvailable: true,
          },
        },
      },
    };
    
    try {
      const promises = tokens.map(token => 
        admin.messaging().send({ ...message, token })
      );
      const results = await Promise.allSettled(promises);
      
      const successCount = results.filter(r => r.status === 'fulfilled').length;
      const failureCount = results.filter(r => r.status === 'rejected').length;
      
      console.log(`Successfully sent ${successCount} notifications`);
      if (failureCount > 0) {
        console.log(`Failed to send ${failureCount} notifications`);
      }
      
      return { success: successCount, failed: failureCount };
    } catch (error) {
      console.error('Error sending notifications:', error);
      return null;
    }
  }
);

// Send notification when incident report is created
exports.sendIncidentNotification = onDocumentCreated(
  'incident_report/{incidentId}',
  async (event) => {
    const data = event.data.data();
    const incidentId = event.params.incidentId;
    const nurseIds = data.assigned_nurse_ids || data.user_id_nu || [];
    
    const incidentType = data.incident_type || 'Incident';
    const elderlyName = data.elderly_name || 'an elderly resident';
    const description = data.incident_description || data.additional_info || '';
    
    const title = '⚠️ Incident Report';
    const body = `${incidentType} involving ${elderlyName}${description ? ' - ' + description : ''}`;
    
    console.log(`Incident report created: ${incidentType} involving ${elderlyName}`);
    console.log(`Notifying ${nurseIds.length} nurses`);
    
    // Get FCM tokens for all assigned nurses
    const tokenPromises = nurseIds.map(nurseId =>
      admin.firestore().collection('fcm_tokens').doc(nurseId).get()
    );
    
    const tokenDocs = await Promise.all(tokenPromises);
    const tokens = tokenDocs
      .filter(doc => doc.exists && doc.data().token)
      .map(doc => doc.data().token);
    
    if (tokens.length === 0) {
      console.log('No FCM tokens found for nurses');
      return null;
    }
    
    console.log(`Found ${tokens.length} FCM tokens`);
    
    // Send notification to all tokens
    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        type: 'incident',
        incidentId: incidentId,
        elderly_name: elderlyName,
        incident_type: incidentType,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'emergency_channel',
          priority: 'max',
          sound: 'default',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            contentAvailable: true,
          },
        },
      },
    };
    
    try {
      const promises = tokens.map(token => 
        admin.messaging().send({ ...message, token })
      );
      const results = await Promise.allSettled(promises);
      
      const successCount = results.filter(r => r.status === 'fulfilled').length;
      const failureCount = results.filter(r => r.status === 'rejected').length;
      
      console.log(`Successfully sent ${successCount} notifications`);
      if (failureCount > 0) {
        console.log(`Failed to send ${failureCount} notifications`);
      }
      
      return { success: successCount, failed: failureCount };
    } catch (error) {
      console.error('Error sending notifications:', error);
      return null;
    }
  }
);
