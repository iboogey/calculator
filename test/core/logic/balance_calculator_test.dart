import 'package:calculator/app/core/logic/balance_calculator.dart';
import 'package:calculator/app/core/logic/period.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';

void main() {
  final october = Period.containing(DateTime(2026, 10, 15), startDay: 1);

  test('the interview example: 500 remaining, 910 saved, 1,410 in total', () {
    final summary = BalanceCalculator.calculate(
      period: october,
      transactions: [
        income(2000000, DateTime(2026, 9, 1)),
        expense(1240000, DateTime(2026, 9, 10)),
        income(1250000, DateTime(2026, 10, 1)),
        expense(600000, DateTime(2026, 10, 5)),
      ],
      movements: [
        saving(760000, DateTime(2026, 9, 30)),
        saving(100000, DateTime(2026, 10, 2), goalId: 2),
        saving(50000, DateTime(2026, 10, 2), goalId: 3),
      ],
    );
    expect(summary.carriedOver, 0);
    expect(summary.income, 1250000);
    expect(summary.expenses, 600000);
    expect(summary.saved, 150000);
    expect(summary.remaining, 500000);
    expect(summary.totalSavings, 910000);
    expect(summary.total, 1410000);
  });

  test('money left last period and not saved carries over', () {
    final summary = BalanceCalculator.calculate(
      period: october,
      transactions: [
        income(1000000, DateTime(2026, 9, 1)),
        expense(900000, DateTime(2026, 9, 20)),
      ],
      movements: const [],
    );
    expect(summary.carriedOver, 100000);
    expect(summary.remaining, 100000);
  });

  test('a withdrawal from savings adds back to remaining', () {
    final summary = BalanceCalculator.calculate(
      period: october,
      transactions: const [],
      movements: [
        saving(300000, DateTime(2026, 9, 1)),
        saving(-50000, DateTime(2026, 10, 3)),
      ],
    );
    expect(summary.saved, -50000);
    expect(summary.remaining, -300000 + 50000);
    expect(summary.totalSavings, 250000);
  });

  test('overspending makes remaining negative', () {
    final summary = BalanceCalculator.calculate(
      period: october,
      transactions: [
        income(100000, DateTime(2026, 10, 1)),
        expense(150000, DateTime(2026, 10, 2)),
      ],
      movements: const [],
    );
    expect(summary.remaining, -50000);
    expect(summary.total, -50000);
  });

  test('entries dated after the period are ignored', () {
    final summary = BalanceCalculator.calculate(
      period: october,
      transactions: [expense(5000, DateTime(2026, 11, 1))],
      movements: [saving(5000, DateTime(2026, 11, 1))],
    );
    expect(summary.remaining, 0);
    expect(summary.totalSavings, 0);
  });
}
