import '../../data/models/savings_goal.dart';
import '../utils/date_utils.dart';
import 'period.dart';

/// How much a goal holds compared with its target.
class GoalProgress {
  const GoalProgress({required this.goal, required this.saved});

  final SavingsGoal goal;
  final int saved;

  int? get target => goal.targetAmount;

  bool get _hasTarget => target != null && target! > 0;

  double get progress => _hasTarget ? (saved / target!).clamp(0.0, 1.0) : 0;

  int get percent => _hasTarget ? saved * 100 ~/ target! : 0;

  bool get isReached => _hasTarget && saved >= target!;

  /// What is still missing (0 without a target or once reached).
  int get remaining => _hasTarget && !isReached ? target! - saved : 0;
}

abstract final class GoalProjection {
  /// The amount to put aside each period to reach the goal by its target
  /// date, rounded up (spec §6.4). Null without a target or a date, or once
  /// the goal is reached. A date in the current period or already past asks
  /// for the whole remaining amount now.
  static int? monthlyNeeded(GoalProgress progress, Period current) {
    final date = progress.goal.targetDate;
    if (date == null || progress.target == null || progress.isReached) {
      return null;
    }
    final day = DateKeys.dateOnly(date);
    var periods = 1;
    var period = current;
    while (!period.end.isAfter(day)) {
      period = period.next;
      periods++;
    }
    final left = progress.remaining;
    return (left + periods - 1) ~/ periods;
  }
}
