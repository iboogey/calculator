import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/logic/debt_summary.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/arabic_count.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/money_text.dart';
import '../controllers/debts_controller.dart';
import 'pay_sheet.dart';
import 'payments_sheet.dart';

class ObligationsTab extends GetView<DebtsController> {
  const ObligationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final unpaid = controller.unpaid.toList();
      final paid = controller.paid.toList();
      final showPaid = controller.showPaid.value;
      final currency = controller.currency;
      if (unpaid.isEmpty && paid.isEmpty) {
        return const EmptyState(
            icon: Icons.receipt_long_outlined, message: 'لا توجد التزامات');
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        children: [
          if (unpaid.isNotEmpty) ...[
            _SummaryTile(
              total: unpaid.fold(0, (sum, s) => sum + s.remaining),
              count: unpaid.length,
              nearest: _nearest(unpaid),
              currency: currency,
            ),
            const SizedBox(height: 12),
            for (final s in unpaid)
              _ObligationCard(
                status: s,
                due: controller.dueOf(s),
                currency: currency,
                onTap: () => _pay(context, s),
                onLongPress: () => _menu(context, s),
              ),
          ],
          if (paid.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => controller.showPaid.toggle(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('تم سدادها (${paid.length})',
                          style: const TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w600)),
                    ),
                    Icon(showPaid ? Icons.expand_less : Icons.expand_more,
                        color: AppColors.muted),
                  ],
                ),
              ),
            ),
            if (showPaid)
              for (final s in paid)
                Opacity(
                  opacity: 0.55,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    onLongPress: () => _menu(context, s),
                    leading: const Icon(Icons.check_circle_outline,
                        color: AppColors.muted),
                    title: Text(s.obligation.title),
                    trailing: MoneyText(s.obligation.amount, currency: currency),
                  ),
                ),
          ],
        ],
      );
    });
  }

  /// The first unpaid obligation with a due date (the list is sorted by it).
  DueInfo? _nearest(List<ObligationStatus> unpaid) {
    for (final s in unpaid) {
      final due = controller.dueOf(s);
      if (due != null) return due;
    }
    return null;
  }

  Future<void> _pay(BuildContext context, ObligationStatus s) async {
    // Captured now: the SnackBar is shown after the awaits below.
    final c = controller;
    final messenger = ScaffoldMessenger.of(context);
    final draft = await showModalBottomSheet<PayDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PaySheet(
        status: s,
        expenseCategories: c.expenseCategories.toList(),
        defaultCategoryId: c.defaultExpenseCategoryId,
        today: c.today,
        currency: c.currency,
      ),
    );
    if (draft == null || !await c.pay(s, draft)) return;
    final notice = c.lastNotice.value;
    if (notice == null) return;
    c.lastNotice.value = null;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(notice)));
  }

  Future<void> _menu(BuildContext context, ObligationStatus s) async {
    final c = controller;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!s.isPaid)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('تعديل'),
                  onTap: () => Navigator.of(sheetContext).pop('edit'),
                ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('السجل'),
                onTap: () => Navigator.of(sheetContext).pop('history'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('حذف'),
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'edit':
        c.openEditObligation(s);
      case 'history':
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => PaymentsSheet(
            title: s.obligation.title,
            currency: c.currency,
            load: () => c.paymentsOf(s),
            onDelete: c.deletePayment,
          ),
        );
      case 'delete':
        if (await _confirmDelete(context)) {
          await c.deleteObligation(s);
        }
    }
  }
}

/// Asks 'حذف الالتزام؟'; true when the user confirms.
Future<bool> _confirmDelete(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('حذف الالتزام؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    ),
  );
  return confirmed == true;
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.total,
    required this.count,
    required this.nearest,
    required this.currency,
  });

  final int total;
  final int count;
  final DueInfo? nearest;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final due = nearest;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.expense.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('المبلغ المستحق عليّ',
              style: TextStyle(color: AppColors.expense, fontSize: 13)),
          const SizedBox(height: 4),
          MoneyText(total,
              currency: currency,
              style: const TextStyle(
                  color: AppColors.expense,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            due == null
                ? ArabicCount.obligations(count)
                : '${ArabicCount.obligations(count)} · أقربها ${ArabicDates.dueLabel(due.daysLeft)}',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ObligationCard extends StatelessWidget {
  const _ObligationCard({
    required this.status,
    required this.due,
    required this.currency,
    required this.onTap,
    required this.onLongPress,
  });

  final ObligationStatus status;
  final DueInfo? due;
  final Currency currency;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final o = status.obligation;
    final info = due;
    final soon = info != null && info.daysLeft <= 3;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.title,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          info == null
                              ? 'بلا موعد محدد'
                              : 'يستحق في ${ArabicDates.dayMonth(o.dueDate!)} · '
                                  '${ArabicDates.dueLabel(info.daysLeft)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: soon ? AppColors.warning : AppColors.muted,
                            fontWeight: soon ? FontWeight.w600 : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  MoneyText(status.remaining,
                      currency: currency,
                      style: const TextStyle(
                          color: AppColors.expense,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              if (status.paid > 0) ...[
                const SizedBox(height: 10),
                Text(
                  'سُدِّد ${MoneyText.label(status.paid, currency)} '
                  'من ${MoneyText.label(o.amount, currency)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: status.paid / o.amount,
                    minHeight: 6,
                    color: AppColors.primary,
                    backgroundColor: AppColors.primarySoft,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
