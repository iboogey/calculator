import 'package:calculator/app/core/logic/period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('start day 1 gives calendar months', () {
    final p = Period.containing(DateTime(2026, 10, 15), startDay: 1);
    expect(p.start, DateTime(2026, 10, 1));
    expect(p.end, DateTime(2026, 11, 1));
    expect(p.lastDay, DateTime(2026, 10, 31));
    expect(p.key, '2026-10');
  });

  test('a date before the start day belongs to the previous period', () {
    final p = Period.containing(DateTime(2026, 10, 10), startDay: 25);
    expect(p.start, DateTime(2026, 9, 25));
    expect(p.end, DateTime(2026, 10, 25));
  });

  test('the start day itself opens a new period', () {
    final p = Period.containing(DateTime(2026, 9, 25, 8), startDay: 25);
    expect(p.start, DateTime(2026, 9, 25));
  });

  test('periods cross the year boundary', () {
    final p = Period.containing(DateTime(2027, 1, 10), startDay: 25);
    expect(p.start, DateTime(2026, 12, 25));
    expect(p.end, DateTime(2027, 1, 25));
    expect(p.key, '2026-12');
    expect(Period.containing(DateTime(2026, 12, 31), startDay: 25), p);
  });

  test('contains ignores the time of day and excludes the end', () {
    final p = Period.containing(DateTime(2026, 10, 15), startDay: 1);
    expect(p.contains(DateTime(2026, 10, 31, 23, 59)), isTrue);
    expect(p.contains(DateTime(2026, 10, 1)), isTrue);
    expect(p.contains(DateTime(2026, 11, 1)), isFalse);
    expect(p.contains(DateTime(2026, 9, 30, 23)), isFalse);
  });

  test('previous and next move one period at a time', () {
    final p = Period.containing(DateTime(2026, 1, 15), startDay: 28);
    expect(p.start, DateTime(2025, 12, 28));
    expect(p.previous.start, DateTime(2025, 11, 28));
    expect(p.previous.end, p.start);
    expect(p.next, Period.containing(DateTime(2026, 2, 1), startDay: 28));
    expect(p.next.end, DateTime(2026, 2, 28));
  });

  test('label shows the first and last day', () {
    final p = Period.containing(DateTime(2026, 10, 1), startDay: 25);
    expect(p.label, '25 أيلول – 24 تشرين الأول');
  });
}
