import 'package:flutter/material.dart';

import '../../../core/logic/balance_calculator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../widgets/money_text.dart';

/// "Remaining from salary" with this period's breakdown.
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.summary, required this.currency});

  final BalanceSummary summary;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('المتبقي من الراتب',
              style: TextStyle(color: AppColors.onPrimaryMuted, fontSize: 13)),
          const SizedBox(height: 4),
          MoneyText(
            summary.remaining,
            currency: currency,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: summary.remaining < 0
                  ? AppColors.negativeOnDark
                  : Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Stat(
                    label: 'الدخل',
                    amount: summary.income,
                    currency: currency,
                    showPlus: true),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Stat(
                    label: 'المصاريف',
                    amount: -summary.expenses,
                    currency: currency),
              ),
            ],
          ),
          if (summary.carriedOver != 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('مرحّل من الفترة الماضية: ',
                    style: TextStyle(color: AppColors.onPrimaryMuted, fontSize: 12)),
                MoneyText(summary.carriedOver,
                    currency: currency,
                    showPlus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.amount,
    required this.currency,
    this.showPlus = false,
  });

  final String label;
  final int amount;
  final Currency currency;
  final bool showPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.onPrimaryMuted, fontSize: 12)),
          const SizedBox(height: 2),
          MoneyText(amount,
              currency: currency,
              showPlus: showPlus,
              showSymbol: false,
              style: const TextStyle(
                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
