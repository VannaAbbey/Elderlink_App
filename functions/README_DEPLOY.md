Deployment

1. From the `functions` directory run:

```bash
npm install
```

2. Deploy the Cloud Function:

```bash
firebase deploy --only functions:scheduledShiftReminder
```

3. The function is scheduled to run hourly. It will send an FCM notification to a nurse when their shift end is within 2 hours and there are pending vitals for that shift. It records sent notifications in the `shift_notifications_sent` Firestore collection to avoid duplicates.

Notes:
- The function expects `house_shift_assignments` documents to have `user_id`, `shift`, and optionally `end_time` (e.g., '22:00'). If `end_time` is missing, a fallback end time is used per shift.
- Users must have `fcm_token` (or `fcmToken`) on their `users/{userId}` document for delivery.
