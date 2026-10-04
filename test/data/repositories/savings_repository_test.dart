import 'package:calculator/app/data/models/savings_goal.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_database.dart';

void main() {
  late DatabaseService database;
  late SavingsRepository repo;

  setUp(() async {
    database = await openTestDatabase();
    repo = SavingsRepository(database);
  });

  Future<SavingsGoal> laptop() => repo.addGoal(SavingsGoal(
      name: 'لابتوب', targetAmount: 900000, createdAt: DateTime(2026, 10, 1)));

  test('General Savings comes first, then goals', () async {
    await laptop();
    final goals = await repo.getGoals();
    expect(goals.map((g) => g.name), ['ادخار عام', 'لابتوب']);
    expect(goals.first.isGeneral, isTrue);
  });

  test('balances add up deposits and withdrawals per goal', () async {
    final goal = await laptop();
    await repo.addMovement(saving(100000, DateTime(2026, 10, 1), goalId: goal.id!));
    await repo.addMovement(saving(-30000, DateTime(2026, 10, 2), goalId: goal.id!));
    await repo.addMovement(saving(5000, DateTime(2026, 10, 2)));
    expect(await repo.balances(), {goal.id: 70000, 1: 5000});
    expect((await repo.getMovements(goal.id!)).map((m) => m.amount), [-30000, 100000]);
  });

  test('a withdrawal larger than the goal holds is refused and nothing is saved', () async {
    final goal = await laptop();
    await repo.addMovement(saving(10000, DateTime(2026, 10, 1), goalId: goal.id!));
    await expectLater(
      repo.addMovement(saving(-20000, DateTime(2026, 10, 2), goalId: goal.id!)),
      throwsA(isA<InsufficientSavingsException>()
          .having((e) => e.available, 'available', 10000)),
    );
    expect((await repo.balances())[goal.id], 10000);
  });

  test('a batch is all or nothing', () async {
    final goal = await laptop();
    await expectLater(
      repo.addMovements([
        saving(50000, DateTime(2026, 10, 1)),
        saving(-1, DateTime(2026, 10, 1), goalId: goal.id!),
      ]),
      throwsA(isA<InsufficientSavingsException>()),
    );
    expect(await repo.getAllMovements(), isEmpty);
  });

  test('a goal is deleted when unused, archived when it has history', () async {
    final unused = await laptop();
    expect(await repo.removeGoal(unused), isFalse);
    expect(await repo.getGoal(unused.id!), isNull);

    final used = await laptop();
    await repo.addMovement(saving(1000, DateTime(2026, 10, 1), goalId: used.id!));
    await repo.addMovement(saving(-1000, DateTime(2026, 10, 2), goalId: used.id!));
    expect(await repo.removeGoal(used), isTrue);
    expect((await repo.getGoal(used.id!))!.isArchived, isTrue);
    expect((await repo.getGoals()).map((g) => g.id), isNot(contains(used.id)));
  });

  test('a goal that still holds money cannot be removed', () async {
    final goal = await laptop();
    await repo.addMovement(saving(1000, DateTime(2026, 10, 1), goalId: goal.id!));
    await expectLater(repo.removeGoal(goal), throwsA(isA<GoalNotEmptyException>()));
  });

  test('General Savings can never be removed', () async {
    final general = (await repo.getGoals()).first;
    await expectLater(repo.removeGoal(general), throwsArgumentError);
  });

  test('a month-end split and its answer are saved together, or not at all', () async {
    await database.db.execute('DROP TABLE settings');
    await expectLater(
      repo.addMovements([saving(1000, DateTime(2026, 10, 1))], answeredPeriodKey: '2026-09'),
      throwsA(anything),
    );
    expect(await repo.getAllMovements(), isEmpty);
  });

  test('a goal with a fixed monthly saving cannot be removed', () async {
    final goal = await laptop();
    await database.db.insert('recurring_rules', {
      'label': 'لابتوب',
      'kind': 'saving',
      'amount': 50000,
      'goal_id': goal.id,
      'day_of_month': 1,
      'start_date': '2026-11-01',
      'is_active': 0,
    });
    await expectLater(repo.removeGoal(goal), throwsA(isA<GoalHasRecurringException>()));
    expect(await repo.getGoal(goal.id!), isNotNull);
  });

}
