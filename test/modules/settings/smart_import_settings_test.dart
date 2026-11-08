import 'package:calculator/app/data/providers/sms_inbox_provider.dart';
import 'package:calculator/app/modules/settings/controllers/settings_controller.dart';
import 'package:calculator/app/modules/settings/views/settings_view.dart';
import 'package:calculator/app/services/message_service.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_sms_inbox.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  FakeSmsInboxProvider fake() =>
      Get.find<SmsInboxProvider>() as FakeSmsInboxProvider;

  SettingsController open() => Get.put(SettingsController(
        settingsService: Get.find(),
        notifications: Get.find(),
        backup: Get.find(),
        files: Get.find(),
        smsInbox: Get.find(),
        smsImport: Get.find(),
        clock: () => DateTime(2026, 10, 4, 9),
      ));

  bool saved() => Get.find<SettingsService>().settings.value.smsImportEnabled;

  test('enabling with permission saves true and scans', () async {
    final c = open();
    await c.setSmsImport(true);
    expect(saved(), isTrue);
    expect(c.smsImportOn, isTrue);
    expect(fake().readCount, 1);
  });

  test('denied permission keeps it off and says why', () async {
    fake().granted = false;
    final c = open();
    await c.setSmsImport(true);
    expect(saved(), isFalse);
    expect(c.smsImportOn, isFalse);
    expect(fake().readCount, 0);
    expect(Get.find<MessageService>().lastMessage.value,
        'لا يمكن قراءة رسائل البنك دون إذن الرسائل');
  });

  test('disabling saves false', () async {
    final c = open();
    await c.setSmsImport(true);
    await c.setSmsImport(false);
    expect(saved(), isFalse);
    expect(c.smsImportOn, isFalse);
  });

  testWidgets('unsupported platform hides the tile', (tester) async {
    fake().supported = false;
    open();
    await tester.pumpWidget(
        const GetMaterialApp(home: Directionality(
            textDirection: TextDirection.rtl, child: SettingsView())));
    await tester.pump();
    expect(find.text('استيراد رسائل البنك'), findsNothing);
  });

  testWidgets('supported platform shows the tile', (tester) async {
    open();
    await tester.pumpWidget(
        const GetMaterialApp(home: Directionality(
            textDirection: TextDirection.rtl, child: SettingsView())));
    await tester.pump();
    expect(find.text('استيراد رسائل البنك'), findsOneWidget);
  });
}
