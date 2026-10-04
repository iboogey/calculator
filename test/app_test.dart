import 'package:calculator/app/app_widget.dart';
import 'package:calculator/app/data/repositories/budget_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:get/get.dart';

import 'helpers/fixtures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_services.dart';

Future<void> boot(WidgetTester tester) async {
  // A phone-sized screen (390×844 points), like the mockup.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.runAsync(setUpTestServices);
  await tester.runAsync(() async {
    await tester.pumpWidget(const AppWidget());
    await settle();
  });
  await tester.pump();
}

/// Lets real database work finish, then draws the result.
Future<void> idle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(settle);
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('opens on Home with an empty month', (tester) async {
    await boot(tester);
    expect(find.text('المتبقي من الراتب'), findsOneWidget);
    expect(find.textContaining('لسا ما سجلت'), findsOneWidget);
  });

  testWidgets('adding an expense from the keypad updates Home', (tester) async {
    await boot(tester);

    await tester.tap(find.byTooltip('إضافة عملية'));
    await idle(tester);
    expect(find.text('عملية جديدة'), findsOneWidget);

    await tester.tap(find.text('5'));
    await tester.tap(find.text('أكل'));
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    await idle(tester);
    await idle(tester);

    expect(find.text('المتبقي من الراتب'), findsOneWidget);
    expect(find.text('أكل'), findsOneWidget);
    expect(find.textContaining('-5.000'), findsWidgets);
  });

  testWidgets('Undo still restores a swiped row after leaving the list', (tester) async {
    await boot(tester);
    final repo = Get.find<TransactionRepository>();
    await tester.runAsync(() => repo.add(expense(5000, DateTime.now())));

    await tester.tap(find.text('العمليات'));
    await brief(tester);
    // RTL: end-to-start is a swipe towards the right.
    await tester.drag(find.text('أكل'), const Offset(600, 0));
    await brief(tester);
    expect(find.text('تراجع'), findsOneWidget);

    await tester.tap(find.text('الرئيسية'));
    await brief(tester);
    await tester.tap(find.text('تراجع'));
    await brief(tester);

    expect(tester.takeException(), isNull);
    final all = await tester.runAsync(repo.getAll);
    expect(all, hasLength(1));
  });

  testWidgets('the budgets tab shows a budget set from the repository', (tester) async {
    await boot(tester);
    await tester.runAsync(() => Get.find<BudgetRepository>().setLimit(1, 200000));
    await tester.tap(find.text('الميزانية'));
    await idle(tester);
    expect(find.text('إضافة ميزانية'), findsOneWidget);
    expect(find.text('أكل'), findsOneWidget);
  });

  testWidgets('Home warns when a budget is nearly used up', (tester) async {
    await boot(tester);
    await tester.runAsync(() async {
      await Get.find<BudgetRepository>().setLimit(1, 10000);
      await Get.find<TransactionRepository>().add(expense(9000, DateTime.now()));
    });
    await idle(tester);
    expect(find.text('صرفت 90% من ميزانية أكل'), findsOneWidget);
  });

  testWidgets('saving a favorite puts a one-tap button on Home', (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip('إضافة عملية'));
    await idle(tester);
    await tester.tap(find.text('1'));
    await tester.tap(find.text('.'));
    await tester.tap(find.text('5'));
    await tester.tap(find.text('أكل'));
    await tester.enterText(find.byType(TextField), 'قهوة');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    await idle(tester);
    await idle(tester);

    final chip = find.textContaining('قهوة ·');
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await brief(tester);
    expect(find.text('انضافت: قهوة'), findsOneWidget);
    final all = await tester.runAsync(Get.find<TransactionRepository>().getAll);
    expect(all, hasLength(2));
  });
}

/// Like [idle] but short enough to keep a SnackBar on screen.
Future<void> brief(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(settle);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}
