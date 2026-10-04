import 'package:calculator/app/core/logic/goal_projection.dart';
import 'package:calculator/app/core/logic/period.dart';
import 'package:calculator/app/data/models/savings_goal.dart';
import 'package:flutter_test/flutter_test.dart';

GoalProgress laptop({int saved = 540000, int? target = 900000, DateTime? date}) =>
    GoalProgress(
      goal: SavingsGoal(
        id: 2,
        name: 'لابتوب',
        targetAmount: target,
        targetDate: date,
        createdAt: DateTime(2026),
      ),
      saved: saved,
    );

void main() {
  final october = Period.containing(DateTime(2026, 10, 4), startDay: 1);

  test('progress, percent and remaining', () {
    final p = laptop(date: DateTime(2027, 3, 10));
    expect(p.percent, 60);
    expect(p.progress, closeTo(0.6, 0.0001));
    expect(p.remaining, 360000);
    expect(p.isReached, isFalse);
    expect(laptop(saved: 950000).progress, 1.0);
    expect(laptop(saved: 950000).isReached, isTrue);
  });

  test('splits what is left across the periods up to the target date', () {
    // October to March = 6 periods; 360 / 6 = 60 a month.
    expect(GoalProjection.monthlyNeeded(laptop(date: DateTime(2027, 3, 10)), october), 60000);
  });

  test('rounds up so the goal is reached in time', () {
    // 360 over 7 periods (Oct–Apr) = 51.428… → 51.429
    expect(GoalProjection.monthlyNeeded(laptop(date: DateTime(2027, 4, 1)), october), 51429);
  });

  test('a date in this period or already passed asks for everything now', () {
    expect(GoalProjection.monthlyNeeded(laptop(date: DateTime(2026, 10, 20)), october), 360000);
    expect(GoalProjection.monthlyNeeded(laptop(date: DateTime(2026, 1, 1)), october), 360000);
  });

  test('no projection without a target, without a date, or once reached', () {
    expect(GoalProjection.monthlyNeeded(laptop(target: null, date: DateTime(2027)), october), isNull);
    expect(GoalProjection.monthlyNeeded(laptop(), october), isNull);
    expect(GoalProjection.monthlyNeeded(laptop(saved: 900000, date: DateTime(2027)), october), isNull);
  });
}
