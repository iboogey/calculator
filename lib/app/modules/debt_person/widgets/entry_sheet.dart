import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/debt_entry.dart';
import '../../../services/settings_service.dart';
import '../../../widgets/amount_field.dart';
import '../controllers/debt_person_controller.dart';

/// Bottom sheet for a new or edited entry. Pops an [EntryDraft].
class EntrySheet extends StatefulWidget {
  const EntrySheet({
    super.key,
    required this.gave,
    required this.personName,
    required this.today,
    this.editing,
  });

  final bool gave;
  final String personName;
  final DateTime today;
  final DebtEntry? editing;

  @override
  State<EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<EntrySheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late bool _gave;
  late DateTime _date;

  /// Wide enough for the edited amount even after a switch to a currency
  /// with fewer decimals.
  late final int _decimals;

  Currency get _currency => Get.find<SettingsService>().currency;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    var editedDecimals = 0;
    if (e == null) {
      _gave = widget.gave;
      _date = DateKeys.dateOnly(widget.today);
    } else {
      _gave = e.amount > 0;
      _date = DateKeys.dateOnly(e.date);
      final editable = Money.toEditable(e.amount.abs());
      final dot = editable.indexOf('.');
      editedDecimals = dot == -1 ? 0 : editable.length - dot - 1;
      _amount.text = editable;
      _note.text = e.note ?? '';
    }
    _decimals = max(_currency.decimals, editedDecimals);
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _parsed {
    final v = Money.parse(_amount.text, decimals: _decimals);
    return (v == null || v <= 0) ? null : v;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = DateKeys.dateOnly(picked));
  }

  void _save() {
    final value = _parsed;
    if (value == null) return;
    final note = _note.text.trim();
    Navigator.of(context).pop(EntryDraft(
      amount: _gave ? value : -value,
      date: _date,
      note: note.isEmpty ? null : note,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing != null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                editing
                    ? 'تعديل السجل'
                    : _gave
                        ? 'أعطيتُ ${widget.personName}'
                        : 'أخذتُ من ${widget.personName}',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 12),
              if (editing) ...[
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('أعطيتُ')),
                    ButtonSegment(value: false, label: Text('أخذتُ')),
                  ],
                  selected: {_gave},
                  onSelectionChanged: (s) => setState(() => _gave = s.first),
                ),
                const SizedBox(height: 12),
              ],
              AmountField(
                controller: _amount,
                currency: _currency,
                decimals: () => _decimals,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(ArabicDates.relativeDay(_date, today: widget.today)),
                onTap: _pickDate,
              ),
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _parsed == null ? null : _save,
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
