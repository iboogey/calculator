import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/logic/month_end_check.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/savings_goal.dart';
import '../../../data/models/savings_movement.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

/// Split last period's leftover across savings goals (spec §6.4).
class MonthEndController extends GetxController {
  MonthEndController({
    required this.savings,
    required this.transactions,
    required this.settings,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SavingsRepository savings;
  final TransactionRepository transactions;
  final SettingsService settings;
  final DateTime Function() _clock;

  final offered = 0.obs;
  final goals = <SavingsGoal>[].obs;
  final allocated = 0.obs;
  final isSaving = false.obs;
  final _inputs = <int, TextEditingController>{};

  late final Future<void> ready;

  Currency get currency => settings.currency;

  bool get canSave =>
      !isSaving.value && allocated.value > 0 && allocated.value <= offered.value;

  @override
  void onInit() {
    super.onInit();
    ready = _load();
  }

  Future<void> _load() async {
    final current = settings.currentPeriod(_clock());
    offered.value = MonthEndCheck.leftoverToOffer(
          current: current,
          lastPromptedKey: settings.settings.value.lastMonthEndPromptPeriod,
          transactions: await transactions.getAll(),
          movements: await savings.getAllMovements(),
        ) ??
        0;
    goals.assignAll(await savings.getGoals());
  }

  TextEditingController controllerFor(int goalId) =>
      _inputs.putIfAbsent(goalId, () {
        final input = TextEditingController();
        input.addListener(_recount);
        return input;
      });

  void _recount() {
    var sum = 0;
    for (final input in _inputs.values) {
      sum += Money.parse(input.text, decimals: 3) ?? 0;
    }
    allocated.value = sum;
  }

  void putAllInGeneral() {
    for (final input in _inputs.values) {
      input.text = '';
    }
    final general = goals.firstWhere((g) => g.isGeneral);
    controllerFor(general.id!).text = Money.toEditable(offered.value);
  }

  /// Saves every amount in one transaction and closes the question for the
  /// period. Returns false when the split is not valid or saving fails.
  Future<bool> save() async {
    if (!canSave) return false;
    isSaving.value = true;
    final date = DateKeys.dateOnly(_clock());
    final now = DateTime.fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch);
    final movements = [
      for (final MapEntry(key: goalId, value: input) in _inputs.entries)
        if (Money.parse(input.text, decimals: 3) case final amount?)
          SavingsMovement(
            goalId: goalId,
            amount: amount,
            date: date,
            source: SavingsSource.monthEnd,
            createdAt: now,
          ),
    ];
    final previous = settings.currentPeriod(_clock()).previous;
    try {
      await savings.addMovements(movements, answeredPeriodKey: previous.key);
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ التوزيع');
      isSaving.value = false;
      return false;
    }
    try {
      await settings.reload();
    } on DatabaseException {
      // Saved already; the next change refreshes the settings anyway.
    } finally {
      isSaving.value = false;
    }
    return true;
  }

  Future<void> skip() async {
    try {
      await _markAnswered();
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ اختيارك');
    }
  }

  Future<void> _markAnswered() {
    final previous = settings.currentPeriod(_clock()).previous;
    return settings.update(settings.settings.value
        .copyWith(lastMonthEndPromptPeriod: previous.key));
  }

  @override
  void onClose() {
    for (final input in _inputs.values) {
      input.dispose();
    }
    super.onClose();
  }
}
