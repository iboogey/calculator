import 'package:calculator/app/core/logic/balance_calculator.dart';
import 'package:calculator/app/core/logic/debt_summary.dart';
import 'package:calculator/app/core/utils/currencies.dart';
import 'package:calculator/app/modules/home/widgets/balance_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const summary = BalanceSummary(
    carriedOver: 0,
    income: 412500,
    expenses: 0,
    saved: 0,
    totalSavings: 0,
  );

  Future<void> pump(WidgetTester tester, DebtTotals? debts,
      {bool showSettled = false, VoidCallback? onToggle}) {
    return tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: BalanceCard(
            summary: summary,
            currency: Currencies.jod,
            debts: debts,
            showSettled: showSettled,
            onToggleSettled: onToggle,
          ),
        ),
      ),
    ));
  }

  testWidgets('settle button switches number to remaining + owed - owe',
      (tester) async {
    const debts = DebtTotals(owedToMe: 1477000, iOwe: 539950);
    await pump(tester, debts);
    expect(find.text('بعد تسوية الديون'), findsOneWidget);
    expect(find.text('المتبقي من الراتب'), findsOneWidget);

    await pump(tester, debts, showSettled: true);
    expect(find.text('المتبقي بعد تسوية الديون'), findsOneWidget);
    expect(find.textContaining('1,349.550'), findsWidgets);
    expect(find.textContaining('لي'), findsWidgets);
    expect(find.text('إخفاء'), findsOneWidget);
  });

  testWidgets('tapping the button calls onToggleSettled', (tester) async {
    var taps = 0;
    await pump(tester, const DebtTotals(owedToMe: 1000, iOwe: 0),
        onToggle: () => taps++);
    await tester.tap(find.text('بعد تسوية الديون'));
    expect(taps, 1);
  });

  testWidgets('no settle button without debts', (tester) async {
    await pump(tester, null);
    expect(find.text('بعد تسوية الديون'), findsNothing);
    await pump(tester, const DebtTotals(owedToMe: 0, iOwe: 0));
    expect(find.text('بعد تسوية الديون'), findsNothing);
  });
}
