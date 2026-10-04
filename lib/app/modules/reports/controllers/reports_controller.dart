import 'package:get/get.dart';

import '../../../core/logic/period.dart';
import '../../../core/logic/report_calculator.dart';
import '../../../core/utils/currencies.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/settings_service.dart';

class ReportsController extends GetxController {
  ReportsController({
    required this.transactions,
    required this.categories,
    required this.settings,
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const reportPeriods = 6;

  final TransactionRepository transactions;
  final CategoryRepository categories;
  final SettingsService settings;
  final DatabaseService database;
  final DateTime Function() _clock;

  final period = Rxn<Period>();
  final shares = <CategoryShare>[].obs;
  final totals = <PeriodTotals>[].obs;
  final change = RxnInt();
  final totalSpent = 0.obs;

  bool _followsCurrent = true;
  late final Worker _reloadOnChange;

  Currency get currency => settings.currency;

  @override
  void onInit() {
    super.onInit();
    _reloadOnChange = ever(database.revision, (_) => load());
    load();
  }

  Future<void> load() async {
    final current = _followsCurrent
        ? settings.currentPeriod(_clock())
        : period.value ?? settings.currentPeriod(_clock());
    final all = await transactions.getAll();
    final allCategories = await categories.getAll(includeArchived: true);

    final periodTotals = ReportCalculator.totals(
        last: current, count: reportPeriods, transactions: all);
    final now = periodTotals.last.expenses;
    final before = periodTotals[periodTotals.length - 2].expenses;

    period.value = current;
    shares.assignAll(ReportCalculator.byCategory(
      period: current,
      transactions: all,
      categoriesById: {for (final c in allCategories) c.id!: c},
    ));
    totals.assignAll(periodTotals);
    totalSpent.value = now;
    change.value = now == 0
        ? null
        : ReportCalculator.changePercent(previous: before, current: now);
  }

  Future<void> previousPeriod() => _show(period.value!.previous);

  Future<void> nextPeriod() => _show(period.value!.next);

  Future<void> _show(Period value) {
    period.value = value;
    _followsCurrent = value == settings.currentPeriod(_clock());
    return load();
  }

  void openSavings() => Get.toNamed(Routes.savings);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
