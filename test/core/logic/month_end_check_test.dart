import 'package:calculator/app/core/logic/month_end_check.dart';
import 'package:calculator/app/core/logic/period.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';

void main() {
  final october = Period.containing(DateTime(2026, 10, 4), startDay: 1);
  final september = [
    income(1250000, DateTime(2026, 9, 1)),
    expense(750000, DateTime(2026, 9, 10)),
  ];

  test('offers what was left at the end of the previous period', () {
    expect(
      MonthEndCheck.leftoverToOffer(
          current: october, lastPromptedKey: null, transactions: september, movements: const []),
      500000,
    );
  });

  test('money already saved last period is not offered again', () {
    expect(
      MonthEndCheck.leftoverToOffer(
        current: october,
        lastPromptedKey: '2026-08',
        transactions: september,
        movements: [saving(200000, DateTime(2026, 9, 20))],
      ),
      300000,
    );
  });

  test('nothing once the user answered for that period', () {
    expect(
      MonthEndCheck.leftoverToOffer(
          current: october, lastPromptedKey: '2026-09', transactions: september, movements: const []),
      isNull,
    );
  });

  test('nothing when the previous period ended at zero or below', () {
    expect(
      MonthEndCheck.leftoverToOffer(
        current: october,
        lastPromptedKey: null,
        transactions: [expense(1000, DateTime(2026, 9, 3))],
        movements: const [],
      ),
      isNull,
    );
    expect(
      MonthEndCheck.leftoverToOffer(
          current: october, lastPromptedKey: null, transactions: const [], movements: const []),
      isNull,
    );
  });
}
