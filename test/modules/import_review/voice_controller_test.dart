import 'package:calculator/app/data/models/app_settings.dart';
import 'package:calculator/app/data/models/pending_item.dart';
import 'package:calculator/app/data/providers/ai_client.dart';
import 'package:calculator/app/data/providers/secret_store.dart';
import 'package:calculator/app/data/providers/speech_provider.dart';
import 'package:calculator/app/data/repositories/debt_repository.dart';
import 'package:calculator/app/data/repositories/import_repository.dart';
import 'package:calculator/app/modules/import_review/controllers/voice_controller.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:calculator/app/services/message_service.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_ai_client.dart';
import '../../helpers/fake_secret_store.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

const _spoken = 'دفعت خمسة دنانير بالسوبرماركت';
const _foodReply =
    '{"kind":"expense","amount":"5","category":"طعام","person":null,'
    '"note":"سوبرماركت","date":null}';

void main() {
  late FakeAiClient client;
  final now = DateTime(2026, 11, 9, 18, 30);

  setUp(() async {
    client = FakeAiClient(_foodReply);
    await setUpTestServices(aiClientFactory: (_, _, _) => client);
  });

  FakeSpeechProvider speech() => Get.find<SpeechProvider>() as FakeSpeechProvider;
  ImportRepository imports() => Get.find<ImportRepository>();
  String? lastMessage() => Get.find<MessageService>().lastMessage.value;

  Future<void> configure() async {
    final settings = Get.find<SettingsService>();
    await settings.update(
        settings.settings.value.copyWith(aiProvider: AiProviderKind.gemini));
    await (Get.find<SecretStore>() as FakeSecretStore)
        .write(apiKeyName(AiProviderKind.gemini), 'k');
  }

  VoiceController open() => Get.put(VoiceController(
        speech: Get.find(),
        ai: Get.find(),
        imports: Get.find(),
        categories: Get.find(),
        debts: Get.find(),
        settings: Get.find(),
        clock: () => now,
      ));

  /// Configured, listening, and the recognizer has settled on [text].
  Future<VoiceController> heard(String text) async {
    await configure();
    final c = open();
    await c.startListening();
    speech().emit(text, isFinal: true);
    return c;
  }

  test('a final result shows the text for editing', () async {
    await configure();
    final c = open();
    await c.startListening();
    expect(c.state.value, VoiceState.listening);
    expect(speech().localeId, 'ar-JO');
    speech().emit('دفعت خمسة');
    expect(c.text.value, 'دفعت خمسة');
    expect(c.state.value, VoiceState.listening);
    speech().emit(_spoken, isFinal: true);
    expect(c.state.value, VoiceState.editing);
    expect(c.text.value, _spoken);
  });

  test('stop with text goes to editing, without text back to idle', () async {
    await configure();
    final c = open();
    await c.startListening();
    speech().emit('دفعت');
    await c.stopListening();
    expect(speech().stopped, isTrue);
    expect(c.state.value, VoiceState.editing);

    await c.startListening();
    expect(c.text.value, isEmpty);
    await c.stopListening();
    expect(c.state.value, VoiceState.idle);
  });

  test('the recognizer ending by itself acts like stop', () async {
    await configure();
    final c = open();
    await c.startListening();
    speech().emit('دفعت');
    speech().done();
    expect(c.state.value, VoiceState.editing);

    await c.startListening();
    speech().done();
    expect(c.state.value, VoiceState.idle);
  });

  test('a late final result after stop still fills the text', () async {
    await configure();
    final c = open();
    await c.startListening();
    speech().emit('دفعت خمسة');
    await c.stopListening();
    speech().emit(_spoken, isFinal: true);
    expect(c.text.value, _spoken);
    c.edit('نص معدّل');
    speech().emit('شيء آخر', isFinal: true);
    expect(c.text.value, 'نص معدّل');
  });

  test('the edited text is what reaches the AI, and the item is stored',
      () async {
    final c = await heard(_spoken);
    c.edit('دفعت خمسة دنانير بالسوبرماركت أمس');
    final item = await c.send();
    expect(client.prompts.single, contains('بالسوبرماركت أمس'));
    expect(item, isNotNull);
    expect(item!.id, isNotNull);
    expect(item.source, PendingSource.voice);
    expect(item.kind, PendingKind.expense);
    expect(item.amount, 5000);
    expect(item.suggestedCategoryId, foodCategoryId);
    expect(item.note, 'سوبرماركت');
    expect(item.occurredAt, now);
    final pending = await imports().getPending();
    expect(pending, [item]);
    expect(c.state.value, VoiceState.idle);
    expect(c.text.value, isEmpty);
  });

  test('a stated date is used', () async {
    client.reply = '{"kind":"income","amount":"100","category":"راتب",'
        '"person":null,"note":null,"date":"2026-11-01"}';
    final c = await heard('استلمت الراتب');
    final item = await c.send();
    expect(item!.occurredAt, DateTime(2026, 11, 1));
    expect(item.kind, PendingKind.income);
    expect(item.suggestedCategoryId, salaryCategoryId);
  });

  test('an unknown or archived category leaves the item uncategorised',
      () async {
    client.reply = '{"kind":"expense","amount":"5","category":"شيء غريب"}';
    final c = await heard(_spoken);
    expect((await c.send())!.suggestedCategoryId, isNull);

    await Get.find<DatabaseService>().db.update(
        'categories', {'is_archived': 1},
        where: 'id = ?', whereArgs: [foodCategoryId]);
    client.reply = _foodReply;
    await c.startListening();
    speech().emit(_spoken, isFinal: true);
    expect((await c.send())!.suggestedCategoryId, isNull);
  });

  test('an income category name does not match an expense', () async {
    client.reply = '{"kind":"expense","amount":"5","category":"راتب"}';
    final c = await heard(_spoken);
    expect((await c.send())!.suggestedCategoryId, isNull);
  });

  test('a debt names an existing person by trimmed, case-insensitive match',
      () async {
    final sami = await Get.find<DebtRepository>().addPerson('Sami');
    client.reply = '{"kind":"debt_gave","amount":"20","category":"طعام",'
        '"person":" sami ","note":null,"date":null}';
    final c = await heard('أعطيت سامي عشرين دينار');
    final item = (await c.send())!;
    expect(item.kind, PendingKind.debtGave);
    expect(item.amount, 20000);
    expect(item.personId, sami.id);
    expect(item.suggestedCategoryId, isNull);
  });

  test('a debt with a new person keeps the spoken name', () async {
    client.reply = '{"kind":"debt_took","amount":"10","person":"رنا"}';
    final c = await heard('أخذت من رنا عشرة دنانير');
    final item = (await c.send())!;
    expect(item.kind, PendingKind.debtTook);
    expect(item.personId, isNull);
    expect(item.personName, 'رنا');
  });

  test('an AI failure shows its message and creates nothing', () async {
    client.reply = const AiException('مفتاح الذكاء الاصطناعي غير صالح');
    final c = await heard(_spoken);
    expect(await c.send(), isNull);
    expect(lastMessage(), 'مفتاح الذكاء الاصطناعي غير صالح');
    expect(await imports().getPending(), isEmpty);
    expect(c.state.value, VoiceState.editing);
    expect(c.text.value, _spoken);
  });

  test('any other failure shows the generic message and creates nothing',
      () async {
    client.reply = StateError('boom');
    final c = await heard(_spoken);
    expect(await c.send(), isNull);
    expect(lastMessage(), 'تعذّر الاتصال بمزوّد الذكاء الاصطناعي');
    expect(await imports().getPending(), isEmpty);
  });

  test('setLanguage persists and the next start uses it', () async {
    await configure();
    final c = open();
    expect(c.language, 'ar-JO');
    await c.setLanguage('en-US');
    expect(c.language, 'en-US');
    expect(Get.find<SettingsService>().settings.value.voiceLanguage, 'en-US');
    await c.startListening();
    expect(speech().localeId, 'en-US');
  });

  test('changing language while listening restarts in the new language',
      () async {
    await configure();
    final c = open();
    await c.startListening();
    await c.setLanguage('en-US');
    expect(speech().localeId, 'en-US');
    expect(c.state.value, VoiceState.listening);
  });

  test('not configured: startListening does nothing and explains', () async {
    final c = open();
    await c.startListening();
    expect(c.state.value, VoiceState.idle);
    expect(speech().localeId, isNull);
    expect(lastMessage(), 'الإدخال الصوتي يحتاج مفتاح ذكاء اصطناعي في الإعدادات');
    expect(await c.ensureConfigured(), isFalse);
    expect(c.configured.value, isFalse);
  });

  test('speech unavailable: explains and stays idle', () async {
    await configure();
    speech().available = false;
    final c = open();
    await c.startListening();
    expect(c.state.value, VoiceState.idle);
    expect(speech().localeId, isNull);
    expect(lastMessage(), 'التعرّف على الكلام غير متاح على هذا الجهاز');
  });

  test('cancel stops listening and ignores later results', () async {
    await configure();
    final c = open();
    await c.startListening();
    await c.cancel();
    expect(speech().stopped, isTrue);
    expect(c.state.value, VoiceState.idle);
    speech().emit(_spoken, isFinal: true);
    expect(c.text.value, isEmpty);
    expect(c.state.value, VoiceState.idle);
  });
}
