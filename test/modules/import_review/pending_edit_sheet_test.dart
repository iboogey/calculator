import 'package:calculator/app/core/utils/currencies.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/pending_item.dart';
import 'package:calculator/app/data/models/transaction_category.dart';
import 'package:calculator/app/modules/import_review/widgets/pending_edit_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _food = TransactionCategory(
  id: 1,
  name: 'طعام',
  iconKey: 'food',
  colorValue: 0xFF0E5E4E,
  kind: TransactionKind.expense,
);

PendingItem _item({int? category}) => PendingItem(
      id: 1,
      source: PendingSource.sms,
      kind: PendingKind.expense,
      amount: 3500,
      occurredAt: DateTime(2026, 11, 3),
      suggestedCategoryId: category,
      createdAt: DateTime(2026, 11, 3),
    );

Future<void> _pump(WidgetTester tester, PendingItem item,
        {Future<bool> Function({
          required PendingKind kind,
          required int amount,
          required DateTime date,
          int? categoryId,
          String? note,
        })? onSave}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PendingEditSheet(
          item: item,
          currency: Currencies.jod,
          categoriesFor: (kind) => kind == TransactionKind.expense ? [_food] : [],
          onSave: onSave ??
              ({required kind, required amount, required date, categoryId, note}) async =>
                  true,
        ),
      ),
    ));

void main() {
  testWidgets('a suggestion outside the visible categories starts unselected',
      (tester) async {
    await _pump(tester, _item(category: 99));
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'حفظ واعتماد'))
            .onPressed,
        isNull);
  });

  testWidgets('save stays disabled until a category is picked', (tester) async {
    await _pump(tester, _item());
    Finder save() => find.widgetWithText(FilledButton, 'حفظ واعتماد');
    expect(tester.widget<FilledButton>(save()).onPressed, isNull);
    await tester.tap(find.text('طعام'));
    await tester.pump();
    expect(tester.widget<FilledButton>(save()).onPressed, isNotNull);
  });

  testWidgets('opens with current values and saves them', (tester) async {
    int? savedAmount;
    int? savedCategory;
    await _pump(tester, _item(category: 1),
        onSave: ({required kind, required amount, required date, categoryId, note}) async {
      savedAmount = amount;
      savedCategory = categoryId;
      return true;
    });
    expect(find.text('3.5'), findsOneWidget);
    await tester.tap(find.text('حفظ واعتماد'));
    await tester.pump();
    expect(savedAmount, 3500);
    expect(savedCategory, 1);
  });
}
