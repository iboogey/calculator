import 'package:calculator/app/core/utils/date_utils.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/transaction_form/controllers/transaction_form_controller.dart';
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

  test('keypad input plus a category makes it savable', () async {
    final c = await open();
    for (final key in ['1', '.', '5']) {
      c.pressKey(key);
    }
    expect(c.amountText.value, '1.5');
    expect(c.amount, 1500);
    expect(c.canSave, isFalse);
    c.selectCategory(foodCategoryId);
    expect(c.canSave, isTrue);
    c.backspace();
    expect(c.amountText.value, '1.');
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
    c.pressKey('5');
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
    c.pressKey('5');
    c.selectCategory(foodCategoryId);
    c.noteController.text = '   ';
    await c.save();
    expect((await repo().getAll()).single.note, isNull);
  });

  test('save refuses without a valid amount', () async {
    final c = await open();
    c.selectCategory(foodCategoryId);
    c.pressKey('0');
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
    c.backspace();
    c.pressKey('7');
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
}
