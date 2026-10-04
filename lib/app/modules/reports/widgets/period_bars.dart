import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/logic/report_calculator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';

/// Expenses of the last periods as bars, newest on the left so the months
/// read right-to-left like the rest of the Arabic UI. The shown period is
/// highlighted.
class PeriodBars extends StatelessWidget {
  const PeriodBars({super.key, required this.totals});

  /// Oldest first, as [ReportCalculator.totals] returns them.
  final List<PeriodTotals> totals;

  @override
  Widget build(BuildContext context) {
    final newestFirst = totals.reversed.toList();
    final maxValue = totals.fold(0, (m, t) => t.expenses > m ? t.expenses : m);
    return SizedBox(
      height: 160,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: BarChart(BarChartData(
          maxY: maxValue == 0 ? 1 : maxValue * 1.15,
          alignment: BarChartAlignment.spaceAround,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final period = newestFirst[value.toInt()].period;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(ArabicDates.months[period.start.month - 1],
                        style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (final (index, total) in newestFirst.indexed)
              BarChartGroupData(x: index, barRods: [
                BarChartRodData(
                  toY: total.expenses.toDouble(),
                  width: 22,
                  color: index == 0
                      ? AppColors.primary
                      : const Color(0xFFC8D6D0),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ]),
          ],
        )),
      ),
    );
  }
}
