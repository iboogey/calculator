import '../../data/models/debt_person.dart';
import '../../data/models/obligation.dart';

/// A person with what they owe me (positive) or I owe them (negative).
class PersonBalance {
  const PersonBalance({required this.person, required this.balance});

  final DebtPerson person;
  final int balance;
}

/// An obligation with how much of it has been paid.
class ObligationStatus {
  const ObligationStatus({required this.obligation, required this.paid});

  final Obligation obligation;
  final int paid;

  int get remaining => obligation.amount - paid;

  bool get isPaid => remaining <= 0;
}

/// An unpaid obligation with the days left until it is due (negative = overdue).
class DueInfo {
  const DueInfo({required this.status, required this.daysLeft});

  final ObligationStatus status;
  final int daysLeft;
}

class DebtTotals {
  const DebtTotals({required this.owedToMe, required this.iOwe});

  final int owedToMe;
  final int iOwe;

  bool get isEmpty => owedToMe == 0 && iOwe == 0;
}

abstract final class DebtSummary {
  /// Non-zero balances first by size, then settled people by name.
  static List<PersonBalance> people(
    List<DebtPerson> people,
    Map<int, int> balances,
  ) {
    final list = [
      for (final p in people)
        PersonBalance(person: p, balance: balances[p.id] ?? 0),
    ];
    list.sort((a, b) {
      final aSettled = a.balance == 0;
      final bSettled = b.balance == 0;
      if (aSettled != bSettled) return aSettled ? 1 : -1;
      if (!aSettled) {
        final bySize = b.balance.abs().compareTo(a.balance.abs());
        if (bySize != 0) return bySize;
      }
      return a.person.name.compareTo(b.person.name);
    });
    return list;
  }

  /// Unpaid first (due date asc, undated last, then created asc), then paid
  /// (newest first).
  static List<ObligationStatus> obligations(
    List<Obligation> list,
    Map<int, int> paid,
  ) {
    final all = [
      for (final o in list)
        ObligationStatus(obligation: o, paid: paid[o.id] ?? 0),
    ];
    all.sort((a, b) {
      if (a.isPaid != b.isPaid) return a.isPaid ? 1 : -1;
      final x = a.obligation;
      final y = b.obligation;
      if (a.isPaid) return y.createdAt.compareTo(x.createdAt);
      if (x.dueDate != null && y.dueDate != null) {
        final byDue = x.dueDate!.compareTo(y.dueDate!);
        if (byDue != 0) return byDue;
      } else if (x.dueDate != null) {
        return -1;
      } else if (y.dueDate != null) {
        return 1;
      }
      return x.createdAt.compareTo(y.createdAt);
    });
    return all;
  }

  static DebtTotals totals(
    List<PersonBalance> people,
    List<ObligationStatus> obligations,
  ) {
    var owedToMe = 0;
    var iOwe = 0;
    for (final p in people) {
      if (p.balance > 0) {
        owedToMe += p.balance;
      } else {
        iOwe -= p.balance;
      }
    }
    for (final o in obligations) {
      if (!o.isPaid) iOwe += o.remaining;
    }
    return DebtTotals(owedToMe: owedToMe, iOwe: iOwe);
  }

  /// Calendar days from [today] to [due]; negative when [due] has passed.
  static int daysUntil(DateTime due, DateTime today) =>
      DateTime.utc(due.year, due.month, due.day)
          .difference(DateTime.utc(today.year, today.month, today.day))
          .inDays;

  /// The unpaid obligation closest to (or past) its due date, if within
  /// [withinDays].
  static DueInfo? mostUrgent(
    List<ObligationStatus> list,
    DateTime today, {
    int withinDays = 3,
  }) {
    DueInfo? best;
    for (final s in list) {
      final due = s.obligation.dueDate;
      if (s.isPaid || due == null) continue;
      final days = daysUntil(due, today);
      if (days <= withinDays && (best == null || days < best.daysLeft)) {
        best = DueInfo(status: s, daysLeft: days);
      }
    }
    return best;
  }

  /// What would remain after collecting everything owed and paying everything due.
  static int settledRemaining(int remaining, DebtTotals totals) =>
      remaining + totals.owedToMe - totals.iOwe;
}
