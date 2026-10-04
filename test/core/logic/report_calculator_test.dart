import 'package:calculator/app/core/logic/period.dart';
import 'package:calculator/app/core/logic/report_calculator.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/transaction_category.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';

const food = TransactionCategory(
    id: 1, name: 'أكل', iconKey: 'food', colorValue: 0, kind: TransactionKind.expense);
const bills = TransactionCategory(
    id: 3, name: 'فواتير', iconKey: 'bills', colorValue: 0, kind: TransactionKind.expense);

void main() {
  final october = Period.containing(DateTime(2026, 10, 4), startDay: 1);

  test('spending by category for the period, largest first, with percentages', () {
    final shares = ReportCalculator.byCategory(
      period: october,
      categoriesById: const {1: food, 3: bills},
      transactions: [
        expense(30000, DateTime(2026, 10, 2)),
        expense(70000, DateTime(2026, 10, 3), categoryId: 3),
        expense(999000, DateTime(2026, 9, 30)),
        income(500000, DateTime(2026, 10, 1)),
      ],
    );
    expect(shares.map((s) => s.category.name), ['فواتير', 'أكل']);
    expect(shares.map((s) => s.percent), [70, 30]);
    expect(shares.first.amount, 70000);
  });

  test('a period without expenses has no shares', () {
    expect(
      ReportCalculator.byCategory(
          period: october, categoriesById: const {1: food}, transactions: const []),
      isEmpty,
    );
  });

  test('totals for the last periods, oldest first', () {
    final totals = ReportCalculator.totals(
      last: october,
      count: 3,
      transactions: [
        expense(10000, DateTime(2026, 8, 5)),
        income(50000, DateTime(2026, 9, 1)),
        expense(20000, DateTime(2026, 10, 2)),
        expense(5000, DateTime(2026, 10, 3)),
      ],
    );
    expect(totals.map((t) => t.period.key), ['2026-08', '2026-09', '2026-10']);
    expect(totals.map((t) => t.expenses), [10000, 0, 25000]);
    expect(totals[1].income, 50000);
  });

  test('change from the previous period', () {
    expect(ReportCalculator.changePercent(previous: 100000, current: 112000), 12);
    expect(ReportCalculator.changePercent(previous: 100000, current: 75000), -25);
    expect(ReportCalculator.changePercent(previous: 0, current: 5000), isNull);
  });
}
