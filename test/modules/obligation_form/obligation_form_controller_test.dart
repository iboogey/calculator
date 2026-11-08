import 'package:calculator/app/data/models/obligation.dart';
import 'package:calculator/app/data/repositories/debt_repository.dart';
import 'package:calculator/app/modules/obligation_form/controllers/obligation_form_controller.dart';
import 'package:calculator/app/services/message_service.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:calculator/app/widgets/money_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<ObligationFormController> open({int? editId}) async {
    final c = Get.put(ObligationFormController(
      debts: Get.find(),
      settings: Get.find(),
      editId: editId,
      clock: () => DateTime(2026, 11, 8, 9),
    ));
    await c.ready;
    return c;
  }

  test('save creates an obligation with trimmed title and optional due date',
      () async {
    final repo = Get.find<DebtRepository>();
    await repo.addObligation(Obligation(
        title: 'الكهرباء', amount: 1000, createdAt: DateTime(2026, 10, 1)));
    final c = await open();
    expect(c.isEditing.value, isFalse);
    expect(c.recentTitles, ['الكهرباء']);

    c.amountController.text = '250';
    c.titleController.text = '  الإيجار  ';
    c.noteController.text = '  شهر 11 ';
    c.setDueDate(DateTime(2026, 11, 30, 15));
    expect(c.canSave, isTrue);
    expect(await c.save(), isTrue);

    final saved = (await repo.getObligations()).last;
    expect(saved.title, 'الإيجار');
    expect(saved.amount, 250000);
    expect(saved.dueDate, DateTime(2026, 11, 30));
    expect(saved.note, 'شهر 11');

    Get.delete<ObligationFormController>();
    final undated = await open();
    undated.amountController.text = '5';
    undated.useTitle('الإيجار');
    expect(undated.titleController.text, 'الإيجار');
    expect(await undated.save(), isTrue);
    final second = (await repo.getObligations()).last;
    expect(second.dueDate, isNull);
    expect(second.note, isNull);
  });

  test('cannot save without a title', () async {
    final c = await open();
    c.amountController.text = '10';
    expect(c.canSave, isFalse);
    c.titleController.text = '   ';
    expect(c.canSave, isFalse);
    expect(await c.save(), isFalse);
    expect(await Get.find<DebtRepository>().getObligations(), isEmpty);
    c.titleController.text = 'الإيجار';
    expect(c.canSave, isTrue);
    c.amountController.text = '';
    expect(c.canSave, isFalse);
  });

  test('editing below paid shows the paid amount', () async {
    final repo = Get.find<DebtRepository>();
    final o = await repo.addObligation(Obligation(
        title: 'الإيجار', amount: 10000, createdAt: DateTime(2026, 11, 1)));
    await repo.pay(obligationId: o.id!, amount: 6000, date: DateTime(2026, 11, 2));

    final c = await open(editId: o.id);
    expect(c.isEditing.value, isTrue);
    expect(c.amountController.text, '10');
    expect(c.titleController.text, 'الإيجار');

    c.amountController.text = '5';
    expect(await c.save(), isFalse);
    final currency = Get.find<SettingsService>().currency;
    expect(Get.find<MessageService>().lastMessage.value,
        'لا يمكن أن يقل المبلغ عن المدفوع (${MoneyText.label(6000, currency)})');
    expect((await repo.getObligation(o.id!))!.amount, 10000);

    c.amountController.text = '7';
    expect(await c.save(), isTrue);
    final edited = (await repo.getObligation(o.id!))!;
    expect(edited.amount, 7000);
    expect(edited.createdAt, o.createdAt);
  });
}
