import 'package:calculator/app/core/logic/bank_sms_parser.dart';
import 'package:calculator/app/data/models/pending_item.dart';
import 'package:calculator/app/data/repositories/import_repository.dart';
import 'package:calculator/app/modules/import_review/controllers/import_review_controller.dart';
import 'package:calculator/app/modules/import_review/views/import_review_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/test_services.dart';

PendingItem _item(int amount, {int? category = 1}) => PendingItem(
      source: PendingSource.sms,
      kind: PendingKind.expense,
      amount: amount,
      occurredAt: DateTime(2026, 11, 3, 9),
      smsType: BankSmsType.cardPurchase,
      name: 'SAMPLE SUPER MARKET',
      suggestedCategoryId: category,
      createdAt: DateTime(2026, 11, 3),
    );

void main() {
  setUp(setUpTestServices);

  Future<void> open(WidgetTester tester, List<PendingItem> items) async {
    await tester.runAsync(() async {
      await Get.find<ImportRepository>().addPending(items);
    });
    final c = Get.put(ImportReviewController(
      imports: Get.find(),
      categories: Get.find(),
      recurring: Get.find(),
      transactions: Get.find(),
      settings: Get.find(),
      database: Get.find(),
    ));
    await tester.runAsync(c.load);
    await tester.pumpWidget(const MaterialApp(home: ImportReviewView()));
  }

  testWidgets('empty state and title, with no approve-all', (tester) async {
    await open(tester, []);
    expect(find.text('مراجعة الحركات'), findsOneWidget);
    expect(find.text('لا توجد حركات جديدة'), findsOneWidget);
    expect(find.text('اعتماد الكل'), findsNothing);
  });

  testWidgets('lists cards without an approve-all button', (tester) async {
    await open(tester, [_item(1000), _item(2000)]);
    expect(find.text('اعتماد'), findsNWidgets(2));
    expect(find.text('اعتماد الكل'), findsNothing);
  });

  testWidgets('approve on an item without a category opens the editor',
      (tester) async {
    await open(tester, [_item(1000, category: null)]);
    await tester.tap(find.text('اعتماد'));
    await tester.pumpAndSettle();
    expect(find.text('حفظ واعتماد'), findsOneWidget);
  });

  testWidgets('dismiss shows Undo, which restores the item', (tester) async {
    await open(tester, [_item(1000)]);
    final c = Get.find<ImportReviewController>();
    await tester.tap(find.text('تجاهل'));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.items, isEmpty);
    expect(find.text('لا توجد حركات جديدة'), findsOneWidget);
    expect(find.text('تراجع'), findsOneWidget);
    await tester.tap(find.text('تراجع'));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 100)));
    await tester.pump();
    expect(c.items, hasLength(1));
    expect(find.text('اعتماد'), findsOneWidget);
  });
}
