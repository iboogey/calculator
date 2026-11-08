import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/obligation.dart';
import 'package:calculator/app/data/repositories/category_repository.dart';
import 'package:calculator/app/data/repositories/debt_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/debts/controllers/debts_controller.dart';
import 'package:calculator/app/modules/debts/widgets/obligations_tab.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:calculator/app/services/message_service.dart';
import 'package:calculator/app/widgets/money_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/test_services.dart';

final _today = DateTime(2026, 11, 8);

DebtsController build() => Get.put(DebtsController(
      debts: Get.find(),
      categories: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      initialTab: DebtsTab.obligations,
      clock: () => _today,
    ));

Future<Obligation> addObligation(
  String title,
  int amount, {
  DateTime? due,
  int minute = 0,
}) =>
    Get.find<DebtRepository>().addObligation(Obligation(
      title: title,
      amount: amount,
      dueDate: due,
      createdAt: DateTime(2026, 11, 1, 0, minute),
    ));

void main() {
  setUp(setUpTestServices);

  test('splits unpaid and paid in order', () async {
    final repo = Get.find<DebtRepository>();
    await addObligation('بلا موعد', 10000, minute: 1);
    await addObligation('لاحق', 20000, due: DateTime(2026, 11, 20), minute: 2);
    await addObligation('قريب', 30000, due: DateTime(2026, 11, 10), minute: 3);
    final done = await addObligation('مسدد', 5000, minute: 4);
    await repo.pay(obligationId: done.id!, amount: 5000, date: _today);

    final c = build();
    await c.load();
    expect(c.unpaid.map((s) => s.obligation.title), ['قريب', 'لاحق', 'بلا موعد']);
    expect(c.paid.map((s) => s.obligation.title), ['مسدد']);
    expect(c.dueOf(c.unpaid.first)!.daysLeft, 2);
    expect(c.dueOf(c.unpaid.last), isNull);
  });

  test('pay with the default category records a bills expense', () async {
    final o = await addObligation('الإيجار', 10000);
    final c = build();
    await c.load();
    final bills = c.expenseCategories
        .firstWhere((x) => x.id == c.defaultExpenseCategoryId);
    expect(bills.iconKey, 'bills');

    final ok = await c.pay(
      c.unpaid.single,
      PayDraft(
          amount: 4000,
          date: _today,
          expenseCategoryId: c.defaultExpenseCategoryId),
    );
    expect(ok, isTrue);
    final payments = await Get.find<DebtRepository>().getPayments(o.id!);
    expect(payments.single.amount, 4000);
    final expense = (await Get.find<TransactionRepository>().getAll()).single;
    expect(expense.kind, TransactionKind.expense);
    expect(expense.amount, 4000);
    expect(expense.categoryId, bills.id);
    expect(expense.note, 'الإيجار');
    expect(payments.single.transactionId, expense.id);
    expect(c.lastNotice.value, isNull);
  });

  test('a second pay while saving is ignored', () async {
    final o = await addObligation('الإيجار', 10000);
    final c = build();
    await c.load();
    final s = c.unpaid.single;
    final first = c.pay(s, PayDraft(amount: 1000, date: _today));
    final second = await c.pay(s, PayDraft(amount: 1000, date: _today));
    expect(second, isFalse);
    expect(await first, isTrue);
    expect(await Get.find<DebtRepository>().getPayments(o.id!), hasLength(1));
    expect(c.isSaving.value, isFalse);
  });

  test('paying the rest sets the paid notice', () async {
    final o = await addObligation('الإيجار', 10000);
    await Get.find<DebtRepository>()
        .pay(obligationId: o.id!, amount: 4000, date: _today);
    final c = build();
    await c.load();
    expect(await c.pay(c.unpaid.single, PayDraft(amount: 6000, date: _today)),
        isTrue);
    expect(c.lastNotice.value, 'تم سداد الإيجار');
    await settle();
    expect(c.unpaid, isEmpty);
    expect(c.paid.single.obligation.title, 'الإيجار');
  });

  test('overpay shows the remaining in the message', () async {
    final o = await addObligation('الإيجار', 10000);
    final c = build();
    await c.load();
    final stale = c.unpaid.single;
    await Get.find<DebtRepository>()
        .pay(obligationId: o.id!, amount: 4000, date: _today);
    expect(await c.pay(stale, PayDraft(amount: 8000, date: _today)), isFalse);
    expect(Get.find<MessageService>().lastMessage.value,
        'المبلغ أكبر من المتبقي (${MoneyText.label(6000, c.currency)})');
    expect(c.lastNotice.value, isNull);
    expect(await Get.find<DebtRepository>().getPayments(o.id!), hasLength(1));
  });

  test('default category falls back when bills is archived', () async {
    await Get.find<DatabaseService>().db.update(
        'categories', {'is_archived': 1},
        where: 'icon_key = ?', whereArgs: ['bills']);
    final c = build();
    await c.load();
    final active = await Get.find<CategoryRepository>()
        .getAll(kind: TransactionKind.expense);
    expect(c.expenseCategories.map((x) => x.id), active.map((x) => x.id));
    expect(c.expenseCategories.any((x) => x.iconKey == 'bills'), isFalse);
    expect(c.defaultExpenseCategoryId, active.first.id);
  });

  testWidgets('the tab shows due lines, progress and the paid section',
      (tester) async {
    await tester.runAsync(() async {
      final repo = Get.find<DebtRepository>();
      final rent =
          await addObligation('الإيجار', 10000, due: DateTime(2026, 11, 10));
      await repo.pay(obligationId: rent.id!, amount: 4000, date: _today);
      await addObligation('بلا موعد', 2000, minute: 1);
      final done = await addObligation('مسدد', 5000, minute: 2);
      await repo.pay(obligationId: done.id!, amount: 5000, date: _today);
    });
    final c = build();
    await tester.runAsync(c.load);
    await tester.pumpWidget(const MaterialApp(
      home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: ObligationsTab())),
    ));

    expect(find.text('المبلغ المستحق عليّ'), findsOneWidget);
    expect(find.text('التزامان · أقربها خلال يومين'), findsOneWidget);
    expect(find.text('يستحق في 10 تشرين الثاني · خلال يومين'), findsOneWidget);
    expect(find.text('بلا موعد محدد'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('تم سدادها (1)'), findsOneWidget);
    expect(find.text('مسدد'), findsNothing);
    await tester.tap(find.text('تم سدادها (1)'));
    await tester.pump();
    expect(find.text('مسدد'), findsOneWidget);
  });
}
