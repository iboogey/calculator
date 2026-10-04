import 'package:flutter/material.dart';

import '../../../core/logic/goal_projection.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../widgets/money_text.dart';

/// One savings pot: what it holds, its target and what to save each month.
class GoalCard extends StatelessWidget {
  const GoalCard({
    super.key,
    required this.progress,
    required this.currency,
    required this.monthlyNeeded,
    required this.onTap,
  });

  final GoalProgress progress;
  final Currency currency;
  final int? monthlyNeeded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final goal = progress.goal;
    final target = progress.target;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(goal.isGeneral ? Icons.savings_outlined : Icons.flag_outlined,
                      color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(goal.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  MoneyText(progress.saved,
                      currency: currency,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              if (target != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.progress,
                    minHeight: 8,
                    color: AppColors.primary,
                    backgroundColor: AppColors.divider,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  progress.isReached
                      ? 'وصلت للهدف'
                      : '${progress.percent}% من ${MoneyText.label(target, currency)}'
                          '${goal.targetDate == null ? '' : ' · قبل ${ArabicDates.dayMonth(goal.targetDate!)} ${goal.targetDate!.year}'}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
              if (monthlyNeeded != null) ...[
                const SizedBox(height: 4),
                Text('وفّر ${MoneyText.label(monthlyNeeded!, currency)} بالشهر لتوصل',
                    style: const TextStyle(color: AppColors.primary, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
