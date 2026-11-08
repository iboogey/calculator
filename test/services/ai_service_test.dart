import 'package:calculator/app/core/logic/bank_sms_parser.dart';
import 'package:calculator/app/data/models/app_settings.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/pending_item.dart';
import 'package:calculator/app/data/providers/ai_client.dart';
import 'package:calculator/app/data/providers/secret_store.dart';
import 'package:calculator/app/data/providers/sms_inbox_provider.dart';
import 'package:calculator/app/data/repositories/category_repository.dart';
import 'package:calculator/app/data/repositories/import_repository.dart';
import 'package:calculator/app/services/ai_service.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:calculator/app/services/sms_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/fake_ai_client.dart';
import '../helpers/fake_secret_store.dart';
import '../helpers/fake_sms_inbox.dart';
import '../helpers/sms_fixtures.dart';
import '../helpers/test_services.dart';

void main() {
  late FakeAiClient client;
  late AiService ai;
  late int foodId;
  final card = const ParsedBankSms(
    type: BankSmsType.cardPurchase,
    amount: 3500,
    name: 'SAMPLE SUPER MARKET',
    city: 'AMMAN',
  );

  Future<void> configure() async {
    final settings = Get.find<SettingsService>();
    await settings.update(settings.settings.value.copyWith(
      aiProvider: AiProviderKind.gemini,
      smsImportEnabled: true,
      periodStartDay: 1,
    ));
    await (Get.find<SecretStore>() as FakeSecretStore)
        .write(apiKeyName(AiProviderKind.gemini), 'k');
  }

  setUp(() async {
    client = FakeAiClient('{"category":"طعام"}');
    await setUpTestServices(aiClientFactory: (_, _, _) => client);
    ai = Get.find<AiService>();
    final all = await Get.find<CategoryRepository>()
        .getAll(kind: TransactionKind.expense);
    foodId = all.firstWhere((c) => c.name == 'طعام').id!;
  });

  test('not configured returns null without calling the client', () async {
    expect(await ai.isConfigured, isFalse);
    expect(await ai.suggestCategory(card), isNull);
    expect(client.prompts, isEmpty);
  });

  test('configured maps the reply to the category id', () async {
    await configure();
    expect(await ai.isConfigured, isTrue);
    expect(await ai.suggestCategory(card), foodId);
  });

  test('the service registers itself as the scan suggester', () {
    expect(Get.find<SmsImportService>().suggester, isNotNull);
  });

  test('provider set but no key is not configured', () async {
    final settings = Get.find<SettingsService>();
    await settings.update(settings.settings.value
        .copyWith(aiProvider: AiProviderKind.claude));
    expect(await ai.isConfigured, isFalse);
  });

  for (final reply in <Object>[
    '{"category":"لا يوجد هذا"}',
    'garbage',
    const AiException('x'),
  ]) {
    test('bad reply $reply gives null and the scan still adds the item',
        () async {
      await configure();
      client.reply = reply;
      expect(await ai.suggestCategory(card), isNull);

      final inbox = Get.find<SmsInboxProvider>() as FakeSmsInboxProvider;
      inbox.messages.add(SmsMessage(date: DateTime(2026, 11, 2), body: smsCard));
      final added =
          await Get.find<SmsImportService>().scan(DateTime(2026, 11, 9, 10));
      expect(added, 1);
      final pending = await Get.find<ImportRepository>().getPending();
      expect(pending.single.suggestedCategoryId, isNull);
    });
  }

  test('scan uses the suggestion end to end', () async {
    await configure();
    final inbox = Get.find<SmsInboxProvider>() as FakeSmsInboxProvider;
    inbox.messages.add(SmsMessage(date: DateTime(2026, 11, 2), body: smsCard));
    await Get.find<SmsImportService>().scan(DateTime(2026, 11, 9, 10));
    final pending = await Get.find<ImportRepository>().getPending();
    expect(pending.single.suggestedCategoryId, foodId);
  });

  test('the prompt has merchant and city but no account or balance', () async {
    await configure();
    final inbox = Get.find<SmsInboxProvider>() as FakeSmsInboxProvider;
    inbox.messages.add(SmsMessage(date: DateTime(2026, 11, 2), body: smsCard));
    await Get.find<SmsImportService>().scan(DateTime(2026, 11, 9, 10));
    expect(client.prompts, hasLength(1));
    final prompt = client.prompts.single;
    expect(prompt, contains('SAMPLE SUPER MARKET'));
    expect(prompt, contains('AMMAN'));
    expect(prompt, isNot(contains('1234567')));
    expect(prompt, isNot(contains('120.250')));
    expect(prompt, isNot(contains('الرصيد')));
  });

  test('a CliQ item never calls the client', () async {
    await configure();
    final inbox = Get.find<SmsInboxProvider>() as FakeSmsInboxProvider;
    inbox.messages
      ..add(SmsMessage(date: DateTime(2026, 11, 2), body: smsCliqSent))
      ..add(SmsMessage(date: DateTime(2026, 11, 3), body: smsCliqReceived));
    await Get.find<SmsImportService>().scan(DateTime(2026, 11, 9, 10));
    expect(client.prompts, isEmpty);
    expect(
        await ai.suggestCategory(const ParsedBankSms(
            type: BankSmsType.cliqSent, amount: 1, name: 'X')),
        isNull);
    expect(client.prompts, isEmpty);
  });

  group('parseVoice', () {
    test('throws the settings message when not configured', () async {
      expect(
        () => ai.parseVoice('صرفت خمسة'),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', aiNotConfiguredMessage)),
      );
    });

    test('parses a valid reply', () async {
      await configure();
      client.reply = '{"kind":"expense","amount":"5","category":"طعام"}';
      final result = await ai.parseVoice('صرفت خمسة دنانير على الأكل');
      expect(result.kind, PendingKind.expense);
      expect(result.amount, 5000);
      expect(result.category, 'طعام');
      expect(client.prompts.single, contains('JOD'));
    });

    test('an unparseable reply throws the understanding message', () async {
      await configure();
      client.reply = 'hello';
      expect(
        () => ai.parseVoice('x'),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', aiVoiceParseMessage)),
      );
    });
  });

  group('testConnection', () {
    test('succeeds, and surfaces provider errors', () async {
      await configure();
      client.reply = 'ok';
      await ai.testConnection();
      client.reply = const AiException(aiInvalidKeyMessage);
      await expectLater(
          ai.testConnection(),
          throwsA(isA<AiException>()
              .having((e) => e.message, 'message', aiInvalidKeyMessage)));
    });

    test('throws when not configured', () {
      expect(() => ai.testConnection(), throwsA(isA<AiException>()));
    });
  });
}
