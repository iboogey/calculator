import 'package:calculator/app/data/models/budget.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/quick_template.dart';
import 'package:calculator/app/data/models/recurring_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Budget round-trips', () {
    const budget = Budget(id: 2, categoryId: 1, limitAmount: 200000);
    expect(budget.toMap()['limit_amount'], 200000);
    expect(Budget.fromMap(budget.toMap()), budget);
  });

  test('RecurringRule round-trips with dates as text', () {
    final rule = RecurringRule(
      id: 3,
      label: 'إيجار',
      kind: RecurringKind.expense,
      amount: 350000,
      categoryId: 4,
      dayOfMonth: 1,
      startDate: DateTime(2026, 10, 1),
      lastGeneratedDate: DateTime(2026, 10, 1),
      isActive: false,
    );
    final map = rule.toMap();
    expect(map['start_date'], '2026-10-01');
    expect(map['kind'], 'expense');
    expect(map['is_active'], 0);
    expect(RecurringRule.fromMap(map), rule);
  });

  test('RecurringRule copyWith keeps the generation state', () {
    final rule = RecurringRule(
      label: 'نت',
      kind: RecurringKind.expense,
      amount: 25000,
      categoryId: 3,
      dayOfMonth: 5,
      startDate: DateTime(2026, 1, 1),
      lastGeneratedDate: DateTime(2026, 9, 5),
    ).withId(9);
    final changed = rule.copyWith(amount: 30000, isActive: false);
    expect(changed.id, 9);
    expect(changed.amount, 30000);
    expect(changed.isActive, isFalse);
    expect(changed.lastGeneratedDate, DateTime(2026, 9, 5));
    expect(changed.startDate, DateTime(2026, 1, 1));
  });

  test('QuickTemplate round-trips', () {
    const template = QuickTemplate(
        id: 1, label: 'قهوة', kind: TransactionKind.expense, amount: 1500, categoryId: 1, sortOrder: 2);
    expect(QuickTemplate.fromMap(template.toMap()), template);
    expect(template.withId(5).id, 5);
  });
}
