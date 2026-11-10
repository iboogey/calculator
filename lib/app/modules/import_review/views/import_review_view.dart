import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/pending_item.dart';
import '../../../widgets/empty_state.dart';
import '../controllers/import_review_controller.dart';
import '../controllers/voice_controller.dart';
import '../widgets/pending_card.dart';
import '../widgets/pending_edit_sheet.dart';
import '../widgets/voice_sheet.dart';

class ImportReviewView extends GetView<ImportReviewController> {
  const ImportReviewView({super.key});

  VoiceController get _voice => Get.find<VoiceController>();

  @override
  Widget build(BuildContext context) {
    // Opened from Home's mic: start voice entry once the screen is shown.
    if (controller.takeVoiceRequest()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _startVoice(context);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('مراجعة الحركات'),
        actions: [
          // Looks disabled without an AI key; tapping then explains why.
          Obx(() => IconButton(
                tooltip: 'إدخال صوتي',
                onPressed: () => _startVoice(context),
                icon: Icon(
                  Icons.mic_none,
                  color: _voice.configured.value
                      ? null
                      : AppColors.muted.withValues(alpha: 0.4),
                ),
              )),
        ],
      ),
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
                personName: controller.personLabel(item),
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

  /// Voice entry; the stored item's edit sheet opens right after (§6.7).
  Future<void> _startVoice(BuildContext context) async {
    final voice = _voice;
    if (!await voice.ensureConfigured() || !context.mounted) return;
    final item = await showModalBottomSheet<PendingItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => VoiceSheet(voice: voice),
    );
    if (item != null && context.mounted) await _edit(context, item);
  }

  Future<void> _edit(BuildContext context, PendingItem item) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PendingEditSheet(
        item: item,
        currency: controller.currency,
        categoriesFor: controller.categoriesFor,
        kinds: controller.kindsFor(item),
        people: controller.people.toList(),
        onSave: ({
          required kind,
          required amount,
          required date,
          categoryId,
          personId,
          personName,
          note,
        }) =>
            controller.approveEdited(item,
                kind: kind,
                amount: amount,
                date: date,
                categoryId: categoryId,
                personId: personId,
                personName: personName,
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
