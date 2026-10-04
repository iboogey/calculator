import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/home/controllers/home_controller.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<HomeController> open(DateTime now) async {
    final controller = Get.put(HomeController(
      transactions: Get.find(),
      categories: Get.find(),
      savings: Get.find(),
      templates: Get.find(),
      budgets: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      clock: () => now,
    ));
    await controller.load();
    return controller;
  }

  TransactionRepository repo() => Get.find<TransactionRepository>();

  test('summarises the current period', () async {
    await repo().add(income(1250000, DateTime(2026, 10, 1)));
    await repo().add(expense(600000, DateTime(2026, 10, 5)));
    final c = await open(DateTime(2026, 10, 15));
    expect(c.period.value!.key, '2026-10');
    expect(c.summary.value!.remaining, 650000);
    expect(c.categoriesById[foodCategoryId]!.name, 'أكل');
  });

  test('reloads after a change anywhere in the database', () async {
    final c = await open(DateTime(2026, 10, 15));
    await repo().add(expense(5000, DateTime(2026, 10, 15)));
    await settle();
    expect(c.summary.value!.expenses, 5000);
    expect(c.recent, hasLength(1));
  });

  test('recent shows the newest five', () async {
    for (var day = 1; day <= 7; day++) {
      await repo().add(expense(1000, DateTime(2026, 10, day)));
    }
    final c = await open(DateTime(2026, 10, 15));
    expect(c.recent.map((t) => t.date.day), [7, 6, 5, 4, 3]);
  });

  test('follows the period start day from settings', () async {
    final settings = Get.find<SettingsService>();
    await settings.update(settings.settings.value.copyWith(periodStartDay: 25));
    final c = await open(DateTime(2026, 10, 10));
    expect(c.period.value!.start, DateTime(2026, 9, 25));
  });
}
