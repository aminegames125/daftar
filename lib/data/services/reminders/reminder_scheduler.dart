import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// One reminder to show at [when] (local time).
class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
  });

  final int id;
  final String title;
  final String body;
  final DateTime when;
}

/// Schedules local notifications. The app talks to this interface only, so tests
/// use a fake. Implementations must never throw: a denied permission or a plugin
/// failure just means no reminder.
abstract interface class ReminderScheduler {
  /// Asks for the notification permission (Android 13+). True when allowed.
  Future<bool> requestPermission();

  /// Replaces every scheduled reminder with [reminders].
  Future<void> replaceAll(List<Reminder> reminders);
}

/// Does nothing (default in tests and on platforms without notifications).
class NoopReminderScheduler implements ReminderScheduler {
  const NoopReminderScheduler();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {}
}

/// Android local notifications through `flutter_local_notifications`.
///
/// Uses inexact alarms (`inexactAllowWhileIdle`): a reminder may be a few minutes
/// late, but no exact-alarm permission is needed.
class LocalNotificationsScheduler implements ReminderScheduler {
  LocalNotificationsScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String channelId = 'bill_reminders';
  static const String channelName = 'Bill reminders';

  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _ready;

  Future<bool> _init() => _ready ??= _doInit();

  Future<bool> _doInit() async {
    try {
      tz_data.initializeTimeZones();
      try {
        final zone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(zone.identifier));
      } catch (_) {
        // Keep UTC: reminders are scheduled as absolute instants anyway.
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Reminders unavailable: $e');
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      if (!await _init()) return false;
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('Notification permission failed: $e');
      return false;
    }
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    try {
      if (!await _init()) return;
      await _plugin.cancelAll();
      for (final r in reminders) {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.when, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelName,
              channelDescription: 'Reminds you before a bill is due',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('Scheduling reminders failed: $e');
    }
  }
}
