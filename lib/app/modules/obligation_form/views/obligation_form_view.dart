import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/date_utils.dart';
import '../../../widgets/amount_field.dart';
import '../controllers/obligation_form_controller.dart';

class ObligationFormView extends GetView<ObligationFormController> {
  const ObligationFormView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(
            controller.isEditing.value ? 'تعديل الالتزام' : 'التزام جديد')),
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
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  AmountField(
                    controller: controller.amountController,
                    currency: controller.currency,
                    decimals: () => controller.inputDecimals,
                    autofocus: controller.editId == null,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller.titleController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'لمن أو ما هو؟',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  Obx(() {
                    final titles = controller.recentTitles.toList();
                    if (titles.isEmpty) return const SizedBox(height: 12);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final t in titles)
                            ActionChip(
                              label: Text(t),
                              onPressed: () => controller.useTitle(t),
                            ),
                        ],
                      ),
                    );
                  }),
                  Obx(() {
                    final due = controller.dueDate.value;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('تاريخ الاستحقاق (اختياري)'),
                      subtitle: due == null
                          ? null
                          : Text(ArabicDates.dayMonth(due)),
                      onTap: () => _pickDueDate(context),
                      trailing: due == null
                          ? null
                          : IconButton(
                              tooltip: 'مسح',
                              icon: const Icon(Icons.close),
                              onPressed: () => controller.setDueDate(null),
                            ),
                    );
                  }),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller.noteController,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظة (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Obx(() => FilledButton(
                    onPressed: controller.canSave ? _save : null,
                    child: const Text('حفظ'),
                  )),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (await controller.save()) Get.back();
  }

  Future<void> _pickDueDate(BuildContext context) async {
    final today = DateKeys.dateOnly(controller.today);
    final picked = await showDatePicker(
      context: context,
      initialDate: controller.dueDate.value ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) controller.setDueDate(picked);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final c = controller;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الالتزام؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed == true && await c.delete()) Get.back();
  }
}
