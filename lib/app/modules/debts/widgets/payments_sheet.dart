import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/obligation_payment.dart';
import '../../../widgets/money_text.dart';

/// An obligation's payments, newest first, each with a delete button.
class PaymentsSheet extends StatefulWidget {
  const PaymentsSheet({
    super.key,
    required this.title,
    required this.currency,
    required this.load,
    required this.onDelete,
  });

  final String title;
  final Currency currency;
  final Future<List<ObligationPayment>> Function() load;

  /// Deletes the payment and the expense it created, if any.
  final Future<void> Function(ObligationPayment p) onDelete;

  @override
  State<PaymentsSheet> createState() => _PaymentsSheetState();
}

class _PaymentsSheetState extends State<PaymentsSheet> {
  List<ObligationPayment>? _payments;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await widget.load();
    if (!mounted) return;
    setState(() => _payments = list);
  }

  Future<void> _delete(ObligationPayment p) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الدفعة؟'),
          content: p.transactionId == null
              ? null
              : const Text('سيُحذف المصروف المسجّل معها أيضًا'),
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
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await widget.onDelete(p);
    await _reload();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final payments = _payments;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'السجل · ${widget.title}',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 8),
              if (payments == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (payments.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('لا توجد دفعات',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted)),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in payments)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: MoneyText(p.amount,
                              currency: widget.currency,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Row(
                            children: [
                              Text(ArabicDates.dayMonth(p.date)),
                              if (p.transactionId != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primarySoft,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text('مسجّل مصروفًا',
                                      style: TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 12)),
                                ),
                              ],
                            ],
                          ),
                          trailing: IconButton(
                            tooltip: 'حذف',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _busy ? null : () => _delete(p),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
