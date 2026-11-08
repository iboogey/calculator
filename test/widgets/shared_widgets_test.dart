import 'package:calculator/app/core/logic/period.dart';
import 'package:calculator/app/core/utils/currencies.dart';
import 'package:calculator/app/widgets/money_text.dart';
import 'package:calculator/app/widgets/period_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(
      home: Directionality(
          textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

void main() {
  testWidgets('MoneyText shows the amount, sign and currency symbol', (tester) async {
    await tester.pumpWidget(wrap(const MoneyText(-12500, currency: Currencies.jod)));
    expect(find.textContaining('-12.500'), findsOneWidget);
    expect(find.textContaining('د.أ'), findsOneWidget);
  });

  testWidgets('PeriodSwitcher fits a long label in a phone-width app bar', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: PeriodSwitcher(
              period: Period.containing(DateTime(2026, 12, 1), startDay: 28),
              onPrevious: () {},
              onNext: () {},
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('الفترة السابقة'), findsOneWidget);
  });
}
