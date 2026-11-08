import 'package:calculator/app/core/logic/duplicate_check.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/recurring_rule.dart';
import 'package:calculator/app/data/models/transaction_record.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';

RecurringRule makeRule({
  RecurringKind kind = RecurringKind.expense,
  int amount = 180000,
  int dayOfMonth = 5,
  DateTime? startDate,
  bool isActive = true,
}) => RecurringRule(
  label: 'قسط السيارة',
  kind: kind,
  amount: amount,
  categoryId: foodCategoryId,
  dayOfMonth: dayOfMonth,
  startDate: startDate ?? DateTime(2026, 1, 1),
  isActive: isActive,
);

String? check({
  TransactionKind kind = TransactionKind.expense,
  int amount = 180000,
  required DateTime date,
  List<RecurringRule> rules = const [],
  List<TransactionRecord> transactions = const [],
}) => DuplicateCheck.find(
  kind: kind,
  amount: amount,
  date: date,
  rules: rules,
  transactions: transactions,
);

void main() {
  final rule = makeRule();

  test('rule due within ±3 days matches', () {
    expect(check(date: DateTime(2026, 11, 7), rules: [rule]), 'قسط السيارة');
    expect(check(date: DateTime(2026, 11, 2), rules: [rule]), 'قسط السيارة');
  });

  test('rule due 4 days away does not match', () {
    expect(check(date: DateTime(2026, 11, 9), rules: [rule]), isNull);
    expect(check(date: DateTime(2026, 11, 1), rules: [rule]), isNull);
  });

  test('month boundary: due 1 Dec, SMS 29 Nov matches', () {
    expect(
      check(date: DateTime(2026, 11, 29), rules: [makeRule(dayOfMonth: 1)]),
      'قسط السيارة',
    );
  });

  test('month boundary: due 28 Nov, SMS 1 Dec matches', () {
    expect(
      check(date: DateTime(2026, 12, 1), rules: [makeRule(dayOfMonth: 28)]),
      'قسط السيارة',
    );
  });

  test('year boundary: due 1 Jan, SMS 30 Dec matches', () {
    expect(
      check(date: DateTime(2026, 12, 30), rules: [makeRule(dayOfMonth: 1)]),
      'قسط السيارة',
    );
  });

  test('inactive rule does not match', () {
    expect(
      check(date: DateTime(2026, 11, 5), rules: [makeRule(isActive: false)]),
      isNull,
    );
  });

  test('saving rule never matches', () {
    expect(
      check(
        date: DateTime(2026, 11, 5),
        rules: [makeRule(kind: RecurringKind.saving)],
      ),
      isNull,
    );
  });

  test('other amount does not match', () {
    expect(
      check(date: DateTime(2026, 11, 5), amount: 180001, rules: [rule]),
      isNull,
    );
  });

  test('other kind does not match', () {
    expect(
      check(
        kind: TransactionKind.income,
        date: DateTime(2026, 11, 5),
        rules: [rule],
      ),
      isNull,
    );
    expect(
      check(
        kind: TransactionKind.income,
        date: DateTime(2026, 11, 5),
        rules: [makeRule(kind: RecurringKind.income)],
      ),
      'قسط السيارة',
    );
  });

  test('due date before startDate is ignored', () {
    expect(
      check(
        date: DateTime(2026, 11, 5),
        rules: [makeRule(startDate: DateTime(2026, 11, 20))],
      ),
      isNull,
    );
  });

  test('transaction same amount and kind within ±1 day matches', () {
    expect(
      check(
        amount: 5240,
        date: DateTime(2026, 11, 2),
        transactions: [
          expense(5240, DateTime(2026, 11, 1), note: 'فاتورة الهاتف'),
        ],
      ),
      'فاتورة الهاتف',
    );
    expect(
      check(
        amount: 5240,
        date: DateTime(2026, 11, 2),
        transactions: [expense(5240, DateTime(2026, 11, 1))],
      ),
      'عملية مسجّلة',
    );
  });

  test('transaction of other kind or amount does not match', () {
    expect(
      check(
        amount: 5240,
        date: DateTime(2026, 11, 2),
        transactions: [income(5240, DateTime(2026, 11, 2))],
      ),
      isNull,
    );
    expect(
      check(
        amount: 5240,
        date: DateTime(2026, 11, 2),
        transactions: [expense(5241, DateTime(2026, 11, 2))],
      ),
      isNull,
    );
  });

  test('transaction 2 days away does not match', () {
    expect(
      check(
        amount: 5240,
        date: DateTime(2026, 11, 3),
        transactions: [expense(5240, DateTime(2026, 11, 1))],
      ),
      isNull,
    );
  });

  test('rule match wins over transaction match', () {
    expect(
      check(
        date: DateTime(2026, 11, 5),
        rules: [rule],
        transactions: [expense(180000, DateTime(2026, 11, 5), note: 'ملاحظة')],
      ),
      'قسط السيارة',
    );
  });
}
