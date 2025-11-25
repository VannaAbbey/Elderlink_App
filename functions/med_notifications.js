const functions = require('firebase-functions');
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// Schedule a single 30-minute-before notification when a medication_take is created
exports.scheduleMedication30Min = functions.firestore
  .document('medication_takes/{takeId}')
  .onCreate(async (snap, context) => {
    const takeData = snap.data();
    const takeId = context.params.takeId;

    try {
      // Get medication details
      const medicationRef = db.collection('medications').doc(takeData.medication_id);
      const medicationDoc = await medicationRef.get();
      if (!medicationDoc.exists) return null;
      const medication = medicationDoc.data();

      // Get elderly details
      const elderlyRef = db.collection('elderly').doc(medication.elderly_id);
      const elderlyDoc = await elderlyRef.get();
      const elderly = elderlyDoc.exists ? elderlyDoc.data() : {};

      const nurseId = medication.created_nurse_id || medication.assigned_nurse_id || null;
      if (!nurseId) return null;

      // Parse scheduled date/time
      const scheduledTime = takeData.scheduled_time; // "HH:mm[:ss]"
      const scheduledDate = takeData.scheduled_date; // Firestore Timestamp optional

      let notificationDateTime;
      if (scheduledDate && scheduledDate.toDate) {
        const date = scheduledDate.toDate();
        const [hours, minutes] = scheduledTime.split(':').map(Number);
        notificationDateTime = new Date(date.getFullYear(), date.getMonth(), date.getDate(), hours, minutes);
      } else {
        const now = new Date();
        const [hours, minutes] = scheduledTime.split(':').map(Number);
        notificationDateTime = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hours, minutes);
      }

      const thirtyMinutesBefore = new Date(notificationDateTime.getTime() - 30 * 60 * 1000);
      const now = new Date();
      if (thirtyMinutesBefore <= now) {
        // Too late to schedule 30-min notification
        return null;
      }

      // Avoid duplicate scheduled notifications for the same take
      const existing = await db.collection('scheduled_notifications')
        .where('takeId', '==', takeId)
        .where('type', '==', 'medication_30min_single')
        .where('status', 'in', ['pending', 'sent'])
        .limit(1)
        .get();

      if (!existing.empty) return null;

      await db.collection('scheduled_notifications').add({
        type: 'medication_30min_single',
        takeId: takeId,
        medicationId: takeData.medication_id,
        nurseId: nurseId,
        elderlyId: medication.elderly_id || null,
        elderlyName: `${elderly.elderly_fname || ''} ${elderly.elderly_lname || ''}`.trim(),
        medicationName: medication.medication_name || '',
        dosage: medication.dosage || '',
        scheduledFor: admin.firestore.Timestamp.fromDate(thirtyMinutesBefore),
        scheduledTime: scheduledTime,
        status: 'pending',
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      });

      console.log(`Scheduled 30-min medication notification for take ${takeId} at ${thirtyMinutesBefore.toISOString()}`);
      return null;
    } catch (err) {
      console.error('Error scheduling medication 30-min', err);
      return null;
    }
  });

// Process scheduled medication notifications (runs every minute)
exports.processMedicationNotifications = functions.pubsub
  .schedule('every 1 minutes')
  .onRun(async (context) => {
    try {
      const now = admin.firestore.Timestamp.fromDate(new Date());
      const due = await db.collection('scheduled_notifications')
        .where('status', '==', 'pending')
        .where('scheduledFor', '<=', now)
        .limit(100)
        .get();

      console.log(`Found ${due.size} due medication notifications`);

      const todayDateString = new Date().toISOString().slice(0, 10);
      const todayDayName = new Date().toLocaleDateString('en-US', { weekday: 'long' });

      for (const doc of due.docs) {
        const notification = doc.data();
        try {
          if (notification.type !== 'medication_30min_single') {
            // skip unrelated types
            continue;
          }

          const nurseId = notification.nurseId;
          if (!nurseId) {
            await doc.ref.update({ status: 'failed', error: 'no_nurse', failedAt: admin.firestore.FieldValue.serverTimestamp() });
            continue;
          }

          // Check attendance: nurse must be present today
          const attendanceQ = await db.collection('attendance')
            .where('user_id', '==', nurseId)
            .where('date', '==', todayDateString)
            .limit(1)
            .get();

          if (!attendanceQ.empty) {
            const att = attendanceQ.docs[0].data();
            if (att.is_present === false) {
              await doc.ref.update({ status: 'skipped', reason: 'absent', skippedAt: admin.firestore.FieldValue.serverTimestamp() });
              console.log(`Skipping ${doc.id} because nurse ${nurseId} is absent`);
              continue;
            }
          } else {
            // If no attendance record, treat as not present (safer)
            await doc.ref.update({ status: 'skipped', reason: 'no_attendance_record', skippedAt: admin.firestore.FieldValue.serverTimestamp() });
            console.log(`Skipping ${doc.id} because no attendance record for nurse ${nurseId}`);
            continue;
          }

          // Check elderly assignment: nurse must be assigned to this elderly currently
          if (notification.elderlyId) {
            const assignQ = await db.collection('elderly_assignments')
              .where('elderly_id', '==', notification.elderlyId)
              .where('user_id', '==', nurseId)
              .where('is_current', '==', true)
              .limit(1)
              .get();

            if (assignQ.empty) {
              await doc.ref.update({ status: 'skipped', reason: 'not_assigned_to_elderly', skippedAt: admin.firestore.FieldValue.serverTimestamp() });
              console.log(`Skipping ${doc.id} because nurse ${nurseId} not assigned to elderly ${notification.elderlyId}`);
              continue;
            }
          }

          // Check shift assignment for today
          const shiftQ = await db.collection('house_shift_assignments')
            .where('user_id', '==', nurseId)
            .where('is_current', '==', true)
            .where('days_assigned', 'array-contains', todayDayName)
            .limit(1)
            .get();

          if (shiftQ.empty) {
            await doc.ref.update({ status: 'skipped', reason: 'not_scheduled_today', skippedAt: admin.firestore.FieldValue.serverTimestamp() });
            console.log(`Skipping ${doc.id} because nurse ${nurseId} not scheduled today`);
            continue;
          }

          // Get FCM token (prefer fcm_tokens collection, fallback to users.fcm_token)
          let tokenDoc = await db.collection('fcm_tokens').doc(nurseId).get();
          let token = tokenDoc.exists && tokenDoc.data().token ? tokenDoc.data().token : null;
          if (!token) {
            const userDoc = await db.collection('users').doc(nurseId).get();
            token = userDoc.exists ? (userDoc.data().fcm_token || userDoc.data().fcmToken) : null;
          }

          if (!token) {
            await doc.ref.update({ status: 'skipped', reason: 'no_token', skippedAt: admin.firestore.FieldValue.serverTimestamp() });
            console.log(`No FCM token for nurse ${nurseId}, skipping ${doc.id}`);
            continue;
          }

          const title = '⏰ Medication Reminder - 30 Minutes';
          const body = `${notification.medicationName} (${notification.dosage}) for ${notification.elderlyName} in 30 minutes at ${notification.scheduledTime}`;

          const message = {
            token: token,
            notification: { title, body },
            android: { priority: 'high' },
            apns: { headers: { 'apns-priority': '10' } },
            data: {
              type: 'medication',
              takeId: notification.takeId || '',
              medicationId: notification.medicationId || '',
              elderlyName: notification.elderlyName || '',
              medicationName: notification.medicationName || '',
              dosage: notification.dosage || '',
              scheduledTime: notification.scheduledTime || '',
              notificationType: notification.type || 'medication_30min_single',
              click_action: 'FLUTTER_NOTIFICATION_CLICK'
            }
          };

          try {
            await admin.messaging().send(message);
            await doc.ref.update({ status: 'sent', sentAt: admin.firestore.FieldValue.serverTimestamp() });
            console.log(`Sent medication 30-min notification ${doc.id} to nurse ${nurseId}`);
          } catch (sendErr) {
            console.error('Error sending medication notification', sendErr);
            await doc.ref.update({ status: 'failed', error: sendErr.message, failedAt: admin.firestore.FieldValue.serverTimestamp() });
          }
        } catch (innerErr) {
          console.error('Error processing notification', innerErr);
          await doc.ref.update({ status: 'failed', error: innerErr.message, failedAt: admin.firestore.FieldValue.serverTimestamp() });
        }
      }

      return null;
    } catch (err) {
      console.error('processMedicationNotifications error', err);
      return null;
    }
  });
