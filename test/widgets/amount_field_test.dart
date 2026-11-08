import 'package:calculator/app/core/utils/currencies.dart';
import 'package:calculator/app/widgets/amount_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TextEditingController input;

  setUp(() => input = TextEditingController());
  tearDown(() => input.dispose());

  Future<void> pump(WidgetTester tester, {int decimals = 3}) =>
      tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: AmountField(
              controller: input,
              currency: Currencies.jod,
              decimals: () => decimals,
            ),
          ),
        ),
      ));

  Finder field() => find.byKey(const ValueKey('amount-field'));

  testWidgets('asks the phone for its number keyboard', (tester) async {
    await pump(tester);
    final textField = tester.widget<TextField>(field());
    expect(textField.keyboardType,
        const TextInputType.numberWithOptions(decimal: true));
    expect(find.text('د.أ'), findsOneWidget);
  });

  testWidgets('keeps typed text a valid amount', (tester) async {
    await pump(tester, decimals: 2);
    await tester.enterText(field(), '١٢٫٥');
    expect(input.text, '12.5');
    await tester.enterText(field(), '12.555');
    expect(input.text, '12.5');
    await tester.enterText(field(), '12.5x');
    expect(input.text, '12.5');
  });
}
