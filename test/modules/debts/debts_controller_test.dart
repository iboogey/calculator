import 'package:calculator/app/data/models/debt_entry.dart';
import 'package:calculator/app/data/repositories/debt_repository.dart';
import 'package:calculator/app/modules/debts/controllers/debts_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/test_services.dart';

DebtsController build({DebtsTab tab = DebtsTab.people}) =>
    Get.put(DebtsController(
      debts: Get.find(),
      categories: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      initialTab: tab,
      clock: () => DateTime(2026, 11, 8),
    ));

void main() {
  setUp(setUpTestServices);

  test('loads people ordered with totals', () async {
    final repo = Get.find<DebtRepository>();
    final a = await repo.addPerson('أحمد');
    final b = await repo.addPerson('بشير');
    await repo.addPerson('جميل');
    await repo.addEntry(DebtEntry(
        personId: a.id!, amount: 5000, date: DateTime(2026, 11, 1), createdAt: DateTime(2026, 11, 1)));
    await repo.addEntry(DebtEntry(
        personId: b.id!, amount: -8000, date: DateTime(2026, 11, 1), createdAt: DateTime(2026, 11, 1)));

    final c = build();
    await c.load();
    expect(c.people.map((p) => p.person.name), ['بشير', 'أحمد', 'جميل']);
    expect(c.totals.value.owedToMe, 5000);
    expect(c.totals.value.iOwe, 8000);
  });

  test('addPerson returns the duplicate message and saves nothing', () async {
    final repo = Get.find<DebtRepository>();
    await repo.addPerson('أحمد');
    final c = build();
    await c.load();
    expect(await c.addPerson(' أحمد '), 'هذا الاسم موجود مسبقًا');
    expect(await c.addPerson('  '), 'اكتب الاسم');
    expect(await repo.getPeople(), hasLength(1));
    expect(await c.addPerson('سالم'), isNull);
    expect(await repo.getPeople(), hasLength(2));
  });

  test('opens on the tab passed in', () async {
    final c = build(tab: DebtsTab.obligations);
    expect(c.tab.value, DebtsTab.obligations);
  });

  test('opens on the people tab by default', () async {
    expect(build().tab.value, DebtsTab.people);
  });

  test('reloads after a repository write', () async {
    final c = build();
    await c.load();
    expect(c.people, isEmpty);
    await Get.find<DebtRepository>().addPerson('أحمد');
    await settle();
    expect(c.people.map((p) => p.person.name), ['أحمد']);
  });
}
