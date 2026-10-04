import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/settings/controllers/settings_controller.dart';
import 'package:calculator/app/modules/transaction_form/controllers/transaction_form_controller.dart';
import 'package:calculator/app/modules/transactions/controllers/transactions_controller.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:calculator/app/services/message_service.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_services.dart';

/// Makes every following database call fail.
Future<void> breakDatabase() => Get.find<DatabaseService>().db.close();

String? lastMessage() => Get.find<MessageService>().lastMessage.value;

void main() {
  setUp(setUpTestServices);

  test('a failed save shows a message and reports false', () async {
    final c = Get.put(TransactionFormController(
        transactions: Get.find(), categories: Get.find(), templates: Get.find(), settings: Get.find()));
    await c.ready;
    c.pressKey('5');
    c.selectCategory(foodCategoryId);
    await breakDatabase();
    expect(await c.save(), isFalse);
    expect(lastMessage(), 'ما قدرنا نحفظ العملية، جرّب مرة ثانية');
    expect(c.isSaving.value, isFalse);
  });

  test('a failed delete in the list brings the row back with a message', () async {
    final saved = await Get.find<TransactionRepository>().add(expense(5000, DateTime.now()));
    final c = Get.put(TransactionsController(
      transactions: Get.find(),
      categories: Get.find(),
      settings: Get.find(),
      database: Get.find(),
    ));
    await c.load();
    final shown = c.groups.expand((g) => g.transactions).single;
    await breakDatabase();
    await c.delete(shown);
    expect(lastMessage(), 'ما قدرنا نحذف العملية، جرّب مرة ثانية');
    expect(c.groups.expand((g) => g.transactions).map((t) => t.id), [saved.id]);
  });

  test('a failed settings change keeps the old value and shows a message', () async {
    final c = Get.put(SettingsController(settingsService: Get.find(), notifications: Get.find()));
    await breakDatabase();
    await c.setStartDay(25);
    expect(Get.find<SettingsService>().settings.value.periodStartDay, 1);
    expect(lastMessage(), 'ما قدرنا نحفظ الإعدادات');
  });
}
