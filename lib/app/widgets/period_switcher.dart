import 'package:flutter/material.dart';

import '../core/logic/period.dart';

/// "› 1 تشرين الأول – 31 تشرين الأول ‹". Chevron icons mirror in RTL, so
/// chevron_left draws pointing right: back towards the start of the line.
class PeriodSwitcher extends StatelessWidget {
  const PeriodSwitcher({
    super.key,
    required this.period,
    required this.onPrevious,
    required this.onNext,
  });

  final Period period;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'الفترة السابقة',
          icon: const Icon(Icons.chevron_left),
          onPressed: onPrevious,
        ),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(period.label,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        IconButton(
          tooltip: 'الفترة التالية',
          icon: const Icon(Icons.chevron_right),
          onPressed: onNext,
        ),
      ],
    );
  }
}
