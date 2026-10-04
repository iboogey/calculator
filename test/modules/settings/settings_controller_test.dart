import 'package:calculator/app/core/utils/money.dart';
import 'package:calculator/app/data/repositories/settings_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/settings/controllers/settings_controller.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  SettingsController open() =>
      Get.put(SettingsController(settingsService: Get.find(), notifications: Get.find()));

  test('changing the start day is saved and shared', () async {
    await open().setStartDay(25);
    expect(Get.find<SettingsService>().settings.value.periodStartDay, 25);
    expect((await Get.find<SettingsRepository>().load()).periodStartDay, 25);
  });

  test('changing currency stores its code and decimals', () async {
    final c = open();
    await c.setCurrency('USD');
    expect(c.settings.currencyCode, 'USD');
    expect(c.settings.currencyDecimals, 2);
  });

  test('switching currency keeps the meaning of saved amounts', () async {
    final saved = await Get.find<TransactionRepository>()
        .add(expense(1250, DateTime(2026, 10, 1)));
    await open().setCurrency('USD');
    final reloaded = await Get.find<TransactionRepository>().getById(saved.id!);
    expect(reloaded!.amount, 1250);
    expect(Money.format(reloaded.amount, decimals: 2), '1.25');
  });
}
