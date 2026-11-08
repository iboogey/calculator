import 'package:flutter/material.dart';

import '../../../core/logic/debt_summary.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../widgets/money_text.dart';

/// "Rent (350.000) is due in 2 days" for the most urgent obligation.
class DueObligationBanner extends StatelessWidget {
  const DueObligationBanner({
    super.key,
    required this.due,
    required this.currency,
    required this.onTap,
  });

  final DueInfo due;
  final Currency currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final overdue = due.daysLeft < 0;
    final status = due.status;
    final subject =
        '${status.obligation.title} (${MoneyText.label(status.remaining, currency)})';
    final message = overdue
        ? '$subject ${ArabicDates.dueLabel(due.daysLeft)}'
        : 'يستحق $subject ${ArabicDates.dueLabel(due.daysLeft)}';
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
              Icon(Icons.event_busy_outlined,
                  color: overdue ? AppColors.danger : AppColors.warning),
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
