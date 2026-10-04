import 'package:calculator/app/data/providers/notification_provider.dart';

/// Records what the app asked the notification system to do.
class FakeNotificationProvider implements NotificationProvider {
  bool granted = true;
  final scheduled = <int, ({int hour, int minute, String body})>{};
  final shown = <({int id, String title, String body})>[];

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<void> scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async =>
      scheduled[id] = (hour: hour, minute: minute, body: body);

  @override
  Future<void> show({required int id, required String title, required String body}) async =>
      shown.add((id: id, title: title, body: body));

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);
}
