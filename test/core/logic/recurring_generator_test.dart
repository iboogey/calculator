import 'package:calculator/app/core/logic/recurring_generator.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/recurring_rule.dart';
import 'package:flutter_test/flutter_test.dart';

RecurringRule rule({
  int day = 1,
  required DateTime start,
  DateTime? last,
  bool active = true,
}) =>
    RecurringRule(
      label: 'إيجار',
      kind: RecurringKind.expense,
      amount: 350000,
      categoryId: 4,
      dayOfMonth: day,
      startDate: start,
      lastGeneratedDate: last,
      isActive: active,
    );

void main() {
  group('dueDates', () {
    test('every missed month since the start date, up to today', () {
      expect(
        RecurringGenerator.dueDates(rule(start: DateTime(2026, 8, 15)), DateTime(2026, 10, 4)),
        [DateTime(2026, 9, 1), DateTime(2026, 10, 1)],
      );
    });

    test('the start date itself counts when it is the due day', () {
      expect(
        RecurringGenerator.dueDates(rule(start: DateTime(2026, 10, 1)), DateTime(2026, 10, 1, 23)),
        [DateTime(2026, 10, 1)],
      );
    });

    test('nothing before the start date', () {
      expect(RecurringGenerator.dueDates(rule(start: DateTime(2026, 10, 5)), DateTime(2026, 10, 4)),
          isEmpty);
    });

    test('nothing again after the last generated date', () {
      final generated = rule(start: DateTime(2026, 1, 1), last: DateTime(2026, 10, 1));
      expect(RecurringGenerator.dueDates(generated, DateTime(2026, 10, 4)), isEmpty);
      expect(RecurringGenerator.dueDates(generated, DateTime(2026, 11, 1)), [DateTime(2026, 11, 1)]);
    });

    test('catches up across a year boundary', () {
      expect(
        RecurringGenerator.dueDates(
            rule(day: 28, start: DateTime(2026, 1, 1), last: DateTime(2026, 11, 28)),
            DateTime(2027, 2, 28)),
        [DateTime(2026, 12, 28), DateTime(2027, 1, 28), DateTime(2027, 2, 28)],
      );
    });

    test('a paused rule creates nothing', () {
      expect(
        RecurringGenerator.dueDates(rule(start: DateTime(2026, 1, 1), active: false), DateTime(2026, 10, 4)),
        isEmpty,
      );
    });
  });

  group('nextDueDate', () {
    test('the next due day after today', () {
      expect(
        RecurringGenerator.nextDueDate(
            rule(day: 25, start: DateTime(2026, 1, 1), last: DateTime(2026, 9, 25)), DateTime(2026, 10, 4)),
        DateTime(2026, 10, 25),
      );
    });

    test('moves to next month once today was generated', () {
      expect(
        RecurringGenerator.nextDueDate(
            rule(day: 25, start: DateTime(2026, 1, 1), last: DateTime(2026, 10, 25)), DateTime(2026, 10, 25)),
        DateTime(2026, 11, 25),
      );
    });

    test('waits for a future start date', () {
      expect(
        RecurringGenerator.nextDueDate(rule(day: 5, start: DateTime(2026, 12, 10)), DateTime(2026, 10, 4)),
        DateTime(2027, 1, 5),
      );
    });
  });

  group('withDay', () {
    test('moving later in the month does not repeat this month', () {
      final moved = RecurringGenerator.withDay(
          rule(day: 5, start: DateTime(2026, 1, 1), last: DateTime(2026, 10, 5)), 20);
      expect(moved.dayOfMonth, 20);
      expect(RecurringGenerator.dueDates(moved, DateTime(2026, 10, 25)), isEmpty);
      expect(RecurringGenerator.dueDates(moved, DateTime(2026, 11, 20)), [DateTime(2026, 11, 20)]);
    });

    test('moving earlier waits for next month', () {
      final moved = RecurringGenerator.withDay(
          rule(day: 20, start: DateTime(2026, 1, 1), last: DateTime(2026, 10, 20)), 5);
      expect(RecurringGenerator.dueDates(moved, DateTime(2026, 10, 31)), isEmpty);
      expect(RecurringGenerator.dueDates(moved, DateTime(2026, 11, 5)), [DateTime(2026, 11, 5)]);
    });

    test('a rule that never ran only changes its day', () {
      final moved = RecurringGenerator.withDay(rule(day: 5, start: DateTime(2026, 12, 1)), 20);
      expect(moved.dayOfMonth, 20);
      expect(moved.lastGeneratedDate, isNull);
    });
  });
}
