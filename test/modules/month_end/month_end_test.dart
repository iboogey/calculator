import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/savings_goal.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/home/controllers/home_controller.dart';
import 'package:calculator/app/modules/month_end/controllers/month_end_controller.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  final today = DateTime(2026, 10, 4);

  setUp(() async {
    await setUpTestServices();
    final repo = Get.find<TransactionRepository>();
    await repo.add(income(1250000, DateTime(2026, 9, 1)));
    await repo.add(expense(750000, DateTime(2026, 9, 10)));
  });

  Future<HomeController> openHome() async {
    final c = Get.put(HomeController(
      transactions: Get.find(),
      categories: Get.find(),
      savings: Get.find(),
      templates: Get.find(),
      budgets: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      clock: () => today,
    ));
    await c.load();
    return c;
  }

  Future<MonthEndController> openMonthEnd() async {
    final c = Get.put(MonthEndController(
      savings: Get.find(),
      transactions: Get.find(),
      settings: Get.find(),
      clock: () => today,
    ));
    await c.ready;
    return c;
  }

  test('Home offers last period\'s leftover, and Skip hides it for good', () async {
    final home = await openHome();
    expect(home.monthEndOffer.value, 500000);
    await home.skipMonthEnd();
    await settle();
    expect(home.monthEndOffer.value, isNull);
    expect(Get.find<SettingsService>().settings.value.lastMonthEndPromptPeriod, '2026-09');
  });

  test('Home shows total savings and the grand total', () async {
    await Get.find<SavingsRepository>().addMovement(saving(100000, DateTime(2026, 10, 2)));
    final home = await openHome();
    expect(home.summary.value!.totalSavings, 100000);
    expect(home.summary.value!.total, 500000);
  });

  test('splitting the leftover across goals saves it in one step', () async {
    final laptop = await Get.find<SavingsRepository>().addGoal(
        SavingsGoal(name: 'لابتوب', createdAt: DateTime(2026, 10, 1)));
    final c = await openMonthEnd();
    expect(c.offered.value, 500000);
    expect(c.goals.map((g) => g.name), ['ادخار عام', 'لابتوب']);

    c.controllerFor(laptop.id!).text = '100';
    c.controllerFor(1).text = '50';
    expect(c.allocated.value, 150000);
    expect(await c.save(), isTrue);

    final movements = await Get.find<SavingsRepository>().getAllMovements();
    expect(movements.map((m) => m.amount).toSet(), {100000, 50000});
    expect(movements.every((m) => m.source == SavingsSource.monthEnd && m.date == today), isTrue);
    expect(Get.find<SettingsService>().settings.value.lastMonthEndPromptPeriod, '2026-09');
  });

  test('more than the leftover cannot be saved', () async {
    final c = await openMonthEnd();
    c.controllerFor(1).text = '600';
    expect(c.canSave, isFalse);
    expect(await c.save(), isFalse);
    expect(await Get.find<SavingsRepository>().getAllMovements(), isEmpty);
  });

  test('"all to General Savings" fills in the whole leftover', () async {
    final c = await openMonthEnd();
    c.putAllInGeneral();
    expect(c.allocated.value, 500000);
    expect(c.canSave, isTrue);
  });
}
