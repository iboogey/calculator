import '../../data/models/budget.dart';
import '../../data/models/enums.dart';
import '../../data/models/transaction_category.dart';
import '../../data/models/transaction_record.dart';
import 'period.dart';

enum BudgetLevel { normal, warning, over }

/// How much of one category's monthly budget is used (spec §6.6).
class BudgetStatus {
  const BudgetStatus({
    required this.category,
    required this.limit,
    required this.spent,
  });

  static const warningPercent = 80;

  final TransactionCategory category;
  final int limit;
  final int spent;

  BudgetLevel get level {
    if (spent >= limit) return BudgetLevel.over;
    if (spent * 100 >= limit * warningPercent) return BudgetLevel.warning;
    return BudgetLevel.normal;
  }

  /// 0.0–1.0, for progress bars.
  double get progress => limit <= 0 ? 0 : (spent / limit).clamp(0.0, 1.0);

  int get percent => limit <= 0 ? 0 : spent * 100 ~/ limit;

  /// Negative when over budget.
  int get remaining => limit - spent;

  /// The alert thresholds (80 and/or 100) this status has reached.
  List<int> get reachedThresholds => [
        if (level != BudgetLevel.normal) warningPercent,
        if (level == BudgetLevel.over) 100,
      ];
}

abstract final class BudgetCalculator {
  /// One status per budget whose category exists, most used (by ratio) first.
  static List<BudgetStatus> calculate({
    required Period period,
    required Iterable<Budget> budgets,
    required Map<int, TransactionCategory> categoriesById,
    required Iterable<TransactionRecord> transactions,
  }) {
    final spent = <int, int>{};
    for (final t in transactions) {
      if (t.kind != TransactionKind.expense || !period.contains(t.date)) continue;
      spent[t.categoryId] = (spent[t.categoryId] ?? 0) + t.amount;
    }
    final statuses = [
      for (final budget in budgets)
        if (categoriesById[budget.categoryId] case final category?)
          BudgetStatus(
            category: category,
            limit: budget.limitAmount,
            spent: spent[budget.categoryId] ?? 0,
          ),
    ];
    statuses.sort((a, b) => (b.spent * a.limit).compareTo(a.spent * b.limit));
    return statuses;
  }

  /// The most used status that is at warning or over, if any.
  static BudgetStatus? mostUrgent(List<BudgetStatus> statuses) {
    BudgetStatus? urgent;
    for (final status in statuses) {
      if (status.level == BudgetLevel.normal) continue;
      if (urgent == null || status.spent * urgent.limit > urgent.spent * status.limit) {
        urgent = status;
      }
    }
    return urgent;
  }
}
