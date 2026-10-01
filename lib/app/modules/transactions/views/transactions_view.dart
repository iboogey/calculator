import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/logic/day_group.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/transaction_record.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/app_bottom_nav.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/money_text.dart';
import '../../../widgets/period_switcher.dart';
import '../../../widgets/transaction_tile.dart';
import '../controllers/transactions_controller.dart';

class TransactionsView extends GetView<TransactionsController> {
  const TransactionsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() {
          final period = controller.period.value;
          return period == null
              ? const Text('العمليات')
              : PeriodSwitcher(
                  period: period,
                  onPrevious: controller.previousPeriod,
                  onNext: controller.nextPeriod,
                );
        }),
      ),
      body: Obx(() {
        final groups = controller.groups.toList();
        if (groups.isEmpty) {
          return const EmptyState(
            icon: Icons.receipt_long_outlined,
            message: 'ما في عمليات بهالفترة',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          itemCount: groups.length,
          itemBuilder: (context, index) => _DaySection(
            group: groups[index],
            controller: controller,
            onDismissed: (t) => _deleteWithUndo(context, t),
          ),
        );
      }),
      bottomNavigationBar: const AppBottomNav(current: Routes.transactions),
    );
  }

  void _deleteWithUndo(BuildContext context, TransactionRecord record) {
    // Captured now: the SnackBar can outlive this screen (and its controller)
    // after a tab switch.
    final transactions = controller;
    transactions.delete(record);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('انحذفت العملية'),
        action: SnackBarAction(
          label: 'تراجع',
          onPressed: () => transactions.undoDelete(record),
        ),
      ));
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.group,
    required this.controller,
    required this.onDismissed,
  });

  final DayGroup group;
  final TransactionsController controller;
  final ValueChanged<TransactionRecord> onDismissed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    ArabicDates.relativeDay(group.day, today: controller.today),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                MoneyText(group.net,
                    currency: controller.currency,
                    showPlus: true,
                    showSymbol: false,
                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (index, t) in group.transactions.indexed) ...[
                  if (index > 0) const Divider(indent: 16, endIndent: 16),
                  Dismissible(
                    key: ValueKey(t.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: AppColors.danger,
                      alignment: AlignmentDirectional.centerEnd,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: const Icon(Icons.delete_outline, color: Colors.white),
                    ),
                    onDismissed: (_) => onDismissed(t),
                    child: TransactionTile(
                      transaction: t,
                      category: controller.categoriesById[t.categoryId],
                      currency: controller.currency,
                      subtitle: t.note ?? (t.isAuto ? 'تلقائي' : ''),
                      onTap: () => controller.openEdit(t),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
