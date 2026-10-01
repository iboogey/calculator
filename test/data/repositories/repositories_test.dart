import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/repositories/category_repository.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/data/repositories/settings_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_database.dart';

void main() {
  late DatabaseService database;

  setUp(() async => database = await openTestDatabase());

  group('SettingsRepository', () {
    test('loads defaults and saves changes', () async {
      final repo = SettingsRepository(database);
      final defaults = await repo.load();
      expect(defaults.periodStartDay, 1);
      await repo.save(defaults.copyWith(periodStartDay: 25));
      expect((await repo.load()).periodStartDay, 25);
    });
  });

  group('CategoryRepository', () {
    test('filters by kind and hides archived categories', () async {
      final repo = CategoryRepository(database);
      expect(await repo.getAll(kind: TransactionKind.expense), hasLength(8));
      expect((await repo.getAll(kind: TransactionKind.income)).first.name, 'راتب');
      await database.db.update('categories', {'is_archived': 1},
          where: 'id = ?', whereArgs: [1]);
      expect(await repo.getAll(), hasLength(9));
      expect(await repo.getAll(includeArchived: true), hasLength(10));
    });
  });

  group('TransactionRepository', () {
    late TransactionRepository repo;
    setUp(() => repo = TransactionRepository(database));

    test('add assigns an id and announces the change', () async {
      final before = database.revision.value;
      final saved = await repo.add(expense(5000, DateTime(2026, 10, 1)));
      expect(saved.id, isNotNull);
      expect(await repo.getById(saved.id!), saved);
      expect(database.revision.value, before + 1);
    });

    test('update changes the record in place', () async {
      final saved = await repo.add(expense(5000, DateTime(2026, 10, 1)));
      final edited = expense(7000, DateTime(2026, 10, 2), note: 'x').withId(saved.id!);
      await repo.update(edited);
      expect(await repo.getAll(), [edited]);
    });

    test('delete then restore brings back the identical record', () async {
      final saved = await repo.add(expense(5000, DateTime(2026, 10, 1),
          note: 'قهوة', createdAt: DateTime.fromMillisecondsSinceEpoch(1790000000123)));
      await repo.delete(saved.id!);
      expect(await repo.getById(saved.id!), isNull);
      await repo.restore(saved);
      expect(await repo.getById(saved.id!), saved);
    });

    test('getBetween includes the start and excludes the end', () async {
      await repo.add(expense(1000, DateTime(2026, 9, 30)));
      await repo.add(expense(2000, DateTime(2026, 10, 1)));
      await repo.add(expense(3000, DateTime(2026, 10, 31)));
      await repo.add(expense(4000, DateTime(2026, 11, 1)));
      final october = await repo.getBetween(DateTime(2026, 10, 1), DateTime(2026, 11, 1));
      expect(october.map((t) => t.amount), [3000, 2000]);
    });

    test('getRecent returns the newest entries first', () async {
      for (var day = 1; day <= 7; day++) {
        await repo.add(expense(day * 1000, DateTime(2026, 10, day)));
      }
      final recent = await repo.getRecent(limit: 5);
      expect(recent.map((t) => t.date.day), [7, 6, 5, 4, 3]);
    });
  });

  group('SavingsRepository', () {
    test('returns all movements', () async {
      final repo = SavingsRepository(database);
      expect(await repo.getAllMovements(), isEmpty);
      final movement = saving(100000, DateTime(2026, 10, 1));
      await database.db.insert('savings_movements', movement.toMap()..remove('id'));
      final all = await repo.getAllMovements();
      expect(all.single.amount, 100000);
    });
  });
}
