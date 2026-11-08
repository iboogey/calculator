import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/debt_entry.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/money_text.dart';
import '../controllers/debt_person_controller.dart';
import '../widgets/entry_sheet.dart';
import '../widgets/person_actions_sheet.dart';

class DebtPersonView extends GetView<DebtPersonController> {
  const DebtPersonView({super.key});

  String _cardText(int balance, String name) {
    if (balance > 0) return 'المستحق لك عند $name';
    if (balance < 0) return 'المستحق عليك لـ$name';
    return 'لا يوجد دين';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(controller.person.value?.name ?? '')),
        actions: [
          IconButton(
            tooltip: 'تعديل',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _openActions(context),
          ),
        ],
      ),
      body: Obx(() {
        final person = controller.person.value;
        if (person == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final balance = controller.balance.value;
        final entries = controller.entries.toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(_cardText(balance, person.name),
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 14)),
                    if (balance != 0)
                      MoneyText(balance.abs(),
                          currency: controller.currency,
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            color: balance > 0
                                ? AppColors.income
                                : AppColors.expense,
                          )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (entries.isEmpty)
              const EmptyState(icon: Icons.history, message: 'لا توجد سجلات')
            else
              Card(
                child: Column(
                  children: [
                    for (final (index, e) in entries.indexed) ...[
                      if (index > 0) const Divider(indent: 16, endIndent: 16),
                      _EntryTile(
                        entry: e,
                        controller: controller,
                        onLongPress: () => _entryMenu(context, e),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      }),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Obx(() {
            final name = controller.person.value?.name ?? '';
            return Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _add(context, gave: true),
                    child: Text('أعطيتُ $name'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => _add(context, gave: false),
                    child: Text('أخذتُ من $name'),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, {required bool gave}) async {
    final draft = await showModalBottomSheet<EntryDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EntrySheet(
        gave: gave,
        personName: controller.person.value?.name ?? '',
        today: controller.today,
      ),
    );
    if (draft != null) await controller.addEntry(draft);
  }

  Future<void> _entryMenu(BuildContext context, DebtEntry e) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('تعديل'),
                onTap: () => Navigator.of(context).pop('edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('حذف'),
                onTap: () => Navigator.of(context).pop('delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'edit') {
      final draft = await showModalBottomSheet<EntryDraft>(
        context: context,
        isScrollControlled: true,
        builder: (_) => EntrySheet(
          gave: e.amount > 0,
          personName: controller.person.value?.name ?? '',
          today: controller.today,
          editing: e,
        ),
      );
      if (draft != null) await controller.updateEntry(e, draft);
    } else if (action == 'delete') {
      _deleteWithUndo(context, e);
    }
  }

  Future<void> _deleteWithUndo(BuildContext context, DebtEntry e) async {
    // Captured now: the SnackBar can outlive this screen and its controller.
    final c = controller;
    final messenger = ScaffoldMessenger.of(context);
    final deleted = await c.deleteEntry(e);
    if (deleted == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('حُذف السجل'),
        action: SnackBarAction(
          label: 'تراجع',
          onPressed: () => c.undoDelete(deleted),
        ),
      ));
  }

  Future<void> _openActions(BuildContext context) async {
    final person = controller.person.value;
    if (person == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => PersonActionsSheet(
        name: person.name,
        onRename: controller.rename,
        onDelete: () async {
          final ok = await _confirmDelete(sheetContext, person.name);
          if (ok != true) return;
          if (await controller.deletePerson()) {
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            Get.back();
          }
        },
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, String name) {
    final balance = controller.balance.value;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الشخص'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('سيُحذف $name وكل سجله'),
              if (balance != 0)
                Text('${_cardText(balance, name)} '
                    '${MoneyText.label(balance.abs(), controller.currency, showSymbol: false)}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.controller,
    required this.onLongPress,
  });

  final DebtEntry entry;
  final DebtPersonController controller;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final gave = entry.amount > 0;
    final color = gave ? AppColors.income : AppColors.expense;
    final note = entry.note;
    return ListTile(
      onLongPress: onLongPress,
      leading: Icon(gave ? Icons.arrow_upward : Icons.arrow_downward,
          color: color),
      title: Text(gave ? 'أعطيتُ' : 'أخذتُ'),
      subtitle: Text(note == null || note.isEmpty
          ? ArabicDates.dayMonth(entry.date)
          : '${ArabicDates.dayMonth(entry.date)} · $note'),
      trailing: MoneyText(entry.amount,
          currency: controller.currency,
          showPlus: true,
          showSymbol: false,
          style: TextStyle(fontWeight: FontWeight.w600, color: color)),
    );
  }
}
