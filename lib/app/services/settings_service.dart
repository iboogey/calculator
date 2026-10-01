import 'package:get/get.dart';

import '../core/logic/period.dart';
import '../core/utils/currencies.dart';
import '../data/models/app_settings.dart';
import '../data/repositories/settings_repository.dart';
import 'database_service.dart';

/// The current settings, shared by every screen.
class SettingsService extends GetxService {
  SettingsService(this._repository, this._database);

  final SettingsRepository _repository;
  final DatabaseService _database;

  final settings = const AppSettings().obs;

  Future<SettingsService> init() async {
    settings.value = await _repository.load();
    return this;
  }

  Future<void> update(AppSettings value) async {
    await _repository.save(value);
    settings.value = value;
    _database.notifyChanged();
  }

  Currency get currency => Currencies.byCode(settings.value.currencyCode);

  Period currentPeriod([DateTime? now]) => Period.containing(
        now ?? DateTime.now(),
        startDay: settings.value.periodStartDay,
      );
}
