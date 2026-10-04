import 'package:calculator/app/core/utils/currencies.dart';
import 'package:calculator/app/widgets/amount_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AmountDialogResult?> open(WidgetTester tester, {String? removeLabel, int? initial}) async {
    AmountDialogResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showDialog<AmountDialogResult>(
            context: context,
            builder: (_) => AmountDialog(
              title: 'إضافة للهدف',
              currency: Currencies.jod,
              initialAmount: initial,
              removeLabel: removeLabel,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('returns the typed text and closes cleanly', (tester) async {
    AmountDialogResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showDialog<AmountDialogResult>(
            context: context,
            builder: (_) =>
                const AmountDialog(title: 'إضافة', currency: Currencies.jod),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '25');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect((result as SaveAmount).text, '25');
  });

  testWidgets('shows the current amount and an optional remove action', (tester) async {
    await open(tester, initial: 12500, removeLabel: 'حذف');
    expect(find.text('12.5'), findsOneWidget);
    expect(find.text('حذف'), findsOneWidget);
  });

  testWidgets('no remove action unless asked', (tester) async {
    await open(tester);
    expect(find.text('حذف'), findsNothing);
  });
}
