const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// Load medication notification handlers (separate file)
try {
  require('./med_notifications');
} catch (e) {
  console.warn('Could not load med_notifications.js', e);
}

// Runs hourly. For each current house_shift_assignment check if the shift end
// time is within 2 hours. If so, check for pending vitals for that shift and
// send a single FCM reminder to the assigned nurse. Record sent reminders in
// `shift_notifications_sent` to avoid duplicates.
exports.scheduledShiftReminder = functions.pubsub
  .schedule('every 1 hours')
  .onRun(async (context) => {
    try {
      const now = new Date();
      const todayDayName = now.toLocaleDateString('en-US', { weekday: 'long' });
      const todayDateString = now.toISOString().slice(0, 10); // yyyy-mm-dd

      const assignmentsSnapshot = await db
        .collection('house_shift_assignments')
        .where('is_current', '==', true)
        .where('days_assigned', 'array-contains', todayDayName)
        .get();

      console.log(`Found ${assignmentsSnapshot.size} shift assignments for ${todayDayName}`);

      for (const doc of assignmentsSnapshot.docs) {
        const data = doc.data();
        const assignmentId = doc.id;
        const shift = data.shift || null; // '1st'|'2nd'|'3rd'
        const userId = data.user_id || null; // nurse id
        const houseId = data.house_id || null;

        if (!shift || !userId || !houseId) continue;

        // Determine shift end time and compute notification time (end - 2 hours)
        let endHour = null;
        let endMinute = 0;
        if (data.end_time) {
          // Expecting something like '22:00' or '06:00'
          const parts = data.end_time.split(':');
          endHour = parseInt(parts[0], 10);
          endMinute = parts[1] ? parseInt(parts[1], 10) : 0;
        } else {
          // fallback by shift end times (authoritative): 1st=14:00, 2nd=22:00, 3rd=06:00
          if (shift === '1st') {
            endHour = 14; // 14:00
          } else if (shift === '2nd') {
            endHour = 22; // 22:00
          } else {
            endHour = 6; // 06:00 (next day for 3rd)
          }
        }

        // Build shift end Date (handle 3rd shift crossing midnight)
        let shiftEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate(), endHour, endMinute, 0);
        if (shift === '3rd') {
          // 3rd shift end is next calendar day at endHour
          shiftEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, endHour, endMinute, 0);
        }

        // Notification time = shiftEnd - 2 hours
        const notificationTime = new Date(shiftEnd.getTime() - 2 * 60 * 60 * 1000);

        // We run hourly; trigger only if current time is within the notification hour window
        // i.e. now >= notificationTime && now < notificationTime + 1 hour
        const oneHour = 60 * 60 * 1000;
        if (!(now.getTime() >= notificationTime.getTime() && now.getTime() < notificationTime.getTime() + oneHour)) {
          // Not the notification window for this shift
          continue;
        }

        // Check if we've already sent notification for this assignment+date+shift
        const sentDocId = `${assignmentId}_${todayDateString}_${shift}`;
        const sentRef = db.collection('shift_notifications_sent').doc(sentDocId);
        const sentSnap = await sentRef.get();
        if (sentSnap.exists) {
          console.log(`Reminder already sent for ${sentDocId}, skipping.`);
          continue;
        }

        // Query vitals_daily for this house and date and check for pending vitals for this shift
        const vitalsSnapshot = await db
          .collection('vitals_daily')
          .where('house_id', '==', houseId)
          .where('assigned_date', '==', todayDateString)
          .get();

        let pendingCount = 0;
        for (const vdoc of vitalsSnapshot.docs) {
          const vdata = vdoc.data();
          const shiftStatus = vdata.shift_status || {};
          const sData = shiftStatus[shift];
          if (!sData) continue;
          const status = sData.status || null;
          const assignedNurseId = sData.assigned_nurse_id || null;

          // If shift_status.assigned_nurse_id is present, prefer it; otherwise fall back to assignment userId
          const relevantNurseId = assignedNurseId || userId;
          if (relevantNurseId === userId && status === 'pending') {
            pendingCount += 1;
          }
        }

        if (pendingCount <= 0) {
          console.log(`No pending vitals for assignment ${assignmentId} (shift ${shift}), skipping.`);
          // Still create a small record to prevent checking repeatedly in the last 2 hours? No — skip.
          continue;
        }

        // Check attendance for this nurse for today+shift. If an attendance record exists
        // and `is_present === false`, the nurse is absent and should NOT receive the reminder.
        try {
          const attendanceQuery = await db
            .collection('attendance')
            .where('user_id', '==', userId)
            .where('date', '==', todayDateString)
            .where('shift', '==', shift)
            .limit(1)
            .get();

          if (!attendanceQuery.empty) {
            const att = attendanceQuery.docs[0].data();
            if (att.is_present === false) {
              console.log(`User ${userId} is marked absent for ${todayDateString} ${shift} — skipping reminder.`);
              continue;
            }
          }
        } catch (attErr) {
          console.warn('Attendance check failed, proceeding with caution', attErr);
        }

        // Get user's FCM token
        const userSnap = await db.collection('users').doc(userId).get();
        if (!userSnap.exists) {
          console.log(`User ${userId} not found, skipping notification.`);
          continue;
        }
        const userData = userSnap.data() || {};
        const fcmToken = userData.fcm_token || userData.fcmToken || null;
        if (!fcmToken) {
          console.log(`No FCM token for user ${userId}, skipping.`);
          continue;
        }

        // Compose a simple reminder message (do not include counts per requirement)
        const message = {
          token: fcmToken,
          notification: {
            title: 'Shift Reminder',
            body: 'You have 2 hours to record remaining vitals in your shift.',
          },
          android: {
            priority: 'high',
          },
          apns: {
            headers: {
              'apns-priority': '10'
            }
          }
        };

        try {
          await admin.messaging().send(message);
          console.log(`Sent reminder to ${userId} for assignment ${assignmentId} (pending=${pendingCount})`);
          // Record that we sent a reminder for this assignment+date+shift
          await sentRef.set({
            assignment_id: assignmentId,
            user_id: userId,
            house_id: houseId,
            shift: shift,
            date: todayDateString,
            sent_at: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (err) {
          console.error('Error sending FCM message', err);
        }
      }

      return null;
    } catch (err) {
      console.error('scheduledShiftReminder error', err);
      return null;
    }
  });
const {onDocumentCreated, onSchedule} = require('firebase-functions/v2/firestore');
const {setGlobalOptions} = require('firebase-functions/v2');
const {onSchedule: onScheduleV2} = require('firebase-functions/v2/scheduler');
// `admin` was initialized above; reuse the existing admin instance

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
      const exactTime = notificationDateTime;

      // Get current Philippines time for comparison
      const phpCurrentTime = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Manila' }));

      console.log(`⏰ Current PHP time: ${phpCurrentTime.toLocaleString()}`);
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

      // Only schedule exact time notification (do not schedule early warnings)
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
        // Skip early medication warnings (30/20/5 minutes) — do not send these for medication
        if (notification.type === 'medication_30min_warning' || notification.type === 'medication_20min_warning' || notification.type === 'medication_5min') {
          console.log(`Skipping early medication notification ${notificationDoc.id} (type=${notification.type})`);
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

// ============================================================================
// NEW VITALS SYSTEM - AUTO-CREATE vitals_daily & HANDLE SHIFT TRANSITIONS
// ============================================================================

// Auto-create vitals_daily documents at day start (runs every 5 minutes at midnight window)
exports.autoCreateVitalsDaily = onScheduleV2('every 5 minutes', async (event) => {
  try {
    const now = new Date();
    const philippinesTime = new Date(now.toLocaleString("en-US", {timeZone: "Asia/Manila"}));
    const currentHour = philippinesTime.getHours();
    const currentMinute = philippinesTime.getMinutes();
    
    // Only run between 12:00 AM and 12:30 AM Philippines time
    if (currentHour !== 0 || currentMinute > 30) {
      return { success: true, message: 'Not in auto-create window' };
    }

    console.log('🌅 Auto-creating vitals_daily documents for new day...');
    
    const today = philippinesTime.toISOString().split('T')[0]; // YYYY-MM-DD
    
    // Get all active elderly residents
    const elderlyQuery = await admin.firestore()
      .collection('elderly')
      .where('status', '==', 'active')
      .get();
    
    if (elderlyQuery.empty) {
      console.log('No active elderly found');
      return { success: true, message: 'No active elderly found' };
    }

    console.log(`Found ${elderlyQuery.size} active elderly residents`);
    
    const batch = admin.firestore().batch();
    let createdCount = 0;

    for (const elderlyDoc of elderlyQuery.docs) {
      const elderlyData = elderlyDoc.data();
      const elderlyId = elderlyDoc.id;
      const elderlyName = `${elderlyData.elderly_fname || ''} ${elderlyData.elderly_lname || ''}`.trim();
      const houseId = elderlyData.house_id || '';

      if (!houseId) {
        console.log(`⚠️ Skipping elderly ${elderlyId} - no house_id`);
        continue;
      }

      // Check if vitals_daily already exists for today
      const vitalsId = `${elderlyId}_${today}`;
      const existingVital = await admin.firestore()
        .collection('vitals_daily')
        .doc(vitalsId)
        .get();

      if (existingVital.exists) {
        console.log(`✅ vitals_daily already exists for ${elderlyName} (${vitalsId})`);
        continue;
      }

      // Create new vitals_daily document
      const vitalsDailyRef = admin.firestore().collection('vitals_daily').doc(vitalsId);
      batch.set(vitalsDailyRef, {
        vitals_id: vitalsId,
        elderly_id: elderlyId,
        elderly_name: elderlyName,
        assigned_date: today,
        house_id: houseId,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        created_by: 'system',
        vital_values: {
          blood_pressure: null,
          temperature: null,
          pulse_rate: null,
          oxygen_saturation: null,
          respiratory_rate: null,
          notes: null,
          last_updated_at: null,
          last_updated_by: null
        },
        shift_status: {
          '1st': { status: 'pending', completed_by: null, completed_at: null, missed_reason: null },
          '2nd': { status: 'pending', completed_by: null, completed_at: null, missed_reason: null },
          '3rd': { status: 'pending', completed_by: null, completed_at: null, missed_reason: null }
        },
        any_completed: false,
        any_missed: false,
        updated_at: null
      });

      createdCount++;
      console.log(`✅ Created vitals_daily for ${elderlyName} (${vitalsId})`);
    }

    if (createdCount > 0) {
      await batch.commit();
      console.log(`🎉 Successfully created ${createdCount} vitals_daily documents`);
    }

    return {
      success: true,
      date: today,
      created: createdCount,
      totalElderly: elderlyQuery.size
    };

  } catch (error) {
    console.error('❌ Error auto-creating vitals_daily:', error);
    return { success: false, error: error.message };
  }
});

// Auto-mark pending shift_status as missed at shift end (runs every 5 minutes)
exports.markShiftVitalsAsMissed = onScheduleV2('every 5 minutes', async (event) => {
  try {
    const now = new Date();
    const philippinesTime = new Date(now.toLocaleString("en-US", {timeZone: "Asia/Manila"}));
    const currentHour = philippinesTime.getHours();
    const currentMinute = philippinesTime.getMinutes();
    const today = philippinesTime.toISOString().split('T')[0];

    let endedShift = '';

    // Check if we're at shift transition time (with 30-minute buffer)
    if (currentHour === 14 && currentMinute >= 0 && currentMinute <= 30) {
      endedShift = '1st';
    } else if (currentHour === 22 && currentMinute >= 0 && currentMinute <= 30) {
      endedShift = '2nd';
    } else if (currentHour === 6 && currentMinute >= 0 && currentMinute <= 30) {
      endedShift = '3rd';
    }

    if (!endedShift) {
      return { success: true, message: 'Not at shift transition time' };
    }

    console.log(`🚨 Shift ${endedShift} ended - marking pending vitals as missed...`);

    // Get all vitals_daily for today with pending status for the ended shift
    const vitalsDailyQuery = await admin.firestore()
      .collection('vitals_daily')
      .where('assigned_date', '==', today)
      .get();

    if (vitalsDailyQuery.empty) {
      console.log('No vitals_daily documents found for today');
      return { success: true, message: 'No vitals_daily found' };
    }

    const batch = admin.firestore().batch();
    let missedCount = 0;

    for (const vitalDoc of vitalsDailyQuery.docs) {
      const vitalData = vitalDoc.data();
      const shiftStatus = vitalData.shift_status || {};
      const currentShiftStatus = shiftStatus[endedShift] || {};

      // Only mark as missed if still pending
      if (currentShiftStatus.status === 'pending') {
        // Update shift_status
        batch.update(vitalDoc.ref, {
          [`shift_status.${endedShift}.status`]: 'missed',
          [`shift_status.${endedShift}.missed_reason`]: `Auto-marked: ${endedShift} shift ended without completion`,
          any_missed: true,
          updated_at: admin.firestore.FieldValue.serverTimestamp()
        });

        // Create activity log
        const activityLogRef = admin.firestore().collection('vitals_activity_logs').doc();
        batch.set(activityLogRef, {
          activity_id: activityLogRef.id,
          vitals_id: vitalDoc.id,
          elderly_id: vitalData.elderly_id,
          elderly_name: vitalData.elderly_name,
          assigned_date: today,
          action_type: 'shift_missed',
          shift: endedShift,
          nurse_id: null,
          nurse_name: 'system',
          old_value: { status: 'pending' },
          new_value: { 
            status: 'missed',
            missed_reason: `Auto-marked: ${endedShift} shift ended without completion`
          },
          remarks: `Automatically marked as missed at ${philippinesTime.toTimeString().substring(0, 5)} PHT`,
          timestamp: admin.firestore.FieldValue.serverTimestamp()
        });

        missedCount++;
        console.log(`✅ Marked ${vitalData.elderly_name} - ${endedShift} shift as missed`);
      }
    }

    if (missedCount > 0) {
      await batch.commit();
      console.log(`🎉 Marked ${missedCount} shift vitals as missed`);
    }

    return {
      success: true,
      shift: endedShift,
      missedCount: missedCount,
      date: today
    };

  } catch (error) {
    console.error('❌ Error marking shift vitals as missed:', error);
    return { success: false, error: error.message };
  }
});
