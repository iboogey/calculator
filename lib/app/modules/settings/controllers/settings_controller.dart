import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/arabic_count.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/providers/file_exchange_provider.dart';
import '../../../data/providers/sms_inbox_provider.dart';
import '../../../routes/app_routes.dart';
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
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SettingsService settingsService;
  final NotificationService notifications;
  final BackupService backup;
  final FileExchangeProvider files;
  final SmsInboxProvider smsInbox;
  final SmsImportService smsImport;
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
