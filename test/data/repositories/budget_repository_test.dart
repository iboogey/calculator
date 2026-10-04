import 'package:calculator/app/data/repositories/budget_repository.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

void main() {
  late DatabaseService database;
  late BudgetRepository repo;

  setUp(() async {
    database = await openTestDatabase();
    repo = BudgetRepository(database);
  });

  test('setLimit creates, then replaces, one budget per category', () async {
    await repo.setLimit(1, 200000);
    await repo.setLimit(1, 150000);
    final all = await repo.getAll();
    expect(all.single.categoryId, 1);
    expect(all.single.limitAmount, 150000);
  });

  test('setLimit and remove announce the change', () async {
    final before = database.revision.value;
    await repo.setLimit(2, 80000);
    await repo.remove(2);
    expect(database.revision.value, before + 2);
    expect(await repo.getAll(), isEmpty);
  });

  test('an alert is marked as sent only once per category, period and threshold', () async {
    expect(await repo.markAlertSent(1, '2026-10', 80), isTrue);
    expect(await repo.markAlertSent(1, '2026-10', 80), isFalse);
    expect(await repo.markAlertSent(1, '2026-10', 100), isTrue);
    expect(await repo.markAlertSent(1, '2026-11', 80), isTrue);
    expect(await repo.markAlertSent(2, '2026-10', 80), isTrue);
  });
}
