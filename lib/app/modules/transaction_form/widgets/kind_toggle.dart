import 'package:flutter/material.dart';

import '../../../data/models/enums.dart';

class KindToggle extends StatelessWidget {
  const KindToggle({super.key, required this.value, required this.onChanged});

  final TransactionKind value;
  final ValueChanged<TransactionKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<TransactionKind>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: TransactionKind.expense, label: Text('مصروف')),
          ButtonSegment(value: TransactionKind.income, label: Text('دخل')),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}
