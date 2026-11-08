import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../data/models/pending_item.dart';
import '../../../widgets/empty_state.dart';
import '../controllers/import_review_controller.dart';
import '../widgets/pending_card.dart';
import '../widgets/pending_edit_sheet.dart';

class ImportReviewView extends GetView<ImportReviewController> {
  const ImportReviewView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مراجعة الحركات')),
      body: SafeArea(
        child: Obx(() {
          final items = controller.items.toList();
          if (items.isEmpty) {
            return const Center(
              child: EmptyState(
                icon: Icons.inbox_outlined,
                message: 'لا توجد حركات جديدة',
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return PendingCard(
                key: ValueKey(item.id),
                item: item,
                currency: controller.currency,
                categoryName: item.suggestedCategoryId == null
                    ? null
                    : controller.categoriesById[item.suggestedCategoryId!]
                        ?.name,
                canApprove: controller.canApproveDirectly(item),
                duplicateLabel: controller.duplicateLabels[item.id],
                onApprove: () => controller.canApproveDirectly(item)
                    ? controller.approve(item)
                    : _edit(context, item),
                onEdit: () => _edit(context, item),
                onDismiss: () => _dismiss(context, item),
              );
            },
          );
        }),
      ),
    );
  }

  Future<void> _edit(BuildContext context, PendingItem item) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PendingEditSheet(
        item: item,
        currency: controller.currency,
        categoriesFor: controller.categoriesFor,
        onSave: ({
          required kind,
          required amount,
          required date,
          categoryId,
          note,
        }) =>
            controller.approveEdited(item,
                kind: kind,
                amount: amount,
                date: date,
                categoryId: categoryId,
                note: note),
      ),
    );
  }

  Future<void> _dismiss(BuildContext context, PendingItem item) async {
    final review = controller;
    final messenger = ScaffoldMessenger.of(context);
    final removed = await review.dismiss(item);
    if (removed == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('تم التجاهل'),
        action: SnackBarAction(
          label: 'تراجع',
          onPressed: () => review.undoDismiss(removed),
        ),
      ));
  }
}
