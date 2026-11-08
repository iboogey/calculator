import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/pending_item.dart';
import '../../../data/models/transaction_category.dart';
import '../../../widgets/amount_field.dart';
import '../../../widgets/category_grid.dart';
import '../../../widgets/kind_toggle.dart';

/// Edits an imported SMS item, then approves it. [onSave] returns true when
/// the item was saved, which closes the sheet.
class PendingEditSheet extends StatefulWidget {
  const PendingEditSheet({
    super.key,
    required this.item,
    required this.currency,
    required this.categoriesFor,
    required this.onSave,
  });

  final PendingItem item;
  final Currency currency;
  final List<TransactionCategory> Function(TransactionKind kind) categoriesFor;
  final Future<bool> Function({
    required PendingKind kind,
    required int amount,
    required DateTime date,
    int? categoryId,
    String? note,
  }) onSave;

  @override
  State<PendingEditSheet> createState() => _PendingEditSheetState();
}

class _PendingEditSheetState extends State<PendingEditSheet> {
  late TransactionKind _kind = widget.item.kind == PendingKind.income
      ? TransactionKind.income
      : TransactionKind.expense;
  late int? _categoryId = widget.item.suggestedCategoryId;
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
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _parsed => Money.parse(_amount.text, decimals: _decimals);

  bool get _canSave => !_saving && _parsed != null && _categoryId != null;

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
    final saved = await widget.onSave(
      kind: _kind == TransactionKind.income
          ? PendingKind.income
          : PendingKind.expense,
      amount: amount,
      date: _date,
      categoryId: _categoryId,
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
              KindToggle(
                value: _kind,
                onChanged: (value) => setState(() {
                  if (value == _kind) return;
                  _kind = value;
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
              const Text('التصنيف',
                  style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 8),
              CategoryGrid(
                categories: widget.categoriesFor(_kind),
                selectedId: _categoryId,
                onSelected: (id) => setState(() => _categoryId = id),
              ),
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
