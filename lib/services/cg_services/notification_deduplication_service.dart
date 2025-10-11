/// Global notification deduplication service
/// Prevents multiple notifications for the same task action within a time window
class NotificationDeduplicationService {
  static final NotificationDeduplicationService _instance = NotificationDeduplicationService._internal();
  factory NotificationDeduplicationService() => _instance;
  NotificationDeduplicationService._internal();

  // Store recent notification keys to prevent duplicates
  final Map<String, DateTime> _recentNotifications = {};
  
  // Time window to prevent duplicates (in seconds)
  static const int _deduplicationWindowSeconds = 30;

  /// Check if a notification should be created (not a duplicate)
  bool shouldCreateNotification({
    required String taskId,
    required String caregiverId, 
    required String notificationType,
    String? additionalKey,
  }) {
    // Create unique key for this notification
    final key = '${caregiverId}_${taskId}_${notificationType}_${additionalKey ?? ''}';
    final now = DateTime.now();
    
    // Clean old entries first
    _cleanOldEntries(now);
    
    // Check if this notification was recently created
    if (_recentNotifications.containsKey(key)) {
      final lastCreated = _recentNotifications[key]!;
      final timeDiff = now.difference(lastCreated).inSeconds;
      
      if (timeDiff < _deduplicationWindowSeconds) {
        print('🚫 DUPLICATE PREVENTED: $key (${timeDiff}s ago)');
        return false; // Don't create duplicate
      }
    }
    
    // Record this notification
    _recentNotifications[key] = now;
    print('✅ NOTIFICATION ALLOWED: $key');
    return true;
  }

  /// Clean old entries to prevent memory leaks
  void _cleanOldEntries(DateTime now) {
    final cutoff = now.subtract(Duration(seconds: _deduplicationWindowSeconds + 10));
    _recentNotifications.removeWhere((key, timestamp) => timestamp.isBefore(cutoff));
  }

  /// Clear all entries (useful for testing)
  void clearAll() {
    _recentNotifications.clear();
    print('🧹 Notification deduplication cache cleared');
  }

  /// Get current cache status (for debugging)
  Map<String, DateTime> getCurrentCache() {
    return Map.from(_recentNotifications);
  }
}