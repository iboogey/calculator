import 'package:flutter/material.dart';

import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/models/transaction_record.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/transaction_tile.dart';

class RecentTransactions extends StatelessWidget {
  const RecentTransactions({
    super.key,
    required this.transactions,
    required this.categoriesById,
    required this.currency,
    required this.today,
    required this.onTap,
  });

  final List<TransactionRecord> transactions;
  final Map<int, TransactionCategory> categoriesById;
  final Currency currency;
  final DateTime today;
  final ValueChanged<TransactionRecord> onTap;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        message: 'لسا ما سجلت أي عملية. اضغط + لتبدأ',
      );
    }
    return Card(
      child: Column(
        children: [
          for (final (index, t) in transactions.indexed) ...[
            if (index > 0) const Divider(indent: 16, endIndent: 16),
            TransactionTile(
              transaction: t,
              category: categoriesById[t.categoryId],
              currency: currency,
              subtitle: ArabicDates.relativeDay(t.date, today: today),
              onTap: () => onTap(t),
            ),
          ],
        ],
      ),
    );
  }
}
