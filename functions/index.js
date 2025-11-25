const {onDocumentCreated, onSchedule} = require('firebase-functions/v2/firestore');
const {setGlobalOptions} = require('firebase-functions/v2');
const {onSchedule: onScheduleV2} = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
admin.initializeApp();

// Set region for all functions
setGlobalOptions({region: 'asia-southeast1'});

// Send notification when emergency alert is created - Updated format
exports.sendEmergencyNotification = onDocumentCreated(
  'emergency_alert/{alertId}',
  async (event) => {
    const data = event.data.data();
    const alertId = event.params.alertId;
    const nurseIds = data.user_id_nu || [];
    
    const emergencyType = data.emergency_type || 'Emergency';
    const houseName = data.house_name || 'Unknown House';
    const description = data.additional_info || '';
    
    // Format timestamp in Philippines timezone (UTC+8)
    const timestamp = data.alert_timestamp || admin.firestore.Timestamp.now();
    const date = timestamp.toDate();
    const formattedTime = date.toLocaleDateString('en-US', {
      month: 'numeric',
      day: 'numeric', 
      year: 'numeric',
      timeZone: 'Asia/Manila'
    }) + ' | ' + date.toLocaleTimeString('en-US', {
      hour: 'numeric',
      minute: '2-digit',
      hour12: true,
      timeZone: 'Asia/Manila'
    });
    
    console.log(`Timestamp conversion: UTC: ${date.toISOString()}, Philippines: ${formattedTime}`);
    
    // New format: "Emergency Alert - House at Date Time"
    const title = `Emergency Alert - ${houseName} at ${formattedTime}`;
    
    // New format: "Emergency Type - Additional Info" 
    let body = emergencyType;
    if (description && description !== 'No description' && description !== 'Emergency alert received') {
      body = `${emergencyType} - ${description}`;
    }
    
    console.log(`Emergency alert created: ${emergencyType} at ${houseName}`);
    console.log(`Notifying ${nurseIds.length} nurses`);
    console.log(`FCM Message - Title: ${title}`);
    console.log(`FCM Message - Body: ${body}`);
    
    // Get FCM tokens for all nurses
    const tokenPromises = nurseIds.map(nurseId =>
      admin.firestore().collection('fcm_tokens').doc(nurseId).get()
    );
    
    const tokenDocs = await Promise.all(tokenPromises);
    const tokens = tokenDocs
      .filter(doc => doc.exists && doc.data().token)
      .map(doc => doc.data().token);
    
    // Remove duplicate tokens to prevent same user getting multiple notifications
    const uniqueTokens = [...new Set(tokens)];
    
    if (uniqueTokens.length === 0) {
      console.log('No FCM tokens found for nurses');
      return null;
    }
    
    console.log(`Found ${tokens.length} total FCM tokens, ${uniqueTokens.length} unique tokens`);
    if (tokens.length !== uniqueTokens.length) {
      console.log(`⚠️ Removed ${tokens.length - uniqueTokens.length} duplicate tokens`);
    }
    
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
        formatted_time: formattedTime,
        timestamp_ms: date.getTime().toString(),
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
      const promises = uniqueTokens.map(token =>
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

// Send notification when incident report is created - Updated format to match Emergency Alert
exports.sendIncidentNotification = onDocumentCreated(
  'incident_report/{incidentId}',
  async (event) => {
    const data = event.data.data();
    const incidentId = event.params.incidentId;
    const nurseIds = data.assigned_nurse_ids || data.user_id_nu || [];
    
    // Check if notification already sent for this incident (deduplication)
    console.log(`🔍 Checking deduplication for incident ${incidentId}`);
    try {
      const notificationDoc = await admin.firestore()
        .collection('incident_notifications_sent')
        .doc(incidentId)
        .get();
        
      if (notificationDoc.exists) {
        const existingData = notificationDoc.data();
        console.log(`⚠️ Incident notification already sent for ${incidentId} at ${existingData.processed_at?.toDate?.() || 'unknown time'}, skipping`);
        return null;
      }
      
      console.log(`✅ First notification for incident ${incidentId}, proceeding`);
      
      // Mark as processing to prevent race conditions
      await admin.firestore()
        .collection('incident_notifications_sent')
        .doc(incidentId)
        .set({
          processed_at: admin.firestore.FieldValue.serverTimestamp(),
          incident_type: data.incident_type || 'Unknown',
          house_name: data.house_name || 'Unknown',
          nurses_notified: nurseIds.length,
          house_id: data.house_id || null
        });
        
      console.log(`📝 Marked incident ${incidentId} as processed in deduplication collection`);
    } catch (error) {
      console.error('❌ Error checking/setting notification deduplication:', error);
      // Don't return null here - continue with notification to avoid missing critical alerts
    }
    
    const incidentType = data.incident_type || 'Incident';
    let houseName = data.house_name || 'Unknown House';
    const description = data.additional_info || '';
    
    // If house_name is not provided, fetch it from house_id
    if (houseName === 'Unknown House' && data.house_id) {
      try {
        const houseDoc = await admin.firestore()
          .collection('house')
          .where('house_id', '==', data.house_id)
          .limit(1)
          .get();
          
        if (!houseDoc.empty) {
          const houseData = houseDoc.docs[0].data();
          houseName = houseData.house_name || 'Unknown House';
          console.log(`Fetched house name from house_id ${data.house_id}: ${houseName}`);
        } else {
          console.log(`No house found with house_id: ${data.house_id}`);
        }
      } catch (error) {
        console.error('Error fetching house name:', error);
      }
    }
    
    // Format timestamp in Philippines timezone (UTC+8)  
    const timestamp = data.incident_date_time || admin.firestore.Timestamp.now();
    const date = timestamp.toDate();
    const formattedTime = date.toLocaleDateString('en-US', {
      month: 'numeric',
      day: 'numeric', 
      year: 'numeric',
      timeZone: 'Asia/Manila'
    }) + ' | ' + date.toLocaleTimeString('en-US', {
      hour: 'numeric',
      minute: '2-digit',
      hour12: true,
      timeZone: 'Asia/Manila'
    });
    
    console.log(`Timestamp conversion: UTC: ${date.toISOString()}, Philippines: ${formattedTime}`);
    
    // New format: "Incident Report - House at Date Time" (matching Emergency Alert format)
    const title = `Incident Report - ${houseName} at ${formattedTime}`;
    
    // New format: "Incident Type - Additional Info"
    let body = incidentType;
    if (description && description !== 'No description' && description !== '') {
      body = `${incidentType} - ${description}`;
    }
    
    console.log(`Incident report created: ${incidentType} at ${houseName}`);
    console.log(`Notifying ${nurseIds.length} nurses`);
    console.log(`FCM Message - Title: ${title}`);
    console.log(`FCM Message - Body: ${body}`);
    
    // Get FCM tokens for all assigned nurses
    const tokenPromises = nurseIds.map(nurseId =>
      admin.firestore().collection('fcm_tokens').doc(nurseId).get()
    );
    
    const tokenDocs = await Promise.all(tokenPromises);
    const tokens = tokenDocs
      .filter(doc => doc.exists && doc.data().token)
      .map(doc => doc.data().token);
    
    // Remove duplicate tokens to prevent same user getting multiple notifications
    const uniqueTokens = [...new Set(tokens)];
    
    if (uniqueTokens.length === 0) {
      console.log('No FCM tokens found for nurses');
      return null;
    }
    
    console.log(`Found ${tokens.length} total FCM tokens, ${uniqueTokens.length} unique tokens`);
    if (tokens.length !== uniqueTokens.length) {
      console.log(`⚠️ Removed ${tokens.length - uniqueTokens.length} duplicate tokens`);
    }
    
    // Send notification to all unique tokens
    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        type: 'incident',
        incidentId: incidentId,
        house_name: houseName,
        incident_type: incidentType,
        formatted_time: formattedTime,
        timestamp_ms: date.getTime().toString(),
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'incident_channel',
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
      const promises = uniqueTokens.map(token => 
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
      
      // Parse scheduled time and date - ENHANCED FOR 7-DAY MEDICATIONS
      const scheduledTime = takeData.scheduled_time; // Format: "HH:mm:ss"
      const scheduledDate = takeData.scheduled_date;
      
      let notificationDateTime;
      if (scheduledDate) {
        // Use explicit scheduled date (for duration-based medications like 7 days)
        // Convert Firestore timestamp to Philippines timezone
        const date = scheduledDate.toDate();
        const [hours, minutes] = scheduledTime.split(':').map(Number);
        
        // Create date in Philippines timezone
        const phpDateStr = date.toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' }); // YYYY-MM-DD format
        const [year, month, day] = phpDateStr.split('-').map(Number);
        notificationDateTime = new Date(year, month - 1, day, hours, minutes); // Month is 0-indexed
        
        console.log(`📅 Using explicit scheduled_date for 7-day med: ${date.toDateString()} at ${scheduledTime}`);
        console.log(`📅 PHP timezone notification: ${notificationDateTime.toLocaleString('en-US', { timeZone: 'Asia/Manila' })}`);
      } else {
        // Use today's date with scheduled time (for Daily medications)
        // Get Philippines time to ensure correct date calculation
        const phpNow = new Date().toLocaleString('en-US', { timeZone: 'Asia/Manila' });
        const now = new Date(phpNow);
        const [hours, minutes] = scheduledTime.split(':').map(Number);
        notificationDateTime = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hours, minutes);
        console.log(`📅 Using today's date for Daily med: ${now.toDateString()} at ${scheduledTime}`);
      }
      
      console.log(`🔔 Scheduling notifications for: ${notificationDateTime.toLocaleString('en-US', { timeZone: 'Asia/Manila' })} PHT`);
      
      // Calculate notification times
      const thirtyMinutesBefore = new Date(notificationDateTime.getTime() - 30 * 60 * 1000);
      const twentyMinutesBefore = new Date(notificationDateTime.getTime() - 20 * 60 * 1000);
      const exactTime = notificationDateTime;
      
      // Get current Philippines time for comparison
      const phpCurrentTime = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Manila' }));
      
      console.log(`⏰ Current PHP time: ${phpCurrentTime.toLocaleString()}`);
      console.log(`⏰ 30-min warning time: ${thirtyMinutesBefore.toLocaleString()}`);
      console.log(`⏰ 20-min warning time: ${twentyMinutesBefore.toLocaleString()}`);
      console.log(`⏰ Exact time: ${exactTime.toLocaleString()}`);
      
      // Check for existing notifications to prevent duplicates
      const existingNotifications = await admin.firestore()
        .collection('scheduled_notifications')
        .where('takeId', '==', takeId)
        .where('status', 'in', ['pending', 'sent'])
        .get();
      
      if (!existingNotifications.empty) {
        console.log(`⚠️ Notifications already exist for takeId: ${takeId}, skipping duplicate creation`);
        return { success: true, message: 'Notifications already exist for this take' };
      }

      // Only schedule if times are in the future (using Philippines time)
      
      // Schedule 30-minute early notification
      if (thirtyMinutesBefore > phpCurrentTime) {
        await admin.firestore().collection('scheduled_notifications').add({
          type: 'medication_30min_warning',
          takeId: takeId,
          medicationId: takeData.medication_id,
          nurseId: nurseId,
          elderlyName: elderlyName,
          medicationName: medicationData.medication_name,
          dosage: medicationData.dosage,
          scheduledTime: scheduledTime,
          scheduledFor: admin.firestore.Timestamp.fromDate(thirtyMinutesBefore),
          status: 'pending',
          createdAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log(`✅ Scheduled 30-min warning for: ${thirtyMinutesBefore.toLocaleString()}`);
      } else {
        console.log(`⏰ Skipping 30-min warning (time already passed): ${thirtyMinutesBefore.toLocaleString()}`);
      }
      
      // Schedule 20-minute early notification
      if (twentyMinutesBefore > phpCurrentTime) {
        await admin.firestore().collection('scheduled_notifications').add({
          type: 'medication_20min_warning',
          takeId: takeId,
          medicationId: takeData.medication_id,
          nurseId: nurseId,
          elderlyName: elderlyName,
          medicationName: medicationData.medication_name,
          dosage: medicationData.dosage,
          scheduledTime: scheduledTime,
          scheduledFor: admin.firestore.Timestamp.fromDate(twentyMinutesBefore),
          status: 'pending',
          createdAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log(`✅ Scheduled 20-min warning for: ${twentyMinutesBefore.toLocaleString()}`);
      } else {
        console.log(`⏰ Skipping 20-min warning (time already passed): ${twentyMinutesBefore.toLocaleString()}`);
      }
      
      // Schedule exact time notification
      if (exactTime > phpCurrentTime) {
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
        console.log(`✅ Scheduled exact time notification for: ${exactTime.toLocaleString()}`);
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
    // Get Philippines time for accurate comparison
    const phpTime = new Date().toLocaleString('en-US', { timeZone: 'Asia/Manila' });
    const phpNow = new Date(phpTime);
    console.log(`🔄 Processing medication notifications at ${phpTime} PHT`);
    console.log(`🔄 UTC time: ${new Date().toISOString()}`);
    
    // Use Philippines time converted to Firestore Timestamp
    const now = admin.firestore.Timestamp.fromDate(phpNow);
    console.log(`🔄 Comparing against timestamp: ${now.toDate().toISOString()}`);
    
    // Query notifications that are due (using Philippines time)
    const dueNotifications = await admin.firestore()
      .collection('scheduled_notifications')
      .where('status', '==', 'pending')
      .where('scheduledFor', '<=', now)
      .get();
      
    console.log(`📋 Found ${dueNotifications.size} due notifications at ${phpTime}`);
    
    for (const notificationDoc of dueNotifications.docs) {
      const notification = notificationDoc.data();
      
      console.log(`📨 Processing notification: ${notificationDoc.id}`);
      console.log(`👤 Nurse: ${notification.nurseId}`);
      console.log(`💊 Medication: ${notification.medicationName} for ${notification.elderlyName}`);
      console.log(`⏰ Scheduled: ${notification.scheduledTime}`);
      console.log(`🏠 Type: ${notification.type}`);
      
      try {
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
        } else if (notification.type === 'medication_20min_warning') {
          title = '🔔 Medication Reminder - 20 Minutes';
          body = `${notification.medicationName} (${notification.dosage}) for ${notification.elderlyName} in 20 minutes at ${notification.scheduledTime}`;
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
              tag: `${notification.type}_${notification.takeId}`, // Unique tag per notification type
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

// Check for pending vitals and send reminder 2 hours before shift ends (runs every 30 minutes)
exports.checkPendingVitalsReminder = onScheduleV2('every 30 minutes', async (event) => {
  try {
    console.log('Checking for pending vitals reminders...');
    
    const now = new Date();
    const currentHour = now.getHours();
    const currentDay = now.toLocaleDateString('en-US', { weekday: 'long' });
    
    // Define shift end times and reminder times (2 hours before)
    const shifts = [
      { name: '1st', endHour: 14, reminderHour: 12 }, // 2:00 PM end, remind at 12:00 PM
      { name: '2nd', endHour: 22, reminderHour: 20 }, // 10:00 PM end, remind at 8:00 PM
      { name: '3rd', endHour: 6, reminderHour: 4 }    // 6:00 AM end, remind at 4:00 AM
    ];
    
    for (const shift of shifts) {
      // Check if current time matches reminder time for this shift
      if (currentHour === shift.reminderHour) {
        console.log(`Processing ${shift.name} shift reminder at ${currentHour}:00`);
        
        // Get all active nurses for this shift
        const shiftAssignments = await admin.firestore()
          .collection('house_shift_assignments')
          .where('shift', '==', shift.name)
          .where('status', '==', 'active')
          .where('is_current', '==', true)
          .get();
          
        console.log(`Found ${shiftAssignments.size} active ${shift.name} shift assignments`);
        
        for (const assignmentDoc of shiftAssignments.docs) {
          const assignment = assignmentDoc.data();
          const nurseId = assignment.user_id;
          const houseId = assignment.house_id;
          
          // Check if nurse is assigned today
          const daysAssigned = assignment.days_assigned || [];
          if (!daysAssigned.includes(currentDay)) {
            console.log(`Nurse ${nurseId} not assigned on ${currentDay}`);
            continue;
          }
          
          try {
            // Get nurse details
            const nurseDoc = await admin.firestore()
              .collection('nurses')
              .doc(nurseId)
              .get();
              
            if (!nurseDoc.exists) {
              console.log(`Nurse ${nurseId} not found`);
              continue;
            }
            
            const nurseData = nurseDoc.data();
            const nurseName = `${nurseData.nurse_fname || ''} ${nurseData.nurse_lname || ''}`.trim();
            
            // Get pending vitals for this nurse's elderly residents
            const elderlyQuery = await admin.firestore()
              .collection('elderly')
              .where('house_id', '==', houseId)
              .get();
              
            const elderlyIds = elderlyQuery.docs.map(doc => doc.id);
            
            if (elderlyIds.length === 0) {
              console.log(`No elderly found for house ${houseId}`);
              continue;
            }
            
            // Get today's date for vitals query
            const today = new Date();
            today.setHours(0, 0, 0, 0);
            const todayTimestamp = admin.firestore.Timestamp.fromDate(today);
            
            // Count pending vitals for today
            let totalPendingVitals = 0;
            const vitalsByElderly = {};
            
            for (const elderlyId of elderlyIds) {
              const vitalsQuery = await admin.firestore()
                .collection('vital_activity_logs')
                .where('elderly_id', '==', elderlyId)
                .where('date', '==', todayTimestamp)
                .where('shift', '==', shift.name)
                .where('status', '==', 'pending')
                .get();
                
              if (vitalsQuery.size > 0) {
                // Get elderly name
                const elderlyDoc = await admin.firestore()
                  .collection('elderly')
                  .doc(elderlyId)
                  .get();
                  
                const elderlyData = elderlyDoc.data();
                const elderlyName = `${elderlyData.elderly_fname || ''} ${elderlyData.elderly_lname || ''}`.trim();
                
                vitalsByElderly[elderlyName] = vitalsQuery.size;
                totalPendingVitals += vitalsQuery.size;
              }
            }
            
            // Only send notification if there are pending vitals
            if (totalPendingVitals > 0) {
              console.log(`Found ${totalPendingVitals} pending vitals for nurse ${nurseName}`);
              
              // Check if we already sent a vitals reminder for this shift today to prevent duplicates
              const today = new Date();
              const todayDateStr = today.toISOString().split('T')[0]; // YYYY-MM-DD format
              
              const existingReminderQuery = await admin.firestore()
                .collection('scheduled_notifications')
                .where('type', '==', 'vitals_reminder')
                .where('nurseId', '==', nurseId)
                .where('shift', '==', shift.name)
                .where('status', '==', 'sent')
                .orderBy('sentAt', 'desc')
                .limit(1)
                .get();
                
              if (!existingReminderQuery.empty) {
                const lastReminder = existingReminderQuery.docs[0].data();
                const lastReminderDate = lastReminder.sentAt.toDate();
                const lastReminderDateStr = lastReminderDate.toISOString().split('T')[0];
                
                if (lastReminderDateStr === todayDateStr) {
                  console.log(`⚠️ Vitals reminder already sent today for nurse ${nurseName} in ${shift.name} shift, skipping duplicate`);
                  continue;
                }
              }
              
              // Get nurse FCM token
              const tokenDoc = await admin.firestore()
                .collection('fcm_tokens')
                .doc(nurseId)
                .get();
                
              if (!tokenDoc.exists || !tokenDoc.data().token) {
                console.log(`No FCM token found for nurse: ${nurseId}`);
                continue;
              }
              
              const token = tokenDoc.data().token;
              
              // Create summary message
              const elderlyList = Object.entries(vitalsByElderly)
                .map(([name, count]) => `${name} (${count})`)
                .join(', ');
                
              const title = '📊 Vitals Reminder - 2 Hours Left';
              const body = `${totalPendingVitals} pending vitals need completion before your ${shift.name} shift ends. Residents: ${elderlyList}`;
              
              const message = {
                notification: {
                  title: title,
                  body: body,
                },
                data: {
                  type: 'vitals_reminder',
                  shift: shift.name,
                  totalPending: totalPendingVitals.toString(),
                  houseId: houseId,
                  nurseId: nurseId,
                  nurseName: nurseName,
                  elderlyDetails: JSON.stringify(vitalsByElderly),
                  click_action: 'FLUTTER_NOTIFICATION_CLICK',
                },
                android: {
                  priority: 'high',
                  notification: {
                    channelId: 'vitals_channel',
                    priority: 'max',
                    sound: 'default',
                    tag: `vitals_reminder_${nurseId}_${shift.name}`,
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
              console.log(`Sent vitals reminder to ${nurseName}: ${totalPendingVitals} pending vitals`);
              
              // Log the reminder in scheduled_notifications for tracking
              await admin.firestore().collection('scheduled_notifications').add({
                type: 'vitals_reminder',
                nurseId: nurseId,
                nurseName: nurseName,
                shift: shift.name,
                houseId: houseId,
                totalPendingVitals: totalPendingVitals,
                elderlyDetails: vitalsByElderly,
                status: 'sent',
                sentAt: admin.firestore.FieldValue.serverTimestamp(),
                createdAt: admin.firestore.FieldValue.serverTimestamp()
              });
              
            } else {
              console.log(`No pending vitals found for nurse ${nurseName} in ${shift.name} shift`);
            }
            
          } catch (error) {
            console.error(`Error processing vitals reminder for nurse ${nurseId}:`, error);
          }
        }
      }
    }
    
    return { success: true, processedAt: now.toISOString() };
  } catch (error) {
    console.error('Error checking pending vitals reminders:', error);
    return null;
  }
});

// Auto-mark pending vitals as missed at shift end (runs every 5 minutes)
exports.markPendingVitalsAsMissedAtShiftEnd = onScheduleV2('every 5 minutes', async (event) => {
  try {
    console.log('🔄 Checking for shift transitions to mark pending vitals as missed...');
    
    // Use Philippines timezone (UTC+8) for shift timing
    const now = new Date();
    const philippinesTime = new Date(now.toLocaleString("en-US", {timeZone: "Asia/Manila"}));
    const currentHour = philippinesTime.getHours();
    const currentMinute = philippinesTime.getMinutes();
    
    console.log(`Current Philippines time: ${philippinesTime.toLocaleString()}`);
    console.log(`Hour: ${currentHour}, Minute: ${currentMinute}`);
    const today = philippinesTime.toISOString().split('T')[0]; // Format: YYYY-MM-DD (Philippines date)

    let endedShift = '';

    // Check if we're at shift transition time (with 30-minute buffer for reliability)
    if (currentHour === 14 && currentMinute >= 0 && currentMinute <= 30) {
      endedShift = '1st'; // 1st shift ended at 2:00 PM (check until 2:30 PM)
    } else if (currentHour === 22 && currentMinute >= 0 && currentMinute <= 30) {
      endedShift = '2nd'; // 2nd shift ended at 10:00 PM (check until 10:30 PM)
    } else if (currentHour === 6 && currentMinute >= 0 && currentMinute <= 30) {
      endedShift = '3rd'; // 3rd shift ended at 6:00 AM (check until 6:30 AM)
    }

    if (!endedShift) {
      console.log('Not at shift transition time, skipping');
      return { success: true, message: 'Not at shift transition time' };
    }

    console.log(`🚨 Shift transition detected: ${endedShift} shift ended, marking pending vitals as missed`);

    // STEP 1: Get all nurse assignments for the ended shift today
    console.log(`📋 Finding nurses who worked ${endedShift} shift today...`);
    const nurseAssignments = await admin.firestore()
      .collection('house_shift_assignments')
      .where('shift', '==', endedShift)
      .where('day', '==', now.toLocaleDateString('en-US', { weekday: 'long', timeZone: 'Asia/Manila' }))
      .where('is_current', '==', true)
      .get();

    if (nurseAssignments.empty) {
      console.log(`No nurse assignments found for ${endedShift} shift today`);
      return { success: true, message: `No nurse assignments found for ${endedShift} shift today` };
    }

    console.log(`Found ${nurseAssignments.size} nurse assignments for ${endedShift} shift`);

    let totalMissedVitals = 0;
    const allProcessedVitals = [];

    // STEP 2: Process each nurse's assignments separately
    for (const assignDoc of nurseAssignments.docs) {
      const assignData = assignDoc.data();
      const nurseId = assignData.user_id;
      const houseId = assignData.house_id;
      const elderlyIds = assignData.elderly_ids || [];

      console.log(`👩‍⚕️ Processing nurse ${nurseId} in house ${houseId} with ${elderlyIds.length} elderly assignments`);

      if (!nurseId || !houseId || elderlyIds.length === 0) {
        console.log(`⚠️ Skipping incomplete assignment: nurseId=${nurseId}, houseId=${houseId}, elderlyCount=${elderlyIds.length}`);
        continue;
      }

      // STEP 3: Get ONLY pending vitals for THIS nurse's assigned elderly
      const nursePendingVitals = await admin.firestore()
        .collection('vitals')
        .where('assigned_date', '==', today)
        .where('shift', '==', endedShift)
        .where('status', '==', 'pending')
        .where('assigned_nurse_id', '==', nurseId)
        .where('house_id', '==', houseId)
        .get();

      if (nursePendingVitals.empty) {
        console.log(`✅ No pending vitals found for nurse ${nurseId} in ${endedShift} shift`);
        continue;
      }

      // STEP 4: Filter to ensure vitals are only for elderly assigned to this nurse
      const validVitals = nursePendingVitals.docs.filter(doc => {
        const vitalData = doc.data();
        const isAssigned = elderlyIds.includes(vitalData.elderly_id);
        if (!isAssigned) {
          console.log(`⚠️ Skipping vital ${doc.id} - elderly ${vitalData.elderly_id} not assigned to nurse ${nurseId}`);
        }
        return isAssigned;
      });

      if (validVitals.length === 0) {
        console.log(`✅ No valid pending vitals found for nurse ${nurseId}'s assigned elderly`);
        continue;
      }

      console.log(`📊 Found ${validVitals.length} pending vitals to mark as missed for nurse ${nurseId}`);
      totalMissedVitals += validVitals.length;

      // STEP 5: Get nurse and elderly names for this nurse's assignments
      let nurseName = 'Unknown Nurse';
      try {
        const nurseDoc = await admin.firestore().collection('users').doc(nurseId).get();
        if (nurseDoc.exists) {
          const userData = nurseDoc.data();
          nurseName = `${userData.user_fname || ''} ${userData.user_lname || ''}`.trim();
        }
      } catch (error) {
        console.error(`Error fetching nurse ${nurseId}:`, error);
      }

      const elderlyNames = {};
      for (const elderlyId of elderlyIds) {
        try {
          const elderlyDoc = await admin.firestore().collection('elderly').doc(elderlyId).get();
          if (elderlyDoc.exists) {
            const elderlyData = elderlyDoc.data();
            elderlyNames[elderlyId] = `${elderlyData.elderly_fname || ''} ${elderlyData.elderly_lname || ''}`.trim();
          } else {
            elderlyNames[elderlyId] = 'Unknown Elderly';
          }
        } catch (error) {
          console.error(`Error fetching elderly ${elderlyId}:`, error);
          elderlyNames[elderlyId] = 'Unknown Elderly';
        }
      }

      // STEP 6: Mark this nurse's pending vitals as missed (with duplicate prevention)
      const batch = admin.firestore().batch();
      const nurseProcessedVitals = [];

      validVitals.forEach(doc => {
        const data = doc.data();
        const elderlyId = data.elderly_id;

        // Update vital status to missed
        batch.update(doc.ref, {
          status: 'missed',
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
          missed_reason: `Auto-marked as missed - ${endedShift} shift ended without completion`,
          missed_at: admin.firestore.FieldValue.serverTimestamp(),
          auto_missed_by: 'system', // ✅ Mark as system processed
          processed_shift: endedShift, // ✅ Track which shift was processed
        });

        // Create activity log for missed vital (with proper elderly name)
        const elderlyName = elderlyNames[elderlyId] || `Elderly-${elderlyId}`;
        const activityLogRef = admin.firestore().collection('vital_activity_logs').doc();
        batch.set(activityLogRef, {
          vital_id: doc.id,
          elderly_id: elderlyId,
          elderly_name: elderlyName, // ✅ Guaranteed proper name
          nurse_id: nurseId,
          nurse_name: nurseName,
          house_id: houseId,
          action_type: 'vital_missed',
          old_value: { 
            status: 'pending', // 🎯 CRITICAL: Store original status for UI filtering
            assigned_date: today,
            shift: endedShift
          },
          new_value: {
            status: 'missed',
            missed_reason: `Auto-marked as missed - ${endedShift} shift ended without completion`,
            missed_at: admin.firestore.FieldValue.serverTimestamp()
          },
          remarks: `Automatically marked as missed at end of ${endedShift} shift (${philippinesTime.toTimeString().substring(0, 5)} PHT)`,
          shift: endedShift,
          assigned_date: today,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          auto_processed: true, // ✅ Mark as automatically processed
          processing_time: philippinesTime.toISOString(), // ✅ Track when processed
          original_status_verified: 'pending', // 🎯 Extra field for double verification
        });

        nurseProcessedVitals.push({
          vital_id: doc.id,
          elderly_name: elderlyNames[elderlyId] || 'Unknown Elderly',
          nurse_name: nurseName,
        });

        console.log(`✅ Marking vital as missed: ${elderlyNames[elderlyId]} (Nurse: ${nurseName}) - ${endedShift} shift`);
      });

      await batch.commit();
      console.log(`🎯 Successfully marked ${validVitals.length} vitals as missed for nurse ${nurseName}`);

      allProcessedVitals.push(...nurseProcessedVitals);
    }

    if (totalMissedVitals === 0) {
      console.log(`✅ No pending vitals found for any nurses in ${endedShift} shift`);
      return { success: true, message: `No pending vitals found for any nurses in ${endedShift} shift` };
    }

    console.log(`🎉 COMPLETED: Marked ${totalMissedVitals} pending vitals as missed for ${endedShift} shift across all nurses`);

    // STEP 7: Also mark pending medication takes as missed at shift end
    let totalMissedMedications = 0;
    const allProcessedMedications = [];

    for (const assignDoc of nurseAssignments.docs) {
      const assignData = assignDoc.data();
      const nurseId = assignData.user_id;
      const houseId = assignData.house_id;
      const elderlyIds = assignData.elderly_ids || [];

      console.log(`💊 Processing medications for nurse ${nurseId} in house ${houseId}`);

      if (!nurseId || !houseId || elderlyIds.length === 0) {
        continue;
      }

      // Get pending medication takes for this nurse's assigned elderly
      const pendingMedicationTakes = await admin.firestore()
        .collection('medication_takes')
        .where('assigned_date', '==', today)
        .where('shift', '==', endedShift)
        .where('status', '==', 'pending')
        .where('assigned_nurse_id', '==', nurseId)
        .where('house_id', '==', houseId)
        .get();

      if (pendingMedicationTakes.empty) {
        console.log(`✅ No pending medication takes for nurse ${nurseId}`);
        continue;
      }

      // Filter to ensure medication takes are only for elderly assigned to this nurse
      const validMedicationTakes = pendingMedicationTakes.docs.filter(doc => {
        const takeData = doc.data();
        const isAssigned = elderlyIds.includes(takeData.elderly_id);
        if (!isAssigned) {
          console.log(`⚠️ Skipping medication take ${doc.id} - elderly ${takeData.elderly_id} not assigned to nurse ${nurseId}`);
        }
        return isAssigned;
      });

      if (validMedicationTakes.length === 0) {
        console.log(`✅ No valid pending medication takes for nurse ${nurseId}'s assigned elderly`);
        continue;
      }

      console.log(`📊 Found ${validMedicationTakes.length} pending medication takes to mark as missed for nurse ${nurseId}`);
      totalMissedMedications += validMedicationTakes.length;

      // Get nurse name for logging
      let nurseName = 'Unknown Nurse';
      try {
        const nurseDoc = await admin.firestore().collection('users').doc(nurseId).get();
        if (nurseDoc.exists) {
          const userData = nurseDoc.data();
          nurseName = `${userData.user_fname || ''} ${userData.user_lname || ''}`.trim();
        }
      } catch (error) {
        console.error(`Error fetching nurse ${nurseId}:`, error);
      }

      // Get elderly names for this nurse's assignments
      const elderlyNames = {};
      for (const elderlyId of elderlyIds) {
        try {
          const elderlyDoc = await admin.firestore().collection('elderly').doc(elderlyId).get();
          if (elderlyDoc.exists) {
            const elderlyData = elderlyDoc.data();
            elderlyNames[elderlyId] = `${elderlyData.elderly_fname || ''} ${elderlyData.elderly_lname || ''}`.trim();
          } else {
            elderlyNames[elderlyId] = 'Unknown Elderly';
          }
        } catch (error) {
          console.error(`Error fetching elderly ${elderlyId}:`, error);
          elderlyNames[elderlyId] = 'Unknown Elderly';
        }
      }

      // Mark medication takes as missed
      const medicationBatch = admin.firestore().batch();
      const nurseProcessedMedications = [];

      validMedicationTakes.forEach(doc => {
        const data = doc.data();
        const elderlyId = data.elderly_id;

        // Update medication take status to missed
        medicationBatch.update(doc.ref, {
          status: 'missed',
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
          missed_reason: `Auto-marked as missed - ${endedShift} shift ended without administration`,
          missed_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Create medication activity log
        const medicationActivityLogRef = admin.firestore().collection('medication_activity_logs').doc();
        medicationBatch.set(medicationActivityLogRef, {
          take_id: doc.id,
          elderly_id: elderlyId,
          elderly_name: elderlyNames[elderlyId] || 'Unknown Elderly',
          nurse_id: nurseId,
          nurse_name: nurseName,
          house_id: houseId,
          action_type: 'medication_missed',
          old_value: { status: 'pending' },
          new_value: {
            status: 'missed',
            missed_reason: `Auto-marked as missed - ${endedShift} shift ended without administration`,
          },
          remarks: `Automatically marked as missed at end of ${endedShift} shift (${philippinesTime.toTimeString().substring(0, 5)} PHT)`,
          shift: endedShift,
          assigned_date: today,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        nurseProcessedMedications.push({
          take_id: doc.id,
          elderly_name: elderlyNames[elderlyId] || 'Unknown Elderly',
          nurse_name: nurseName,
          medication_name: data.medication_name || 'Unknown Medication',
        });

        console.log(`✅ Marking medication take as missed: ${data.medication_name} for ${elderlyNames[elderlyId]} (Nurse: ${nurseName}) - ${endedShift} shift`);
      });

      await medicationBatch.commit();
      console.log(`🎯 Successfully marked ${validMedicationTakes.length} medication takes as missed for nurse ${nurseName}`);

      allProcessedMedications.push(...nurseProcessedMedications);
    }

    console.log(`🎉 COMPLETED: Marked ${totalMissedVitals} vitals and ${totalMissedMedications} medications as missed for ${endedShift} shift across all nurses`);

    return {
      success: true,
      shift: endedShift,
      vitalsMarkedAsMissed: totalMissedVitals,
      medicationsMarkedAsMissed: totalMissedMedications,
      processedVitals: allProcessedVitals,
      processedMedications: allProcessedMedications,
      processedAt: now.toISOString()
    };

  } catch (error) {
    console.error('❌ Error marking pending vitals as missed:', error);
    return { success: false, error: error.message };
  }
});
