import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';

/// The amount being typed, e.g. "7.25 د.أ".
class AmountDisplay extends StatelessWidget {
  const AmountDisplay({super.key, required this.text, required this.currency});

  final String text;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final shown = text.isEmpty ? '0' : text;
    return Column(
      children: [
        const Text('المبلغ', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 4),
        Text(
          '\u2066$shown\u2069 ${currency.symbol}',
          style: const TextStyle(
              fontSize: 36, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
      ],
    );
  }
}
