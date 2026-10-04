import 'package:calculator/app/core/logic/budget_status.dart';
import 'package:calculator/app/core/logic/period.dart';
import 'package:calculator/app/data/models/budget.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/transaction_category.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';

const food = TransactionCategory(
    id: 1, name: 'أكل', iconKey: 'food', colorValue: 0, kind: TransactionKind.expense);
const transport = TransactionCategory(
    id: 2, name: 'مواصلات', iconKey: 'transport', colorValue: 0, kind: TransactionKind.expense);

BudgetStatus status(int spent, {int limit = 100000}) =>
    BudgetStatus(category: food, limit: limit, spent: spent);

void main() {
  group('BudgetStatus', () {
    test('levels switch at 80 % and 100 %', () {
      expect(status(79999).level, BudgetLevel.normal);
      expect(status(80000).level, BudgetLevel.warning);
      expect(status(99999).level, BudgetLevel.warning);
      expect(status(100000).level, BudgetLevel.over);
      expect(status(150000).level, BudgetLevel.over);
    });

    test('reached thresholds', () {
      expect(status(50000).reachedThresholds, isEmpty);
      expect(status(88000).reachedThresholds, [80]);
      expect(status(120000).reachedThresholds, [80, 100]);
    });

    test('progress is capped at 1 while percent and remaining are not', () {
      final over = status(150000);
      expect(over.progress, 1.0);
      expect(over.percent, 150);
      expect(over.remaining, -50000);
      expect(status(88000).progress, closeTo(0.88, 0.0001));
    });
  });

  group('BudgetCalculator', () {
    final october = Period.containing(DateTime(2026, 10, 10), startDay: 1);
    const byId = {1: food, 2: transport};

    test('sums this period expenses per budgeted category, most used first', () {
      final statuses = BudgetCalculator.calculate(
        period: october,
        budgets: const [
          Budget(categoryId: 1, limitAmount: 200000),
          Budget(categoryId: 2, limitAmount: 80000),
        ],
        categoriesById: byId,
        transactions: [
          expense(176000, DateTime(2026, 10, 3)),
          expense(42000, DateTime(2026, 10, 4), categoryId: 2),
          expense(99000, DateTime(2026, 9, 30)),
          income(500000, DateTime(2026, 10, 1), categoryId: 1),
        ],
      );
      expect(statuses.map((s) => s.category.name), ['أكل', 'مواصلات']);
      expect(statuses.first.spent, 176000);
      expect(statuses.last.spent, 42000);
    });

    test('a budget without spending shows zero', () {
      final statuses = BudgetCalculator.calculate(
        period: october,
        budgets: const [Budget(categoryId: 2, limitAmount: 80000)],
        categoriesById: byId,
        transactions: const [],
      );
      expect(statuses.single.spent, 0);
      expect(statuses.single.level, BudgetLevel.normal);
    });

    test('mostUrgent picks the highest status at warning or over', () {
      expect(BudgetCalculator.mostUrgent([status(10000)]), isNull);
      final urgent = BudgetCalculator.mostUrgent([status(120000), status(85000)]);
      expect(urgent!.spent, 120000);
    });
  });
}
