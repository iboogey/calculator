import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/enums.dart';
import '../../../widgets/amount_dialog.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/money_text.dart';
import '../controllers/goal_detail_controller.dart';

class GoalDetailView extends GetView<GoalDetailController> {
  const GoalDetailView({super.key});

  static const _sourceLabels = {
    SavingsSource.manual: 'يدوي',
    SavingsSource.monthEnd: 'من آخر الشهر',
    SavingsSource.recurring: 'تلقائي',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(controller.goal.value?.name ?? '')),
        actions: [
          Obx(() => controller.goal.value?.isGeneral ?? true
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'تعديل الهدف',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: controller.openEdit,
                )),
        ],
      ),
      body: Obx(() {
        final goal = controller.goal.value;
        if (goal == null) return const Center(child: CircularProgressIndicator());
        final movements = controller.movements.toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Center(
              child: Column(
                children: [
                  const Text('بالهدف هلأ',
                      style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  MoneyText(controller.saved.value,
                      currency: controller.currency,
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
                  if (goal.targetAmount != null)
                    Text('من ${MoneyText.label(goal.targetAmount!, controller.currency)}',
                        style: const TextStyle(color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _ask(context, 'إضافة للهدف', controller.deposit),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => _ask(context, 'سحب من الهدف', controller.withdraw),
                    icon: const Icon(Icons.remove),
                    label: const Text('سحب'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('الحركات', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            if (movements.isEmpty)
              const EmptyState(icon: Icons.history, message: 'ما في حركات لسا')
            else
              Card(
                child: Column(
                  children: [
                    for (final (index, m) in movements.indexed) ...[
                      if (index > 0) const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        title: Text(_sourceLabels[m.source]!),
                        subtitle: Text(
                            ArabicDates.relativeDay(m.date, today: controller.today)),
                        trailing: MoneyText(m.amount,
                            currency: controller.currency,
                            showPlus: true,
                            showSymbol: false,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: m.amount > 0 ? AppColors.income : AppColors.expense,
                            )),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }

  Future<void> _ask(
    BuildContext context,
    String title,
    Future<bool> Function(String text) action,
  ) async {
    final result = await showDialog<AmountDialogResult>(
      context: context,
      builder: (_) => AmountDialog(title: title, currency: controller.currency),
    );
    if (result is SaveAmount) await action(result.text);
  }
}
