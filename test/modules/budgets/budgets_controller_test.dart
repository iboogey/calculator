import 'package:calculator/app/core/logic/budget_status.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/recurring_rule.dart';
import 'package:calculator/app/data/repositories/recurring_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/budgets/controllers/budgets_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<BudgetsController> open(DateTime now) async {
    final c = Get.put(BudgetsController(
      budgets: Get.find(),
      categories: Get.find(),
      transactions: Get.find(),
      recurring: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      clock: () => now,
    ));
    await c.load();
    return c;
  }

  test('setting a limit shows its status and removes it from the add list', () async {
    await Get.find<TransactionRepository>().add(expense(176000, DateTime(2026, 10, 3)));
    final c = await open(DateTime(2026, 10, 10));
    expect(c.unbudgeted, hasLength(8));
    expect(await c.setLimit(foodCategoryId, '200'), isTrue);
    await settle();
    final food = c.statuses.single;
    expect(food.limit, 200000);
    expect(food.spent, 176000);
    expect(food.level, BudgetLevel.warning);
    expect(c.unbudgeted.map((x) => x.id), isNot(contains(foodCategoryId)));
  });

  test('an invalid limit is refused', () async {
    final c = await open(DateTime(2026, 10, 10));
    expect(await c.setLimit(foodCategoryId, '0'), isFalse);
    expect(await c.setLimit(foodCategoryId, 'abc'), isFalse);
    expect(c.statuses, isEmpty);
  });

  test('removing a limit', () async {
    final c = await open(DateTime(2026, 10, 10));
    await c.setLimit(foodCategoryId, '50');
    await c.removeLimit(foodCategoryId);
    await settle();
    expect(c.statuses, isEmpty);
  });

  test('lists active recurring rules with their next date and days left', () async {
    await Get.find<RecurringRepository>().add(RecurringRule(
      label: 'نت',
      kind: RecurringKind.expense,
      amount: 25000,
      categoryId: 3,
      dayOfMonth: 15,
      startDate: DateTime(2026, 10, 15),
    ));
    final c = await open(DateTime(2026, 10, 10));
    expect(c.rules.single.label, 'نت');
    expect(c.nextDue(c.rules.single), DateTime(2026, 10, 15));
    expect(c.daysLeft, 22);
  });
}
