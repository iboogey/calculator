import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../data/models/quick_template.dart';
import '../../../widgets/money_text.dart';

/// One-tap favorites: "قهوة · 1.500".
class QuickTemplatesRow extends StatelessWidget {
  const QuickTemplatesRow({
    super.key,
    required this.favorites,
    required this.currency,
    required this.onTap,
  });

  final List<QuickTemplate> favorites;
  final Currency currency;
  final ValueChanged<QuickTemplate> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: favorites.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final favorite = favorites[index];
          return ActionChip(
            backgroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.border),
            shape: const StadiumBorder(),
            label: Text(
                '${favorite.label} · ${MoneyText.label(favorite.amount, currency, showSymbol: false)}'),
            onPressed: () => onTap(favorite),
          );
        },
      ),
    );
  }
}
