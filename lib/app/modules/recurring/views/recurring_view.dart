import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/enums.dart';
import '../../../widgets/category_avatar.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/money_text.dart';
import '../controllers/recurring_controller.dart';

class RecurringView extends GetView<RecurringController> {
  const RecurringView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المصاريف الثابتة')),
      body: Obx(() {
        final rules = controller.rules.toList();
        final categories = Map.of(controller.categoriesById);
        if (rules.isEmpty) {
          return const EmptyState(
            icon: Icons.event_repeat_outlined,
            message: 'أضف الإيجار، الإنترنت أو الراتب مرة وحدة، والتطبيق بيسجّلها كل شهر لحاله.',
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
          children: [
            Card(
              child: Column(
                children: [
                  for (final (index, rule) in rules.indexed) ...[
                    if (index > 0) const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      onTap: () => controller.openEdit(rule),
                      leading: categories[rule.categoryId] == null
                          ? null
                          : CategoryAvatar(category: categories[rule.categoryId]!),
                      title: Text(rule.label,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        rule.isActive
                            ? 'كل شهر يوم ${rule.dayOfMonth} · الجاي: '
                                '${ArabicDates.relativeDay(controller.nextDue(rule), today: controller.today)}'
                            : 'موقوفة',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MoneyText(
                            rule.kind == RecurringKind.income ? rule.amount : -rule.amount,
                            currency: controller.currency,
                            showPlus: true,
                            showSymbol: false,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: rule.kind == RecurringKind.income
                                  ? AppColors.income
                                  : AppColors.expense,
                            ),
                          ),
                          Switch(
                            value: rule.isActive,
                            onChanged: (_) => controller.toggleActive(rule),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      }),
      floatingActionButton: FloatingActionButton(
        tooltip: 'إضافة مصروف ثابت',
        onPressed: controller.openAdd,
        child: const Icon(Icons.add),
      ),
    );
  }
}
