import 'package:flutter/material.dart';

import '../../../core/utils/currencies.dart';
import '../../../core/utils/money.dart';

/// What the user chose in [BudgetLimitDialog].
sealed class BudgetLimitResult {
  const BudgetLimitResult();
}

class SaveBudgetLimit extends BudgetLimitResult {
  const SaveBudgetLimit(this.text);

  final String text;
}

class RemoveBudgetLimit extends BudgetLimitResult {
  const RemoveBudgetLimit();
}

/// Asks for a category's monthly limit. It owns its text controller, so the
/// controller is disposed only after the dialog has finished closing.
class BudgetLimitDialog extends StatefulWidget {
  const BudgetLimitDialog({
    super.key,
    required this.categoryName,
    required this.currency,
    this.currentLimit,
  });

  final String categoryName;
  final Currency currency;

  /// The existing limit, or null when adding a new budget.
  final int? currentLimit;

  @override
  State<BudgetLimitDialog> createState() => _BudgetLimitDialogState();
}

class _BudgetLimitDialogState extends State<BudgetLimitDialog> {
  late final _input = TextEditingController(
      text: widget.currentLimit == null
          ? ''
          : Money.toEditable(widget.currentLimit!));

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('ميزانية ${widget.categoryName} الشهرية'),
      content: TextField(
        controller: _input,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          hintText: 'المبلغ',
          suffixText: widget.currency.symbol,
        ),
      ),
      actions: [
        if (widget.currentLimit != null)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const RemoveBudgetLimit()),
            child: const Text('حذف الميزانية'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(
            onPressed: () =>
                Navigator.pop(context, SaveBudgetLimit(_input.text)),
            child: const Text('حفظ')),
      ],
    );
  }
}
