import 'package:calculator/app/data/models/savings_goal.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/modules/savings/controllers/savings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  test('lists General Savings and goals with what each holds and the total', () async {
    final repo = Get.find<SavingsRepository>();
    final goal = await repo.addGoal(SavingsGoal(
      name: 'لابتوب',
      targetAmount: 900000,
      targetDate: DateTime(2027, 3, 10),
      createdAt: DateTime(2026, 10, 1),
    ));
    await repo.addMovement(saving(540000, DateTime(2026, 10, 1), goalId: goal.id!));
    await repo.addMovement(saving(20000, DateTime(2026, 10, 1)));

    final c = Get.put(SavingsController(
      savings: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      clock: () => DateTime(2026, 10, 4),
    ));
    await c.load();
    expect(c.goals.map((g) => g.goal.name), ['ادخار عام', 'لابتوب']);
    expect(c.goals.last.saved, 540000);
    expect(c.total.value, 560000);
    expect(c.monthlyNeeded(c.goals.last), 60000);
    expect(c.monthlyNeeded(c.goals.first), isNull);
  });
}
