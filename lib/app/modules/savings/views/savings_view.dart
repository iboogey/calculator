import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../widgets/money_text.dart';
import '../controllers/savings_controller.dart';
import '../widgets/goal_card.dart';

class SavingsView extends GetView<SavingsController> {
  const SavingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المدخرات')),
      body: Obx(() {
        final goals = controller.goals.toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('مجموع المدخرات',
                      style: TextStyle(color: AppColors.onPrimaryMuted, fontSize: 13)),
                  const SizedBox(height: 4),
                  MoneyText(controller.total.value,
                      currency: controller.currency,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            for (final goal in goals) ...[
              GoalCard(
                progress: goal,
                currency: controller.currency,
                monthlyNeeded: controller.monthlyNeeded(goal),
                onTap: () => controller.openGoal(goal),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      }),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: controller.openAddGoal,
        icon: const Icon(Icons.add),
        label: const Text('هدف جديد'),
      ),
    );
  }
}
