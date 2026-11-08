import 'package:calculator/app/app_widget.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/repositories/budget_repository.dart';
import 'package:calculator/app/modules/home/widgets/balance_card.dart';
import 'package:calculator/app/modules/home/widgets/debts_card.dart';
import 'package:calculator/app/widgets/money_text.dart';
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

/// Money text wraps numbers in bidi isolate marks; match without them.
Finder textIgnoringBidi(String part) => find.byWidgetPredicate((w) =>
    w is Text &&
    (w.data ?? '').replaceAll(RegExp('[\\u2066-\\u2069]'), '').contains(part));

void main() {
  testWidgets('opens on Home with an empty month', (tester) async {
    await boot(tester);
    expect(find.text('المتبقي من الراتب'), findsOneWidget);
    expect(find.textContaining('لم تسجّل أي عملية'), findsOneWidget);
  });

  testWidgets('adding an expense updates Home', (tester) async {
    await boot(tester);

    await tester.tap(find.byTooltip('إضافة عملية'));
    await idle(tester);
    expect(find.text('عملية جديدة'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('amount-field')), '5');
    await tester.tap(find.text('طعام'));
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    await idle(tester);
    await idle(tester);

    expect(find.text('المتبقي من الراتب'), findsOneWidget);
    expect(find.text('طعام'), findsOneWidget);
    expect(find.textContaining('-5.000'), findsWidgets);
  });

  testWidgets('Undo still restores a swiped row after leaving the list', (tester) async {
    await boot(tester);
    final repo = Get.find<TransactionRepository>();
    await tester.runAsync(() => repo.add(expense(5000, DateTime.now())));

    await tester.tap(find.text('العمليات'));
    await brief(tester);
    // RTL: end-to-start is a swipe towards the right.
    await tester.drag(find.text('طعام'), const Offset(600, 0));
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
    expect(find.text('طعام'), findsOneWidget);
  });

  testWidgets('Home warns when a budget is nearly used up', (tester) async {
    await boot(tester);
    await tester.runAsync(() async {
      await Get.find<BudgetRepository>().setLimit(1, 10000);
      await Get.find<TransactionRepository>().add(expense(9000, DateTime.now()));
    });
    await idle(tester);
    expect(find.text('صرفت 90% من ميزانية طعام'), findsOneWidget);
  });

  testWidgets('saving a favorite puts a one-tap button on Home', (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip('إضافة عملية'));
    await idle(tester);
    await tester.enterText(find.byKey(const ValueKey('amount-field')), '1.5');
    await tester.tap(find.text('طعام'));
    await tester.enterText(find.widgetWithText(TextField, 'ملاحظة (اختياري)'), 'قهوة');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    await idle(tester);
    await idle(tester);

    final chip = find.textContaining('قهوة ·');
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await brief(tester);
    expect(find.text('أُضيفت: قهوة'), findsOneWidget);
    final all = await tester.runAsync(Get.find<TransactionRepository>().getAll);
    expect(all, hasLength(2));
  });

  testWidgets('owing the university: add, pay part as expense, Home updates', (tester) async {
    await boot(tester);
    await tester.tap(find.byType(DebtsCard));
    await idle(tester);
    await tester.tap(find.text('عليّ'));
    await idle(tester);
    await tester.tap(find.text('التزام جديد'));
    await idle(tester);
    await tester.enterText(find.byKey(const ValueKey('amount-field')), '600');
    await tester.enterText(find.widgetWithText(TextField, 'لمن أو ما هو؟'), 'رسوم الجامعة');
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    await idle(tester);
    await idle(tester);

    await tester.tap(find.text('رسوم الجامعة'));
    await idle(tester);
    await tester.tap(find.text('جزء منه'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('amount-field')), '300');
    await tester.pump();
    await tester.tap(find.text('تسديد'));
    await idle(tester);
    await idle(tester);

    await tester.tap(find.byType(BackButton));
    await idle(tester);
    await idle(tester);

    final all = await tester.runAsync(Get.find<TransactionRepository>().getAll);
    expect(all, hasLength(1));
    expect(all!.single.amount, 300000);
    expect(all.single.kind, TransactionKind.expense);
    expect(textIgnoringBidi('المستحق عليّ 300.000'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(BalanceCard),
            matching: find.byWidgetPredicate(
                (w) => w is MoneyText && w.amount == -300000 && w.showSymbol)),
        findsOneWidget);
  });

  testWidgets('lending to a person never changes the Home balance', (tester) async {
    await boot(tester);
    await tester.tap(find.byType(DebtsCard));
    await idle(tester);
    await tester.tap(find.text('إضافة شخص'));
    await idle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'الاسم'), 'علا');
    await tester.tap(find.text('إضافة'));
    await idle(tester);
    await idle(tester);

    await tester.tap(find.text('علا'));
    await idle(tester);
    await tester.tap(find.text('أعطيتُ علا'));
    await idle(tester);
    await tester.enterText(find.byKey(const ValueKey('amount-field')), '50');
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    await idle(tester);
    await idle(tester);

    await tester.tap(find.byType(BackButton));
    await idle(tester);
    await tester.tap(find.byType(BackButton));
    await idle(tester);
    await idle(tester);

    expect(find.text('المتبقي من الراتب'), findsOneWidget);
    expect(textIgnoringBidi('0.000 د.أ'), findsWidgets);
    expect(
        textIgnoringBidi('دخل 0.000 · مصاريف 0.000'), findsOneWidget);
    final all = await tester.runAsync(Get.find<TransactionRepository>().getAll);
    expect(all, isEmpty);
    await tester.tap(find.text('بعد تسوية الديون'));
    await idle(tester);
    expect(textIgnoringBidi('+ لي 50.000'), findsOneWidget);
  });

  testWidgets('on an iPhone-sized screen the note and favorite option sit above Save', (tester) async {
    await boot(tester);
    // iPhone 17 Pro: 402×874 points, minus the status bar and home indicator.
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.padding = const FakeViewPadding(top: 186, bottom: 102);
    await tester.tap(find.byTooltip('إضافة عملية'));
    await idle(tester);

    final saveTop = tester.getTopLeft(find.byType(FilledButton)).dy;
    final note = find.widgetWithText(TextField, 'ملاحظة (اختياري)');
    expect(tester.getBottomLeft(note).dy, lessThanOrEqualTo(saveTop));
    expect(tester.getBottomLeft(find.byType(CheckboxListTile)).dy, lessThanOrEqualTo(saveTop));
  });

  testWidgets('adding a budget from its dialog closes cleanly', (tester) async {
    await boot(tester);
    await tester.tap(find.text('الميزانية'));
    await idle(tester);
    await tester.tap(find.text('إضافة ميزانية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('طعام'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '10');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.runAsync(settle);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final budgets = await tester.runAsync(Get.find<BudgetRepository>().getAll);
    expect(budgets!.single.limitAmount, 10000);
  });

  testWidgets('the reports tab shows spending by category', (tester) async {
    await boot(tester);
    await tester.runAsync(
        () => Get.find<TransactionRepository>().add(expense(5000, DateTime.now())));
    await tester.tap(find.text('التقارير'));
    await idle(tester);
    expect(find.text('طعام'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('Home opens savings from the savings total', (tester) async {
    await boot(tester);
    await tester.tap(find.text('مجموع المدخرات'));
    await idle(tester);
    expect(find.text('ادخار عام'), findsOneWidget);
    expect(find.text('هدف جديد'), findsOneWidget);
  });

  testWidgets('Home offers last month\'s leftover', (tester) async {
    await boot(tester);
    final now = DateTime.now();
    await tester.runAsync(() => Get.find<TransactionRepository>()
        .add(income(100000, DateTime(now.year, now.month - 1, 1))));
    await idle(tester);
    expect(find.textContaining('انتهى الشهر الماضي'), findsOneWidget);
    await tester.tap(find.text('ليس الآن'));
    await idle(tester);
    expect(find.textContaining('انتهى الشهر الماضي'), findsNothing);
  });
}

/// Like [idle] but short enough to keep a SnackBar on screen.
Future<void> brief(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(settle);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}
