import 'package:calculator/app/core/utils/date_utils.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/obligation.dart';
import 'package:calculator/app/data/repositories/debt_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/transaction_form/controllers/transaction_form_controller.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<TransactionFormController> open({int? editId}) async {
    final controller = Get.put(TransactionFormController(
      transactions: Get.find(),
      categories: Get.find(),
      settings: Get.find(),
      debts: Get.find(),
      editId: editId,
    ));
    await controller.ready;
    return controller;
  }

  TransactionRepository repo() => Get.find<TransactionRepository>();

  test('starts as an empty expense that cannot be saved', () async {
    final c = await open();
    expect(c.kind.value, TransactionKind.expense);
    expect(c.amountText.value, '');
    expect(c.canSave, isFalse);
    expect(c.isEditing.value, isFalse);
    expect(c.visibleCategories, hasLength(8));
  });

  test('a typed amount plus a category makes it savable', () async {
    final c = await open();
    c.amountController.text = '1.5';
    expect(c.amountText.value, '1.5');
    expect(c.amount, 1500);
    expect(c.canSave, isFalse);
    c.selectCategory(foodCategoryId);
    expect(c.canSave, isTrue);
    c.amountController.text = '';
    expect(c.canSave, isFalse);
  });

  test('switching to income clears the category and shows income categories', () async {
    final c = await open();
    c.selectCategory(foodCategoryId);
    c.setKind(TransactionKind.income);
    expect(c.categoryId.value, isNull);
    expect(c.visibleCategories.map((x) => x.name), ['راتب', 'دخل آخر']);
  });

  test('save adds a dated expense with a trimmed note', () async {
    final c = await open();
    c.amountController.text = '5';
    c.selectCategory(foodCategoryId);
    c.noteController.text = '  غدا  ';
    expect(await c.save(), isTrue);
    final saved = (await repo().getAll()).single;
    expect(saved.amount, 5000);
    expect(saved.kind, TransactionKind.expense);
    expect(saved.note, 'غدا');
    expect(saved.date, DateKeys.dateOnly(DateTime.now()));
  });

  test('an empty note is stored as null', () async {
    final c = await open();
    c.amountController.text = '5';
    c.selectCategory(foodCategoryId);
    c.noteController.text = '   ';
    await c.save();
    expect((await repo().getAll()).single.note, isNull);
  });

  test('save refuses without a valid amount', () async {
    final c = await open();
    c.selectCategory(foodCategoryId);
    c.amountController.text = '0';
    expect(await c.save(), isFalse);
    expect(await repo().getAll(), isEmpty);
  });

  test('editing loads the record and saves it in place', () async {
    final existing = await repo().add(
        expense(12500, DateTime(2026, 9, 20), note: 'غدا'));
    final c = await open(editId: existing.id);
    expect(c.isEditing.value, isTrue);
    expect(c.amountText.value, '12.5');
    expect(c.categoryId.value, foodCategoryId);
    expect(c.noteController.text, 'غدا');
    expect(c.date.value, DateTime(2026, 9, 20));
    c.amountController.text = '12.7';
    expect(await c.save(), isTrue);
    final all = await repo().getAll();
    expect(all.single.id, existing.id);
    expect(all.single.amount, 12700);
    expect(all.single.createdAt, existing.createdAt);
  });

  test('delete removes the record being edited', () async {
    final existing = await repo().add(expense(5000, DateTime(2026, 9, 20)));
    final c = await open(editId: existing.id);
    await c.delete();
    expect(await repo().getAll(), isEmpty);
  });

  test('a second save while the first is still running is ignored', () async {
    final c = await open();
    c.amountController.text = '5';
    c.selectCategory(foodCategoryId);
    final results = await Future.wait([c.save(), c.save()]);
    expect(results, [true, false]);
    expect(await repo().getAll(), hasLength(1));
  });

  test('an amount more precise than a newly chosen currency can still be edited', () async {
    final existing = await repo().add(expense(1255, DateTime(2026, 9, 20)));
    final settings = Get.find<SettingsService>();
    await settings.update(settings.settings.value
        .copyWith(currencyCode: 'USD', currencyDecimals: 2));
    final c = await open(editId: existing.id);
    expect(c.amountText.value, '1.255');
    expect(c.canSave, isTrue);
    c.selectCategory(2);
    expect(await c.save(), isTrue);
    final saved = (await repo().getAll()).single;
    expect(saved.amount, 1255);
    expect(saved.categoryId, 2);
  });
  test("editing a payment's expense keeps its amount and kind but saves the new category",
      () async {
    final debts = Get.find<DebtRepository>();
    final o = await debts.addObligation(Obligation(
        title: 'قسط', amount: 50000, createdAt: DateTime(2026, 10, 1)));
    await debts.pay(
        obligationId: o.id!,
        amount: 10000,
        date: DateTime(2026, 10, 5),
        expenseCategoryId: foodCategoryId);
    final id = (await debts.linkedExpenses()).keys.single;
    final c = await open(editId: id);
    expect(c.linkedTitle.value, 'قسط');
    c.amountController.text = '99';
    c.setKind(TransactionKind.income);
    c.selectCategory(2);
    c.noteController.text = 'ملاحظة';
    expect(await c.save(), isTrue);
    final saved = (await repo().getById(id))!;
    expect(saved.amount, 10000);
    expect(saved.kind, TransactionKind.expense);
    expect(saved.categoryId, 2);
    expect(saved.note, 'ملاحظة');
    expect(await c.delete(), isFalse);
    expect(await repo().getById(id), isNotNull);
  });

  test('an unlinked record has no linked title', () async {
    final existing = await repo().add(expense(5000, DateTime(2026, 9, 20)));
    final c = await open(editId: existing.id);
    expect(c.linkedTitle.value, isNull);
  });

  test('the linked title is known before the form reports editing', () async {
    final debts = Get.find<DebtRepository>();
    final o = await debts.addObligation(Obligation(
        title: 'قسط', amount: 50000, createdAt: DateTime(2026, 10, 1)));
    await debts.pay(
        obligationId: o.id!,
        amount: 10000,
        date: DateTime(2026, 10, 5),
        expenseCategoryId: foodCategoryId);
    final id = (await debts.linkedExpenses()).keys.single;
    final c = Get.put(TransactionFormController(
      transactions: Get.find(),
      categories: Get.find(),
      settings: Get.find(),
      debts: Get.find(),
      editId: id,
    ));
    final seen = <String?>[];
    ever(c.isEditing, (editing) {
      if (editing) seen.add(c.linkedTitle.value);
    });
    await c.ready;
    expect(c.linkedTitle.value, 'قسط');
    expect(seen, ['قسط']);
  });
}
