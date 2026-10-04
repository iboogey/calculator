import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/currencies.dart';
import '../data/models/enums.dart';
import '../data/models/transaction_category.dart';
import '../data/models/transaction_record.dart';
import 'category_avatar.dart';
import 'money_text.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.category,
    required this.currency,
    required this.subtitle,
    this.onTap,
  });

  final TransactionRecord transaction;
  final TransactionCategory? category;
  final Currency currency;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.kind == TransactionKind.income;
    return ListTile(
      onTap: onTap,
      leading: category == null ? null : CategoryAvatar(category: category!),
      title: Text(category?.name ?? '—',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      trailing: MoneyText(
        transaction.signedAmount,
        currency: currency,
        showPlus: true,
        showSymbol: false,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: isIncome ? AppColors.income : AppColors.expense,
        ),
      ),
    );
  }
}
