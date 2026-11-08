import 'package:calculator/app/data/models/debt_entry.dart';
import 'package:calculator/app/data/models/obligation.dart';
import 'package:calculator/app/data/models/pending_item.dart';
import 'package:calculator/app/data/repositories/import_repository.dart';
import 'package:calculator/app/data/repositories/debt_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/debts/controllers/debts_controller.dart';
import 'package:calculator/app/modules/home/controllers/home_controller.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<HomeController> open(DateTime now) async {
    final controller = Get.put(HomeController(
      transactions: Get.find(),
      categories: Get.find(),
      savings: Get.find(),
      templates: Get.find(),
      budgets: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      debts: Get.find(),
      imports: Get.find(),
      clock: () => now,
    ));
    await controller.load();
    return controller;
  }

  TransactionRepository repo() => Get.find<TransactionRepository>();

  test('summarises the current period', () async {
    await repo().add(income(1250000, DateTime(2026, 10, 1)));
    await repo().add(expense(600000, DateTime(2026, 10, 5)));
    final c = await open(DateTime(2026, 10, 15));
    expect(c.period.value!.key, '2026-10');
    expect(c.summary.value!.remaining, 650000);
    expect(c.categoriesById[foodCategoryId]!.name, 'طعام');
  });

  test('reloads after a change anywhere in the database', () async {
    final c = await open(DateTime(2026, 10, 15));
    await repo().add(expense(5000, DateTime(2026, 10, 15)));
    await settle();
    expect(c.summary.value!.expenses, 5000);
    expect(c.recent, hasLength(1));
  });

  test('recent shows the newest five', () async {
    for (var day = 1; day <= 7; day++) {
      await repo().add(expense(1000, DateTime(2026, 10, day)));
    }
    final c = await open(DateTime(2026, 10, 15));
    expect(c.recent.map((t) => t.date.day), [7, 6, 5, 4, 3]);
  });

  test('follows the period start day from settings', () async {
    final settings = Get.find<SettingsService>();
    await settings.update(settings.settings.value.copyWith(periodStartDay: 25));
    final c = await open(DateTime(2026, 10, 10));
    expect(c.period.value!.start, DateTime(2026, 9, 25));
  });

  test('debt totals include people and unpaid obligations', () async {
    final debts = Get.find<DebtRepository>();
    final ola = await debts.addPerson('علا');
    final sami = await debts.addPerson('سامي');
    await debts.addEntry(DebtEntry(
        personId: ola.id!,
        amount: 50000,
        date: DateTime(2026, 10, 1),
        createdAt: DateTime(2026, 10, 1)));
    await debts.addEntry(DebtEntry(
        personId: sami.id!,
        amount: -20000,
        date: DateTime(2026, 10, 1),
        createdAt: DateTime(2026, 10, 1)));
    await debts.addObligation(Obligation(
        title: 'رسوم', amount: 600000, createdAt: DateTime(2026, 10, 1)));
    final c = await open(DateTime(2026, 10, 15));
    expect(c.debtTotals.value.owedToMe, 50000);
    expect(c.debtTotals.value.iOwe, 620000);
  });

  test('due banner picks the most urgent within 3 days', () async {
    final debts = Get.find<DebtRepository>();
    await debts.addObligation(Obligation(
        title: 'بعيد',
        amount: 1000,
        dueDate: DateTime(2026, 10, 30),
        createdAt: DateTime(2026, 10, 1)));
    await debts.addObligation(Obligation(
        title: 'قريب',
        amount: 2000,
        dueDate: DateTime(2026, 10, 17),
        createdAt: DateTime(2026, 10, 1)));
    final c = await open(DateTime(2026, 10, 15));
    expect(c.dueObligation.value!.status.obligation.title, 'قريب');
    expect(c.dueObligation.value!.daysLeft, 2);
  });

  test('toggleSettled flips and starts off', () async {
    final c = await open(DateTime(2026, 10, 15));
    expect(c.showSettled.value, isFalse);
    c.toggleSettled();
    expect(c.showSettled.value, isTrue);
    c.toggleSettled();
    expect(c.showSettled.value, isFalse);
    expect(DebtsTab.values, contains(DebtsTab.people));
  });

  test('pendingCount reflects pending rows and follows changes', () async {
    final imports = Get.find<ImportRepository>();
    final c = await open(DateTime(2026, 10, 15));
    expect(c.pendingCount.value, 0);
    final at = DateTime(2026, 10, 14);
    await imports.addPending([
      PendingItem(
          source: PendingSource.sms,
          kind: PendingKind.expense,
          amount: 1000,
          occurredAt: at,
          createdAt: at),
      PendingItem(
          source: PendingSource.sms,
          kind: PendingKind.income,
          amount: 2000,
          occurredAt: at,
          createdAt: at),
    ]);
    await settle();
    expect(c.pendingCount.value, 2);
    await imports.dismiss((await imports.getPending()).first.id!);
    await settle();
    expect(c.pendingCount.value, 1);
  });
}
