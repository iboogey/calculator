import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/amount_input.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/quick_template.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/models/transaction_record.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

/// Add a new transaction, or edit/delete the one with [editId].
class TransactionFormController extends GetxController {
  TransactionFormController({
    required this.transactions,
    required this.categories,
    required this.settings,
    this.editId,
  });

  final TransactionRepository transactions;
  final CategoryRepository categories;
  final SettingsService settings;
  final int? editId;

  final kind = TransactionKind.expense.obs;
  final amountText = ''.obs;
  final categoryId = RxnInt();
  final date = DateKeys.dateOnly(DateTime.now()).obs;
  final isEditing = false.obs;
  final isSaving = false.obs;
  final saveAsFavorite = false.obs;
  final _allCategories = <TransactionCategory>[].obs;
  final noteController = TextEditingController();

  TransactionRecord? _editing;

  /// Fraction digits of the edited amount, so a 3-decimal amount saved
  /// before a switch to a 2-decimal currency stays editable.
  int _editingDecimals = 0;

  /// Completes when categories (and the edited record) are loaded.
  late final Future<void> ready;

  Currency get currency => settings.currency;

  int get _inputDecimals => max(currency.decimals, _editingDecimals);

  int? get amount => Money.parse(amountText.value, decimals: _inputDecimals);

  bool get canSave =>
      !isSaving.value && amount != null && categoryId.value != null;

  List<TransactionCategory> get visibleCategories =>
      _allCategories.where((c) => c.kind == kind.value).toList();

  @override
  void onInit() {
    super.onInit();
    ready = _load();
  }

  Future<void> _load() async {
    _allCategories.assignAll(await categories.getAll());
    if (editId == null) return;
    final record = await transactions.getById(editId!);
    if (record == null) return;
    _editing = record;
    isEditing.value = true;
    kind.value = record.kind;
    amountText.value = Money.toEditable(record.amount);
    final dot = amountText.value.indexOf('.');
    _editingDecimals = dot == -1 ? 0 : amountText.value.length - dot - 1;
    categoryId.value = record.categoryId;
    noteController.text = record.note ?? '';
    date.value = record.date;
  }

  void setKind(TransactionKind value) {
    if (kind.value == value) return;
    kind.value = value;
    categoryId.value = null;
  }

  void pressKey(String key) => amountText.value =
      AmountInput.append(amountText.value, key, decimals: _inputDecimals);

  void backspace() => amountText.value = AmountInput.backspace(amountText.value);

  void selectCategory(int id) => categoryId.value = id;

  void setDate(DateTime value) => date.value = DateKeys.dateOnly(value);

  /// Saves the form. Returns false (and saves nothing) when it is incomplete,
  /// a save is already running, or the database fails (a message is shown).
  Future<bool> save() async {
    if (!canSave) return false;
    isSaving.value = true;
    try {
      return await _save();
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ العملية، جرّب مرة ثانية');
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  Future<bool> _save() async {
    final value = amount;
    final category = categoryId.value;
    if (value == null || category == null) return false;
    final note = noteController.text.trim();
    final record = TransactionRecord(
      id: _editing?.id,
      kind: kind.value,
      amount: value,
      categoryId: category,
      date: date.value,
      note: note.isEmpty ? null : note,
      recurringRuleId: _editing?.recurringRuleId,
      recurringDueDate: _editing?.recurringDueDate,
      createdAt: _editing?.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(
              DateTime.now().millisecondsSinceEpoch),
    );
    if (_editing == null) {
      await transactions.add(
        record,
        favorite: saveAsFavorite.value
            ? QuickTemplate(
                label: note.isNotEmpty
                    ? note
                    : _allCategories.firstWhere((c) => c.id == category).name,
                kind: record.kind,
                amount: value,
                categoryId: category,
              )
            : null,
      );
    } else {
      await transactions.update(record);
    }
    return true;
  }

  /// Deletes the edited record. Returns false when there is nothing to
  /// delete, a save/delete is already running, or the database fails.
  Future<bool> delete() async {
    final id = _editing?.id;
    if (id == null || isSaving.value) return false;
    isSaving.value = true;
    try {
      await transactions.delete(id);
      return true;
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحذف العملية، جرّب مرة ثانية');
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  @override
  void onClose() {
    noteController.dispose();
    super.onClose();
  }
}
