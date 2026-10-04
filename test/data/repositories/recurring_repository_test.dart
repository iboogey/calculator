import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/recurring_rule.dart';
import 'package:calculator/app/data/repositories/recurring_repository.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

RecurringRule rent({DateTime? start, bool active = true}) => RecurringRule(
      label: 'إيجار',
      kind: RecurringKind.expense,
      amount: 350000,
      categoryId: 4,
      dayOfMonth: 1,
      startDate: start ?? DateTime(2026, 8, 15),
      isActive: active,
    );

void main() {
  late DatabaseService database;
  late RecurringRepository repo;
  late TransactionRepository transactions;

  setUp(() async {
    database = await openTestDatabase();
    repo = RecurringRepository(database);
    transactions = TransactionRepository(database);
  });

  test('add, list (active first) and update', () async {
    final paused = await repo.add(rent(active: false).copyWith(label: 'نادي'));
    final active = await repo.add(rent());
    expect((await repo.getAll()).map((r) => r.id), [active.id, paused.id]);
    await repo.update(active.copyWith(amount: 360000));
    expect((await repo.getAll()).first.amount, 360000);
  });

  test('applyDue creates each missed month once, as auto entries', () async {
    final rule = await repo.add(rent());
    expect(await repo.applyDue(DateTime(2026, 10, 4)), 2);
    final created = await transactions.getAll();
    expect(created.map((t) => t.date), [DateTime(2026, 10, 1), DateTime(2026, 9, 1)]);
    expect(created.every((t) => t.isAuto && t.note == 'إيجار' && t.amount == 350000), isTrue);
    expect(created.first.recurringRuleId, rule.id);
    expect((await repo.getAll()).single.lastGeneratedDate, DateTime(2026, 10, 1));
  });

  test('running applyDue again creates nothing and does not announce', () async {
    await repo.add(rent());
    await repo.applyDue(DateTime(2026, 10, 4));
    final before = database.revision.value;
    expect(await repo.applyDue(DateTime(2026, 10, 4)), 0);
    expect(await transactions.getAll(), hasLength(2));
    expect(database.revision.value, before);
  });

  test('a paused rule creates nothing until it is resumed', () async {
    final rule = await repo.add(rent(active: false));
    expect(await repo.applyDue(DateTime(2026, 10, 4)), 0);
    await repo.setActive(rule.id!, true);
    expect(await repo.applyDue(DateTime(2026, 10, 4)), 2);
  });

  test('a saving rule creates savings movements', () async {
    await repo.add(RecurringRule(
      label: 'لابتوب',
      kind: RecurringKind.saving,
      amount: 50000,
      goalId: 1,
      dayOfMonth: 1,
      startDate: DateTime(2026, 10, 1),
    ));
    await repo.applyDue(DateTime(2026, 10, 4));
    final movements = await SavingsRepository(database).getAllMovements();
    expect(movements.single.amount, 50000);
    expect(movements.single.source, SavingsSource.recurring);
    expect(await transactions.getAll(), isEmpty);
  });

  test('deleting a rule keeps the entries it created', () async {
    final rule = await repo.add(rent());
    await repo.applyDue(DateTime(2026, 10, 4));
    await repo.delete(rule.id!);
    expect(await repo.getAll(), isEmpty);
    final kept = await transactions.getAll();
    expect(kept, hasLength(2));
    expect(kept.every((t) => !t.isAuto), isTrue);
  });
}
