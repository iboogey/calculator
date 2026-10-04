import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/quick_template.dart';
import 'package:calculator/app/data/repositories/budget_repository.dart';
import 'package:calculator/app/data/repositories/template_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/home/controllers/home_controller.dart';
import 'package:calculator/app/modules/templates/controllers/templates_controller.dart';
import 'package:calculator/app/modules/transaction_form/controllers/transaction_form_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<HomeController> openHome() async {
    final c = Get.put(HomeController(
      transactions: Get.find(),
      categories: Get.find(),
      savings: Get.find(),
      templates: Get.find(),
      budgets: Get.find(),
      settings: Get.find(),
      database: Get.find(),
    ));
    await c.load();
    return c;
  }

  test('saving with "save as favorite" also creates a favorite', () async {
    final form = Get.put(TransactionFormController(
        transactions: Get.find(), categories: Get.find(), templates: Get.find(), settings: Get.find()));
    await form.ready;
    for (final key in ['1', '.', '5']) {
      form.pressKey(key);
    }
    form.selectCategory(foodCategoryId);
    form.noteController.text = 'قهوة';
    form.saveAsFavorite.value = true;
    await form.save();
    final favorite = (await Get.find<TemplateRepository>().getAll()).single;
    expect(favorite.label, 'قهوة');
    expect(favorite.amount, 1500);
    expect(favorite.categoryId, foodCategoryId);
  });

  test('a favorite without a note is named after its category', () async {
    final form = Get.put(TransactionFormController(
        transactions: Get.find(), categories: Get.find(), templates: Get.find(), settings: Get.find()));
    await form.ready;
    form.pressKey('3');
    form.selectCategory(2);
    form.saveAsFavorite.value = true;
    await form.save();
    expect((await Get.find<TemplateRepository>().getAll()).single.label, 'مواصلات');
  });

  test('one tap on a favorite adds today\'s transaction, and undo removes it', () async {
    await Get.find<TemplateRepository>().add(const QuickTemplate(
        label: 'قهوة', kind: TransactionKind.expense, amount: 1500, categoryId: 1));
    final home = await openHome();
    expect(home.favorites.single.label, 'قهوة');
    final added = await home.addFavorite(home.favorites.single);
    final all = await Get.find<TransactionRepository>().getAll();
    expect(all.single.amount, 1500);
    expect(all.single.note, 'قهوة');
    expect(all.single.date.day, DateTime.now().day);
    await home.undoFavorite(added!);
    expect(await Get.find<TransactionRepository>().getAll(), isEmpty);
  });

  test('Home shows the most urgent budget', () async {
    await Get.find<BudgetRepository>().setLimit(foodCategoryId, 10000);
    await Get.find<TransactionRepository>().add(expense(8800, DateTime.now()));
    final home = await openHome();
    expect(home.urgentBudget.value!.category.name, 'أكل');
    expect(home.urgentBudget.value!.percent, 88);
  });

  test('favorites can be deleted from the manage list', () async {
    await Get.find<TemplateRepository>().add(const QuickTemplate(
        label: 'تكسي', kind: TransactionKind.expense, amount: 3000, categoryId: 2));
    final c = Get.put(TemplatesController(
        templates: Get.find(), categories: Get.find(), settings: Get.find(), database: Get.find()));
    await c.load();
    await c.delete(c.items.single);
    await settle();
    expect(c.items, isEmpty);
  });
}
