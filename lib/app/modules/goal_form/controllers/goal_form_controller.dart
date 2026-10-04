import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/savings_goal.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

/// Create a savings goal, or edit/remove the one with [editId].
class GoalFormController extends GetxController {
  GoalFormController({
    required this.savings,
    required this.settings,
    this.editId,
  });

  final SavingsRepository savings;
  final SettingsService settings;
  final int? editId;

  final nameController = TextEditingController();
  final targetController = TextEditingController();
  final _name = ''.obs;
  final _target = ''.obs;
  final targetDate = Rxn<DateTime>();
  final isEditing = false.obs;
  final isSaving = false.obs;

  SavingsGoal? _editing;
  late final Future<void> ready;

  Currency get currency => settings.currency;

  int? get _targetAmount => Money.parse(_target.value, decimals: 3);

  bool get canSave =>
      !isSaving.value &&
      _name.value.trim().isNotEmpty &&
      (_target.value.trim().isEmpty || _targetAmount != null);

  @override
  void onInit() {
    super.onInit();
    nameController.addListener(() => _name.value = nameController.text);
    targetController.addListener(() => _target.value = targetController.text);
    ready = _load();
  }

  Future<void> _load() async {
    if (editId == null) return;
    final goal = await savings.getGoal(editId!);
    if (goal == null) return;
    _editing = goal;
    isEditing.value = true;
    nameController.text = goal.name;
    targetController.text =
        goal.targetAmount == null ? '' : Money.toEditable(goal.targetAmount!);
    targetDate.value = goal.targetDate;
  }

  void setTargetDate(DateTime? value) =>
      targetDate.value = value == null ? null : DateKeys.dateOnly(value);

  Future<bool> save() async {
    if (!canSave) return false;
    final goal = SavingsGoal(
      id: _editing?.id,
      name: _name.value.trim(),
      targetAmount: _targetAmount,
      targetDate: targetDate.value,
      isGeneral: _editing?.isGeneral ?? false,
      createdAt: _editing?.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch),
    );
    isSaving.value = true;
    try {
      if (_editing == null) {
        await savings.addGoal(goal);
      } else {
        await savings.updateGoal(goal);
      }
      return true;
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ الهدف');
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  /// Removes the edited goal; refused (with a message) while it holds money.
  Future<bool> remove() async {
    final goal = _editing;
    if (goal == null || goal.isGeneral) return false;
    try {
      await savings.removeGoal(goal);
      return true;
    } on GoalNotEmptyException catch (e) {
      Get.find<MessageService>().showError(
          'اسحب المبلغ من الهدف أول (فيه ${Money.format(e.balance, decimals: currency.decimals)})');
      return false;
    } on GoalHasRecurringException {
      Get.find<MessageService>().showError(
          'هالهدف عليه ادخار شهري ثابت. احذفه من المصاريف الثابتة أول');
      return false;
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحذف الهدف');
      return false;
    }
  }

  @override
  void onClose() {
    nameController.dispose();
    targetController.dispose();
    super.onClose();
  }
}
