import 'package:calculator/app/data/repositories/debt_repository.dart';
import 'package:calculator/app/modules/debt_person/controllers/debt_person_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/test_services.dart';

final _day = DateTime(2026, 11, 8);

void main() {
  late DebtRepository repo;
  late int id;

  Future<DebtPersonController> build() async {
    repo = Get.find<DebtRepository>();
    id = (await repo.addPerson('علا')).id!;
    final c = Get.put(DebtPersonController(
      debts: repo,
      settings: Get.find(),
      database: Get.find(),
      personId: id,
      clock: () => _day,
    ));
    await c.load();
    return c;
  }

  setUp(setUpTestServices);

  test('a gave entry adds a positive amount and raises the balance', () async {
    final c = await build();
    expect(await c.addEntry(EntryDraft(amount: 5000, date: _day, note: 'x')), isTrue);
    await settle();
    expect(c.balance.value, 5000);
    expect(c.entries.single.amount, 5000);
    expect(c.entries.single.note, 'x');
  });

  test('a took entry adds a negative amount', () async {
    final c = await build();
    await c.addEntry(EntryDraft(amount: -2500, date: _day));
    await settle();
    expect(c.balance.value, -2500);
  });

  test('editing can flip the direction and clear the note', () async {
    final c = await build();
    await c.addEntry(EntryDraft(amount: 5000, date: _day, note: 'x'));
    await settle();
    final old = c.entries.single;
    expect(await c.updateEntry(old, EntryDraft(amount: -3000, date: _day)), isTrue);
    await settle();
    expect(c.balance.value, -3000);
    expect(c.entries.single.note, isNull);
    expect(c.entries.single.createdAt, old.createdAt);
  });

  test('delete then undo restores the entry', () async {
    final c = await build();
    await c.addEntry(EntryDraft(amount: 5000, date: _day));
    await settle();
    final e = (await c.deleteEntry(c.entries.single))!;
    await settle();
    expect(c.entries, isEmpty);
    await c.undoDelete(e);
    await settle();
    expect(c.entries.single, e);
    expect(c.balance.value, 5000);
  });

  test('rename to an existing name returns the message', () async {
    final c = await build();
    await repo.addPerson('سالم');
    expect(await c.rename('سالم'), 'هذا الاسم موجود مسبقًا');
    expect(await c.rename('  '), 'اكتب الاسم');
    expect(await c.rename('منى'), isNull);
    await settle();
    expect(c.person.value!.name, 'منى');
  });

  test('deletePerson removes everything', () async {
    final c = await build();
    await c.addEntry(EntryDraft(amount: 5000, date: _day));
    expect(await c.deletePerson(), isTrue);
    expect(await repo.getPerson(id), isNull);
    expect(await repo.getEntries(id), isEmpty);
  });
}
