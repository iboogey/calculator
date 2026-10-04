import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// A calculator-style number pad. Always laid out left-to-right, like a
/// phone keypad.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({
    super.key,
    required this.onKey,
    required this.onBackspace,
    this.showDot = true,
  });

  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final bool showDot;

  static const _digits = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.8,
        children: [
          for (final digit in _digits) _KeyButton(label: digit, onPressed: () => onKey(digit)),
          if (showDot)
            _KeyButton(label: '.', onPressed: () => onKey('.'))
          else
            const SizedBox.shrink(),
          _KeyButton(label: '0', onPressed: () => onKey('0')),
          _KeyButton(
            icon: Icons.backspace_outlined,
            tooltip: 'مسح',
            onPressed: onBackspace,
          ),
        ],
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({this.label, this.icon, this.tooltip, required this.onPressed});

  final String? label;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: icon == null ? AppColors.surface : AppColors.divider,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Center(
          child: icon != null
              ? Icon(icon, color: AppColors.ink)
              : Text(label!,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.ink)),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
