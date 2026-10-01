import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/transactions/controllers/transactions_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<TransactionsController> open(DateTime now) async {
    final controller = Get.put(TransactionsController(
      transactions: Get.find(),
      categories: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      clock: () => now,
    ));
    await controller.load();
    return controller;
  }

  TransactionRepository repo() => Get.find<TransactionRepository>();

  Future<void> seed() async {
    await repo().add(expense(2000, DateTime(2026, 10, 3)));
    await repo().add(expense(1000, DateTime(2026, 10, 3)));
    await repo().add(income(10000, DateTime(2026, 10, 5)));
    await repo().add(expense(3000, DateTime(2026, 10, 5)));
    await repo().add(expense(9000, DateTime(2026, 9, 20)));
  }

  test('groups the current period by day, newest first', () async {
    await seed();
    final c = await open(DateTime(2026, 10, 15));
    expect(c.groups.map((g) => g.day), [DateTime(2026, 10, 5), DateTime(2026, 10, 3)]);
    expect(c.groups.first.net, 7000);
    expect(c.groups.last.transactions, hasLength(2));
  });

  test('moves to the previous and next period', () async {
    await seed();
    final c = await open(DateTime(2026, 10, 15));
    await c.previousPeriod();
    expect(c.period.value!.key, '2026-09');
    expect(c.groups.single.transactions.single.amount, 9000);
    await c.nextPeriod();
    expect(c.period.value!.key, '2026-10');
  });

  test('delete hides the row at once and undo restores the same record', () async {
    await seed();
    final c = await open(DateTime(2026, 10, 15));
    final target = c.groups.first.transactions.first;
    final pending = c.delete(target);
    expect(c.groups.expand((g) => g.transactions).map((t) => t.id),
        isNot(contains(target.id)));
    await pending;
    expect(await repo().getById(target.id!), isNull);
    await c.undoDelete(target);
    expect(await repo().getById(target.id!), target);
    await settle();
    expect(c.groups.expand((g) => g.transactions).map((t) => t.id), contains(target.id));
  });
}
