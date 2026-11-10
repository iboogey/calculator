import 'package:calculator/app/core/logic/bank_sms_parser.dart';
import 'package:calculator/app/core/utils/currencies.dart';
import 'package:calculator/app/data/models/debt_person.dart';
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

final _sami = DebtPerson(id: 3, name: 'سامي', createdAt: DateTime(2026, 1, 1));

PendingItem _voice(PendingKind kind, {int? personId, String? personName}) =>
    PendingItem(
      id: 2,
      source: PendingSource.voice,
      kind: kind,
      amount: 20000,
      occurredAt: DateTime(2026, 11, 3),
      personId: personId,
      personName: personName,
      createdAt: DateTime(2026, 11, 3),
    );

typedef _Save = Future<bool> Function({
  required PendingKind kind,
  required int amount,
  required DateTime date,
  int? categoryId,
  int? personId,
  String? personName,
  String? note,
});

Future<void> _pump(WidgetTester tester, PendingItem item,
        {_Save? onSave, List<DebtPerson> people = const []}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PendingEditSheet(
          item: item,
          currency: Currencies.jod,
          categoriesFor: (kind) => kind == TransactionKind.expense ? [_food] : [],
          people: people,
          onSave: onSave ??
              ({required kind,
                required amount,
                required date,
                categoryId,
                personId,
                personName,
                note}) async =>
                  true,
        ),
      ),
    ));

Finder _save() => find.widgetWithText(FilledButton, 'حفظ واعتماد');

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
        onSave: ({required kind,
            required amount,
            required date,
            categoryId,
            personId,
            personName,
            note}) async {
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

  testWidgets('an SMS item can become a debt, with the person picked',
      (tester) async {
    PendingKind? savedKind;
    int? savedPerson;
    await _pump(tester, _item(category: 1),
        people: [_sami],
        onSave: ({required kind,
            required amount,
            required date,
            categoryId,
            personId,
            personName,
            note}) async {
      savedKind = kind;
      savedPerson = personId;
      return true;
    });
    expect(find.text('مصروف'), findsOneWidget);
    expect(find.text('دخل'), findsOneWidget);
    await tester.tap(find.text('دين'));
    await tester.pump();
    expect(_save(), findsOneWidget);
    expect(tester.widget<FilledButton>(_save()).onPressed, isNull);
    await tester.tap(find.text('سامي'));
    await tester.pump();
    await tester.tap(_save());
    await tester.pump();
    // Money out: "I gave".
    expect(savedKind, PendingKind.debtGave);
    expect(savedPerson, 3);
  });

  testWidgets('money in switched to a debt starts on "I took"',
      (tester) async {
    PendingKind? savedKind;
    await _pump(tester, _item().copyWith(kind: PendingKind.income),
        people: [_sami],
        onSave: ({required kind,
            required amount,
            required date,
            categoryId,
            personId,
            personName,
            note}) async {
      savedKind = kind;
      return true;
    });
    await tester.tap(find.text('دين'));
    await tester.pump();
    await tester.tap(find.text('سامي'));
    await tester.pump();
    await tester.tap(_save());
    await tester.pump();
    expect(savedKind, PendingKind.debtTook);
  });

  testWidgets('switching a bank item to a debt starts with no person',
      (tester) async {
    await _pump(
        tester,
        _item().copyWith(
            smsType: BankSmsType.cliqSent, name: 'SAMI KHALED HADDAD'),
        people: [_sami]);
    await tester.tap(find.text('دين'));
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'شخص جديد'))
            .controller!
            .text,
        isEmpty);
    expect(tester.widget<FilledButton>(_save()).onPressed, isNull);
  });

  testWidgets('a voice debt opens with its person and direction', (tester) async {
    PendingKind? savedKind;
    int? savedPerson;
    int? savedAmount;
    await _pump(tester, _voice(PendingKind.debtGave, personId: 3),
        people: [_sami],
        onSave: ({required kind,
            required amount,
            required date,
            categoryId,
            personId,
            personName,
            note}) async {
      savedKind = kind;
      savedPerson = personId;
      savedAmount = amount;
      return true;
    });
    expect(find.text('دين'), findsOneWidget);
    expect(find.text('أعطيتُ'), findsOneWidget);
    expect(find.text('أخذتُ'), findsOneWidget);
    expect(find.text('التصنيف'), findsNothing);
    expect(tester.widget<FilledButton>(_save()).onPressed, isNotNull);
    await tester.tap(find.text('أخذتُ'));
    await tester.pump();
    await tester.tap(_save());
    await tester.pump();
    expect(savedKind, PendingKind.debtTook);
    expect(savedPerson, 3);
    expect(savedAmount, 20000);
  });

  testWidgets('a spoken new name fills the new person field', (tester) async {
    int? savedPerson;
    String? savedName;
    await _pump(tester, _voice(PendingKind.debtTook, personName: 'رنا'),
        people: [_sami],
        onSave: ({required kind,
            required amount,
            required date,
            categoryId,
            personId,
            personName,
            note}) async {
      savedPerson = personId;
      savedName = personName;
      return true;
    });
    expect(find.widgetWithText(TextField, 'رنا'), findsOneWidget);
    await tester.tap(_save());
    await tester.pump();
    expect(savedPerson, isNull);
    expect(savedName, 'رنا');
  });

  testWidgets('a spoken name of an existing person selects them', (tester) async {
    int? savedPerson;
    await _pump(tester, _voice(PendingKind.debtGave, personName: ' سامي '),
        people: [_sami],
        onSave: ({required kind,
            required amount,
            required date,
            categoryId,
            personId,
            personName,
            note}) async {
      savedPerson = personId;
      return true;
    });
    await tester.tap(_save());
    await tester.pump();
    expect(savedPerson, 3);
  });

  testWidgets('switching a voice expense to a debt needs a person',
      (tester) async {
    PendingKind? savedKind;
    String? savedName;
    await _pump(tester, _voice(PendingKind.expense),
        people: [_sami],
        onSave: ({required kind,
            required amount,
            required date,
            categoryId,
            personId,
            personName,
            note}) async {
      savedKind = kind;
      savedName = personName;
      return true;
    });
    await tester.tap(find.text('دين'));
    await tester.pump();
    expect(find.text('سامي'), findsOneWidget);
    expect(tester.widget<FilledButton>(_save()).onPressed, isNull);
    await tester.enterText(
        find.widgetWithText(TextField, 'شخص جديد'), 'هدى');
    await tester.pump();
    await tester.tap(_save());
    await tester.pump();
    expect(savedKind, PendingKind.debtGave);
    expect(savedName, 'هدى');
  });
}
