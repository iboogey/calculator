import 'package:calculator/app/data/models/debt_entry.dart';
import 'package:calculator/app/modules/debt_person/controllers/debt_person_controller.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:get/get.dart';
import 'package:calculator/app/modules/debt_person/widgets/entry_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  testWidgets('EntrySheet returns a negative amount for took', (tester) async {
    EntryDraft? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showModalBottomSheet<EntryDraft>(
                context: context,
                isScrollControlled: true,
                builder: (_) => EntrySheet(
                    gave: false,
                    personName: 'علا',
                    today: DateTime(2026, 11, 8)),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('amount-field')), '2.5');
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(result!.amount, -2500);
    expect(result!.date, DateTime(2026, 11, 8));
    expect(result!.note, isNull);
  });

  testWidgets('an entry with more decimals than the currency can be saved unchanged',
      (tester) async {
    final settings = Get.find<SettingsService>();
    settings.settings.value =
        settings.settings.value.copyWith(currencyCode: 'USD');
    EntryDraft? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showModalBottomSheet<EntryDraft>(
                context: context,
                isScrollControlled: true,
                builder: (_) => EntrySheet(
                  gave: true,
                  personName: 'علا',
                  today: DateTime(2026, 11, 8),
                  editing: DebtEntry(
                      id: 1,
                      personId: 1,
                      amount: 2505,
                      date: DateTime(2026, 11, 1),
                      createdAt: DateTime(2026, 11, 1)),
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
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(result!.amount, 2505);
  });
}
