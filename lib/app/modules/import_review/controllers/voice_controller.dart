import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/logic/ai_prompts.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/pending_item.dart';
import '../../../data/providers/ai_client.dart';
import '../../../data/providers/speech_provider.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/debt_repository.dart';
import '../../../data/repositories/import_repository.dart';
import '../../../services/ai_service.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

enum VoiceState { idle, listening, editing, sending }

const voiceNeedsKeyMessage =
    'الإدخال الصوتي يحتاج مفتاح ذكاء اصطناعي في الإعدادات';
const speechUnavailableMessage = 'التعرّف على الكلام غير متاح على هذا الجهاز';

/// Voice entry: listens, lets the user fix the words, then asks the AI to
/// extract an entry and stores it as a pending voice item.
class VoiceController extends GetxController {
  VoiceController({
    required this.speech,
    required this.ai,
    required this.imports,
    required this.categories,
    required this.debts,
    required this.settings,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SpeechProvider speech;
  final AiService ai;
  final ImportRepository imports;
  final CategoryRepository categories;
  final DebtRepository debts;
  final SettingsService settings;
  final DateTime Function() _clock;

  static const languages = ['ar-JO', 'en-US'];

  final state = VoiceState.idle.obs;
  final text = ''.obs;

  /// Whether an AI key is set, for showing the mic enabled or not.
  final configured = false.obs;

  /// Bumped on every start and cancel, so callbacks from an older listening
  /// session are ignored.
  int _session = 0;

  /// The user typed in the text, so late recognizer results must not
  /// replace it.
  bool _edited = false;

  /// `'ar-JO'` or `'en-US'`; the last choice is remembered in settings.
  String get language => settings.settings.value.voiceLanguage;

  MessageService get _messages => Get.find<MessageService>();

  @override
  void onInit() {
    super.onInit();
    _refreshConfigured();
  }

  Future<bool> _refreshConfigured() async {
    bool value;
    try {
      value = await ai.isConfigured;
    } catch (_) {
      value = false;
    }
    configured.value = value;
    return value;
  }

  /// Re-checks the key; without one, explains that voice needs it.
  Future<bool> ensureConfigured() async {
    final ok = await _refreshConfigured();
    if (!ok) _messages.showError(voiceNeedsKeyMessage);
    return ok;
  }

  Future<void> setLanguage(String code) async {
    if (!languages.contains(code) || code == language) return;
    try {
      await settings
          .update(settings.settings.value.copyWith(voiceLanguage: code));
    } on DatabaseException {
      _messages.showError('تعذّر حفظ الإعدادات');
      return;
    }
    if (state.value == VoiceState.listening) {
      _session++;
      await _stopSpeech();
      await _listen();
    }
  }

  Future<void> startListening() async {
    if (state.value == VoiceState.listening ||
        state.value == VoiceState.sending) {
      return;
    }
    // Closing the sheet or tapping again while this call waits bumps the
    // session; then this call stops, so the recognizer never starts without
    // a sheet or twice.
    final session = ++_session;
    if (!await ensureConfigured() || session != _session) return;
    bool available;
    try {
      available = await speech.init();
    } catch (_) {
      available = false;
    }
    if (session != _session) return;
    if (!available) {
      state.value = VoiceState.idle;
      _messages.showError(speechUnavailableMessage);
      return;
    }
    await _listen();
  }

  Future<void> _listen() async {
    final session = ++_session;
    text.value = '';
    _edited = false;
    state.value = VoiceState.listening;
    try {
      await speech.start(
        localeId: language,
        onResult: (words, isFinal) => _onResult(session, words, isFinal),
        onDone: () => _onDone(session),
      );
    } catch (_) {
      if (session != _session) return;
      state.value = VoiceState.idle;
      _messages.showError(speechUnavailableMessage);
    }
  }

  void _onResult(int session, String words, bool isFinal) {
    if (session != _session) return;
    switch (state.value) {
      case VoiceState.listening:
        text.value = words;
        if (isFinal) _finish();
      case VoiceState.editing:
        // A final result can arrive just after the user tapped stop.
        if (!_edited) text.value = words;
      case VoiceState.idle:
      case VoiceState.sending:
        break;
    }
  }

  void _onDone(int session) {
    if (session == _session && state.value == VoiceState.listening) _finish();
  }

  /// Ends listening: with words, they can be edited; without, back to idle.
  void _finish() {
    state.value =
        text.value.trim().isEmpty ? VoiceState.idle : VoiceState.editing;
  }

  Future<void> stopListening() async {
    if (state.value != VoiceState.listening) return;
    await _stopSpeech();
    _finish();
  }

  Future<void> _stopSpeech() async {
    try {
      await speech.stop();
    } catch (_) {
      // Already stopped.
    }
  }

  /// The user typed a correction.
  void edit(String value) {
    text.value = value;
    _edited = true;
  }

  /// Stops listening and forgets the words (the sheet was closed). A send
  /// already under way finishes on its own.
  Future<void> cancel() async {
    if (state.value == VoiceState.sending) return;
    final wasListening = state.value == VoiceState.listening;
    _session++;
    state.value = VoiceState.idle;
    text.value = '';
    _edited = false;
    if (wasListening) await _stopSpeech();
  }

  /// Sends the words to the AI and stores the extracted entry as a pending
  /// item, which it returns. On any failure shows a message, keeps the words
  /// and returns null.
  Future<PendingItem?> send() async {
    final spoken = text.value.trim();
    if (spoken.isEmpty || state.value == VoiceState.sending) return null;
    if (state.value == VoiceState.listening) {
      _session++;
      await _stopSpeech();
    }
    state.value = VoiceState.sending;
    try {
      final result = await ai.parseVoice(spoken);
      final saved = await imports.addPending([await _toPending(result)]);
      text.value = '';
      _edited = false;
      state.value = VoiceState.idle;
      return saved.single;
    } on AiException catch (e) {
      _messages.showError(e.message);
    } catch (_) {
      _messages.showError(aiGenericMessage);
    }
    state.value = VoiceState.editing;
    return null;
  }

  Future<PendingItem> _toPending(VoiceResult result) async {
    final now = _clock();
    int? categoryId;
    int? personId;
    String? personName;
    final kind = switch (result.kind) {
      PendingKind.expense => TransactionKind.expense,
      PendingKind.income => TransactionKind.income,
      _ => null,
    };
    if (kind != null) {
      if (result.category case final name?) {
        for (final c in await categories.getAll(kind: kind)) {
          if (_sameName(c.name, name)) {
            categoryId = c.id;
            break;
          }
        }
      }
    } else if (result.person case final spoken?) {
      personName = spoken;
      for (final p in await debts.getPeople()) {
        if (_sameName(p.name, spoken)) {
          personId = p.id;
          personName = p.name;
          break;
        }
      }
    }
    return PendingItem(
      source: PendingSource.voice,
      kind: result.kind,
      amount: result.amount,
      occurredAt: result.date ?? now,
      suggestedCategoryId: categoryId,
      personId: personId,
      personName: personName,
      note: result.note,
      createdAt: now,
    );
  }

  static bool _sameName(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();
}
