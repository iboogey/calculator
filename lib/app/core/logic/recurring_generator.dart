import '../../data/models/recurring_rule.dart';
import '../utils/date_utils.dart';

/// When recurring rules are due (spec §6.5). There is no background work: the
/// app asks on start and on resume which entries are due and creates them.
abstract final class RecurringGenerator {
  /// The rule's due dates that have not been created yet, up to and including
  /// [today]. Empty for a paused rule.
  static List<DateTime> dueDates(RecurringRule rule, DateTime today) {
    if (!rule.isActive) return const [];
    final end = DateKeys.dateOnly(today);
    final dates = <DateTime>[];
    var due = _onOrAfter(_firstCandidate(rule), rule.dayOfMonth);
    while (!due.isAfter(end)) {
      dates.add(due);
      due = DateTime(due.year, due.month + 1, rule.dayOfMonth);
    }
    return dates;
  }

  /// The next date the rule will create an entry, counting from [today].
  static DateTime nextDueDate(RecurringRule rule, DateTime today) {
    final candidate = _firstCandidate(rule);
    final now = DateKeys.dateOnly(today);
    return _onOrAfter(candidate.isAfter(now) ? candidate : now, rule.dayOfMonth);
  }

  /// [rule] moved to [day]. When the rule already ran this month, this
  /// month counts as done for the new day too, so moving the day never
  /// creates a second entry in the same month.
  static RecurringRule withDay(RecurringRule rule, int day) {
    final last = rule.lastGeneratedDate;
    if (last == null || day == rule.dayOfMonth) {
      return rule.copyWith(dayOfMonth: day);
    }
    final sameMonth = DateTime(last.year, last.month, day);
    return rule.copyWith(
      dayOfMonth: day,
      lastGeneratedDate: sameMonth.isAfter(last) ? sameMonth : last,
    );
  }

  static DateTime _firstCandidate(RecurringRule rule) {
    final last = rule.lastGeneratedDate;
    final start = DateKeys.dateOnly(rule.startDate);
    if (last == null) return start;
    final afterLast = DateTime(last.year, last.month, last.day + 1);
    return afterLast.isAfter(start) ? afterLast : start;
  }

  static DateTime _onOrAfter(DateTime from, int day) {
    final sameMonth = DateTime(from.year, from.month, day);
    return sameMonth.isBefore(from)
        ? DateTime(from.year, from.month + 1, day)
        : sameMonth;
  }
}
