import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/savings_goal.dart';
import '../../../data/models/savings_movement.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

class GoalDetailController extends GetxController {
  GoalDetailController({
    required this.savings,
    required this.settings,
    required this.database,
    required this.goalId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SavingsRepository savings;
  final SettingsService settings;
  final DatabaseService database;
  final int goalId;
  final DateTime Function() _clock;

  final goal = Rxn<SavingsGoal>();
  final saved = 0.obs;
  final movements = <SavingsMovement>[].obs;

  late final Worker _reloadOnChange;

  Currency get currency => settings.currency;

  DateTime get today => _clock();

  @override
  void onInit() {
    super.onInit();
    _reloadOnChange = ever(database.revision, (_) => load());
    load();
  }

  Future<void> load() async {
    goal.value = await savings.getGoal(goalId);
    saved.value = (await savings.balances())[goalId] ?? 0;
    movements.assignAll(await savings.getMovements(goalId));
  }

  Future<bool> deposit(String text) => _move(text, 1);

  Future<bool> withdraw(String text) => _move(text, -1);

  Future<bool> _move(String text, int sign) async {
    final amount = Money.parse(text, decimals: 3);
    if (amount == null) return false;
    try {
      await savings.addMovement(SavingsMovement(
        goalId: goalId,
        amount: sign * amount,
        date: DateKeys.dateOnly(_clock()),
        source: SavingsSource.manual,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            DateTime.now().millisecondsSinceEpoch),
      ));
      return true;
    } on InsufficientSavingsException catch (e) {
      Get.find<MessageService>().showError(
          'بالهدف بس ${Money.format(e.available, decimals: currency.decimals)}');
      return false;
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ الحركة');
      return false;
    }
  }

  void openEdit() => Get.toNamed(Routes.goalForm, arguments: goalId);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
