import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/logic/budget_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/transaction_category.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/app_bottom_nav.dart';
import '../../../widgets/category_avatar.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/section_header.dart';
import '../controllers/budgets_controller.dart';
import '../widgets/budget_progress_tile.dart';
import '../widgets/recurring_summary.dart';

class BudgetsView extends GetView<BudgetsController> {
  const BudgetsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الميزانية')),
      body: Obx(() {
        final period = controller.period.value;
        if (period == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final statuses = controller.statuses.toList();
        final rules = controller.rules.toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text('${period.label} · باقي ${controller.daysLeft} يوم',
                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 12),
            if (statuses.isEmpty)
              const EmptyState(
                icon: Icons.donut_large_outlined,
                message: 'ما حطيت ميزانية لأي تصنيف لسا.',
              )
            else
              Card(
                child: Column(
                  children: [
                    for (final (index, status) in statuses.indexed) ...[
                      if (index > 0) const Divider(indent: 16, endIndent: 16),
                      BudgetProgressTile(
                        status: status,
                        currency: controller.currency,
                        onTap: () => _editLimit(context, status.category, status),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 8),
            if (controller.unbudgeted.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _pickCategory(context),
                icon: const Icon(Icons.add),
                label: const Text('إضافة ميزانية'),
              ),
            const SizedBox(height: 24),
            SectionHeader(
              title: 'مصاريف ثابتة — تنحسب تلقائياً',
              actionLabel: 'إدارة',
              onAction: controller.openRecurring,
            ),
            const SizedBox(height: 8),
            RecurringSummary(
              rules: rules,
              currency: controller.currency,
              nextDue: controller.nextDue,
              today: controller.today,
            ),
          ],
        );
      }),
      bottomNavigationBar: const AppBottomNav(current: Routes.budgets),
    );
  }

  Future<void> _pickCategory(BuildContext context) async {
    final category = await showModalBottomSheet<TransactionCategory>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final category in controller.unbudgeted)
              ListTile(
                leading: CategoryAvatar(category: category, size: 36),
                title: Text(category.name),
                onTap: () => Navigator.pop(context, category),
              ),
          ],
        ),
      ),
    );
    if (category != null && context.mounted) {
      await _editLimit(context, category, null);
    }
  }

  Future<void> _editLimit(
    BuildContext context,
    TransactionCategory category,
    BudgetStatus? current,
  ) async {
    final input = TextEditingController(
        text: current == null ? '' : Money.toEditable(current.limit));
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ميزانية ${category.name} الشهرية'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: 'المبلغ',
            suffixText: controller.currency.symbol,
          ),
        ),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () => Navigator.pop(context, 'remove'),
              child: const Text('حذف الميزانية'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('حفظ')),
        ],
      ),
    );
    final text = input.text;
    input.dispose();
    if (action == 'remove') {
      await controller.removeLimit(category.id!);
    } else if (action == 'save') {
      final saved = await controller.setLimit(category.id!, text);
      if (!saved && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('اكتب مبلغ أكبر من صفر')));
      }
    }
  }
}
