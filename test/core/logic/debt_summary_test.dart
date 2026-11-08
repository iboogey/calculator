import 'package:calculator/app/core/logic/debt_summary.dart';
import 'package:calculator/app/data/models/debt_person.dart';
import 'package:calculator/app/data/models/obligation.dart';
import 'package:flutter_test/flutter_test.dart';

DebtPerson person(int id, String name) =>
    DebtPerson(id: id, name: name, createdAt: DateTime(2026, 1, id));

Obligation ob(int id, int amount, {DateTime? due, int day = 1}) => Obligation(
      id: id,
      title: 'o$id',
      amount: amount,
      dueDate: due,
      createdAt: DateTime(2026, 1, day),
    );

void main() {
  test('people orders owed first by size, settled last by name', () {
    final result = DebtSummary.people(
      [person(1, 'ياسر'), person(2, 'أحمد'), person(3, 'سعد'), person(4, 'بلال')],
      {1: 0, 2: 50000, 3: -90000},
    );
    expect(result.map((e) => e.person.id), [3, 2, 4, 1]);
    expect(result.first.balance, -90000);
  });

  test('obligations puts unpaid by due date with undated last, paid after', () {
    final result = DebtSummary.obligations(
      [
        ob(1, 100, day: 1),
        ob(2, 100, due: DateTime(2026, 5, 10), day: 2),
        ob(3, 100, due: DateTime(2026, 5, 5), day: 3),
        ob(4, 100, day: 4),
        ob(5, 100, due: DateTime(2026, 5, 1), day: 5),
        ob(6, 100, day: 6),
      ],
      {5: 100, 6: 100},
    );
    expect(result.map((e) => e.obligation.id), [3, 2, 1, 4, 6, 5]);
  });

  test('totals adds people I owe and unpaid remainders', () {
    final people = DebtSummary.people(
      [person(1, 'a'), person(2, 'b'), person(3, 'c')],
      {1: 980000, 2: -40000, 3: 0},
    );
    final obs = DebtSummary.obligations(
      [ob(1, 600000), ob(2, 157200), ob(3, 50000)],
      {1: 300000, 3: 50000},
    );
    final totals = DebtSummary.totals(people, obs);
    expect(totals.owedToMe, 980000);
    expect(totals.iOwe, 40000 + 300000 + 157200);
    expect(totals.isEmpty, isFalse);
  });

  test('remaining never counts a fully paid obligation', () {
    final obs = DebtSummary.obligations([ob(1, 50000)], {1: 70000});
    expect(obs.single.isPaid, isTrue);
    expect(DebtSummary.totals(const [], obs).iOwe, 0);
    expect(DebtSummary.totals(const [], obs).isEmpty, isTrue);
  });

  test('mostUrgent picks overdue over due-in-2 and ignores due-in-4', () {
    final today = DateTime(2026, 5, 10, 15);
    final obs = DebtSummary.obligations([
      ob(1, 100, due: DateTime(2026, 5, 12)),
      ob(2, 100, due: DateTime(2026, 5, 8)),
      ob(3, 100, due: DateTime(2026, 5, 14)),
    ], {});
    final urgent = DebtSummary.mostUrgent(obs, today)!;
    expect(urgent.status.obligation.id, 2);
    expect(urgent.daysLeft, -2);
    final only4 = DebtSummary.obligations(
        [ob(3, 100, due: DateTime(2026, 5, 14))], {});
    expect(DebtSummary.mostUrgent(only4, today), isNull);
  });

  test('mostUrgent is null without due dates', () {
    final obs = DebtSummary.obligations([ob(1, 100)], {});
    expect(DebtSummary.mostUrgent(obs, DateTime(2026, 5, 10)), isNull);
  });

  test('mostUrgent ignores paid obligations', () {
    final obs = DebtSummary.obligations(
        [ob(1, 100, due: DateTime(2026, 5, 9))], {1: 100});
    expect(DebtSummary.mostUrgent(obs, DateTime(2026, 5, 10)), isNull);
  });

  test('daysUntil across a year boundary', () {
    final due = DateTime(2027, 1, 1);
    expect(DebtSummary.daysUntil(due, DateTime(2026, 12, 31, 23)), 1);
    expect(DebtSummary.daysUntil(due, DateTime(2027, 1, 2)), -1);
  });

  test('settledRemaining adds what I am owed and subtracts what I owe', () {
    const totals = DebtTotals(owedToMe: 1477000, iOwe: 539950);
    expect(DebtSummary.settledRemaining(412500, totals), 1349550);
  });
}
