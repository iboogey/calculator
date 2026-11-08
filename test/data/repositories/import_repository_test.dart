import 'package:calculator/app/core/logic/bank_sms_parser.dart';
import 'package:calculator/app/data/models/debt_entry.dart';
import 'package:calculator/app/data/models/pending_item.dart';
import 'package:calculator/app/data/repositories/import_repository.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_database.dart';

PendingItem sms({DateTime? at, String name = 'Sample Super Market'}) =>
    PendingItem(
      source: PendingSource.sms,
      kind: PendingKind.expense,
      amount: 12500,
      occurredAt: at ?? DateTime(2026, 11, 1, 10),
      smsType: BankSmsType.cardPurchase,
      name: name,
      createdAt: DateTime(2026, 11, 2),
    );

PendingItem voice() => PendingItem(
      source: PendingSource.voice,
      kind: PendingKind.expense,
      amount: 3000,
      occurredAt: DateTime(2026, 11, 3),
      note: 'coffee',
      createdAt: DateTime(2026, 11, 3),
    );

void main() {
  late DatabaseService database;
  late ImportRepository repo;

  setUp(() async {
    database = await openTestDatabase();
    repo = ImportRepository(database);
  });
  tearDown(() => database.db.close());

  test('scan point is null, can be set, and never moves backwards', () async {
    expect(await repo.scanPoint(), isNull);
    await repo.setScanPoint(DateTime(2026, 11, 5));
    expect(await repo.scanPoint(), DateTime(2026, 11, 5));
    await repo.setScanPoint(DateTime(2026, 11, 1));
    expect(await repo.scanPoint(), DateTime(2026, 11, 5));
    await repo.setScanPoint(DateTime(2026, 11, 6));
    expect(await repo.scanPoint(), DateTime(2026, 11, 6));
  });

  test('addPending then getPending is newest first', () async {
    await repo.addPending(
        [sms(at: DateTime(2026, 11, 1)), sms(at: DateTime(2026, 11, 4))]);
    final items = await repo.getPending();
    expect(items.map((e) => e.occurredAt),
        [DateTime(2026, 11, 4), DateTime(2026, 11, 1)]);
    expect(items.every((e) => e.id != null), isTrue);
    expect(await repo.pendingCount(), 2);
  });

  test('addPending with an empty list does not notify', () async {
    final before = database.revision.value;
    await repo.addPending([]);
    expect(database.revision.value, before);
    await repo.addPending([sms()]);
    expect(database.revision.value, before + 1);
  });

  test('approveAsTransaction inserts, removes pending and learns', () async {
    await repo.addPending([sms()]);
    final item = (await repo.getPending()).single;
    final saved = await repo.approveAsTransaction(
        item, expense(12500, DateTime(2026, 11, 1), categoryId: 2));
    expect(saved.id, isNotNull);
    expect(await repo.pendingCount(), 0);
    final rows = await database.db
        .query('transactions', where: 'id = ?', whereArgs: [saved.id]);
    expect(rows, hasLength(1));
    expect(await repo.learnedCategory('shop:SAMPLE SUPER MARKET'), 2);
  });

  test('last category choice wins', () async {
    for (final category in [2, 3]) {
      await repo.addPending([sms()]);
      final item = (await repo.getPending()).single;
      await repo.approveAsTransaction(
          item, expense(12500, DateTime(2026, 11, 1), categoryId: category));
    }
    expect(await repo.learnedCategory('shop:SAMPLE SUPER MARKET'), 3);
  });

  test('voice approval learns nothing', () async {
    await repo.addPending([voice()]);
    final item = (await repo.getPending()).single;
    await repo.approveAsTransaction(item, expense(3000, DateTime(2026, 11, 3)));
    expect(await database.db.query('learned_categories'), isEmpty);
  });

  test('approveAsDebt inserts an entry and removes pending', () async {
    final personId = await database.db.insert('debt_people',
        {'name': 'Sami', 'created_at': DateTime(2026, 11, 1).millisecondsSinceEpoch});
    await repo.addPending([voice().copyWith(kind: PendingKind.debtGave)]);
    final item = (await repo.getPending()).single;
    final saved = await repo.approveAsDebt(
        item,
        DebtEntry(
            personId: personId,
            amount: 3000,
            date: DateTime(2026, 11, 3),
            createdAt: DateTime(2026, 11, 3)));
    expect(saved.id, isNotNull);
    expect(await database.db.query('debt_entries'), hasLength(1));
    expect(await repo.pendingCount(), 0);
    expect(await database.db.query('learned_categories'), isEmpty);
  });

  test('dismiss removes and restore brings back the same id', () async {
    await repo.addPending([sms()]);
    final item = (await repo.getPending()).single;
    await repo.dismiss(item.id!);
    expect(await repo.pendingCount(), 0);
    await repo.restore(item);
    expect(await repo.getPending(), [item]);
  });

  test('update changes a pending row', () async {
    await repo.addPending([sms()]);
    final item = (await repo.getPending()).single;
    await repo.update(item.copyWith(note: 'edited'));
    expect((await repo.getPending()).single.note, 'edited');
  });

  test('archived category is not suggested', () async {
    await repo.addPending([sms()]);
    final item = (await repo.getPending()).single;
    await repo.approveAsTransaction(
        item, expense(12500, DateTime(2026, 11, 1), categoryId: 2));
    await database.db
        .update('categories', {'is_archived': 1}, where: 'id = 2');
    expect(await repo.learnedCategory('shop:SAMPLE SUPER MARKET'), isNull);
  });

  test('no table holds the SMS body after approval', () async {
    await repo.addPending([sms()]);
    final item = (await repo.getPending()).single;
    await repo.approveAsTransaction(item, expense(12500, DateTime(2026, 11, 1)));
    expect(await database.db.query('pending_items'), isEmpty);
    final tables = (await database.db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'"))
        .map((r) => r['name'])
        .toSet();
    expect(tables, {
      'pending_items', 'learned_categories', 'device_state', 'debt_people',
      'debt_entries', 'obligations', 'obligation_payments', 'categories',
      'savings_goals', 'recurring_rules', 'transactions', 'budgets',
      'savings_movements', 'quick_templates', 'budget_alerts_sent', 'settings',
    });
  });
}
