import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/utils/amount_input.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/models/transaction_record.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
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
  final _allCategories = <TransactionCategory>[].obs;
  final noteController = TextEditingController();

  TransactionRecord? _editing;

  /// Completes when categories (and the edited record) are loaded.
  late final Future<void> ready;

  Currency get currency => settings.currency;

  int? get amount => Money.parse(amountText.value, decimals: currency.decimals);

  bool get canSave => amount != null && categoryId.value != null;

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
      AmountInput.append(amountText.value, key, decimals: currency.decimals);

  void backspace() => amountText.value = AmountInput.backspace(amountText.value);

  void selectCategory(int id) => categoryId.value = id;

  void setDate(DateTime value) => date.value = DateKeys.dateOnly(value);

  /// Saves the form. Returns false (and saves nothing) when it is incomplete.
  Future<bool> save() async {
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
      await transactions.add(record);
    } else {
      await transactions.update(record);
    }
    return true;
  }

  Future<void> delete() async {
    final id = _editing?.id;
    if (id != null) await transactions.delete(id);
  }

  @override
  void onClose() {
    noteController.dispose();
    super.onClose();
  }
}
