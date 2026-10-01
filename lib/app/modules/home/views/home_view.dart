import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/app_bottom_nav.dart';
import '../../../widgets/section_header.dart';
import '../controllers/home_controller.dart';
import '../widgets/balance_card.dart';
import '../widgets/recent_transactions.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          final summary = controller.summary.value;
          final period = controller.period.value;
          if (summary == null || period == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            children: [
              const Text('الشهر المالي',
                  style: TextStyle(color: AppColors.muted, fontSize: 13)),
              Text(period.label,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              BalanceCard(summary: summary, currency: controller.currency),
              const SizedBox(height: 24),
              SectionHeader(
                title: 'آخر العمليات',
                actionLabel: 'عرض الكل',
                onAction: controller.openAll,
              ),
              const SizedBox(height: 8),
              RecentTransactions(
                transactions: controller.recent.toList(),
                categoriesById: Map.of(controller.categoriesById),
                currency: controller.currency,
                today: controller.today,
                onTap: controller.openEdit,
              ),
            ],
          );
        }),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'إضافة عملية',
        onPressed: controller.openAdd,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: const AppBottomNav(current: Routes.home),
    );
  }
}
