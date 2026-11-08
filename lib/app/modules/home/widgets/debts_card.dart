import 'package:flutter/material.dart';

import '../../../core/logic/debt_summary.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../widgets/money_text.dart';

/// "Debts" entry point on Home: what people owe me and what I owe.
class DebtsCard extends StatelessWidget {
  const DebtsCard({
    super.key,
    required this.totals,
    required this.currency,
    required this.onTap,
  });

  final DebtTotals totals;
  final Currency currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final line = totals.isEmpty
        ? 'سجّل ديونك والتزاماتك'
        : 'المستحق لي ${MoneyText.label(totals.owedToMe, currency)}'
            ' · المستحق عليّ ${MoneyText.label(totals.iOwe, currency)}';
    return Material(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.handshake_outlined, color: AppColors.primaryDark),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الديون',
                        style: TextStyle(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(line,
                        style: const TextStyle(
                            color: AppColors.primaryDark, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.primaryDark),
            ],
          ),
        ),
      ),
    );
  }
}
