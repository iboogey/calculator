import 'package:calculator/app/data/repositories/budget_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/fake_notifications.dart';
import '../helpers/fixtures.dart';
import '../helpers/test_services.dart';

void main() {
  late FakeNotificationProvider fake;
  late TransactionRepository transactions;
  final today = DateTime.now();

  setUp(() async {
    fake = await setUpTestServices();
    transactions = Get.find<TransactionRepository>();
    await Get.find<BudgetRepository>().setLimit(foodCategoryId, 10000);
    await settle();
  });

  test('warns once at 80 % and once more at 100 %', () async {
    await transactions.add(expense(8000, today));
    await settle();
    expect(fake.shown.map((n) => n.title), ['قرّبت تخلص ميزانية أكل']);

    await transactions.add(expense(1000, today));
    await settle();
    expect(fake.shown, hasLength(1));

    await transactions.add(expense(2000, today));
    await settle();
    expect(fake.shown.map((n) => n.title).last, 'تجاوزت ميزانية أكل');
    expect(fake.shown, hasLength(2));
  });

  test('jumping straight past the limit sends a single alert', () async {
    await transactions.add(expense(15000, today));
    await settle();
    expect(fake.shown.single.title, 'تجاوزت ميزانية أكل');
  });

  test('categories without a budget never alert', () async {
    await transactions.add(expense(999000, today, categoryId: 2));
    await settle();
    expect(fake.shown, isEmpty);
  });
}
