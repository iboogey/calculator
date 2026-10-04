import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/recurring_rule.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/recurring_repository.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

/// Add a fixed monthly income or expense, or edit/delete the one with
/// [editId].
class RecurringFormController extends GetxController {
  RecurringFormController({
    required this.recurring,
    required this.categories,
    required this.settings,
    this.editId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RecurringRepository recurring;
  final CategoryRepository categories;
  final SettingsService settings;
  final int? editId;
  final DateTime Function() _clock;

  final kind = TransactionKind.expense.obs;
  final amountText = ''.obs;
  final categoryId = RxnInt();
  late final RxInt dayOfMonth = min(_clock().day, 28).obs;
  final isEditing = false.obs;
  final isSaving = false.obs;
  final labelController = TextEditingController();
  final amountController = TextEditingController();
  final _allCategories = <TransactionCategory>[].obs;

  RecurringRule? _editing;
  int _editingDecimals = 0;

  late final Future<void> ready;

  Currency get currency => settings.currency;

  int? get amount => Money.parse(amountText.value,
      decimals: max(currency.decimals, _editingDecimals));

  bool get canSave =>
      !isSaving.value && amount != null && categoryId.value != null;

  List<TransactionCategory> get visibleCategories =>
      _allCategories.where((c) => c.kind == kind.value).toList();

  @override
  void onInit() {
    super.onInit();
    amountController.addListener(() => amountText.value = amountController.text);
    ready = _load();
  }

  Future<void> _load() async {
    _allCategories.assignAll(await categories.getAll());
    if (editId == null) return;
    final rule = (await recurring.getAll()).where((r) => r.id == editId).firstOrNull;
    if (rule == null) return;
    _editing = rule;
    isEditing.value = true;
    kind.value = rule.kind == RecurringKind.income
        ? TransactionKind.income
        : TransactionKind.expense;
    labelController.text = rule.label;
    amountController.text = Money.toEditable(rule.amount);
    final dot = amountController.text.indexOf('.');
    _editingDecimals = dot == -1 ? 0 : amountController.text.length - dot - 1;
    categoryId.value = rule.categoryId;
    dayOfMonth.value = rule.dayOfMonth;
  }

  void setKind(TransactionKind value) {
    if (kind.value == value) return;
    kind.value = value;
    categoryId.value = null;
  }

  void selectCategory(int id) => categoryId.value = id;

  void setDay(int day) => dayOfMonth.value = day;

  /// Saves the rule and immediately creates any entry that is already due.
  Future<bool> save() async {
    final value = amount;
    final category = categoryId.value;
    if (!canSave || value == null || category == null) return false;
    isSaving.value = true;
    try {
      final typed = labelController.text.trim();
      final label = typed.isNotEmpty
          ? typed
          : _allCategories.firstWhere((c) => c.id == category).name;
      final recurringKind = kind.value == TransactionKind.income
          ? RecurringKind.income
          : RecurringKind.expense;
      final editing = _editing;
      if (editing == null) {
        await recurring.add(RecurringRule(
          label: label,
          kind: recurringKind,
          amount: value,
          categoryId: category,
          dayOfMonth: dayOfMonth.value,
          startDate: DateKeys.dateOnly(_clock()),
        ));
      } else {
        await recurring.update(editing.copyWith(
          label: label,
          kind: recurringKind,
          amount: value,
          categoryId: category,
          dayOfMonth: dayOfMonth.value,
        ));
      }
      await recurring.applyDue(_clock());
      return true;
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ المصروف الثابت');
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  /// Deletes the rule; entries it already created stay.
  Future<bool> delete() async {
    final id = _editing?.id;
    if (id == null || isSaving.value) return false;
    isSaving.value = true;
    try {
      await recurring.delete(id);
      return true;
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحذف المصروف الثابت');
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  @override
  void onClose() {
    labelController.dispose();
    amountController.dispose();
    super.onClose();
  }
}
