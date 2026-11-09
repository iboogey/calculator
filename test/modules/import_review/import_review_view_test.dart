import 'package:calculator/app/core/logic/bank_sms_parser.dart';
import 'package:calculator/app/core/theme/app_theme.dart';
import 'package:calculator/app/data/models/app_settings.dart';
import 'package:calculator/app/data/models/pending_item.dart';
import 'package:calculator/app/data/providers/secret_store.dart';
import 'package:calculator/app/data/providers/speech_provider.dart';
import 'package:calculator/app/data/repositories/debt_repository.dart';
import 'package:calculator/app/data/repositories/import_repository.dart';
import 'package:calculator/app/modules/import_review/controllers/import_review_controller.dart';
import 'package:calculator/app/modules/import_review/controllers/voice_controller.dart';
import 'package:calculator/app/modules/import_review/views/import_review_view.dart';
import 'package:calculator/app/services/message_service.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_ai_client.dart';
import '../../helpers/fake_secret_store.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/test_services.dart';

PendingItem _item(int amount, {int? category = 1}) => PendingItem(
      source: PendingSource.sms,
      kind: PendingKind.expense,
      amount: amount,
      occurredAt: DateTime(2026, 11, 3, 9),
      smsType: BankSmsType.cardPurchase,
      name: 'SAMPLE SUPER MARKET',
      suggestedCategoryId: category,
      createdAt: DateTime(2026, 11, 3),
    );

void main() {
  late FakeAiClient client;

  setUp(() async {
    client = FakeAiClient('{"kind":"debt_gave","amount":"20","person":"سامي"}');
    await setUpTestServices(aiClientFactory: (_, _, _) => client);
  });

  FakeSpeechProvider speech() => Get.find<SpeechProvider>() as FakeSpeechProvider;

  Future<void> configure() async {
    final settings = Get.find<SettingsService>();
    await settings.update(
        settings.settings.value.copyWith(aiProvider: AiProviderKind.gemini));
    await (Get.find<SecretStore>() as FakeSecretStore)
        .write(apiKeyName(AiProviderKind.gemini), 'k');
  }

  /// Lets database and AI work started by a tap finish: each awaited
  /// database call needs some real time, then a pump to resume.
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  Future<void> open(WidgetTester tester, List<PendingItem> items,
      {bool openVoice = false}) async {
    await tester.runAsync(() async {
      await Get.find<ImportRepository>().addPending(items);
    });
    final c = Get.put(ImportReviewController(
      imports: Get.find(),
      categories: Get.find(),
      recurring: Get.find(),
      transactions: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      debts: Get.find(),
      openVoice: openVoice,
    ));
    Get.put(VoiceController(
      speech: Get.find(),
      ai: Get.find(),
      imports: Get.find(),
      categories: Get.find(),
      debts: Get.find(),
      settings: Get.find(),
    ));
    await tester.runAsync(c.load);
    // The app's theme: its full-width FilledButton must not break the cards.
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const ImportReviewView()));
  }

  testWidgets('empty state and title, with no approve-all', (tester) async {
    await open(tester, []);
    expect(find.text('مراجعة الحركات'), findsOneWidget);
    expect(find.text('لا توجد حركات جديدة'), findsOneWidget);
    expect(find.text('اعتماد الكل'), findsNothing);
  });

  testWidgets('lists cards without an approve-all button', (tester) async {
    await open(tester, [_item(1000), _item(2000)]);
    expect(find.text('اعتماد'), findsNWidgets(2));
    expect(find.text('اعتماد الكل'), findsNothing);
  });

  testWidgets('approve on an item without a category opens the editor',
      (tester) async {
    await open(tester, [_item(1000, category: null)]);
    await tester.tap(find.text('اعتماد'));
    await tester.pumpAndSettle();
    expect(find.text('حفظ واعتماد'), findsOneWidget);
  });

  testWidgets('dismiss shows Undo, which restores the item', (tester) async {
    await open(tester, [_item(1000)]);
    final c = Get.find<ImportReviewController>();
    await tester.tap(find.text('تجاهل'));
    await drain(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.items, isEmpty);
    expect(find.text('لا توجد حركات جديدة'), findsOneWidget);
    expect(find.text('تراجع'), findsOneWidget);
    await tester.tap(find.text('تراجع'));
    await drain(tester);
    expect(c.items, hasLength(1));
    expect(find.text('اعتماد'), findsOneWidget);
  });

  testWidgets('without a key the mic explains instead of listening',
      (tester) async {
    await open(tester, []);
    await tester.tap(find.byTooltip('إدخال صوتي'));
    await drain(tester);
    expect(Get.find<MessageService>().lastMessage.value,
        'الإدخال الصوتي يحتاج مفتاح ذكاء اصطناعي في الإعدادات');
    expect(find.text('عربي'), findsNothing);
    expect(speech().localeId, isNull);
  });

  testWidgets('voice: listen, fix the words, send, then edit the item',
      (tester) async {
    await tester.runAsync(configure);
    await tester.runAsync(() => Get.find<DebtRepository>().addPerson('سامي'));
    await open(tester, []);
    await tester.tap(find.byTooltip('إدخال صوتي'));
    await drain(tester);
    // The mic pulses forever, so wait out the sheet animation by time.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('عربي'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('إيقاف'), findsOneWidget);
    expect(speech().localeId, 'ar-JO');

    speech().emit('أعطيت سامي');
    await tester.pump();
    expect(find.text('أعطيت سامي'), findsOneWidget);
    speech().emit('أعطيت سامي عشرين', isFinal: true);
    await tester.pump();
    expect(find.text('إيقاف'), findsNothing);
    await tester.enterText(find.byType(TextField), 'أعطيت سامي عشرين دينار');
    await tester.tap(find.text('إرسال'));
    await drain(tester);
    await tester.pumpAndSettle();

    expect(client.prompts.single, contains('أعطيت سامي عشرين دينار'));
    expect(find.text('حفظ واعتماد'), findsOneWidget);
    expect(find.text('أعطيتُ'), findsOneWidget);
    await tester.tap(find.text('حفظ واعتماد'));
    await drain(tester);
    await tester.pumpAndSettle();
    final sami = (await tester
            .runAsync(() => Get.find<DebtRepository>().getPeople()))!
        .single;
    final entries = await tester
        .runAsync(() => Get.find<DebtRepository>().getEntries(sami.id!));
    expect(entries!.single.amount, 20000);
    expect(find.text('حفظ واعتماد'), findsNothing);
  });

  testWidgets('opened from Home, the voice sheet starts by itself',
      (tester) async {
    await tester.runAsync(configure);
    await open(tester, [], openVoice: true);
    await drain(tester);
    expect(find.text('عربي'), findsOneWidget);
    expect(speech().localeId, 'ar-JO');
  });
}
