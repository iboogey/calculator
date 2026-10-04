import 'package:calculator/app/data/models/app_settings.dart';
import 'package:calculator/app/data/models/savings_goal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SavingsGoal round-trips with an optional target', () {
    final goal = SavingsGoal(
      id: 2,
      name: 'لابتوب',
      targetAmount: 900000,
      targetDate: DateTime(2027, 3, 10),
      createdAt: DateTime.fromMillisecondsSinceEpoch(1790000000000),
    );
    expect(goal.toMap()['target_date'], '2027-03-10');
    expect(SavingsGoal.fromMap(goal.toMap()), goal);

    final general = SavingsGoal(
      id: 1,
      name: 'ادخار عام',
      isGeneral: true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    );
    expect(SavingsGoal.fromMap(general.toMap()), general);
    expect(general.withId(7).id, 7);
  });

  test('AppSettings copyWith sets the month-end and backup fields', () {
    final changed = const AppSettings().copyWith(
      lastMonthEndPromptPeriod: '2026-09',
      lastBackupAt: DateTime.fromMillisecondsSinceEpoch(1790000000000),
    );
    expect(changed.lastMonthEndPromptPeriod, '2026-09');
    expect(changed.copyWith(periodStartDay: 5).lastBackupAt,
        DateTime.fromMillisecondsSinceEpoch(1790000000000));
    expect(AppSettings.fromMap(changed.toMap()), changed);
  });
}
