import 'package:calculator/app/core/utils/date_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('date keys round-trip and drop the time of day', () {
    expect(DateKeys.fromDate(DateTime(2026, 3, 7, 23, 59)), '2026-03-07');
    expect(DateKeys.toDate('2026-03-07'), DateTime(2026, 3, 7));
  });

  test('Arabic day and month labels', () {
    expect(ArabicDates.dayMonth(DateTime(2026, 9, 25)), '25 أيلول');
    expect(ArabicDates.dayMonth(DateTime(2026, 1, 1)), '1 كانون الثاني');
  });

  test('relative day labels', () {
    final today = DateTime(2026, 10, 1, 9);
    expect(ArabicDates.relativeDay(DateTime(2026, 10, 1, 22), today: today), 'اليوم');
    expect(ArabicDates.relativeDay(DateTime(2026, 9, 30), today: today), 'أمس');
    expect(ArabicDates.relativeDay(DateTime(2026, 9, 29), today: today), '29 أيلول');
  });

  test('due labels', () {
    expect(ArabicDates.dueLabel(0), 'اليوم');
    expect(ArabicDates.dueLabel(1), 'خلال يوم');
    expect(ArabicDates.dueLabel(2), 'خلال يومين');
    expect(ArabicDates.dueLabel(3), 'خلال 3 أيام');
    expect(ArabicDates.dueLabel(10), 'خلال 10 أيام');
    expect(ArabicDates.dueLabel(11), 'خلال 11 يومًا');
    expect(ArabicDates.dueLabel(-1), 'متأخر منذ يوم');
    expect(ArabicDates.dueLabel(-2), 'متأخر منذ يومين');
    expect(ArabicDates.dueLabel(-5), 'متأخر منذ 5 أيام');
    expect(ArabicDates.dueLabel(-12), 'متأخر منذ 12 يومًا');
  });
}
