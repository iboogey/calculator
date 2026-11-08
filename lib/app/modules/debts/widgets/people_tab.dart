import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/logic/debt_summary.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../widgets/money_text.dart';
import '../controllers/debts_controller.dart';

class PeopleTab extends GetView<DebtsController> {
  const PeopleTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final people = controller.people.toList();
      final totals = controller.totals.value;
      final currency = controller.currency;
      if (people.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline, size: 48, color: AppColors.muted),
                SizedBox(height: 12),
                Text('لا يوجد أشخاص بعد',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text('أضف شخصًا لتسجيل ما بينكما من ديون',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        children: [
          Row(
            children: [
              Expanded(
                child: _TotalTile(
                    label: 'المستحق لي',
                    amount: totals.owedToMe,
                    color: AppColors.income,
                    currency: currency),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TotalTile(
                    label: 'المستحق عليّ',
                    amount: totals.iOwe,
                    color: AppColors.expense,
                    currency: currency),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final p in people) _PersonRow(p, currency, () => controller.openPerson(p)),
        ],
      );
    });
  }
}

class _TotalTile extends StatelessWidget {
  const _TotalTile({
    required this.label,
    required this.amount,
    required this.color,
    required this.currency,
  });

  final String label;
  final int amount;
  final Color color;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 13)),
          const SizedBox(height: 4),
          MoneyText(amount,
              currency: currency,
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow(this.p, this.currency, this.onTap);

  final PersonBalance p;
  final Currency currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final balance = p.balance;
    final color = balance > 0
        ? AppColors.income
        : balance < 0
            ? AppColors.expense
            : AppColors.muted;
    final sub = balance > 0
        ? 'مستحق لك'
        : balance < 0
            ? 'مستحق عليك'
            : 'لا يوجد دين';
    final name = p.person.name;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Text(name.characters.first,
            style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ),
      title: Text(name),
      subtitle: Text(sub, style: TextStyle(color: color)),
      trailing: MoneyText(balance.abs(),
          currency: currency,
          style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }
}
