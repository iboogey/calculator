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
  occurredAt: DateTime(2026, 11, 3, 14, 5),
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
          today: DateTime(2026, 11, 9),
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
    expect(find.text('3 تشرين الثاني · 14:05'), findsOneWidget);
    expect(find.byIcon(Icons.sms_outlined), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsNothing);
  });

  testWidgets('shows "بلا تصنيف" and no warning without them', (tester) async {
    await _pump(tester, categoryName: null, canApprove: false);
    expect(find.text('بلا تصنيف'), findsOneWidget);
    expect(find.textContaining('قد يكون مسجّلًا'), findsNothing);
    expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'اعتماد'))
            .onPressed,
        isNotNull);
  });

  testWidgets('a voice item shows the mic icon', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PendingCard(
          item: PendingItem(
            id: 2,
            source: PendingSource.voice,
            kind: PendingKind.expense,
            amount: 1000,
            occurredAt: DateTime(2026, 11, 9, 8, 0),
            createdAt: DateTime(2026, 11, 9),
          ),
          currency: Currencies.jod,
          categoryName: null,
          canApprove: false,
          today: DateTime(2026, 11, 9),
          onApprove: () {},
          onEdit: () {},
          onDismiss: () {},
        ),
      ),
    ));
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(find.text('اليوم · 08:00'), findsOneWidget);
  });

  testWidgets('approve button calls back when enabled', (tester) async {
    var taps = 0;
    await _pump(tester, onApprove: () => taps++);
    await tester.tap(find.text('اعتماد'));
    expect(taps, 1);
  });

  Future<void> pumpVoice(WidgetTester tester, PendingItem item,
          {String? personName}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PendingCard(
            item: item,
            currency: Currencies.jod,
            categoryName: null,
            personName: personName,
            canApprove: true,
            today: DateTime(2026, 11, 9),
            onApprove: () {},
            onEdit: () {},
            onDismiss: () {},
          ),
        ),
      ));

  final voiceDebt = PendingItem(
    id: 3,
    source: PendingSource.voice,
    kind: PendingKind.debtGave,
    amount: 20000,
    occurredAt: DateTime(2026, 11, 9, 8, 0),
    personName: 'سامي',
    note: 'سلفة',
    createdAt: DateTime(2026, 11, 9),
  );

  testWidgets('a voice debt shows its person instead of a category',
      (tester) async {
    await pumpVoice(tester, voiceDebt, personName: 'سامي');
    expect(find.text('دين: سامي'), findsOneWidget);
    expect(find.text('بلا تصنيف'), findsNothing);
    expect(find.text('سلفة'), findsOneWidget);
  });

  testWidgets('a voice debt without a person says so', (tester) async {
    await pumpVoice(tester, voiceDebt);
    expect(find.text('دين'), findsOneWidget);
    expect(find.text('بلا تصنيف'), findsNothing);
  });
}
