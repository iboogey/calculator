import 'package:flutter/material.dart';

import '../../../core/logic/budget_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../widgets/category_avatar.dart';
import '../../../widgets/money_text.dart';

/// One category's budget: spent / limit, a colored bar and a hint.
class BudgetProgressTile extends StatelessWidget {
  const BudgetProgressTile({
    super.key,
    required this.status,
    required this.currency,
    this.onTap,
  });

  final BudgetStatus status;
  final Currency currency;
  final VoidCallback? onTap;

  Color get _color => switch (status.level) {
        BudgetLevel.normal => AppColors.primary,
        BudgetLevel.warning => AppColors.warning,
        BudgetLevel.over => AppColors.danger,
      };

  String? get _hint => switch (status.level) {
        BudgetLevel.normal => null,
        BudgetLevel.warning =>
          'قرّبت توصل للحد — باقي ${MoneyText.label(status.remaining, currency)}',
        BudgetLevel.over =>
          'تجاوزت الميزانية بـ ${MoneyText.label(-status.remaining, currency)}',
      };

  @override
  Widget build(BuildContext context) {
    final hint = _hint;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CategoryAvatar(category: status.category, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(status.category.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text(
                  '${MoneyText.label(status.spent, currency, showSymbol: false)} / '
                  '${MoneyText.label(status.limit, currency, showSymbol: false)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: status.progress,
                minHeight: 8,
                color: _color,
                backgroundColor: AppColors.divider,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(hint, style: TextStyle(color: _color, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
