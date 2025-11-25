const {onDocumentCreated, onSchedule} = require('firebase-functions/v2/firestore');
const {setGlobalOptions} = require('firebase-functions/v2');
const {onSchedule: onScheduleV2} = require('firebase-functions/v2/scheduler');
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

// Schedule medication notifications when medication_takes are created
exports.scheduleMedicationNotifications = onDocumentCreated(
  'medication_takes/{takeId}',
  async (event) => {
    const takeData = event.data.data();
    const takeId = event.params.takeId;
    
    try {
      console.log(`New medication take created: ${takeId}`);
      
      // Get medication details
      const medicationDoc = await admin.firestore()
        .collection('medications')
        .doc(takeData.medication_id)
        .get();
        
      if (!medicationDoc.exists) {
        console.error('Medication not found');
        return null;
      }
      
      const medicationData = medicationDoc.data();
      
      // Get elderly details
      const elderlyDoc = await admin.firestore()
        .collection('elderly')
        .doc(medicationData.elderly_id)
        .get();
        
      if (!elderlyDoc.exists) {
        console.error('Elderly not found');
        return null;
      }
      
      const elderlyData = elderlyDoc.data();
      const elderlyName = `${elderlyData.elderly_fname || ''} ${elderlyData.elderly_lname || ''}`.trim();
      
      // Get nurse ID from medication
      const nurseId = medicationData.created_nurse_id;
      if (!nurseId) {
        console.error('No nurse ID found for medication');
        return null;
      }
      
      // Parse scheduled time
      const scheduledTime = takeData.scheduled_time; // Format: "HH:mm:ss"
      const scheduledDate = takeData.scheduled_date;
      
      let notificationDateTime;
      if (scheduledDate) {
        // Use explicit scheduled date
        const date = scheduledDate.toDate();
        const [hours, minutes] = scheduledTime.split(':').map(Number);
        notificationDateTime = new Date(date.getFullYear(), date.getMonth(), date.getDate(), hours, minutes);
      } else {
        // Use today's date with scheduled time
        const now = new Date();
        const [hours, minutes] = scheduledTime.split(':').map(Number);
        notificationDateTime = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hours, minutes);
      }
      
      console.log(`Scheduling notifications for: ${notificationDateTime}`);
      
      // Calculate notification times
      const exactTime = notificationDateTime;

      // Only schedule if time is in the future
      const now = new Date();

      // Schedule exact time notification only (do NOT schedule 30-minute early warnings)
      if (exactTime > now) {
        await admin.firestore().collection('scheduled_notifications').add({
          type: 'medication_exact_time',
          takeId: takeId,
          medicationId: takeData.medication_id,
          nurseId: nurseId,
          elderlyName: elderlyName,
          medicationName: medicationData.medication_name,
          dosage: medicationData.dosage,
          scheduledTime: scheduledTime,
          scheduledFor: admin.firestore.Timestamp.fromDate(exactTime),
          status: 'pending',
          createdAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log(`Scheduled exact time notification for: ${exactTime}`);
      }
      
      return { success: true };
    } catch (error) {
      console.error('Error scheduling medication notifications:', error);
      return null;
    }
  }
);

// Process scheduled medication notifications (runs every minute)
exports.processMedicationNotifications = onScheduleV2('every 1 minutes', async (event) => {
  try {
    console.log('Processing scheduled medication notifications...');
    
    const now = admin.firestore.Timestamp.now();
    
    // Query notifications that are due
    const dueNotifications = await admin.firestore()
      .collection('scheduled_notifications')
      .where('status', '==', 'pending')
      .where('scheduledFor', '<=', now)
      .get();
      
    console.log(`Found ${dueNotifications.size} due notifications`);
    
    for (const notificationDoc of dueNotifications.docs) {
      const notification = notificationDoc.data();
      
      try {
        // Skip 30-minute (or any 5-minute) medication warnings — do not send for medication
        if (notification.type === 'medication_30min_warning' || notification.type === 'medication_5min') {
          console.log(`Skipping medication early-warning notification ${notificationDoc.id} (type=${notification.type})`);
          await notificationDoc.ref.update({
            status: 'skipped',
            skippedAt: admin.firestore.FieldValue.serverTimestamp()
          });
          continue;
        }
        // Get nurse FCM token
        const tokenDoc = await admin.firestore()
          .collection('fcm_tokens')
          .doc(notification.nurseId)
          .get();
          
        if (!tokenDoc.exists || !tokenDoc.data().token) {
          console.log(`No FCM token found for nurse: ${notification.nurseId}`);
          continue;
        }
        
        const token = tokenDoc.data().token;
        
        let title, body;
        
        if (notification.type === 'medication_30min_warning') {
          title = '⏰ Medication Reminder - 30 Minutes';
          body = `${notification.medicationName} (${notification.dosage}) for ${notification.elderlyName} in 30 minutes at ${notification.scheduledTime}`;
        } else if (notification.type === 'medication_exact_time') {
          title = '💊 Medication Time - ACTION REQUIRED';
          body = `Time to administer ${notification.medicationName} (${notification.dosage}) to ${notification.elderlyName}. You have 1 hour before it becomes missed.`;
        }
        
        const message = {
          notification: {
            title: title,
            body: body,
          },
          data: {
            type: 'medication',
            takeId: notification.takeId,
            medicationId: notification.medicationId,
            elderlyName: notification.elderlyName,
            medicationName: notification.medicationName,
            dosage: notification.dosage,
            scheduledTime: notification.scheduledTime,
            notificationType: notification.type,
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
          android: {
            priority: 'high',
            notification: {
              channelId: 'medication_channel',
              priority: 'max',
              sound: 'default',
              tag: `medication_${notification.takeId}`,
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
          token: token
        };
        
        await admin.messaging().send(message);
        console.log(`Sent ${notification.type} notification for take: ${notification.takeId}`);
        
        // Mark notification as sent
        await notificationDoc.ref.update({
          status: 'sent',
          sentAt: admin.firestore.FieldValue.serverTimestamp()
        });
        
      } catch (error) {
        console.error(`Error sending notification ${notificationDoc.id}:`, error);
        // Mark as failed but don't retry to avoid spam
        await notificationDoc.ref.update({
          status: 'failed',
          error: error.message,
          failedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      }
    }
    
    return { processed: dueNotifications.size };
  } catch (error) {
    console.error('Error processing medication notifications:', error);
    return null;
  }
});

// Clean up old notifications (runs daily)
exports.cleanupOldNotifications = onScheduleV2('every 24 hours', async (event) => {
  try {
    console.log('Cleaning up old notifications...');
    
    // Delete notifications older than 7 days
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
    const cutoff = admin.firestore.Timestamp.fromDate(sevenDaysAgo);
    
    const oldNotifications = await admin.firestore()
      .collection('scheduled_notifications')
      .where('createdAt', '<', cutoff)
      .get();
      
    const batch = admin.firestore().batch();
    oldNotifications.docs.forEach(doc => {
      batch.delete(doc.ref);
    });
    
    if (oldNotifications.size > 0) {
      await batch.commit();
      console.log(`Cleaned up ${oldNotifications.size} old notifications`);
    }
    
    return { cleaned: oldNotifications.size };
  } catch (error) {
    console.error('Error cleaning up notifications:', error);
    return null;
  }
});