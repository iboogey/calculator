import 'package:calculator/app/modules/settings/controllers/settings_controller.dart';
import 'package:calculator/app/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_notifications.dart';
import '../../helpers/test_services.dart';

void main() {
  late FakeNotificationProvider fake;

  setUp(() async => fake = await setUpTestServices());

  SettingsController open() => Get.put(
      SettingsController(settingsService: Get.find(), notifications: Get.find()));

  test('shows the reminder time as HH:MM', () {
    expect(open().reminderLabel, '21:00');
  });

  test('changing the time reschedules the reminder', () async {
    final c = open();
    await c.setReminderTime(7, 5);
    await settle();
    expect(c.reminderLabel, '07:05');
    final reminder = fake.scheduled[NotificationService.reminderId]!;
    expect((reminder.hour, reminder.minute), (7, 5));
  });

  test('turning the reminder off cancels it', () async {
    final c = open();
    await c.setReminderEnabled(false);
    await settle();
    expect(c.settings.reminderEnabled, isFalse);
    expect(fake.scheduled, isEmpty);
  });

  test('reports when notifications are refused', () async {
    fake.granted = false;
    await Get.find<NotificationService>().init();
    expect(open().permissionGranted, isFalse);
  });
}
