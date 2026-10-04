import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../widgets/money_text.dart';

/// "Last month ended with X left — move some to savings?"
class MonthEndBanner extends StatelessWidget {
  const MonthEndBanner({
    super.key,
    required this.amount,
    required this.currency,
    required this.onSplit,
    required this.onSkip,
  });

  final int amount;
  final Currency currency;
  final VoidCallback onSplit;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'خلص الشهر الماضي وضل معك ${MoneyText.label(amount, currency)}. بدك تحوّل منهم للادخار؟',
            style: const TextStyle(color: AppColors.primaryDark, fontSize: 13),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onSkip, child: const Text('مش هلأ')),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: onSplit,
                child: const Text('وزّع'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
