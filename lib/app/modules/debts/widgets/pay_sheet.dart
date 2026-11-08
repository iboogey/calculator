import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/logic/debt_summary.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/category_icons.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/transaction_category.dart';
import '../../../widgets/amount_field.dart';
import '../../../widgets/money_text.dart';
import '../controllers/debts_controller.dart';

/// Bottom sheet that pays toward an obligation. Pops a [PayDraft].
class PaySheet extends StatefulWidget {
  const PaySheet({
    super.key,
    required this.status,
    required this.expenseCategories,
    required this.defaultCategoryId,
    required this.today,
    required this.currency,
  });

  final ObligationStatus status;
  final List<TransactionCategory> expenseCategories;
  final int? defaultCategoryId;
  final DateTime today;
  final Currency currency;

  @override
  State<PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<PaySheet> {
  final _amount = TextEditingController();
  final _amountFocus = FocusNode();
  late DateTime _date;
  late bool _asExpense;
  int? _categoryId;

  /// Enough fraction digits to type the remaining amount exactly, even after
  /// a switch to a currency with fewer decimals.
  late final int _decimals;

  int get _remaining => widget.status.remaining;

  @override
  void initState() {
    super.initState();
    final editable = Money.toEditable(_remaining);
    final dot = editable.indexOf('.');
    _decimals =
        max(widget.currency.decimals, dot == -1 ? 0 : editable.length - dot - 1);
    _amount.text = editable;
    _amount.addListener(() => setState(() {}));
    _date = DateKeys.dateOnly(widget.today);
    _categoryId = widget.defaultCategoryId;
    _asExpense = _categoryId != null;
  }

  @override
  void dispose() {
    _amount.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  int? get _parsed => Money.parse(_amount.text, decimals: _decimals);

  bool get _tooMuch => (_parsed ?? 0) > _remaining;

  String _label(int amount) => MoneyText.label(amount, widget.currency);

  String get _categoryName {
    for (final c in widget.expenseCategories) {
      if (c.id == _categoryId) return c.name;
    }
    return '';
  }

  void _payAll() {
    _amount.text = Money.toEditable(_remaining);
    _amount.selection = TextSelection.collapsed(offset: _amount.text.length);
  }

  void _payPart() {
    _amount.clear();
    _amountFocus.requestFocus();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted || picked == null) return;
    setState(() => _date = DateKeys.dateOnly(picked));
  }

  Future<void> _pickCategory() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in widget.expenseCategories)
                ListTile(
                  leading: Icon(CategoryIcons.of(c.iconKey),
                      color: Color(c.colorValue)),
                  title: Text(c.name),
                  trailing: c.id == _categoryId
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(c.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _categoryId = picked);
  }

  void _submit() {
    final value = _parsed;
    if (value == null || value > _remaining) return;
    Navigator.of(context).pop(PayDraft(
      amount: value,
      date: _date,
      expenseCategoryId: _asExpense ? _categoryId : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.status.obligation;
    final canRecord = _categoryId != null;
    final canPay = _parsed != null && !_tooMuch;
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
                'تسديد ${o.title}',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                'المتبقي عليك ${_label(_remaining)} من ${_label(o.amount)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              AmountField(
                label: 'المبلغ المدفوع',
                controller: _amount,
                currency: widget.currency,
                decimals: () => _decimals,
                focusNode: _amountFocus,
              ),
              if (_tooMuch)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('أكبر من المتبقي',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.expense)),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _payAll,
                      child: Text('المبلغ كاملًا (${_label(_remaining)})'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _payPart,
                      child: const Text('جزء منه'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _asExpense,
                onChanged: canRecord
                    ? (v) => setState(() => _asExpense = v ?? false)
                    : null,
                title: const Text('سجّله مصروفًا'),
              ),
              if (_asExpense && canRecord)
                InkWell(
                  onTap: _pickCategory,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(color: AppColors.muted),
                        children: [
                          TextSpan(
                              text: 'يُخصم من «المتبقي من الراتب» ضمن تصنيف '
                                  '$_categoryName · '),
                          const TextSpan(
                            text: 'تغيير',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(ArabicDates.relativeDay(_date, today: widget.today)),
                onTap: _pickDate,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: canPay ? _submit : null,
                child: const Text('تسديد'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
