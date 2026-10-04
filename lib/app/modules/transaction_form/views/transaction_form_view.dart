import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../widgets/amount_keypad.dart';
import '../controllers/transaction_form_controller.dart';
import '../widgets/amount_display.dart';
import '../../../widgets/category_grid.dart';
import '../../../widgets/kind_toggle.dart';

class TransactionFormView extends GetView<TransactionFormController> {
  const TransactionFormView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() =>
            Text(controller.isEditing.value ? 'تعديل عملية' : 'عملية جديدة')),
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  Obx(() => KindToggle(
                      value: controller.kind.value, onChanged: controller.setKind)),
                  const SizedBox(height: 20),
                  Obx(() => AmountDisplay(
                      text: controller.amountText.value,
                      currency: controller.currency)),
                  const SizedBox(height: 20),
                  const Text('التصنيف',
                      style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 8),
                  Obx(() => CategoryGrid(
                        categories: controller.visibleCategories,
                        selectedId: controller.categoryId.value,
                        onSelected: controller.selectCategory,
                      )),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller.noteController,
                          decoration: const InputDecoration(
                            hintText: 'ملاحظة (اختياري)',
                            prefixIcon: Icon(Icons.edit_note),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Obx(() => OutlinedButton.icon(
                            onPressed: () => _pickDate(context),
                            icon: const Icon(Icons.calendar_today_outlined, size: 18),
                            label: Text(ArabicDates.relativeDay(
                                controller.date.value,
                                today: DateTime.now())),
                          )),
                    ],
                  ),
                  Obx(() => controller.isEditing.value
                      ? const SizedBox.shrink()
                      : CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: controller.saveAsFavorite.value,
                          onChanged: (v) =>
                              controller.saveAsFavorite.value = v ?? false,
                          title: const Text(
                              'احفظها كمفضّلة (زر بضغطة وحدة بالرئيسية)'),
                        )),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  AmountKeypad(
                    onKey: controller.pressKey,
                    onBackspace: controller.backspace,
                    showDot: controller.currency.decimals > 0,
                  ),
                  const SizedBox(height: 12),
                  Obx(() => FilledButton(
                        onPressed: controller.canSave ? _save : null,
                        child: const Text('حفظ'),
                      )),
                ],
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

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: controller.date.value,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) controller.setDate(picked);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف العملية؟'),
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
