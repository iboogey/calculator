import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/amount_input.dart';
import '../core/utils/currencies.dart';

/// The big amount field, e.g. "7.25 د.أ". Typing uses the phone's own number
/// keyboard.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.currency,
    required this.decimals,
    this.autofocus = false,
    this.focusNode,
    this.label = 'المبلغ',
  });

  final TextEditingController controller;
  final Currency currency;

  /// Fraction digits allowed while typing; read on every keystroke.
  final int Function() decimals;
  final bool autofocus;
  final FocusNode? focusNode;
  final String label;

  static const _style = TextStyle(
      fontSize: 36, fontWeight: FontWeight.w700, color: AppColors.ink);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 40, maxWidth: 260),
              child: IntrinsicWidth(
                child: TextField(
                  key: const ValueKey('amount-field'),
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: autofocus,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: _style,
                  inputFormatters: [AmountInputFormatter(decimals)],
                  decoration: const InputDecoration(
                    hintText: '0',
                    hintStyle: TextStyle(color: AppColors.muted),
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(currency.symbol, style: _style),
          ],
        ),
      ],
    );
  }
}

/// Keeps the amount field valid as the user types (see [AmountInput.clean]).
class AmountInputFormatter extends TextInputFormatter {
  AmountInputFormatter(this.decimals);

  final int Function() decimals;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final cleaned = AmountInput.clean(newValue.text, decimals: decimals());
    if (cleaned == null) return oldValue;
    if (cleaned == newValue.text) return newValue;
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
  }
}
