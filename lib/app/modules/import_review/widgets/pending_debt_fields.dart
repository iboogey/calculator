import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/debt_person.dart';

/// The debt part of the edit sheet: who (an existing person or a new name)
/// and which direction (I gave / I took).
class PendingDebtFields extends StatelessWidget {
  const PendingDebtFields({
    super.key,
    required this.people,
    required this.selectedPersonId,
    required this.newPerson,
    required this.gave,
    required this.onPersonSelected,
    required this.onNewPersonTyped,
    required this.onGaveChanged,
  });

  final List<DebtPerson> people;
  final int? selectedPersonId;

  /// The "new person" name; used when no existing person is selected.
  final TextEditingController newPerson;
  final bool gave;
  final ValueChanged<int> onPersonSelected;
  final VoidCallback onNewPersonTyped;
  final ValueChanged<bool> onGaveChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: true, label: Text('أعطيتُ')),
            ButtonSegment(value: false, label: Text('أخذتُ')),
          ],
          selected: {gave},
          onSelectionChanged: (s) => onGaveChanged(s.first),
        ),
        const SizedBox(height: 12),
        const Text('الشخص',
            style: TextStyle(color: AppColors.muted, fontSize: 13)),
        if (people.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in people)
                ChoiceChip(
                  label: Text(p.name),
                  selected: p.id == selectedPersonId,
                  onSelected: (_) => onPersonSelected(p.id!),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: newPerson,
          textInputAction: TextInputAction.done,
          onChanged: (_) => onNewPersonTyped(),
          decoration: const InputDecoration(
            hintText: 'شخص جديد',
            prefixIcon: Icon(Icons.person_add_alt),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
