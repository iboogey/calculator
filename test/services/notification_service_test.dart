import 'package:calculator/app/services/notification_service.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/test_services.dart';

void main() {
  test('schedules the daily reminder at 21:00 by default', () async {
    final fake = await setUpTestServices();
    final reminder = fake.scheduled[NotificationService.reminderId]!;
    expect((reminder.hour, reminder.minute), (21, 0));
    expect(reminder.body, 'سجّلت مصاريف اليوم؟');
    expect(Get.find<NotificationService>().permissionGranted.value, isTrue);
  });

  test('follows the reminder settings', () async {
    final fake = await setUpTestServices();
    final settings = Get.find<SettingsService>();
    await settings.update(settings.settings.value.copyWith(reminderMinutes: 8 * 60 + 30));
    await settle();
    expect(fake.scheduled[NotificationService.reminderId]!.hour, 8);
    expect(fake.scheduled[NotificationService.reminderId]!.minute, 30);
    await settings.update(settings.settings.value.copyWith(reminderEnabled: false));
    await settle();
    expect(fake.scheduled, isEmpty);
  });

  test('schedules nothing when notifications are refused', () async {
    final fake = await setUpTestServices();
    fake.granted = false;
    final service = Get.find<NotificationService>();
    await service.init();
    fake.scheduled.clear();
    await service.syncReminder();
    expect(service.permissionGranted.value, isFalse);
    expect(fake.scheduled, isEmpty);
  });
}
