import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/pending_item.dart';
import 'package:calculator/app/data/models/recurring_rule.dart';
import 'package:calculator/app/data/repositories/debt_repository.dart';
import 'package:calculator/app/data/repositories/import_repository.dart';
import 'package:calculator/app/data/repositories/recurring_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/core/logic/bank_sms_parser.dart';
import 'package:calculator/app/modules/import_review/controllers/import_review_controller.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:calculator/app/services/message_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

PendingItem _item({
  required int amount,
  required DateTime at,
  PendingKind kind = PendingKind.expense,
  int? category = foodCategoryId,
  String? name = 'SAMPLE SUPER MARKET',
  String? note,
}) =>
    PendingItem(
      source: PendingSource.sms,
      kind: kind,
      amount: amount,
      occurredAt: at,
      smsType: BankSmsType.cardPurchase,
      name: name,
      suggestedCategoryId: category,
      note: note,
      createdAt: at,
    );

PendingItem _voiceDebt({
  required PendingKind kind,
  required int amount,
  int? personId,
  String? personName,
  String? note,
}) =>
    PendingItem(
      source: PendingSource.voice,
      kind: kind,
      amount: amount,
      occurredAt: DateTime(2026, 11, 4, 12),
      personId: personId,
      personName: personName,
      note: note,
      createdAt: DateTime(2026, 11, 4, 12),
    );

void main() {
  setUp(setUpTestServices);

  ImportRepository imports() => Get.find<ImportRepository>();

  Future<ImportReviewController> open() async {
    final c = Get.put(ImportReviewController(
      imports: Get.find(),
      categories: Get.find(),
      recurring: Get.find(),
      transactions: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      debts: Get.find(),
    ));
    await c.load();
    return c;
  }

  test('load lists items newest first', () async {
    await imports().addPending([
      _item(amount: 1000, at: DateTime(2026, 11, 1, 9)),
      _item(amount: 2000, at: DateTime(2026, 11, 3, 9)),
      _item(amount: 3000, at: DateTime(2026, 11, 2, 9)),
    ]);
    final c = await open();
    expect(c.items.map((i) => i.amount), [2000, 3000, 1000]);
  });

  test('approve writes one transaction and the item leaves the list', () async {
    await imports().addPending(
        [_item(amount: 3500, at: DateTime(2026, 11, 3, 14, 30), note: 'غداء')]);
    final c = await open();
    expect(await c.approve(c.items.single), isTrue);
    final saved = await Get.find<TransactionRepository>().getAll();
    expect(saved, hasLength(1));
    expect(saved.single.amount, 3500);
    expect(saved.single.kind, TransactionKind.expense);
    expect(saved.single.categoryId, foodCategoryId);
    expect(saved.single.date, DateTime(2026, 11, 3));
    expect(saved.single.note, 'غداء');
    await settle();
    expect(c.items, isEmpty);
  });

  test('approve without a category returns false and writes nothing', () async {
    await imports().addPending(
        [_item(amount: 3500, at: DateTime(2026, 11, 3), category: null)]);
    final c = await open();
    expect(c.canApproveDirectly(c.items.single), isFalse);
    expect(await c.approve(c.items.single), isFalse);
    expect(await Get.find<TransactionRepository>().getAll(), isEmpty);
    expect(c.items, hasLength(1));
  });

  test('canApproveDirectly follows kind, category and person', () async {
    final c = await open();
    final at = DateTime(2026, 11, 3);
    expect(c.canApproveDirectly(_item(amount: 1, at: at)), isTrue);
    expect(
        c.canApproveDirectly(
            _item(amount: 1, at: at, kind: PendingKind.income, category: null)),
        isFalse);
    expect(
        c.canApproveDirectly(
            _item(amount: 1, at: at, kind: PendingKind.debtGave, category: null)),
        isFalse);
    expect(
        c.canApproveDirectly(_item(amount: 1, at: at, kind: PendingKind.debtGave)
            .copyWith(personName: 'علا')),
        isTrue);
  });

  test('approveEdited writes the edited values and learns the category',
      () async {
    await imports().addPending(
        [_item(amount: 3500, at: DateTime(2026, 11, 3), category: null)]);
    final c = await open();
    final item = c.items.single;
    final ok = await c.approveEdited(
      item,
      kind: PendingKind.income,
      amount: 4000,
      date: DateTime(2026, 11, 5, 18),
      categoryId: salaryCategoryId,
      note: 'تعديل',
    );
    expect(ok, isTrue);
    final saved = (await Get.find<TransactionRepository>().getAll()).single;
    expect(saved.kind, TransactionKind.income);
    expect(saved.amount, 4000);
    expect(saved.date, DateTime(2026, 11, 5));
    expect(saved.categoryId, salaryCategoryId);
    expect(saved.note, 'تعديل');
    expect(await imports().learnedCategory(item.learnKey!), salaryCategoryId);
    expect(await imports().getPending(), isEmpty);
  });

  test('dismiss removes the item and undoDismiss brings it back', () async {
    await imports().addPending([_item(amount: 1000, at: DateTime(2026, 11, 3))]);
    final c = await open();
    final removed = await c.dismiss(c.items.single);
    expect(removed, isNotNull);
    await settle();
    expect(c.items, isEmpty);
    await c.undoDismiss(removed!);
    await settle();
    expect(c.items.single.amount, 1000);
    expect(c.items.single.id, removed.id);
  });

  test('flags an item matching a recurring rule due 2 days away', () async {
    final rule = await Get.find<RecurringRepository>().add(RecurringRule(
      label: 'قسط السيارة',
      kind: RecurringKind.expense,
      amount: 150000,
      categoryId: foodCategoryId,
      dayOfMonth: 5,
      startDate: DateTime(2026, 1, 1),
    ));
    await imports().addPending([
      _item(amount: 150000, at: DateTime(2026, 11, 3, 10)),
      _item(amount: 99000, at: DateTime(2026, 11, 3, 11)),
    ]);
    final c = await open();
    final matching = c.items.firstWhere((i) => i.amount == 150000);
    final other = c.items.firstWhere((i) => i.amount == 99000);
    expect(c.duplicateLabels[matching.id], rule.label);
    expect(c.duplicateLabels.containsKey(other.id), isFalse);
  });

  test('flags an item matching an existing transaction the day before',
      () async {
    await Get.find<TransactionRepository>()
        .add(expense(7000, DateTime(2026, 11, 2), note: 'بقالة'));
    await imports().addPending([_item(amount: 7000, at: DateTime(2026, 11, 3))]);
    final c = await open();
    expect(c.duplicateLabels[c.items.single.id], 'بقالة');
  });

  test('a database failure during approve shows a message', () async {
    await imports().addPending([_item(amount: 3500, at: DateTime(2026, 11, 3))]);
    final c = await open();
    await Get.find<DatabaseService>().db.close();
    expect(await c.approve(c.items.single), isFalse);
    expect(Get.find<MessageService>().lastMessage.value,
        'تعذّر حفظ العملية، حاول مرة أخرى');
    expect(c.isSaving.value, isFalse);
  });

  group('voice debts', () {
    DebtRepository debts() => Get.find<DebtRepository>();

    test('approve with an existing person writes a positive entry for them',
        () async {
      final sami = await debts().addPerson('سامي');
      await imports().addPending([
        _voiceDebt(
            kind: PendingKind.debtGave,
            amount: 20000,
            personId: sami.id,
            personName: 'سامي',
            note: 'سلفة'),
      ]);
      final c = await open();
      expect(c.canApproveDirectly(c.items.single), isTrue);
      expect(await c.approve(c.items.single), isTrue);
      final entry = (await debts().getEntries(sami.id!)).single;
      expect(entry.amount, 20000);
      expect(entry.date, DateTime(2026, 11, 4));
      expect(entry.note, 'سلفة');
      expect(await debts().getPeople(), hasLength(1));
      expect(await imports().getPending(), isEmpty);
      expect(await Get.find<TransactionRepository>().getAll(), isEmpty);
    });

    test('approve with an unknown person creates them and a negative entry',
        () async {
      await imports().addPending([
        _voiceDebt(kind: PendingKind.debtTook, amount: 10000, personName: 'رنا'),
      ]);
      final c = await open();
      expect(await c.approve(c.items.single), isTrue);
      final rana = (await debts().getPeople()).single;
      expect(rana.name, 'رنا');
      expect((await debts().getEntries(rana.id!)).single.amount, -10000);
      expect(await imports().getPending(), isEmpty);
    });

    test('a name that already exists reuses that person', () async {
      final sami = await debts().addPerson('Sami');
      await imports().addPending([
        _voiceDebt(kind: PendingKind.debtGave, amount: 5000, personName: ' sami'),
      ]);
      final c = await open();
      expect(await c.approve(c.items.single), isTrue);
      expect(await debts().getPeople(), hasLength(1));
      expect((await debts().getEntries(sami.id!)).single.amount, 5000);
    });

    test('a person deleted while pending falls back to the spoken name',
        () async {
      final sami = await debts().addPerson('سامي');
      await imports().addPending([
        _voiceDebt(
            kind: PendingKind.debtGave,
            amount: 5000,
            personId: sami.id,
            personName: 'سامي'),
      ]);
      await debts().deletePerson(sami.id!);
      final c = await open();
      expect(await c.approve(c.items.single), isTrue);
      final again = (await debts().getPeople()).single;
      expect(again.id, isNot(sami.id));
      expect((await debts().getEntries(again.id!)).single.amount, 5000);
    });

    test('a debt without a person cannot be approved directly', () async {
      await imports().addPending(
          [_voiceDebt(kind: PendingKind.debtGave, amount: 5000)]);
      final c = await open();
      expect(c.canApproveDirectly(c.items.single), isFalse);
      expect(await c.approve(c.items.single), isFalse);
      expect(await imports().getPending(), hasLength(1));
    });

    test('approveEdited saves the chosen person, direction and values',
        () async {
      final sami = await debts().addPerson('سامي');
      await imports().addPending([
        _voiceDebt(kind: PendingKind.debtGave, amount: 5000),
      ]);
      final c = await open();
      expect(
          await c.approveEdited(c.items.single,
              kind: PendingKind.debtTook,
              amount: 7000,
              date: DateTime(2026, 11, 6, 9),
              personId: sami.id,
              note: 'مطعم'),
          isTrue);
      final entry = (await debts().getEntries(sami.id!)).single;
      expect(entry.amount, -7000);
      expect(entry.date, DateTime(2026, 11, 6));
      expect(entry.note, 'مطعم');
    });

    test('approveEdited with a new name creates the person', () async {
      await imports().addPending([
        _voiceDebt(kind: PendingKind.debtGave, amount: 5000),
      ]);
      final c = await open();
      expect(
          await c.approveEdited(c.items.single,
              kind: PendingKind.debtGave,
              amount: 5000,
              date: DateTime(2026, 11, 4),
              personName: 'هدى'),
          isTrue);
      final huda = (await debts().getPeople()).single;
      expect(huda.name, 'هدى');
      expect((await debts().getEntries(huda.id!)).single.amount, 5000);
    });

    test('an SMS item can never become a debt', () async {
      final sami = await debts().addPerson('سامي');
      await imports().addPending([_item(amount: 3500, at: DateTime(2026, 11, 3))]);
      final c = await open();
      expect(
          await c.approveEdited(c.items.single,
              kind: PendingKind.debtGave,
              amount: 3500,
              date: DateTime(2026, 11, 3),
              personId: sami.id),
          isFalse);
      expect(await debts().getEntries(sami.id!), isEmpty);
      expect(await imports().getPending(), hasLength(1));
    });

    test('kindsFor offers debts only for voice items', () async {
      final c = await open();
      final sms = _item(amount: 1, at: DateTime(2026, 11, 3));
      final voice = _voiceDebt(kind: PendingKind.expense, amount: 1);
      expect(c.kindsFor(sms), [PendingKind.expense, PendingKind.income]);
      expect(c.kindsFor(voice), containsAll([
        PendingKind.expense,
        PendingKind.income,
        PendingKind.debtGave,
        PendingKind.debtTook,
      ]));
    });

    test('load lists the debt people and labels a voice debt', () async {
      final sami = await debts().addPerson('سامي');
      await imports().addPending([
        _voiceDebt(kind: PendingKind.debtGave, amount: 1, personId: sami.id),
        _voiceDebt(kind: PendingKind.debtTook, amount: 2, personName: 'رنا'),
      ]);
      final c = await open();
      expect(c.people.map((p) => p.name), ['سامي']);
      final byAmount = {for (final i in c.items) i.amount: i};
      expect(c.personLabel(byAmount[1]!), 'سامي');
      expect(c.personLabel(byAmount[2]!), 'رنا');
    });
  });
}
