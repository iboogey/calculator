import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/logic/report_calculator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../widgets/money_text.dart';

/// Spending by category as a donut, with a legend.
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({
    super.key,
    required this.shares,
    required this.total,
    required this.currency,
  });

  final List<CategoryShare> shares;
  final int total;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(PieChartData(
                centerSpaceRadius: 60,
                sectionsSpace: 2,
                startDegreeOffset: -90,
                sections: [
                  for (final share in shares)
                    PieChartSectionData(
                      value: share.amount.toDouble(),
                      color: Color(share.category.colorValue),
                      radius: 26,
                      showTitle: false,
                    ),
                ],
              )),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('المصاريف',
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  MoneyText(total,
                      currency: currency,
                      showSymbol: false,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final share in shares)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Color(share.category.colorValue),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(share.category.name)),
                MoneyText(share.amount,
                    currency: currency,
                    showSymbol: false,
                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 40,
                  child: Text('${share.percent}%',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
