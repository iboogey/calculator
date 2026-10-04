import 'package:flutter/material.dart';

import '../../../core/logic/budget_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../widgets/money_text.dart';

class BudgetAlertBanner extends StatelessWidget {
  const BudgetAlertBanner({
    super.key,
    required this.status,
    required this.currency,
    required this.onTap,
  });

  final BudgetStatus status;
  final Currency currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final over = status.level == BudgetLevel.over;
    final message = over
        ? 'تجاوزت ميزانية ${status.category.name} بـ ${MoneyText.label(-status.remaining, currency)}'
        : 'صرفت ${status.percent}% من ميزانية ${status.category.name}';
    return Material(
      color: AppColors.warningSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFF5C9A6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: over ? AppColors.danger : AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message,
                    style: const TextStyle(color: AppColors.danger, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
