import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/quick_template.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/app_bottom_nav.dart';
import '../../../widgets/section_header.dart';
import '../controllers/home_controller.dart';
import '../widgets/balance_card.dart';
import '../widgets/budget_alert_banner.dart';
import '../widgets/month_end_banner.dart';
import '../widgets/quick_templates_row.dart';
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
          final urgent = controller.urgentBudget.value;
          final favorites = controller.favorites.toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            children: [
              const Text('الشهر المالي',
                  style: TextStyle(color: AppColors.muted, fontSize: 13)),
              Text(period.label,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              BalanceCard(
                summary: summary,
                currency: controller.currency,
                onSavingsTap: controller.openSavings,
              ),
              if (controller.monthEndOffer.value case final offer?) ...[
                const SizedBox(height: 12),
                MonthEndBanner(
                  amount: offer,
                  currency: controller.currency,
                  onSplit: controller.openMonthEnd,
                  onSkip: controller.skipMonthEnd,
                ),
              ],
              if (urgent != null) ...[
                const SizedBox(height: 12),
                BudgetAlertBanner(
                  status: urgent,
                  currency: controller.currency,
                  onTap: controller.openBudgets,
                ),
              ],
              if (favorites.isNotEmpty) ...[
                const SizedBox(height: 20),
                SectionHeader(
                  title: 'مفضّلة — بضغطة وحدة',
                  actionLabel: 'تعديل',
                  onAction: controller.openFavorites,
                ),
                const SizedBox(height: 4),
                QuickTemplatesRow(
                  favorites: favorites,
                  currency: controller.currency,
                  onTap: (favorite) => _addFavorite(context, favorite),
                ),
              ],
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

  Future<void> _addFavorite(BuildContext context, QuickTemplate favorite) async {
    final home = controller;
    final messenger = ScaffoldMessenger.of(context);
    final added = await home.addFavorite(favorite);
    if (added == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('انضافت: ${favorite.label}'),
        action: SnackBarAction(
          label: 'تراجع',
          onPressed: () => home.undoFavorite(added),
        ),
      ));
  }
}
