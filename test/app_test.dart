import 'package:calculator/app/app_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_services.dart';

Future<void> boot(WidgetTester tester) async {
  // A phone-sized screen (390×844 points), like the mockup.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.runAsync(setUpTestServices);
  await tester.runAsync(() async {
    await tester.pumpWidget(const AppWidget());
    await settle();
  });
  await tester.pump();
}

/// Lets real database work finish, then draws the result.
Future<void> idle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(settle);
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('opens on Home with an empty month', (tester) async {
    await boot(tester);
    expect(find.text('المتبقي من الراتب'), findsOneWidget);
    expect(find.textContaining('لسا ما سجلت'), findsOneWidget);
  });

  testWidgets('adding an expense from the keypad updates Home', (tester) async {
    await boot(tester);

    await tester.tap(find.byTooltip('إضافة عملية'));
    await idle(tester);
    expect(find.text('عملية جديدة'), findsOneWidget);

    await tester.tap(find.text('5'));
    await tester.tap(find.text('أكل'));
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    await idle(tester);
    await idle(tester);

    expect(find.text('المتبقي من الراتب'), findsOneWidget);
    expect(find.text('أكل'), findsOneWidget);
    expect(find.textContaining('-5.000'), findsWidgets);
  });
}
