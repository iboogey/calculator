import 'package:calculator/app/data/models/obligation.dart';
import 'package:calculator/app/data/models/transaction_record.dart';
import 'package:calculator/app/data/repositories/debt_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  late DebtRepository repo;
  late TransactionRepository txRepo;

  setUp(() async {
    await setUpTestServices();
    repo = Get.find<DebtRepository>();
    txRepo = Get.find<TransactionRepository>();
  });

  Obligation obligation(String title, int amount, {DateTime? created}) =>
      Obligation(
        title: title,
        amount: amount,
        createdAt: created ?? DateTime(2026, 11, 1),
      );

  final day = DateTime(2026, 11, 5);

  test(
    'pay with expense creates a linked expense in the same category and date',
    () async {
      final o = await repo.addObligation(obligation('إيجار', 600000));
      final p = await repo.pay(
        obligationId: o.id!,
        amount: 400000,
        date: day,
        expenseCategoryId: foodCategoryId,
      );
      expect(p.id, isNotNull);
      expect(p.transactionId, isNotNull);
      final all = await txRepo.getAll();
      expect(all, hasLength(1));
      expect(all.single.id, p.transactionId);
      expect(all.single.amount, 400000);
      expect(all.single.categoryId, foodCategoryId);
      expect(all.single.date, day);
      expect(all.single.note, 'إيجار');
    },
  );

  test('pay without expense leaves transactions untouched', () async {
    final o = await repo.addObligation(obligation('إيجار', 600000));
    final p = await repo.pay(obligationId: o.id!, amount: 100000, date: day);
    expect(p.transactionId, isNull);
    expect(await txRepo.getAll(), isEmpty);
    expect((await repo.paidTotals())[o.id], 100000);
  });

  test('pay refuses more than remaining', () async {
    final o = await repo.addObligation(obligation('إيجار', 600000));
    await repo.pay(obligationId: o.id!, amount: 400000, date: day);
    await expectLater(
      repo.pay(obligationId: o.id!, amount: 300000, date: day),
      throwsA(
        isA<OverpaymentException>().having(
          (e) => e.remaining,
          'remaining',
          200000,
        ),
      ),
    );
    expect(await repo.getPayments(o.id!), hasLength(1));
    expect(
      () => repo.pay(obligationId: o.id!, amount: 0, date: day),
      throwsArgumentError,
    );
  });

  test('pay that fails half-way saves nothing', () async {
    final o = await repo.addObligation(obligation('إيجار', 600000));
    await expectLater(
      repo.pay(
        obligationId: o.id!,
        amount: 100000,
        date: day,
        expenseCategoryId: 99999,
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect(await repo.getPayments(o.id!), isEmpty);
    expect(await txRepo.getAll(), isEmpty);
  });

  test('deletePayment removes its expense even after it was edited', () async {
    final o = await repo.addObligation(obligation('إيجار', 600000));
    final p = await repo.pay(
      obligationId: o.id!,
      amount: 100000,
      date: day,
      expenseCategoryId: foodCategoryId,
    );
    final tx = (await txRepo.getAll()).single;
    await txRepo.update(
      TransactionRecord(
        id: tx.id,
        kind: tx.kind,
        amount: tx.amount,
        categoryId: 2,
        date: DateTime(2026, 11, 7),
        note: tx.note,
        createdAt: tx.createdAt,
      ),
    );
    await repo.deletePayment(p);
    expect(await txRepo.getAll(), isEmpty);
    expect(await repo.getPayments(o.id!), isEmpty);
  });

  test('updateObligation below paid is refused', () async {
    final o = await repo.addObligation(obligation('إيجار', 600000));
    await repo.pay(obligationId: o.id!, amount: 400000, date: day);
    await expectLater(
      repo.updateObligation(o.copyWith(amount: 300000)),
      throwsA(
        isA<AmountBelowPaidException>().having((e) => e.paid, 'paid', 400000),
      ),
    );
    expect((await repo.getObligation(o.id!))!.amount, 600000);
    await repo.updateObligation(o.copyWith(title: ' جديد ', amount: 400000));
    expect((await repo.getObligation(o.id!))!.title, 'جديد');
    expect(
      () => repo.updateObligation(o.copyWith(title: ' ')),
      throwsArgumentError,
    );
  });

  test('deleteObligation keeps the expenses its payments created', () async {
    final o = await repo.addObligation(obligation('إيجار', 600000));
    await repo.pay(
      obligationId: o.id!,
      amount: 100000,
      date: day,
      expenseCategoryId: foodCategoryId,
    );
    await repo.deleteObligation(o.id!);
    expect(await repo.getObligations(), isEmpty);
    expect(await repo.getPayments(o.id!), isEmpty);
    expect(await txRepo.getAll(), hasLength(1));
  });

  test('recentTitles is distinct and newest first', () async {
    await repo.addObligation(
      obligation('أ', 1000, created: DateTime(2026, 11, 1)),
    );
    await repo.addObligation(
      obligation('ب', 1000, created: DateTime(2026, 11, 2)),
    );
    await repo.addObligation(
      obligation('أ', 1000, created: DateTime(2026, 11, 3)),
    );
    expect(await repo.recentTitles(), ['أ', 'ب']);
    expect(await repo.recentTitles(limit: 1), ['أ']);
  });

  test('linkedExpenses maps transaction ids to titles', () async {
    final o = await repo.addObligation(obligation('إيجار', 600000));
    final p = await repo.pay(
      obligationId: o.id!,
      amount: 100000,
      date: day,
      expenseCategoryId: foodCategoryId,
    );
    await repo.pay(obligationId: o.id!, amount: 100000, date: day);
    expect(await repo.linkedExpenses(), {p.transactionId!: 'إيجار'});
  });

  test('a failing payment insert rolls back the linked expense', () async {
    final o = await repo.addObligation(obligation('إيجار', 600000));
    await Get.find<DatabaseService>().db.execute(
        "CREATE TRIGGER fail_pay BEFORE INSERT ON obligation_payments "
        "BEGIN SELECT RAISE(ABORT, 'boom'); END");
    await expectLater(
      repo.pay(
          obligationId: o.id!,
          amount: 400000,
          date: day,
          expenseCategoryId: foodCategoryId),
      throwsA(isA<DatabaseException>()),
    );
    expect(await txRepo.getAll(), isEmpty);
    final rows = await Get.find<DatabaseService>()
        .db
        .query('obligation_payments');
    expect(rows, isEmpty);
  });
}
