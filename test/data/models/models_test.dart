import 'package:calculator/app/data/models/app_settings.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/savings_movement.dart';
import 'package:calculator/app/data/models/transaction_category.dart';
import 'package:calculator/app/data/models/transaction_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TransactionCategory round-trips through a database row', () {
    const category = TransactionCategory(
      id: 3,
      name: 'فواتير',
      iconKey: 'bills',
      colorValue: 0xFF0E5E4E,
      kind: TransactionKind.expense,
      sortOrder: 2,
      isArchived: true,
    );
    expect(category.toMap()['is_archived'], 1);
    expect(category.toMap()['kind'], 'expense');
    expect(TransactionCategory.fromMap(category.toMap()), category);
  });

  test('TransactionRecord round-trips and stores dates as text', () {
    final record = TransactionRecord(
      id: 7,
      kind: TransactionKind.expense,
      amount: 12500,
      categoryId: 1,
      date: DateTime(2026, 10, 1),
      note: 'غدا',
      recurringRuleId: 2,
      recurringDueDate: DateTime(2026, 10, 1),
      createdAt: DateTime.fromMillisecondsSinceEpoch(1790000000000),
    );
    final map = record.toMap();
    expect(map['date'], '2026-10-01');
    expect(map['created_at'], 1790000000000);
    expect(TransactionRecord.fromMap(map), record);
  });

  test('signedAmount is negative for expenses and positive for income', () {
    final expense = TransactionRecord(
      kind: TransactionKind.expense,
      amount: 5000,
      categoryId: 1,
      date: DateTime(2026, 10, 1),
      createdAt: DateTime(2026, 10, 1),
    );
    expect(expense.signedAmount, -5000);
    expect(expense.isAuto, isFalse);
    final income = TransactionRecord(
      kind: TransactionKind.income,
      amount: 5000,
      categoryId: 9,
      date: DateTime(2026, 10, 1),
      createdAt: DateTime(2026, 10, 1),
    );
    expect(income.signedAmount, 5000);
    expect(income.withId(4).id, 4);
  });

  test('SavingsMovement round-trips', () {
    final movement = SavingsMovement(
      id: 1,
      goalId: 1,
      amount: -2000,
      date: DateTime(2026, 9, 30),
      source: SavingsSource.monthEnd,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1790000000000),
    );
    expect(movement.toMap()['source'], 'monthEnd');
    expect(SavingsMovement.fromMap(movement.toMap()), movement);
  });

  test('AppSettings defaults, copyWith and round-trip', () {
    const defaults = AppSettings();
    expect(defaults.periodStartDay, 1);
    expect(defaults.currencyCode, 'JOD');
    expect(defaults.currencyDecimals, 3);
    final changed = defaults.copyWith(periodStartDay: 25, currencyCode: 'USD', currencyDecimals: 2);
    expect(changed.periodStartDay, 25);
    expect(changed.reminderMinutes, defaults.reminderMinutes);
    expect(AppSettings.fromMap(changed.toMap()), changed);
  });
}
