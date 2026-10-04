import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/reports/controllers/reports_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<ReportsController> open() async {
    final c = Get.put(ReportsController(
      transactions: Get.find(),
      categories: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      clock: () => DateTime(2026, 10, 15),
    ));
    await c.load();
    return c;
  }

  test('shares, six-period totals and the change from last period', () async {
    final repo = Get.find<TransactionRepository>();
    await repo.add(expense(100000, DateTime(2026, 9, 5)));
    await repo.add(expense(84000, DateTime(2026, 10, 2)));
    await repo.add(expense(28000, DateTime(2026, 10, 3), categoryId: 3));

    final c = await open();
    expect(c.shares.map((s) => s.category.name), ['أكل', 'فواتير']);
    expect(c.shares.map((s) => s.percent), [75, 25]);
    expect(c.totalSpent.value, 112000);
    expect(c.totals, hasLength(ReportsController.reportPeriods));
    expect(c.totals.last.expenses, 112000);
    expect(c.change.value, 12);
  });

  test('an empty period has no shares and no change', () async {
    final c = await open();
    expect(c.shares, isEmpty);
    expect(c.totalSpent.value, 0);
    expect(c.change.value, isNull);
  });

  test('moving to the previous period', () async {
    await Get.find<TransactionRepository>().add(expense(100000, DateTime(2026, 9, 5)));
    final c = await open();
    await c.previousPeriod();
    expect(c.period.value!.key, '2026-09');
    expect(c.totalSpent.value, 100000);
  });
}
