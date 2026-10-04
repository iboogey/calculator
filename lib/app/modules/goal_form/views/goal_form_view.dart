import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/date_utils.dart';
import '../controllers/goal_form_controller.dart';

class GoalFormView extends GetView<GoalFormController> {
  const GoalFormView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(controller.isEditing.value ? 'تعديل الهدف' : 'هدف جديد')),
        actions: [
          Obx(() => controller.isEditing.value
              ? IconButton(
                  tooltip: 'حذف الهدف',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _remove,
                )
              : const SizedBox.shrink()),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: controller.nameController,
              decoration: const InputDecoration(
                labelText: 'اسم الهدف',
                hintText: 'مثلاً لابتوب أو سفرة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller.targetController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'المبلغ المطلوب (اختياري)',
                suffixText: controller.currency.symbol,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Obx(() {
              final date = controller.targetDate.value;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('بدّي أوصل قبل'),
                subtitle: Text(date == null
                    ? 'بدون تاريخ'
                    : '${ArabicDates.dayMonth(date)} ${date.year}'),
                trailing: date == null
                    ? null
                    : IconButton(
                        tooltip: 'شيل التاريخ',
                        icon: const Icon(Icons.close),
                        onPressed: () => controller.setTargetDate(null),
                      ),
                onTap: () => _pickDate(context),
              );
            }),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: Listenable.merge(
                  [controller.nameController, controller.targetController]),
              builder: (context, _) => FilledButton(
                onPressed: controller.canSave ? _save : null,
                child: const Text('حفظ'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (await controller.save()) Get.back();
  }

  Future<void> _remove() async {
    if (await controller.remove()) Get.back();
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: controller.targetDate.value ?? DateTime(now.year + 1, now.month, 1),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 30),
    );
    if (picked != null) controller.setTargetDate(picked);
  }
}
