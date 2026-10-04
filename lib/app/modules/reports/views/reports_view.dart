import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/app_bottom_nav.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/period_switcher.dart';
import '../controllers/reports_controller.dart';
import '../widgets/category_donut.dart';
import '../widgets/period_bars.dart';

class ReportsView extends GetView<ReportsController> {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() {
          final period = controller.period.value;
          return period == null
              ? const Text('التقارير')
              : PeriodSwitcher(
                  period: period,
                  onPrevious: controller.previousPeriod,
                  onNext: controller.nextPeriod,
                );
        }),
      ),
      body: Obx(() {
        final shares = controller.shares.toList();
        final totals = controller.totals.toList();
        final change = controller.change.value;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: shares.isEmpty
                    ? const EmptyState(
                        icon: Icons.pie_chart_outline,
                        message: 'ما في مصاريف بهالفترة',
                      )
                    : CategoryDonut(
                        shares: shares,
                        total: controller.totalSpent.value,
                        currency: controller.currency,
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('مقارنة آخر 6 شهور',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        if (change != null)
                          Text(
                            change >= 0
                                ? '↑ $change% عن الشهر الماضي'
                                : '↓ ${-change}% عن الشهر الماضي',
                            style: TextStyle(
                              fontSize: 12,
                              color: change > 0 ? AppColors.expense : AppColors.income,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (totals.isNotEmpty) PeriodBars(totals: totals),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: controller.openSavings,
              icon: const Icon(Icons.savings_outlined),
              label: const Text('المدخرات والأهداف'),
            ),
          ],
        );
      }),
      bottomNavigationBar: const AppBottomNav(current: Routes.reports),
    );
  }
}
