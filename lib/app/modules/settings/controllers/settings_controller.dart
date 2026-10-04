import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/providers/file_exchange_provider.dart';
import '../../../routes/app_routes.dart';
import '../../../services/backup_service.dart';
import '../../../services/message_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/settings_service.dart';

class SettingsController extends GetxController {
  SettingsController({
    required this.settingsService,
    required this.notifications,
    required this.backup,
    required this.files,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SettingsService settingsService;
  final NotificationService notifications;
  final BackupService backup;
  final FileExchangeProvider files;
  final DateTime Function() _clock;

  static const backupReminderDays = 30;

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
    if (last == null) return 'ما عملت نسخة احتياطية لسا';
    final days =
        DateKeys.dateOnly(_clock()).difference(DateKeys.dateOnly(last)).inDays;
    if (days <= 0) return 'آخر نسخة: اليوم';
    if (days == 1) return 'آخر نسخة: مبارح';
    return 'آخر نسخة: قبل $days يوم';
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
      Get.find<MessageService>().showError('ما قدرنا نعمل النسخة الاحتياطية');
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
      Get.find<MessageService>().showError('ما قدرنا نفتح الملف');
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
          .showError('ما قدرنا نسترجع النسخة. بياناتك الحالية ما تغيّرت');
      return false;
    }
  }

  void openRecurring() => Get.toNamed(Routes.recurring);

  void openFavorites() => Get.toNamed(Routes.templates);

  Future<void> _update(AppSettings value) async {
    try {
      await settingsService.update(value);
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ الإعدادات');
    }
  }
}
