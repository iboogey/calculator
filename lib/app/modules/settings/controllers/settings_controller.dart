import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/arabic_count.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/providers/ai/claude_client.dart';
import '../../../data/providers/ai/gemini_client.dart';
import '../../../data/providers/ai/openai_client.dart';
import '../../../data/providers/ai_client.dart';
import '../../../data/providers/file_exchange_provider.dart';
import '../../../data/providers/secret_store.dart';
import '../../../data/providers/sms_inbox_provider.dart';
import '../../../routes/app_routes.dart';
import '../../../services/ai_service.dart';
import '../../../services/backup_service.dart';
import '../../../services/message_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/sms_import_service.dart';

class SettingsController extends GetxController with WidgetsBindingObserver {
  SettingsController({
    required this.settingsService,
    required this.notifications,
    required this.backup,
    required this.files,
    required this.smsInbox,
    required this.smsImport,
    required this.ai,
    required this.secrets,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SettingsService settingsService;
  final NotificationService notifications;
  final BackupService backup;
  final FileExchangeProvider files;
  final SmsInboxProvider smsInbox;
  final SmsImportService smsImport;
  final AiService ai;
  final SecretStore secrets;
  final DateTime Function() _clock;

  static const backupReminderDays = 30;

  final _smsPermission = false.obs;

  bool get smsSupported => smsInbox.isSupported;

  /// The setting is on and the Android permission is still granted.
  bool get smsImportOn =>
      settings.smsImportEnabled && _smsPermission.value;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _refreshSmsPermission();
    _refreshHasApiKey();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshSmsPermission();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  Future<void> _refreshSmsPermission() async {
    if (!smsSupported) return;
    try {
      _smsPermission.value = await smsInbox.hasPermission();
    } catch (_) {
      _smsPermission.value = false;
    }
  }

  Future<void> setSmsImport(bool enabled) async {
    if (!enabled) {
      await _update(settings.copyWith(smsImportEnabled: false));
      return;
    }
    bool granted;
    try {
      granted = await smsInbox.requestPermission();
    } catch (_) {
      granted = false;
    }
    _smsPermission.value = granted;
    if (!granted) {
      Get.find<MessageService>()
          .showError('لا يمكن قراءة رسائل البنك دون إذن الرسائل');
      return;
    }
    await _update(settings.copyWith(smsImportEnabled: true));
    try {
      await smsImport.scan(_clock());
    } catch (_) {
      // The next start or resume scans again.
    }
  }

  /// Whether a key is stored for the chosen provider. The key itself is never
  /// exposed.
  final hasApiKey = false.obs;

  final testingConnection = false.obs;

  Future<void> _refreshHasApiKey() async {
    final provider = settings.aiProvider;
    if (provider == AiProviderKind.none) {
      hasApiKey.value = false;
      return;
    }
    try {
      final key = (await secrets.read(apiKeyName(provider)))?.trim();
      // Ignore a stale answer if the provider changed meanwhile.
      if (provider == settings.aiProvider) {
        hasApiKey.value = key != null && key.isNotEmpty;
      }
    } catch (_) {
      hasApiKey.value = false;
    }
  }

  /// The model the provider uses when the field is empty.
  String defaultModelFor(AiProviderKind kind) {
    switch (kind) {
      case AiProviderKind.gemini:
        return GeminiClient.defaultModel;
      case AiProviderKind.claude:
        return ClaudeClient.defaultModel;
      case AiProviderKind.openai:
        return OpenAiClient.defaultModel;
      case AiProviderKind.none:
        return '';
    }
  }

  Future<void> setAiProvider(AiProviderKind kind) async {
    // The model is provider-specific, so a change of provider resets it.
    await _update(settings.copyWith(aiProvider: kind, clearAiModel: true));
    await _refreshHasApiKey();
  }

  /// True when the key was stored.
  Future<bool> saveApiKey(String key) async {
    final provider = settings.aiProvider;
    final trimmed = key.trim();
    if (trimmed.isEmpty || provider == AiProviderKind.none) return false;
    try {
      await secrets.write(apiKeyName(provider), trimmed);
    } catch (_) {
      Get.find<MessageService>().showError('تعذّر حفظ المفتاح');
      return false;
    }
    await _refreshHasApiKey();
    return true;
  }

  Future<void> deleteApiKey() async {
    final provider = settings.aiProvider;
    if (provider == AiProviderKind.none) return;
    try {
      await secrets.delete(apiKeyName(provider));
    } catch (_) {
      Get.find<MessageService>().showError('تعذّر حذف المفتاح');
      return;
    }
    await _refreshHasApiKey();
  }

  Future<void> setAiModel(String text) {
    final model = text.trim();
    return _update(model.isEmpty
        ? settings.copyWith(clearAiModel: true)
        : settings.copyWith(aiModel: model));
  }

  /// Checks the key with a tiny request; reports the outcome as a message.
  Future<bool> testAiConnection() async {
    if (testingConnection.value) return false;
    testingConnection.value = true;
    final messages = Get.find<MessageService>();
    try {
      await ai.testConnection();
      messages.showInfo('تم الاتصال بنجاح');
      return true;
    } on AiException catch (e) {
      messages.showError(e.message);
      return false;
    } catch (_) {
      messages.showError(aiGenericMessage);
      return false;
    } finally {
      testingConnection.value = false;
    }
  }

  /// Reads the reactive value, so an `Obx` that uses it rebuilds on change.
  AppSettings get settings => settingsService.settings.value;

  bool get permissionGranted => notifications.permissionGranted.value;

  /// "21:00"
  String get reminderLabel {
    final minutes = settings.reminderMinutes;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(minutes ~/ 60)}:${two(minutes % 60)}';
  }

  Future<void> setStartDay(int day) =>
      _update(settings.copyWith(periodStartDay: day));

  Future<void> setCurrency(String code) {
    final currency = Currencies.byCode(code);
    return _update(
      settings.copyWith(
        currencyCode: currency.code,
        currencyDecimals: currency.decimals,
      ),
    );
  }

  Future<void> setReminderEnabled(bool enabled) =>
      _update(settings.copyWith(reminderEnabled: enabled));

  Future<void> setReminderTime(int hour, int minute) =>
      _update(settings.copyWith(reminderMinutes: hour * 60 + minute));

  String get lastBackupLabel {
    final last = settings.lastBackupAt;
    if (last == null) return 'لم تُنشئ نسخة احتياطية بعد';
    final days =
        DateKeys.dateOnly(_clock()).difference(DateKeys.dateOnly(last)).inDays;
    if (days <= 0) return 'آخر نسخة: اليوم';
    if (days == 1) return 'آخر نسخة: أمس';
    final ago = ArabicCount.of(days,
        one: 'يوم', two: 'يومين', few: 'أيام', many: 'يومًا');
    return 'آخر نسخة: قبل $ago';
  }

  bool get backupOverdue {
    final last = settings.lastBackupAt;
    return last == null || _clock().difference(last).inDays > backupReminderDays;
  }

  bool _exporting = false;

  Future<void> exportBackup() async {
    if (_exporting) return;
    _exporting = true;
    try {
      await backup.shareBackup(_clock());
    } catch (_) {
      Get.find<MessageService>().showError('تعذّر إنشاء النسخة الاحتياطية');
    } finally {
      _exporting = false;
    }
  }

  /// Lets the user pick a backup file. Null when cancelled or invalid (a
  /// message explains why).
  Future<BackupSummary?> pickBackup() async {
    final String? text;
    try {
      text = await files.pickJsonText();
    } catch (_) {
      Get.find<MessageService>().showError('تعذّر فتح الملف');
      return null;
    }
    if (text == null) return null;
    try {
      return backup.parse(text);
    } on BackupFormatException catch (e) {
      Get.find<MessageService>().showError(e.message);
      return null;
    }
  }

  Future<bool> restore(BackupSummary summary) async {
    try {
      await backup.restore(summary);
      return true;
    } catch (_) {
      Get.find<MessageService>()
          .showError('تعذّرت استعادة النسخة. لم تتغيّر بياناتك الحالية');
      return false;
    }
  }

  void openRecurring() => Get.toNamed(Routes.recurring);

  void openFavorites() => Get.toNamed(Routes.templates);

  Future<void> _update(AppSettings value) async {
    try {
      await settingsService.update(value);
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر حفظ الإعدادات');
    }
  }
}
