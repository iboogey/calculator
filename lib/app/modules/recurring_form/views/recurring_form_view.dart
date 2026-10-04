import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../widgets/category_grid.dart';
import '../../../widgets/kind_toggle.dart';
import '../controllers/recurring_form_controller.dart';

class RecurringFormView extends GetView<RecurringFormController> {
  const RecurringFormView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(
            controller.isEditing.value ? 'تعديل مصروف ثابت' : 'مصروف ثابت جديد')),
        actions: [
          Obx(() => controller.isEditing.value
              ? IconButton(
                  tooltip: 'حذف',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context),
                )
              : const SizedBox.shrink()),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Obx(() => KindToggle(
                value: controller.kind.value, onChanged: controller.setKind)),
            const SizedBox(height: 16),
            TextField(
              controller: controller.labelController,
              decoration: const InputDecoration(
                labelText: 'الاسم (اختياري)',
                hintText: 'مثلاً إيجار',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller.amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'المبلغ',
                suffixText: controller.currency.symbol,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('ينحسب كل شهر يوم')),
                Obx(() => DropdownButton<int>(
                      value: controller.dayOfMonth.value,
                      items: [
                        for (var day = 1; day <= 28; day++)
                          DropdownMenuItem(value: day, child: Text('$day')),
                      ],
                      onChanged: (day) {
                        if (day != null) controller.setDay(day);
                      },
                    )),
              ],
            ),
            const SizedBox(height: 12),
            const Text('التصنيف',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 8),
            Obx(() => CategoryGrid(
                  categories: controller.visibleCategories,
                  selectedId: controller.categoryId.value,
                  onSelected: controller.selectCategory,
                )),
            const SizedBox(height: 20),
            Obx(() => FilledButton(
                  onPressed: controller.canSave ? _save : null,
                  child: const Text('حفظ'),
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (await controller.save()) Get.back();
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المصروف الثابت؟'),
        content: const Text('العمليات اللي انسجلت قبل بتضل موجودة.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed == true && await controller.delete()) Get.back();
  }
}
