import 'package:calculator/app/core/logic/bank_sms_parser.dart';
import 'package:calculator/app/core/utils/currencies.dart';
import 'package:calculator/app/core/utils/money.dart';
import 'package:calculator/app/data/models/pending_item.dart';
import 'package:calculator/app/modules/import_review/widgets/pending_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _item = PendingItem(
  id: 1,
  source: PendingSource.sms,
  kind: PendingKind.expense,
  amount: 3500,
  occurredAt: DateTime(2026, 11, 3),
  smsType: BankSmsType.cardPurchase,
  name: 'SAMPLE SUPER MARKET',
  city: 'AMMAN',
  suggestedCategoryId: 1,
  createdAt: DateTime(2026, 11, 3),
);

Future<void> _pump(
  WidgetTester tester, {
  String? categoryName = 'طعام',
  String? duplicate,
  bool canApprove = true,
  VoidCallback? onApprove,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PendingCard(
          item: _item,
          currency: Currencies.jod,
          categoryName: categoryName,
          canApprove: canApprove,
          duplicateLabel: duplicate,
          onApprove: onApprove ?? () {},
          onEdit: () {},
          onDismiss: () {},
        ),
      ),
    ));

void main() {
  testWidgets('shows amount, name, city, category, warning and buttons',
      (tester) async {
    await _pump(tester, duplicate: 'قسط السيارة');
    final currency = Currencies.jod;
    final amount = Money.format(3500, decimals: currency.decimals);
    expect(find.textContaining(amount), findsOneWidget);
    expect(find.text('SAMPLE SUPER MARKET'), findsOneWidget);
    expect(find.text('AMMAN'), findsOneWidget);
    expect(find.text('طعام'), findsOneWidget);
    expect(find.text('قد يكون مسجّلًا مسبقًا: قسط السيارة'), findsOneWidget);
    expect(find.text('اعتماد'), findsOneWidget);
    expect(find.text('تعديل'), findsOneWidget);
    expect(find.text('تجاهل'), findsOneWidget);
    expect(find.text('اعتماد الكل'), findsNothing);
  });

  testWidgets('shows "بلا تصنيف" and no warning without them', (tester) async {
    await _pump(tester, categoryName: null, canApprove: false);
    expect(find.text('بلا تصنيف'), findsOneWidget);
    expect(find.textContaining('قد يكون مسجّلًا'), findsNothing);
    expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'اعتماد'))
            .onPressed,
        isNull);
  });

  testWidgets('approve button calls back when enabled', (tester) async {
    var taps = 0;
    await _pump(tester, onApprove: () => taps++);
    await tester.tap(find.text('اعتماد'));
    expect(taps, 1);
  });
}
