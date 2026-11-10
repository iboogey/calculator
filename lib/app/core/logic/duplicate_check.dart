import '../../data/models/enums.dart';
import '../../data/models/recurring_rule.dart';
import '../../data/models/transaction_record.dart';
import '../utils/date_utils.dart';

/// Decides whether an imported income/expense may already be recorded, either
/// by a recurring rule that is due around the same day or by an existing
/// transaction with the same amount on (almost) the same day.
abstract final class DuplicateCheck {
  static const _ruleToleranceDays = 3;
  static const _transactionToleranceDays = 1;
  static const _fallbackLabel = 'عملية مسجّلة';

  /// Returns the label to show after "قد يكون مسجّلًا مسبقًا: ", or null.
  /// A matching rule wins over a matching transaction.
  static String? find({
    required TransactionKind kind,
    required int amount,
    required DateTime date,
    required List<RecurringRule> rules,
    required List<TransactionRecord> transactions,
  }) {
    final day = DateKeys.dateOnly(date);

    for (final rule in rules) {
      if (!rule.isActive || rule.amount != amount) continue;
      if (_kindOf(rule.kind) != kind) continue;
      if (_ruleDueNear(rule, day)) return rule.label;
    }

    for (final tx in transactions) {
      if (tx.kind != kind || tx.amount != amount) continue;
      if (_daysBetween(tx.date, day) <= _transactionToleranceDays) {
        final note = tx.note?.trim();
        return note == null || note.isEmpty ? _fallbackLabel : note;
      }
    }
    return null;
  }

  static TransactionKind? _kindOf(RecurringKind kind) => switch (kind) {
    RecurringKind.income => TransactionKind.income,
    RecurringKind.expense => TransactionKind.expense,
    RecurringKind.saving => null,
  };

  static bool _ruleDueNear(RecurringRule rule, DateTime day) {
    final start = DateKeys.dateOnly(rule.startDate);
    for (var k = -1; k <= 1; k++) {
      final due = DateTime(day.year, day.month + k, rule.dayOfMonth);
      if (due.isBefore(start)) continue;
      if (_daysBetween(due, day) <= _ruleToleranceDays) return true;
    }
    return false;
  }

  /// Whole-day distance, computed in UTC so DST shifts cannot skew it.
  static int _daysBetween(DateTime a, DateTime b) {
    final x = DateTime.utc(a.year, a.month, a.day);
    final y = DateTime.utc(b.year, b.month, b.day);
    return x.difference(y).inDays.abs();
  }
}
