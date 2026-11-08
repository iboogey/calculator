import 'package:calculator/app/data/models/app_settings.dart';
import 'package:calculator/app/data/providers/ai_client.dart';
import 'package:calculator/app/data/providers/secret_store.dart';
import 'package:calculator/app/data/providers/sms_inbox_provider.dart';
import 'package:calculator/app/services/ai_service.dart';
import 'package:calculator/app/services/backup_service.dart';
import 'package:calculator/app/modules/settings/controllers/settings_controller.dart';
import 'package:calculator/app/modules/settings/views/settings_view.dart';
import 'package:calculator/app/services/message_service.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_secret_store.dart';
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
        ai: Get.find(),
        secrets: Get.find(),
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
    // The AI settings still show without SMS support.
    expect(find.text('الاستيراد الذكي'), findsOneWidget);
    expect(find.text('مزوّد الذكاء الاصطناعي'), findsOneWidget);
  });

  testWidgets('supported platform shows the tile', (tester) async {
    open();
    await tester.pumpWidget(
        const GetMaterialApp(home: Directionality(
            textDirection: TextDirection.rtl, child: SettingsView())));
    await tester.pump();
    expect(find.text('استيراد رسائل البنك'), findsOneWidget);
  });

  group('AI settings', () {
    FakeSecretStore secrets() => Get.find<SecretStore>() as FakeSecretStore;
    AiProviderKind provider() =>
        Get.find<SettingsService>().settings.value.aiProvider;

    test('choosing a provider saves it', () async {
      final c = open();
      await c.setAiProvider(AiProviderKind.gemini);
      expect(provider(), AiProviderKind.gemini);
    });

    test('saveApiKey trims, stores securely and never in the backup',
        () async {
      final c = open();
      await c.setAiProvider(AiProviderKind.gemini);
      await c.saveApiKey('  abc ');
      expect(secrets().values['ai_key_gemini'], 'abc');
      expect(c.hasApiKey.value, isTrue);
      final json = await Get.find<BackupService>().exportJson(DateTime(2026));
      expect(json.contains('abc'), isFalse);
    });

    test('empty key is ignored', () async {
      final c = open();
      await c.setAiProvider(AiProviderKind.gemini);
      await c.saveApiKey('   ');
      expect(secrets().values, isEmpty);
      expect(c.hasApiKey.value, isFalse);
    });

    test('deleteApiKey removes it', () async {
      final c = open();
      await c.setAiProvider(AiProviderKind.gemini);
      await c.saveApiKey('abc');
      await c.deleteApiKey();
      expect(secrets().values, isEmpty);
      expect(c.hasApiKey.value, isFalse);
    });

    test('keys are per provider and hasApiKey follows the provider',
        () async {
      final c = open();
      await c.setAiProvider(AiProviderKind.gemini);
      await c.saveApiKey('abc');
      await c.setAiProvider(AiProviderKind.claude);
      expect(c.hasApiKey.value, isFalse);
      await c.setAiProvider(AiProviderKind.gemini);
      expect(c.hasApiKey.value, isTrue);
    });

    test('hasApiKey is read on init', () async {
      secrets().values['ai_key_openai'] = 'k';
      await Get.find<SettingsService>().update(Get.find<SettingsService>()
          .settings
          .value
          .copyWith(aiProvider: AiProviderKind.openai));
      final c = open();
      await Future<void>.delayed(Duration.zero);
      expect(c.hasApiKey.value, isTrue);
    });

    test('model text is saved; empty clears it', () async {
      final c = open();
      await c.setAiModel(' my-model ');
      expect(Get.find<SettingsService>().settings.value.aiModel, 'my-model');
      await c.setAiModel('  ');
      expect(Get.find<SettingsService>().settings.value.aiModel, isNull);
    });

    test('test connection reports success', () async {
      await setUpTestServices(
          aiClientFactory: (kind, key, model) => _FakeClient());
      final c = open();
      await c.setAiProvider(AiProviderKind.gemini);
      await c.saveApiKey('abc');
      expect(await c.testAiConnection(), isTrue);
      expect(Get.find<MessageService>().lastMessage.value,
          'تم الاتصال بنجاح');
    });

    test('test connection reports failure', () async {
      await setUpTestServices(
          aiClientFactory: (kind, key, model) =>
              _FakeClient(const AiException(aiInvalidKeyMessage)));
      final c = open();
      await c.setAiProvider(AiProviderKind.gemini);
      await c.saveApiKey('abc');
      expect(await c.testAiConnection(), isFalse);
      expect(Get.find<MessageService>().lastMessage.value,
          aiInvalidKeyMessage);
    });

    test('test connection without a key says to add one', () async {
      final c = open();
      await c.setAiProvider(AiProviderKind.gemini);
      expect(await c.testAiConnection(), isFalse);
      expect(Get.find<MessageService>().lastMessage.value,
          aiNotConfiguredMessage);
    });

    testWidgets('key, model and test widgets only show with a provider',
        (tester) async {
      final c = open();
      Future<void> show() async {
        await tester.pumpWidget(const GetMaterialApp(
            home: Directionality(
                textDirection: TextDirection.rtl, child: SettingsView())));
        await tester.pump();
      }

      await show();
      expect(find.text('مفتاح API'), findsNothing);
      expect(find.text('اختبار الاتصال'), findsNothing);

      await tester.runAsync(() => c.setAiProvider(AiProviderKind.gemini));
      await tester.pump();
      expect(find.text('مفتاح API'), findsOneWidget);
      expect(find.text('النموذج'), findsOneWidget);
      expect(find.text('اختبار الاتصال'), findsOneWidget);
      expect(find.text('gemini-3.5-flash-lite'), findsOneWidget);
    });

    testWidgets('saving clears the field and never shows the key back',
        (tester) async {
      final c = open();
      await tester.runAsync(() => c.setAiProvider(AiProviderKind.gemini));
      await tester.pumpWidget(const GetMaterialApp(
          home: Directionality(
              textDirection: TextDirection.rtl, child: SettingsView())));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('apiKeyField')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('apiKeyField')), 'secret1');
      await tester.tap(find.byKey(const Key('saveApiKey')));
      await tester.pump();
      await tester.pump();
      expect(secrets().values['ai_key_gemini'], 'secret1');
      expect(find.text('secret1'), findsNothing);
      expect(find.text('تم حفظ المفتاح'), findsOneWidget);
    });
  });
}

class _FakeClient implements AiClient {
  _FakeClient([this.error]);

  final AiException? error;

  @override
  Future<String> complete(String prompt, {required Duration timeout}) async {
    if (error != null) throw error!;
    return 'ok';
  }
}
