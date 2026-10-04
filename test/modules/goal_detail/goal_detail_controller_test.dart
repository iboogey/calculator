import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/modules/goal_detail/controllers/goal_detail_controller.dart';
import 'package:calculator/app/services/message_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<GoalDetailController> open() async {
    final c = Get.put(GoalDetailController(
      savings: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      goalId: 1,
      clock: () => DateTime(2026, 10, 4),
    ));
    await c.load();
    return c;
  }

  test('deposit and withdraw move money in and out of the goal', () async {
    final c = await open();
    expect(c.goal.value!.name, 'ادخار عام');
    expect(await c.deposit('100'), isTrue);
    expect(await c.withdraw('40'), isTrue);
    await settle();
    expect(c.saved.value, 60000);
    expect(c.movements.map((m) => m.amount), [-40000, 100000]);
    expect(c.movements.every((m) => m.source == SavingsSource.manual), isTrue);
    expect(c.movements.first.date, DateTime(2026, 10, 4));
  });

  test('withdrawing more than the goal holds is refused with a message', () async {
    final c = await open();
    await c.deposit('10');
    expect(await c.withdraw('25'), isFalse);
    expect(Get.find<MessageService>().lastMessage.value, contains('10.000'));
    expect((await Get.find<SavingsRepository>().balances())[1], 10000);
  });

  test('invalid amounts are refused', () async {
    final c = await open();
    expect(await c.deposit('0'), isFalse);
    expect(await c.withdraw('abc'), isFalse);
    expect(await Get.find<SavingsRepository>().getAllMovements(), isEmpty);
  });
}
