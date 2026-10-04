import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/recurring_rule.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/money_text.dart';

/// Active fixed costs with the next date each one is added.
class RecurringSummary extends StatelessWidget {
  const RecurringSummary({
    super.key,
    required this.rules,
    required this.currency,
    required this.nextDue,
    required this.today,
  });

  final List<RecurringRule> rules;
  final Currency currency;
  final DateTime Function(RecurringRule) nextDue;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    if (rules.isEmpty) {
      return const EmptyState(
        icon: Icons.event_repeat_outlined,
        message: 'ما في مصاريف ثابتة. أضف الإيجار أو الاشتراكات لتنحسب لحالها.',
      );
    }
    return Card(
      child: Column(
        children: [
          for (final (index, rule) in rules.indexed) ...[
            if (index > 0) const Divider(indent: 16, endIndent: 16),
            ListTile(
              title: Text(rule.label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'كل شهر يوم ${rule.dayOfMonth} · الجاي: '
                '${ArabicDates.relativeDay(nextDue(rule), today: today)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              trailing: MoneyText(rule.amount,
                  currency: currency,
                  showSymbol: false,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }
}
