import 'package:get/get.dart';

import '../core/logic/ai_prompts.dart';
import '../core/logic/bank_sms_parser.dart';
import '../data/models/app_settings.dart';
import '../data/models/enums.dart';
import '../data/providers/ai_client.dart';
import '../data/providers/secret_store.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/debt_repository.dart';
import 'settings_service.dart';
import 'sms_import_service.dart';

/// Builds the client for the chosen provider; replaced in tests.
typedef AiClientFactory = AiClient Function(
    AiProviderKind kind, String apiKey, String? model);

const aiNotConfiguredMessage = 'أضف مفتاح الذكاء الاصطناعي في الإعدادات';
const aiVoiceParseMessage = 'تعذّر فهم الطلب، حاول مرة أخرى';

/// Ties the user's AI provider and key to category suggestions (SMS scan),
/// voice entry parsing and the settings connection test.
class AiService extends GetxService {
  AiService({
    required this.settings,
    required this.secrets,
    required this.categories,
    required this.debts,
    AiClientFactory? clientFactory,
  }) : _factory = clientFactory ?? _defaultFactory;

  final SettingsService settings;
  final SecretStore secrets;
  final CategoryRepository categories;
  final DebtRepository debts;
  final AiClientFactory _factory;

  static AiClient _defaultFactory(
          AiProviderKind kind, String apiKey, String? model) =>
      createAiClient(kind, apiKey: apiKey, model: model);

  @override
  void onInit() {
    super.onInit();
    Get.find<SmsImportService>().suggester = suggestCategory;
  }

  Future<String?> _key() async {
    final provider = settings.settings.value.aiProvider;
    if (provider == AiProviderKind.none) return null;
    final key = (await secrets.read(apiKeyName(provider)))?.trim();
    return (key == null || key.isEmpty) ? null : key;
  }

  Future<bool> get isConfigured async => await _key() != null;

  /// The configured client, or null when no provider or key is set.
  Future<AiClient?> _client() async {
    final key = await _key();
    if (key == null) return null;
    final value = settings.settings.value;
    return _factory(value.aiProvider, key, value.aiModel);
  }

  /// A category id for an unknown card-purchase shop, or null. Only the shop
  /// name and city leave the device; never throws.
  Future<int?> suggestCategory(ParsedBankSms sms) async {
    if (sms.type != BankSmsType.cardPurchase) return null;
    try {
      final client = await _client();
      if (client == null) return null;
      final all = await categories.getAll(kind: TransactionKind.expense);
      final reply = await client.complete(
        AiPrompts.category(
          merchant: sms.name,
          city: sms.city,
          categories: [for (final c in all) c.name],
        ),
        timeout: const Duration(seconds: 15),
      );
      final name = AiResponses.category(reply, [for (final c in all) c.name]);
      if (name == null) return null;
      for (final c in all) {
        if (c.name == name) return c.id;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Turns a spoken note into a money entry. Throws [AiException] (Arabic
  /// message) when not configured, on provider failure or an unusable reply.
  Future<VoiceResult> parseVoice(String text) async {
    final client = await _client();
    if (client == null) throw const AiException(aiNotConfiguredMessage);
    final expense = await categories.getAll(kind: TransactionKind.expense);
    final income = await categories.getAll(kind: TransactionKind.income);
    final people = await debts.getPeople();
    final reply = await client.complete(
      AiPrompts.voice(
        text: text,
        categories: [
          for (final c in expense) c.name,
          for (final c in income) c.name,
        ],
        people: [for (final p in people) p.name],
        today: DateTime.now(),
        currencyCode: settings.currency.code,
      ),
      timeout: const Duration(seconds: 20),
    );
    final result = AiResponses.voice(reply);
    if (result == null) throw const AiException(aiVoiceParseMessage);
    return result;
  }

  /// Sends a tiny prompt to check the key. Throws [AiException] on failure.
  Future<void> testConnection() async {
    final client = await _client();
    if (client == null) throw const AiException(aiNotConfiguredMessage);
    await client.complete('Reply with the single word: ok',
        timeout: const Duration(seconds: 15));
  }
}
