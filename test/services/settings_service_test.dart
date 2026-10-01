import 'package:calculator/app/data/models/app_settings.dart';
import 'package:calculator/app/data/repositories/settings_repository.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/test_database.dart';

void main() {
  test('update saves, exposes the new value, then announces the change', () async {
    final database = await openTestDatabase();
    final service = await SettingsService(SettingsRepository(database), database).init();
    AppSettings? seenOnChange;
    ever(database.revision, (_) => seenOnChange = service.settings.value);

    await service.update(service.settings.value.copyWith(periodStartDay: 25));
    await Future<void>.delayed(Duration.zero);

    expect(seenOnChange?.periodStartDay, 25);
    expect((await SettingsRepository(database).load()).periodStartDay, 25);
  });

  test('currency and current period follow the settings', () async {
    final database = await openTestDatabase();
    final service = await SettingsService(SettingsRepository(database), database).init();
    expect(service.currency.code, 'JOD');
    await service.update(service.settings.value
        .copyWith(periodStartDay: 25, currencyCode: 'USD', currencyDecimals: 2));
    expect(service.currency.decimals, 2);
    expect(service.currentPeriod(DateTime(2026, 10, 10)).start, DateTime(2026, 9, 25));
  });
}
