import 'package:calculator/app/core/logic/report_calculator.dart';
import 'package:calculator/app/core/utils/currencies.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/transaction_category.dart';
import 'package:calculator/app/modules/reports/widgets/category_donut.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a 100% share stays on one line at phone width', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(36),
            children: const [
              CategoryDonut(
                shares: [
                  CategoryShare(
                    category: TransactionCategory(
                        id: 3,
                        name: 'فواتير',
                        iconKey: 'bills',
                        colorValue: 0xFFB45309,
                        kind: TransactionKind.expense),
                    amount: 1500,
                    percent: 100,
                  ),
                ],
                total: 1500,
                currency: Currencies.jod,
              ),
            ],
          ),
        ),
      ),
    ));
    final percent = find.text('100%');
    expect(percent, findsOneWidget);
    // One line is 20 in the test font; a wrapped label is 40.
    expect(tester.getSize(percent).height, lessThan(30));
  });
}
