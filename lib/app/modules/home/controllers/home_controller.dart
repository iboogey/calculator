import 'package:get/get.dart';

import '../../../core/logic/balance_calculator.dart';
import '../../../core/logic/period.dart';
import '../../../core/utils/currencies.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/models/transaction_record.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/settings_service.dart';

class HomeController extends GetxController {
  HomeController({
    required this.transactions,
    required this.categories,
    required this.savings,
    required this.settings,
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TransactionRepository transactions;
  final CategoryRepository categories;
  final SavingsRepository savings;
  final SettingsService settings;
  final DatabaseService database;
  final DateTime Function() _clock;

  final summary = Rxn<BalanceSummary>();
  final period = Rxn<Period>();
  final recent = <TransactionRecord>[].obs;
  final categoriesById = <int, TransactionCategory>{}.obs;

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
    final current = settings.currentPeriod(_clock());
    final all = await transactions.getAll();
    final movements = await savings.getAllMovements();
    final allCategories = await categories.getAll(includeArchived: true);
    final latest = await transactions.getRecent(limit: 5);

    categoriesById.assignAll({for (final c in allCategories) c.id!: c});
    recent.assignAll(latest);
    period.value = current;
    summary.value = BalanceCalculator.calculate(
        period: current, transactions: all, movements: movements);
  }

  void openAdd() => Get.toNamed(Routes.transactionForm);

  void openEdit(TransactionRecord t) =>
      Get.toNamed(Routes.transactionForm, arguments: t.id);

  void openAll() => Get.offAllNamed(Routes.transactions);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
