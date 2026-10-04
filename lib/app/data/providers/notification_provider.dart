import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The device's local notifications. An interface so tests can use a fake.
abstract class NotificationProvider {
  Future<void> init();

  /// Asks the user (once; later calls return the current answer).
  Future<bool> requestPermission();

  /// Repeats every day at [hour]:[minute] local time.
  Future<void> scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  });

  Future<void> show({required int id, required String title, required String body});

  Future<void> cancel(int id);
}

/// [NotificationProvider] backed by flutter_local_notifications. Everything
/// is scheduled on the device; nothing uses the network.
class LocalNotificationProvider implements NotificationProvider {
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _reminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'daily_reminder',
      'التذكير اليومي',
      channelDescription: 'تذكير يومي لتسجيل المصاريف',
    ),
    iOS: DarwinNotificationDetails(),
  );

  static const _alertDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'budget_alerts',
      'تنبيهات الميزانية',
      channelDescription: 'لما تقرّب أو تتجاوز ميزانية تصنيف',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> init() async {
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      // Unknown zone name: keep the default (UTC) rather than fail start-up.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  @override
  Future<bool> requestPermission() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: next,
      notificationDetails: _reminderDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> show({required int id, required String title, required String body}) =>
      _plugin.show(id: id, title: title, body: body, notificationDetails: _alertDetails);

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);
}
