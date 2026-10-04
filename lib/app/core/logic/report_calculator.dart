import '../../data/models/enums.dart';
import '../../data/models/transaction_category.dart';
import '../../data/models/transaction_record.dart';
import 'period.dart';

class CategoryShare {
  const CategoryShare({
    required this.category,
    required this.amount,
    required this.percent,
  });

  final TransactionCategory category;
  final int amount;
  final int percent;
}

class PeriodTotals {
  const PeriodTotals({
    required this.period,
    required this.income,
    required this.expenses,
  });

  final Period period;
  final int income;
  final int expenses;
}

abstract final class ReportCalculator {
  /// Expenses of [period] per category, largest first. Empty when nothing
  /// was spent.
  static List<CategoryShare> byCategory({
    required Period period,
    required Iterable<TransactionRecord> transactions,
    required Map<int, TransactionCategory> categoriesById,
  }) {
    final sums = <int, int>{};
    for (final t in transactions) {
      if (t.kind != TransactionKind.expense || !period.contains(t.date)) continue;
      sums[t.categoryId] = (sums[t.categoryId] ?? 0) + t.amount;
    }
    final total = sums.values.fold(0, (a, b) => a + b);
    if (total == 0) return const [];
    final shares = [
      for (final MapEntry(key: id, value: amount) in sums.entries)
        if (categoriesById[id] case final category?)
          CategoryShare(
            category: category,
            amount: amount,
            percent: (amount * 100 / total).round(),
          ),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    return shares;
  }

  /// Income and expenses of the [count] periods ending with [last], oldest
  /// first.
  static List<PeriodTotals> totals({
    required Period last,
    required int count,
    required Iterable<TransactionRecord> transactions,
  }) {
    final periods = <Period>[last];
    while (periods.length < count) {
      periods.insert(0, periods.first.previous);
    }
    return [
      for (final period in periods)
        PeriodTotals(
          period: period,
          income: _sum(transactions, period, TransactionKind.income),
          expenses: _sum(transactions, period, TransactionKind.expense),
        ),
    ];
  }

  /// Percent change from [previous] to [current]; null when [previous] is 0.
  static int? changePercent({required int previous, required int current}) =>
      previous == 0 ? null : ((current - previous) * 100 / previous).round();

  static int _sum(
    Iterable<TransactionRecord> transactions,
    Period period,
    TransactionKind kind,
  ) =>
      transactions
          .where((t) => t.kind == kind && period.contains(t.date))
          .fold(0, (sum, t) => sum + t.amount);
}
