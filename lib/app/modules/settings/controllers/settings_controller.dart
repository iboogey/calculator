import 'package:get/get.dart';

import '../../../core/utils/currencies.dart';
import '../../../data/models/app_settings.dart';
import '../../../services/settings_service.dart';

class SettingsController extends GetxController {
  SettingsController({required this.settingsService});

  final SettingsService settingsService;

  /// Reads the reactive value, so an `Obx` that uses it rebuilds on change.
  AppSettings get settings => settingsService.settings.value;

  Future<void> setStartDay(int day) =>
      settingsService.update(settings.copyWith(periodStartDay: day));

  Future<void> setCurrency(String code) {
    final currency = Currencies.byCode(code);
    return settingsService.update(settings.copyWith(
      currencyCode: currency.code,
      currencyDecimals: currency.decimals,
    ));
  }
}
