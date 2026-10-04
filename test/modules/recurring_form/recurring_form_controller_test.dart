import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/repositories/recurring_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/recurring_form/controllers/recurring_form_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  final today = DateTime(2026, 10, 4);

  Future<RecurringFormController> open({int? editId}) async {
    final c = Get.put(RecurringFormController(
      recurring: Get.find(),
      categories: Get.find(),
      settings: Get.find(),
      editId: editId,
      clock: () => today,
    ));
    await c.ready;
    return c;
  }

  test('defaults to an expense due on today\'s day of the month', () async {
    final c = await open();
    expect(c.kind.value, TransactionKind.expense);
    expect(c.dayOfMonth.value, 4);
    expect(c.canSave, isFalse);
  });

  test('saving a rule due today creates today\'s entry right away', () async {
    final c = await open();
    c.labelController.text = 'نت';
    c.amountController.text = '25';
    c.amountText.value = '25';
    c.selectCategory(3);
    expect(await c.save(), isTrue);
    final rule = (await Get.find<RecurringRepository>().getAll()).single;
    expect(rule.label, 'نت');
    expect(rule.amount, 25000);
    expect(rule.dayOfMonth, 4);
    expect(rule.startDate, today);
    final created = await Get.find<TransactionRepository>().getAll();
    expect(created.single.date, today);
    expect(created.single.isAuto, isTrue);
  });

  test('an empty name falls back to the category name', () async {
    final c = await open();
    c.amountText.value = '350';
    c.selectCategory(4);
    c.setDay(1);
    await c.save();
    expect((await Get.find<RecurringRepository>().getAll()).single.label, 'سكن');
  });

  test('editing keeps the start date and does not duplicate entries', () async {
    final c = await open();
    c.amountText.value = '25';
    c.selectCategory(3);
    await c.save();
    final id = (await Get.find<RecurringRepository>().getAll()).single.id;
    Get.delete<RecurringFormController>();

    final edit = await open(editId: id);
    expect(edit.isEditing.value, isTrue);
    expect(edit.amountText.value, '25');
    edit.amountText.value = '30';
    await edit.save();
    final rules = await Get.find<RecurringRepository>().getAll();
    expect(rules.single.amount, 30000);
    expect(rules.single.lastGeneratedDate, today);
    expect(await Get.find<TransactionRepository>().getAll(), hasLength(1));
  });

  test('switching to income clears the category', () async {
    final c = await open();
    c.selectCategory(3);
    c.setKind(TransactionKind.income);
    expect(c.categoryId.value, isNull);
    expect(c.visibleCategories.map((x) => x.name), ['راتب', 'دخل آخر']);
  });
}
