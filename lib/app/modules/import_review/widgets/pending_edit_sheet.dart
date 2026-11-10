import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/debt_person.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/pending_item.dart';
import '../../../data/models/transaction_category.dart';
import '../../../widgets/amount_field.dart';
import '../../../widgets/category_grid.dart';
import 'pending_debt_fields.dart';

typedef PendingSave = Future<bool> Function({
  required PendingKind kind,
  required int amount,
  required DateTime date,
  int? categoryId,
  int? personId,
  String? personName,
  String? note,
});

/// Edits an imported item, then approves it as an expense, income or debt.
/// [onSave] returns true when the item was saved, which closes the sheet.
class PendingEditSheet extends StatefulWidget {
  const PendingEditSheet({
    super.key,
    required this.item,
    required this.currency,
    required this.categoriesFor,
    required this.onSave,
    this.people = const [],
  });

  final PendingItem item;
  final Currency currency;
  final List<TransactionCategory> Function(TransactionKind kind) categoriesFor;

  /// Existing debt people, for the person picker.
  final List<DebtPerson> people;
  final PendingSave onSave;

  @override
  State<PendingEditSheet> createState() => _PendingEditSheetState();
}

enum _Mode { expense, income, debt }

class _PendingEditSheetState extends State<PendingEditSheet> {
  late _Mode _mode = switch (widget.item.kind) {
    PendingKind.expense => _Mode.expense,
    PendingKind.income => _Mode.income,
    PendingKind.debtGave || PendingKind.debtTook => _Mode.debt,
  };

  TransactionKind get _kind =>
      _mode == _Mode.income ? TransactionKind.income : TransactionKind.expense;

  /// Money that came in (income, or a debt I took) starts on "I took".
  late bool _gave = widget.item.kind != PendingKind.debtTook &&
      widget.item.kind != PendingKind.income;

  /// The suggested person, matched by id or by trimmed, case-insensitive name.
  late int? _personId = () {
    final item = widget.item;
    if (widget.people.any((p) => p.id == item.personId)) return item.personId;
    final name = item.personName?.trim().toLowerCase();
    if (name == null || name.isEmpty) return null;
    for (final p in widget.people) {
      if (p.name.trim().toLowerCase() == name) return p.id;
    }
    return null;
  }();
  late final _newPerson = TextEditingController(
      text: _personId == null ? widget.item.personName?.trim() ?? '' : '');

  late int? _categoryId = () {
    final suggested = widget.item.suggestedCategoryId;
    final visible = widget.categoriesFor(_kind);
    return visible.any((c) => c.id == suggested) ? suggested : null;
  }();
  late DateTime _date = DateKeys.dateOnly(widget.item.occurredAt);
  late final _amount =
      TextEditingController(text: Money.toEditable(widget.item.amount));
  late final _note = TextEditingController(text: widget.item.note ?? '');
  bool _saving = false;

  /// Keeps an amount with more digits than the currency shows editable.
  late final int _decimals = () {
    final editable = Money.toEditable(widget.item.amount);
    final dot = editable.indexOf('.');
    final own = dot == -1 ? 0 : editable.length - dot - 1;
    return own > widget.currency.decimals ? own : widget.currency.decimals;
  }();

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
    _newPerson.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _newPerson.dispose();
    super.dispose();
  }

  int? get _parsed {
    final value = Money.parse(_amount.text, decimals: _decimals);
    return (value == null || value <= 0) ? null : value;
  }

  bool get _hasPerson =>
      _personId != null || _newPerson.text.trim().isNotEmpty;

  bool get _canSave =>
      !_saving &&
      _parsed != null &&
      (_mode == _Mode.debt ? _hasPerson : _categoryId != null);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = DateKeys.dateOnly(picked));
  }

  Future<void> _save() async {
    final amount = _parsed;
    if (!_canSave || amount == null) return;
    setState(() => _saving = true);
    final note = _note.text.trim();
    final isDebt = _mode == _Mode.debt;
    final saved = await widget.onSave(
      kind: switch (_mode) {
        _Mode.expense => PendingKind.expense,
        _Mode.income => PendingKind.income,
        _Mode.debt => _gave ? PendingKind.debtGave : PendingKind.debtTook,
      },
      amount: amount,
      date: _date,
      categoryId: isDebt ? null : _categoryId,
      personId: isDebt ? _personId : null,
      personName: isDebt && _personId == null ? _newPerson.text.trim() : null,
      note: note.isEmpty ? null : note,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_Mode>(
                showSelectedIcon: false,
                segments: [
                  for (final mode in _Mode.values)
                    ButtonSegment(
                      value: mode,
                      label: Text(switch (mode) {
                        _Mode.expense => 'مصروف',
                        _Mode.income => 'دخل',
                        _Mode.debt => 'دين',
                      }),
                    ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) => setState(() {
                  if (selection.first == _mode) return;
                  _mode = selection.first;
                  _categoryId = null;
                }),
              ),
              const SizedBox(height: 12),
              AmountField(
                controller: _amount,
                currency: widget.currency,
                decimals: () => _decimals,
              ),
              const SizedBox(height: 12),
              if (_mode == _Mode.debt)
                PendingDebtFields(
                  people: widget.people,
                  selectedPersonId: _personId,
                  newPerson: _newPerson,
                  gave: _gave,
                  onPersonSelected: (id) {
                    _newPerson.clear();
                    setState(() => _personId = id);
                  },
                  onNewPersonTyped: () => setState(() => _personId = null),
                  onGaveChanged: (gave) => setState(() => _gave = gave),
                )
              else ...[
                const Text('التصنيف',
                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 8),
                CategoryGrid(
                  categories: widget.categoriesFor(_kind),
                  selectedId: _categoryId,
                  onSelected: (id) => setState(() => _categoryId = id),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _note,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        hintText: 'ملاحظة (اختياري)',
                        prefixIcon: Icon(Icons.edit_note),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(
                        ArabicDates.relativeDay(_date, today: DateTime.now())),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _canSave ? _save : null,
                child: const Text('حفظ واعتماد'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
