import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/pending_item.dart';
import '../../../widgets/money_text.dart';

/// One imported item with its approve / edit / dismiss buttons.
class PendingCard extends StatelessWidget {
  const PendingCard({
    super.key,
    required this.item,
    required this.currency,
    required this.categoryName,
    required this.canApprove,
    required this.onApprove,
    required this.onEdit,
    required this.onDismiss,
    this.personName,
    this.duplicateLabel,
    this.today,
  });

  final PendingItem item;
  final Currency currency;

  /// Null when the item has no category yet.
  final String? categoryName;

  /// The person of a voice debt, when known.
  final String? personName;

  /// Whether one tap may approve; otherwise approving opens the editor.
  final bool canApprove;
  final String? duplicateLabel;

  /// For the relative day label; defaults to now.
  final DateTime? today;
  final VoidCallback onApprove;
  final VoidCallback onEdit;
  final VoidCallback onDismiss;

  String _when() {
    final at = item.occurredAt;
    final day = ArabicDates.relativeDay(at, today: today ?? DateTime.now());
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '$day · $hh:$mm';
  }

  bool get _isDebt =>
      item.kind == PendingKind.debtGave || item.kind == PendingKind.debtTook;

  @override
  Widget build(BuildContext context) {
    // Money coming in: income, or a debt where I took money.
    final isIncome =
        item.kind == PendingKind.income || item.kind == PendingKind.debtTook;
    final place = item.city;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      color: AppColors.surface,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  item.source == PendingSource.voice
                      ? Icons.mic_none
                      : Icons.sms_outlined,
                  size: 16,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 6),
                Text(_when(),
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(item.name ?? item.note ?? '—',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                MoneyText(
                  item.amount,
                  currency: currency,
                  showPlus: isIncome,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isIncome ? AppColors.income : AppColors.expense,
                  ),
                ),
              ],
            ),
            if (place != null && place.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(place,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ],
            const SizedBox(height: 8),
            if (_isDebt)
              Chip(
                label: Text(personName == null ? 'دين' : 'دين: $personName'),
                visualDensity: VisualDensity.compact,
                backgroundColor: personName == null
                    ? AppColors.warningSoft
                    : AppColors.primarySoft,
              )
            else
              Chip(
                label: Text(categoryName ?? 'بلا تصنيف'),
                visualDensity: VisualDensity.compact,
                backgroundColor: categoryName == null
                    ? AppColors.warningSoft
                    : AppColors.primarySoft,
              ),
            if (duplicateLabel != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 18, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('قد يكون مسجّلًا مسبقًا: $duplicateLabel',
                        style: const TextStyle(
                            color: AppColors.warning, fontSize: 13)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  // The theme's full-width minimum can't fit in a Row.
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: onApprove,
                  child: const Text('اعتماد'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: onEdit, child: const Text('تعديل')),
                const Spacer(),
                TextButton(onPressed: onDismiss, child: const Text('تجاهل')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
