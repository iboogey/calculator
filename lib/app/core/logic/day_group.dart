import '../../data/models/transaction_record.dart';
import '../utils/date_utils.dart';

/// Transactions of one calendar day, for the grouped list.
class DayGroup {
  const DayGroup({required this.day, required this.transactions});

  final DateTime day;
  final List<TransactionRecord> transactions;

  int get net => transactions.fold(0, (sum, t) => sum + t.signedAmount);

  /// Groups [items] by day, newest day first. Order inside a day is kept
  /// newest first as well.
  static List<DayGroup> group(Iterable<TransactionRecord> items) {
    final sorted = items.toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
      });
    final groups = <DayGroup>[];
    for (final t in sorted) {
      final day = DateKeys.dateOnly(t.date);
      if (groups.isEmpty || groups.last.day != day) {
        groups.add(DayGroup(day: day, transactions: [t]));
      } else {
        groups.last.transactions.add(t);
      }
    }
    return groups;
  }
}
