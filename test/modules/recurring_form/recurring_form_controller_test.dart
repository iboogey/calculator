import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/repositories/recurring_repository.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/recurring_form/controllers/recurring_form_controller.dart';
import 'package:calculator/app/services/database_service.dart';
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
      savings: Get.find(),
      settings: Get.find(),
      editId: editId,
      clock: () => today,
    ));
    await c.ready;
    return c;
  }

  test('defaults to an expense due on today\'s day of the month', () async {
    final c = await open();
    expect(c.kind.value, RecurringKind.expense);
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
    c.setKind(RecurringKind.income);
    expect(c.categoryId.value, isNull);
    expect(c.visibleCategories.map((x) => x.name), ['راتب', 'دخل آخر']);
  });

  test('moving the day later after it ran does not charge this month twice', () async {
    final c = await open();
    c.amountText.value = '25';
    c.selectCategory(3);
    await c.save();
    final id = (await Get.find<RecurringRepository>().getAll()).single.id;
    Get.delete<RecurringFormController>();

    final edit = Get.put(RecurringFormController(
      recurring: Get.find(),
      categories: Get.find(),
      savings: Get.find(),
      settings: Get.find(),
      editId: id,
      clock: () => DateTime(2026, 10, 25),
    ));
    await edit.ready;
    edit.setDay(20);
    await edit.save();
    final october = (await Get.find<TransactionRepository>().getAll())
        .where((t) => t.date.month == 10);
    expect(october, hasLength(1));
  });

  test('a rule is saved once even when the catch-up afterwards fails', () async {
    final failing = _ClosesBeforeCatchUp(Get.find<DatabaseService>());
    final c = Get.put(RecurringFormController(
      recurring: failing,
      categories: Get.find(),
      savings: Get.find(),
      settings: Get.find(),
      clock: () => today,
    ));
    await c.ready;
    c.amountText.value = '25';
    c.selectCategory(3);
    expect(await c.save(), isTrue);
    expect(failing.rulesBeforeCatchUp, 1);
  });

  test('a monthly saving goes to the chosen goal as a recurring movement', () async {
    final c = await open();
    c.setKind(RecurringKind.saving);
    expect(c.visibleCategories, isEmpty);
    expect(c.goals.first.name, 'ادخار عام');
    c.amountText.value = '50';
    expect(c.canSave, isFalse);
    c.selectGoal(1);
    expect(c.canSave, isTrue);
    expect(await c.save(), isTrue);

    final rule = (await Get.find<RecurringRepository>().getAll()).single;
    expect(rule.kind, RecurringKind.saving);
    expect(rule.goalId, 1);
    expect(rule.categoryId, isNull);
    expect(rule.label, 'ادخار عام');
    final movement = (await Get.find<SavingsRepository>().getAllMovements()).single;
    expect(movement.amount, 50000);
    expect(movement.source, SavingsSource.recurring);
  });
}

/// Saves rules normally, then makes the catch-up fail (closed database).
class _ClosesBeforeCatchUp extends RecurringRepository {
  _ClosesBeforeCatchUp(this.database) : super(database);

  final DatabaseService database;
  int? rulesBeforeCatchUp;

  @override
  Future<int> applyDue(DateTime today) async {
    rulesBeforeCatchUp = (await getAll()).length;
    await database.db.close();
    return super.applyDue(today);
  }
}
