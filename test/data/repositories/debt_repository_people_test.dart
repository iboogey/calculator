import 'package:calculator/app/data/models/debt_entry.dart';
import 'package:calculator/app/data/repositories/debt_repository.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/test_services.dart';

void main() {
  late DebtRepository repo;

  setUp(() async {
    await setUpTestServices();
    repo = Get.find<DebtRepository>();
  });

  DebtEntry entry(int personId, int amount, DateTime date) => DebtEntry(
      personId: personId,
      amount: amount,
      date: date,
      createdAt: DateTime(2026, 11, 1));

  test('addPerson trims and refuses duplicates', () async {
    final ola = await repo.addPerson('علا ');
    expect(ola.name, 'علا');
    expect(ola.id, isNotNull);
    expect(() => repo.addPerson('علا'),
        throwsA(isA<DuplicateNameException>()));
    expect(() => repo.addPerson('  '), throwsArgumentError);
    expect(() => repo.addPerson(''), throwsArgumentError);
  });

  test('renamePerson to its own name is allowed, to another\'s is refused',
      () async {
    final a = await repo.addPerson('علا');
    final b = await repo.addPerson('سامر');
    await repo.renamePerson(a.id!, ' علا ');
    expect(() => repo.renamePerson(a.id!, 'سامر'),
        throwsA(isA<DuplicateNameException>()));
    expect(() => repo.renamePerson(a.id!, ' '), throwsArgumentError);
    await repo.renamePerson(b.id!, 'خالد');
    expect((await repo.getPerson(b.id!))!.name, 'خالد');
    expect((await repo.getPeople()).map((p) => p.name), ['خالد', 'علا']);
  });

  test('balances sum signed entries per person', () async {
    final a = await repo.addPerson('علا');
    final b = await repo.addPerson('سامر');
    await repo.addEntry(entry(a.id!, 5000, DateTime(2026, 11, 1)));
    await repo.addEntry(entry(a.id!, -2000, DateTime(2026, 11, 2)));
    await repo.addEntry(entry(b.id!, -7000, DateTime(2026, 11, 2)));
    expect(await repo.personBalances(), {a.id!: 3000, b.id!: -7000});
  });

  test('entries come newest first', () async {
    final a = await repo.addPerson('علا');
    final e1 = await repo.addEntry(entry(a.id!, 1000, DateTime(2026, 11, 1)));
    final e2 = await repo.addEntry(entry(a.id!, 2000, DateTime(2026, 11, 3)));
    final e3 = await repo.addEntry(entry(a.id!, 3000, DateTime(2026, 11, 3)));
    final ids = (await repo.getEntries(a.id!)).map((e) => e.id);
    expect(ids, [e3.id, e2.id, e1.id]);
  });

  test('updateEntry and deleteEntry change the ledger', () async {
    final a = await repo.addPerson('علا');
    final e = await repo.addEntry(entry(a.id!, 1000, DateTime(2026, 11, 1)));
    await repo.updateEntry(e.copyWith(amount: 4000));
    expect((await repo.getEntries(a.id!)).single.amount, 4000);
    await repo.deleteEntry(e.id!);
    expect(await repo.getEntries(a.id!), isEmpty);
  });

  test('deletePerson removes their entries', () async {
    final a = await repo.addPerson('علا');
    await repo.addEntry(entry(a.id!, 1000, DateTime(2026, 11, 1)));
    await repo.deletePerson(a.id!);
    expect(await repo.getPerson(a.id!), isNull);
    expect(await repo.getEntries(a.id!), isEmpty);
    expect(await repo.personBalances(), isEmpty);
  });

  test('restoreEntry brings back the same id', () async {
    final a = await repo.addPerson('علا');
    final e = await repo.addEntry(entry(a.id!, 1000, DateTime(2026, 11, 1)));
    await repo.deleteEntry(e.id!);
    await repo.restoreEntry(e);
    final back = (await repo.getEntries(a.id!)).single;
    expect(back.id, e.id);
    expect(back.amount, 1000);
  });

  test('every write bumps database.revision', () async {
    final db = Get.find<DatabaseService>();
    var last = db.revision.value;
    void expectBumped() {
      expect(db.revision.value, greaterThan(last));
      last = db.revision.value;
    }

    final a = await repo.addPerson('علا');
    expectBumped();
    await repo.renamePerson(a.id!, 'سامر');
    expectBumped();
    final e = await repo.addEntry(entry(a.id!, 1000, DateTime(2026, 11, 1)));
    expectBumped();
    await repo.updateEntry(e.copyWith(amount: 2000));
    expectBumped();
    await repo.deleteEntry(e.id!);
    expectBumped();
    await repo.restoreEntry(e);
    expectBumped();
    await repo.deletePerson(a.id!);
    expectBumped();
  });
}
