# Task Reminder System

## Overview
The Task Reminder System provides real-time notifications and alarms for caregivers when their assigned tasks are about to start. The system is implemented as a separate service to keep the main task screen clean and maintainable.

## Features

### Notification Types
1. **15-minute Warning**: Reminder notification 15 minutes before task start
2. **5-minute Warning**: Urgent reminder 5 minutes before task start  
3. **Task Start Alarm**: High-priority alarm when task should begin
4. **Overdue Alert**: Warning 15 minutes after task start if not completed

### Integration Points
- **Task Creation**: Automatically schedules reminders when new tasks are created
- **Task Completion**: Cancels pending reminders when tasks are marked complete/incomplete
- **Recurring Tasks**: Handles scheduling for "Only once", "Every Assigned Day", and "Custom" frequency types

## Implementation Details

### Files Added/Modified
1. `lib/services/task_reminder_service.dart` - Main reminder service
2. `lib/main.dart` - Service initialization 
3. `lib/caregiver/upcoming_tasks_screen.dart` - Integration with task creation/completion
4. `pubspec.yaml` - Added notification dependencies
5. `android/app/src/main/AndroidManifest.xml` - Android permissions and services

### Dependencies Added
- `flutter_local_notifications: ^17.2.2` - Cross-platform notifications
- `android_alarm_manager_plus: ^4.0.4` - Android alarm scheduling
- `permission_handler: ^11.3.1` - Runtime permissions  
- `workmanager: ^0.5.2` - Background processing
- `flutter_ringtone_player: ^4.0.0+3` - Alarm sounds
- `timezone: ^0.9.4` - Timezone handling

## Usage

### Automatic Integration
The reminder system automatically integrates with your existing task system:

1. **When creating tasks**: Reminders are scheduled automatically in `_saveCareTask()`
2. **When completing tasks**: Reminders are cancelled in `TaskService.markTaskComplete()`
3. **When marking incomplete**: Reminders are cancelled in `TaskService.markTaskIncomplete()`

### Manual Operations
You can also use the service directly:

```dart
// Schedule reminders for a task
await TaskReminderService().scheduleTaskReminders(
  taskId: 'task_123',
  taskStartTime: DateTime.now().add(Duration(hours: 1)),
  taskTitle: 'Give medication',
  elderlyName: 'John Doe',
);

// Cancel reminders for a task
await TaskReminderService().cancelTaskReminders('task_123');

// Cancel all reminders
await TaskReminderService().cancelAllReminders();
```

## Android Configuration

### Permissions
The system requests these permissions:
- `POST_NOTIFICATIONS` - Show notifications
- `SCHEDULE_EXACT_ALARM` - Schedule precise alarms
- `WAKE_LOCK` - Wake device for alarms
- `RECEIVE_BOOT_COMPLETED` - Restart alarms after reboot

### Battery Optimization
Users may need to disable battery optimization for the app to ensure reliable notification delivery.

## Notification Behavior

### Timing
- **15-min warning**: Standard notification with sound
- **5-min warning**: High priority with vibration
- **Start alarm**: Maximum priority, full screen intent, continuous until dismissed
- **Overdue**: High priority reminder every 15 minutes

### Sound & Vibration
- Uses system alarm sound for urgent notifications
- Custom vibration patterns for different alert types
- Respects user's notification settings

## Troubleshooting

### Common Issues
1. **Notifications not appearing**: Check app permissions and battery optimization
2. **No sound**: Verify notification channel settings and device volume
3. **Alarms not precise**: Ensure SCHEDULE_EXACT_ALARM permission is granted

### Testing
Test notifications by creating tasks with start times 1-2 minutes in the future to verify the reminder system is working correctly.

## Future Enhancements

### Planned Features
1. **Snooze functionality**: Allow caregivers to snooze reminders
2. **Custom reminder intervals**: Let users set their own warning times  
3. **Task priority levels**: Different alarm types for urgent vs routine tasks
4. **Notification history**: Track reminder delivery and interaction
5. **Integration with wearables**: Send reminders to smartwatches

### Optimization
1. **Battery efficiency**: Optimize background processing
2. **Network sync**: Sync reminder status across devices
3. **Smart scheduling**: Adjust reminders based on caregiver location/status