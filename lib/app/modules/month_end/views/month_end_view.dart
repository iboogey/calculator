import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../widgets/money_text.dart';
import '../controllers/month_end_controller.dart';

class MonthEndView extends GetView<MonthEndController> {
  const MonthEndView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('وزّع اللي ضل معك')),
      body: SafeArea(
        child: Obx(() {
          final goals = controller.goals.toList();
          final offered = controller.offered.value;
          final allocated = controller.allocated.value;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('ضل معك من الشهر الماضي ${MoneyText.label(offered, controller.currency)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'وزّعت ${MoneyText.label(allocated, controller.currency)} · باقي ${MoneyText.label(offered - allocated, controller.currency)}',
                style: TextStyle(
                    color: allocated > offered ? AppColors.danger : AppColors.muted,
                    fontSize: 13),
              ),
              const SizedBox(height: 16),
              for (final goal in goals) ...[
                TextField(
                  controller: controller.controllerFor(goal.id!),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: goal.name,
                    suffixText: controller.currency.symbol,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextButton(
                onPressed: controller.putAllInGeneral,
                child: const Text('حط الكل بالادخار العام'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: controller.canSave ? _save : null,
                child: const Text('حفظ'),
              ),
              TextButton(onPressed: _skip, child: const Text('مش هلأ — خليهم مرحّلين')),
            ],
          );
        }),
      ),
    );
  }

  Future<void> _save() async {
    if (await controller.save()) Get.back();
  }

  Future<void> _skip() async {
    await controller.skip();
    Get.back();
  }
}
