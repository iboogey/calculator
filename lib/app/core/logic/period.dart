import '../utils/date_utils.dart';

/// A financial month: from [start] (inclusive) to [end] (exclusive), both on
/// the same day of the month (the user's period start day, 1–28).
class Period {
  const Period._(this.start, this.end);

  /// The period that contains [date] when periods begin on [startDay].
  factory Period.containing(DateTime date, {required int startDay}) {
    assert(startDay >= 1 && startDay <= 28, 'startDay must be 1–28');
    final day = DateKeys.dateOnly(date);
    var start = DateTime(day.year, day.month, startDay);
    if (day.isBefore(start)) start = DateTime(day.year, day.month - 1, startDay);
    return Period._(start, DateTime(start.year, start.month + 1, startDay));
  }

  final DateTime start;
  final DateTime end;

  DateTime get lastDay => DateTime(end.year, end.month, end.day - 1);

  /// "2026-09" — the month in which the period starts.
  String get key =>
      '${start.year}-${start.month.toString().padLeft(2, '0')}';

  /// "25 أيلول – 24 تشرين الأول"
  String get label =>
      '${ArabicDates.dayMonth(start)} – ${ArabicDates.dayMonth(lastDay)}';

  bool contains(DateTime date) {
    final day = DateKeys.dateOnly(date);
    return !day.isBefore(start) && day.isBefore(end);
  }

  Period get previous =>
      Period._(DateTime(start.year, start.month - 1, start.day), start);

  Period get next => Period._(end, DateTime(end.year, end.month + 1, end.day));

  @override
  bool operator ==(Object other) =>
      other is Period && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'Period($key)';
}
