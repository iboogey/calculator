import 'package:calculator/app/core/logic/debt_summary.dart';
import 'package:calculator/app/core/utils/currencies.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/obligation.dart';
import 'package:calculator/app/data/models/transaction_category.dart';
import 'package:calculator/app/modules/debts/controllers/debts_controller.dart';
import 'package:calculator/app/modules/debts/widgets/pay_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _bills = TransactionCategory(
  id: 3,
  name: 'فواتير',
  iconKey: 'bills',
  colorValue: 0xFFB45309,
  kind: TransactionKind.expense,
);

final _status = ObligationStatus(
  obligation: Obligation(
    id: 1,
    title: 'الإيجار',
    amount: 10000,
    createdAt: DateTime(2026, 11, 1),
  ),
  paid: 5000,
);

/// Opens the sheet; the returned getter gives what it popped.
Future<PayDraft? Function()> _openSheet(WidgetTester tester) async {
  PayDraft? result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showModalBottomSheet<PayDraft>(
              context: context,
              isScrollControlled: true,
              builder: (_) => PaySheet(
                status: _status,
                expenseCategories: const [_bills],
                defaultCategoryId: _bills.id,
                today: DateTime(2026, 11, 8),
                currency: Currencies.jod,
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

void main() {
  testWidgets('prefills the remaining and disables pay above it',
      (tester) async {
    await _openSheet(tester);

    final field = find.byKey(const ValueKey('amount-field'));
    expect(tester.widget<TextField>(field).controller!.text, '5');
    expect(find.text('أكبر من المتبقي'), findsNothing);

    await tester.enterText(field, '6');
    await tester.pump();
    expect(find.text('أكبر من المتبقي'), findsOneWidget);
    final pay = find.widgetWithText(FilledButton, 'تسديد');
    expect(tester.widget<FilledButton>(pay).onPressed, isNull);

    await tester.tap(find.text('جزء منه'));
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '');
    expect(tester.widget<FilledButton>(pay).onPressed, isNull);

    await tester.tap(find.textContaining('المبلغ كاملًا'));
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '5');
    expect(tester.widget<FilledButton>(pay).onPressed, isNotNull);
  });

  testWidgets('unticking the expense returns a null category', (tester) async {
    final result = await _openSheet(tester);

    expect(
        find.text('يُخصم من «المتبقي من الراتب» ضمن تصنيف فواتير · تغيير',
            findRichText: true),
        findsOneWidget);
    await tester.tap(find.text('سجّله مصروفًا'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('amount-field')), '2.5');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'تسديد'));
    await tester.pumpAndSettle();

    final draft = result();
    expect(draft, isNotNull);
    expect(draft!.amount, 2500);
    expect(draft.date, DateTime(2026, 11, 8));
    expect(draft.expenseCategoryId, isNull);
  });
}
