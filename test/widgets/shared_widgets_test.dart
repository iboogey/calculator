import 'package:calculator/app/core/utils/currencies.dart';
import 'package:calculator/app/widgets/amount_keypad.dart';
import 'package:calculator/app/widgets/money_text.dart';
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

  testWidgets('AmountKeypad reports keys and backspace', (tester) async {
    final pressed = <String>[];
    var backspaces = 0;
    await tester.pumpWidget(wrap(AmountKeypad(
      onKey: pressed.add,
      onBackspace: () => backspaces++,
    )));
    await tester.tap(find.text('7'));
    await tester.tap(find.text('.'));
    await tester.tap(find.byTooltip('مسح'));
    expect(pressed, ['7', '.']);
    expect(backspaces, 1);
  });

  testWidgets('AmountKeypad hides the dot for currencies without decimals', (tester) async {
    await tester.pumpWidget(wrap(AmountKeypad(onKey: (_) {}, onBackspace: () {}, showDot: false)));
    expect(find.text('.'), findsNothing);
  });
}
