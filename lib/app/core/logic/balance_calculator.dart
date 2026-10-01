import '../../data/models/enums.dart';
import '../../data/models/savings_movement.dart';
import '../../data/models/transaction_record.dart';
import 'period.dart';

/// The numbers on the Home card for one period (spec §6.3).
class BalanceSummary {
  const BalanceSummary({
    required this.carriedOver,
    required this.income,
    required this.expenses,
    required this.saved,
    required this.totalSavings,
  });

  /// Money left from earlier periods that was not moved to savings.
  final int carriedOver;
  final int income;
  final int expenses;

  /// Net amount moved to savings during the period (negative after a
  /// withdrawal).
  final int saved;

  /// Everything held in savings at the end of the period.
  final int totalSavings;

  /// "Remaining from salary".
  int get remaining => carriedOver + income - expenses - saved;

  /// "Total you have".
  int get total => remaining + totalSavings;
}

abstract final class BalanceCalculator {
  static BalanceSummary calculate({
    required Period period,
    required Iterable<TransactionRecord> transactions,
    required Iterable<SavingsMovement> movements,
  }) {
    var carriedOver = 0;
    var income = 0;
    var expenses = 0;
    var saved = 0;
    var totalSavings = 0;

    for (final t in transactions) {
      if (!t.date.isBefore(period.end)) continue;
      if (t.date.isBefore(period.start)) {
        carriedOver += t.signedAmount;
      } else if (t.kind == TransactionKind.income) {
        income += t.amount;
      } else {
        expenses += t.amount;
      }
    }

    for (final m in movements) {
      if (!m.date.isBefore(period.end)) continue;
      totalSavings += m.amount;
      if (m.date.isBefore(period.start)) {
        carriedOver -= m.amount;
      } else {
        saved += m.amount;
      }
    }

    return BalanceSummary(
      carriedOver: carriedOver,
      income: income,
      expenses: expenses,
      saved: saved,
      totalSavings: totalSavings,
    );
  }
}
