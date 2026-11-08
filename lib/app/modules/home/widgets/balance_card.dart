import 'package:flutter/material.dart';

import '../../../core/logic/balance_calculator.dart';
import '../../../core/logic/debt_summary.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../widgets/money_text.dart';

/// "Remaining from salary" with this period's breakdown, total savings and
/// everything the user has (spec §6.3).
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.summary,
    required this.currency,
    this.onSavingsTap,
    this.debts,
    this.showSettled = false,
    this.onToggleSettled,
  });

  final BalanceSummary summary;
  final Currency currency;
  final VoidCallback? onSavingsTap;
  final DebtTotals? debts;
  final bool showSettled;
  final VoidCallback? onToggleSettled;

  @override
  Widget build(BuildContext context) {
    String label(int amount) =>
        MoneyText.label(amount, currency, showSymbol: false);
    final totals = debts;
    final hasDebts = totals != null && !totals.isEmpty;
    final settled = showSettled && hasDebts;
    final big = settled
        ? DebtSummary.settledRemaining(summary.remaining, totals)
        : summary.remaining;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(settled ? 'المتبقي بعد تسوية الديون' : 'المتبقي من الراتب',
              style: TextStyle(color: AppColors.onPrimaryMuted, fontSize: 13)),
          const SizedBox(height: 4),
          MoneyText(
            big,
            currency: currency,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: big < 0 ? AppColors.negativeOnDark : Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            settled
                ? 'المتبقي ${label(summary.remaining)} + لي ${label(totals.owedToMe)} − عليّ ${label(totals.iOwe)}'
                : 'دخل ${label(summary.income)} · مصاريف ${label(summary.expenses)}'
                    '${summary.saved == 0 ? '' : ' · للادخار ${label(summary.saved)}'}'
                    '${summary.carriedOver == 0 ? '' : ' · مرحّل ${label(summary.carriedOver)}'}',
            style: const TextStyle(color: AppColors.onPrimaryMuted, fontSize: 12),
          ),
          if (hasDebts)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onToggleSettled,
              child: Text(settled ? 'إخفاء' : 'بعد تسوية الديون'),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'مجموع المدخرات',
                  amount: summary.totalSavings,
                  currency: currency,
                  onTap: onSavingsTap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Stat(
                  label: 'إجمالي ما لديك',
                  amount: summary.total,
                  currency: currency,
                ),
              ),
            ],
          ),
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
    this.onTap,
  });

  final String label;
  final int amount;
  final Currency currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            color: AppColors.onPrimaryMuted, fontSize: 12)),
                  ),
                  if (onTap != null)
                    const Icon(Icons.chevron_right,
                        color: AppColors.onPrimaryMuted, size: 18),
                ],
              ),
              const SizedBox(height: 2),
              MoneyText(amount,
                  currency: currency,
                  showSymbol: false,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
