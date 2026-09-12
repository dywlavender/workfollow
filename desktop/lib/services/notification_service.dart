import 'package:flutter/services.dart';

/// Keeps system notifications in sync with task reminders. The controller
/// calls it fire-and-forget; a missing platform channel (tests, non-macOS
/// hosts) degrades to a no-op instead of throwing.
abstract class ReminderScheduler {
  Future<bool> requestPermission();
  Future<String?> authorizationStatus();
  Future<void> schedule({
    required String taskId,
    required String title,
    String? body,
    required DateTime at,
  });
  Future<void> cancel(String taskId);
  Future<void> cancelAll();
  set onNotificationClicked(void Function(String taskId)? handler);
}

class NotificationService implements ReminderScheduler {
  NotificationService();

  static const MethodChannel _channel =
      MethodChannel('workfollow/notifications');

  @override
  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<String?> authorizationStatus() async {
    try {
      return await _channel.invokeMethod<String>('authorizationStatus');
    } on Object {
      return null;
    }
  }

  @override
  Future<void> schedule({
    required String taskId,
    required String title,
    String? body,
    required DateTime at,
  }) async {
    try {
      await _channel.invokeMethod<void>('schedule', {
        'taskId': taskId,
        'title': title,
        'body': body,
        'fireAtMillis': at.millisecondsSinceEpoch,
      });
    } on Object {
      // A missed registration must not break editing the task.
    }
  }

  @override
  Future<void> cancel(String taskId) async {
    try {
      await _channel
          .invokeMethod<void>('cancel', <String, dynamic>{'taskId': taskId});
    } on Object {
      // Same as above.
    }
  }

  @override
  Future<void> cancelAll() async {
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } on Object {
      // Same as above.
    }
  }

  @override
  set onNotificationClicked(void Function(String taskId)? handler) {
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'notificationClicked' &&
            call.arguments is String &&
            handler != null) {
          handler(call.arguments as String);
        }
        return null;
      });
    } on Object {
      // Pure Dart tests run without a binary messenger; notification clicks
      // are simply not wired there.
    }
  }
}
