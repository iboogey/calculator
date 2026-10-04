import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/currencies.dart';
import '../../../data/models/app_settings.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

class SettingsController extends GetxController {
  SettingsController({required this.settingsService});

  final SettingsService settingsService;

  /// Reads the reactive value, so an `Obx` that uses it rebuilds on change.
  AppSettings get settings => settingsService.settings.value;

  Future<void> setStartDay(int day) =>
      _update(settings.copyWith(periodStartDay: day));

  Future<void> setCurrency(String code) {
    final currency = Currencies.byCode(code);
    return _update(settings.copyWith(
      currencyCode: currency.code,
      currencyDecimals: currency.decimals,
    ));
  }

  Future<void> _update(AppSettings value) async {
    try {
      await settingsService.update(value);
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ الإعدادات');
    }
  }
}
