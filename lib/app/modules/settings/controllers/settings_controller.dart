import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/currencies.dart';
import '../../../data/models/app_settings.dart';
import '../../../routes/app_routes.dart';
import '../../../services/message_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/settings_service.dart';

class SettingsController extends GetxController {
  SettingsController({
    required this.settingsService,
    required this.notifications,
  });

  final SettingsService settingsService;
  final NotificationService notifications;

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
