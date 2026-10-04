import 'package:flutter/material.dart';

import '../core/utils/currencies.dart';
import '../core/utils/money.dart';

/// What the user chose in [AmountDialog].
sealed class AmountDialogResult {
  const AmountDialogResult();
}

class SaveAmount extends AmountDialogResult {
  const SaveAmount(this.text);

  final String text;
}

class RemoveAmount extends AmountDialogResult {
  const RemoveAmount();
}

/// Asks for an amount. It owns its text controller, so the controller is
/// disposed only after the dialog has finished closing.
class AmountDialog extends StatefulWidget {
  const AmountDialog({
    super.key,
    required this.title,
    required this.currency,
    this.initialAmount,
    this.removeLabel,
  });

  final String title;
  final Currency currency;
  final int? initialAmount;

  /// Shows a remove action with this label when not null.
  final String? removeLabel;

  @override
  State<AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<AmountDialog> {
  late final _input = TextEditingController(
      text: widget.initialAmount == null
          ? ''
          : Money.toEditable(widget.initialAmount!));

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
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
        if (widget.removeLabel != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const RemoveAmount()),
            child: Text(widget.removeLabel!),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(
            onPressed: () => Navigator.pop(context, SaveAmount(_input.text)),
            child: const Text('حفظ')),
      ],
    );
  }
}
