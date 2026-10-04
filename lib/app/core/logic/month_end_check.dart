import '../../data/models/savings_movement.dart';
import '../../data/models/transaction_record.dart';
import 'balance_calculator.dart';
import 'period.dart';

abstract final class MonthEndCheck {
  /// What was left at the end of the period before [current], when the user
  /// has not answered the month-end question for it yet (spec §6.4).
  static int? leftoverToOffer({
    required Period current,
    required String? lastPromptedKey,
    required Iterable<TransactionRecord> transactions,
    required Iterable<SavingsMovement> movements,
  }) {
    final previous = current.previous;
    if (lastPromptedKey == previous.key) return null;
    final remaining = BalanceCalculator.calculate(
      period: previous,
      transactions: transactions,
      movements: movements,
    ).remaining;
    return remaining > 0 ? remaining : null;
  }
}
