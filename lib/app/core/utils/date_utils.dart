/// Calendar-date helpers. Dates are stored as "YYYY-MM-DD" text so they never
/// shift with time zones.
abstract final class DateKeys {
  static String fromDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-${_two(date.day)}';

  static DateTime toDate(String key) {
    final parts = key.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// Arabic (Levantine) date labels with Western digits, as in the mockup.
abstract final class ArabicDates {
  static const months = [
    'كانون الثاني',
    'شباط',
    'آذار',
    'نيسان',
    'أيار',
    'حزيران',
    'تموز',
    'آب',
    'أيلول',
    'تشرين الأول',
    'تشرين الثاني',
    'كانون الأول',
  ];

  /// "25 أيلول"
  static String dayMonth(DateTime date) =>
      '${date.day} ${months[date.month - 1]}';

  /// "اليوم", "أمس", or the day and month.
  static String relativeDay(DateTime date, {required DateTime today}) {
    final day = DateKeys.dateOnly(date);
    final now = DateKeys.dateOnly(today);
    if (day == now) return 'اليوم';
    if (day == DateTime(now.year, now.month, now.day - 1)) return 'أمس';
    return dayMonth(day);
  }
}
