import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/logic/recurring_generator.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/recurring_rule.dart';
import '../../../data/models/savings_goal.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/recurring_repository.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

/// Add a fixed monthly income, expense or saving, or edit/delete the one
/// with [editId].
class RecurringFormController extends GetxController {
  RecurringFormController({
    required this.recurring,
    required this.categories,
    required this.savings,
    required this.settings,
    this.editId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RecurringRepository recurring;
  final CategoryRepository categories;
  final SavingsRepository savings;
  final SettingsService settings;
  final int? editId;
  final DateTime Function() _clock;

  final kind = RecurringKind.expense.obs;
  final amountText = ''.obs;
  final categoryId = RxnInt();
  final goalId = RxnInt();
  final goals = <SavingsGoal>[].obs;
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

  bool get _isSaving => kind.value == RecurringKind.saving;

  bool get canSave =>
      !isSaving.value &&
      amount != null &&
      (_isSaving ? goalId.value != null : categoryId.value != null);

  List<TransactionCategory> get visibleCategories => _isSaving
      ? const []
      : _allCategories.where((c) => c.kind.name == kind.value.name).toList();

  @override
  void onInit() {
    super.onInit();
    amountController.addListener(() => amountText.value = amountController.text);
    ready = _load();
  }

  Future<void> _load() async {
    _allCategories.assignAll(await categories.getAll());
    goals.assignAll(await savings.getGoals());
    if (editId == null) return;
    final rule = (await recurring.getAll()).where((r) => r.id == editId).firstOrNull;
    if (rule == null) return;
    _editing = rule;
    isEditing.value = true;
    kind.value = rule.kind;
    goalId.value = rule.goalId;
    labelController.text = rule.label;
    amountController.text = Money.toEditable(rule.amount);
    final dot = amountController.text.indexOf('.');
    _editingDecimals = dot == -1 ? 0 : amountController.text.length - dot - 1;
    categoryId.value = rule.categoryId;
    dayOfMonth.value = rule.dayOfMonth;
  }

  void setKind(RecurringKind value) {
    if (kind.value == value) return;
    kind.value = value;
    categoryId.value = null;
    goalId.value = null;
  }

  void selectCategory(int id) => categoryId.value = id;

  void selectGoal(int id) => goalId.value = id;

  void setDay(int day) => dayOfMonth.value = day;

  /// Saves the rule and immediately creates any entry that is already due.
  Future<bool> save() async {
    final value = amount;
    if (!canSave || value == null) return false;
    isSaving.value = true;
    try {
      final saving = _isSaving;
      final category = saving ? null : categoryId.value;
      final goal = saving ? goalId.value : null;
      final typed = labelController.text.trim();
      final label = typed.isNotEmpty
          ? typed
          : saving
              ? goals.firstWhere((g) => g.id == goal).name
              : _allCategories.firstWhere((c) => c.id == category).name;
      final editing = _editing;
      if (editing == null) {
        await recurring.add(RecurringRule(
          label: label,
          kind: kind.value,
          amount: value,
          categoryId: category,
          goalId: goal,
          dayOfMonth: dayOfMonth.value,
          startDate: DateKeys.dateOnly(_clock()),
        ));
      } else {
        // Built directly (not copyWith) so switching between a category and
        // a goal clears the other one.
        final moved = RecurringGenerator.withDay(editing, dayOfMonth.value);
        await recurring.update(RecurringRule(
          id: moved.id,
          label: label,
          kind: kind.value,
          amount: value,
          categoryId: category,
          goalId: goal,
          dayOfMonth: moved.dayOfMonth,
          startDate: moved.startDate,
          lastGeneratedDate: moved.lastGeneratedDate,
          isActive: moved.isActive,
        ));
      }
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ المصروف الثابت');
      isSaving.value = false;
      return false;
    }
    // The rule is saved. Creating its due entries now is a convenience:
    // if it fails, the next start or resume catches up.
    try {
      await recurring.applyDue(_clock());
    } on DatabaseException {
      // Ignored on purpose; reporting "not saved" here would invite a
      // second, duplicate rule.
    } finally {
      isSaving.value = false;
    }
    return true;
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
