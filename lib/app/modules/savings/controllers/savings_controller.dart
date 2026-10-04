import 'package:get/get.dart';

import '../../../core/logic/goal_projection.dart';
import '../../../core/utils/currencies.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/settings_service.dart';

class SavingsController extends GetxController {
  SavingsController({
    required this.savings,
    required this.settings,
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SavingsRepository savings;
  final SettingsService settings;
  final DatabaseService database;
  final DateTime Function() _clock;

  final goals = <GoalProgress>[].obs;
  final total = 0.obs;

  late final Worker _reloadOnChange;

  Currency get currency => settings.currency;

  @override
  void onInit() {
    super.onInit();
    _reloadOnChange = ever(database.revision, (_) => load());
    load();
  }

  Future<void> load() async {
    final balances = await savings.balances();
    final list = await savings.getGoals();
    goals.assignAll([
      for (final goal in list) GoalProgress(goal: goal, saved: balances[goal.id] ?? 0),
    ]);
    total.value = balances.values.fold(0, (a, b) => a + b);
  }

  int? monthlyNeeded(GoalProgress progress) => GoalProjection.monthlyNeeded(
      progress, settings.currentPeriod(_clock()));

  void openGoal(GoalProgress progress) =>
      Get.toNamed(Routes.goalDetail, arguments: progress.goal.id);

  void openAddGoal() => Get.toNamed(Routes.goalForm);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
