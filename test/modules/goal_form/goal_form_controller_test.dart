import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/recurring_rule.dart';
import 'package:calculator/app/data/repositories/recurring_repository.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/modules/goal_form/controllers/goal_form_controller.dart';
import 'package:calculator/app/services/message_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<GoalFormController> open({int? editId}) async {
    final c = Get.put(GoalFormController(
        savings: Get.find(), settings: Get.find(), editId: editId));
    await c.ready;
    return c;
  }

  test('a name is required; the target is optional but must be valid', () async {
    final c = await open();
    expect(c.canSave, isFalse);
    c.nameController.text = 'سفرة';
    expect(c.canSave, isTrue);
    c.targetController.text = 'abc';
    expect(c.canSave, isFalse);
    c.targetController.text = '1000';
    expect(c.canSave, isTrue);
  });

  test('creates a goal with a target and a date', () async {
    final c = await open();
    c.nameController.text = 'سفرة';
    c.targetController.text = '1000';
    c.setTargetDate(DateTime(2027, 6, 1));
    expect(await c.save(), isTrue);
    final goal = (await Get.find<SavingsRepository>().getGoals()).last;
    expect(goal.name, 'سفرة');
    expect(goal.targetAmount, 1000000);
    expect(goal.targetDate, DateTime(2027, 6, 1));
  });

  test('editing keeps the id and can clear the target', () async {
    final c = await open();
    c.nameController.text = 'سفرة';
    c.targetController.text = '1000';
    await c.save();
    final id = (await Get.find<SavingsRepository>().getGoals()).last.id;
    Get.delete<GoalFormController>();

    final edit = await open(editId: id);
    expect(edit.nameController.text, 'سفرة');
    expect(edit.targetController.text, '1000');
    edit.targetController.text = '';
    await edit.save();
    final goal = await Get.find<SavingsRepository>().getGoal(id!);
    expect(goal!.targetAmount, isNull);
  });

  test('a goal that still holds money cannot be removed', () async {
    final c = await open();
    c.nameController.text = 'سفرة';
    await c.save();
    final goal = (await Get.find<SavingsRepository>().getGoals()).last;
    await Get.find<SavingsRepository>()
        .addMovement(saving(1000, DateTime(2026, 10, 1), goalId: goal.id!));
    Get.delete<GoalFormController>();

    final edit = await open(editId: goal.id);
    expect(await edit.remove(), isFalse);
    expect(Get.find<MessageService>().lastMessage.value, contains('اسحب'));
  });

  test('a double tap on Save creates one goal', () async {
    final c = await open();
    c.nameController.text = 'سفرة';
    final results = await Future.wait([c.save(), c.save()]);
    expect(results, [true, false]);
    expect((await Get.find<SavingsRepository>().getGoals()).where((g) => g.name == 'سفرة'), hasLength(1));
  });

  test('a goal with a fixed monthly saving explains why it cannot be removed', () async {
    final c = await open();
    c.nameController.text = 'سفرة';
    await c.save();
    final goal = (await Get.find<SavingsRepository>().getGoals()).last;
    await Get.find<RecurringRepository>().add(RecurringRule(
      label: 'سفرة',
      kind: RecurringKind.saving,
      amount: 10000,
      goalId: goal.id,
      dayOfMonth: 28,
      startDate: DateTime(2026, 12, 1),
    ));
    Get.delete<GoalFormController>();

    final edit = await open(editId: goal.id);
    expect(await edit.remove(), isFalse);
    expect(Get.find<MessageService>().lastMessage.value, contains('ادخار شهري'));
  });

}
