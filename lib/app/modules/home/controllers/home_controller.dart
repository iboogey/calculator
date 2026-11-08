import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/logic/balance_calculator.dart';
import '../../../core/logic/budget_status.dart';
import '../../../core/logic/debt_summary.dart';
import '../../../core/logic/month_end_check.dart';
import '../../../core/logic/period.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/quick_template.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/models/transaction_record.dart';
import '../../../data/repositories/budget_repository.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/debt_repository.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../data/repositories/template_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';
import '../../debts/controllers/debts_controller.dart';

class HomeController extends GetxController {
  HomeController({
    required this.transactions,
    required this.categories,
    required this.savings,
    required this.templates,
    required this.budgets,
    required this.settings,
    required this.database,
    required this.debts,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TransactionRepository transactions;
  final CategoryRepository categories;
  final SavingsRepository savings;
  final TemplateRepository templates;
  final BudgetRepository budgets;
  final SettingsService settings;
  final DatabaseService database;
  final DebtRepository debts;
  final DateTime Function() _clock;

  final summary = Rxn<BalanceSummary>();
  final period = Rxn<Period>();
  final recent = <TransactionRecord>[].obs;
  final categoriesById = <int, TransactionCategory>{}.obs;
  final favorites = <QuickTemplate>[].obs;

  /// The budget closest to (or furthest past) its limit, when one is at
  /// 80 % or more.
  final urgentBudget = Rxn<BudgetStatus>();

  /// Last period's leftover, while the month-end question is unanswered.
  final monthEndOffer = RxnInt();

  final debtTotals = const DebtTotals(owedToMe: 0, iOwe: 0).obs;

  /// The unpaid obligation due within 3 days (or overdue), if any.
  final dueObligation = Rxn<DueInfo>();

  /// "After settling debts" preview; off on every open, never saved.
  final showSettled = false.obs;

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
    final favoriteList = await templates.getAll();
    final budgetList = await budgets.getAll();
    final people = DebtSummary.people(
        await debts.getPeople(), await debts.personBalances());
    final obligations = DebtSummary.obligations(
        await debts.getObligations(), await debts.paidTotals());

    final byId = {for (final c in allCategories) c.id!: c};
    categoriesById.assignAll(byId);
    recent.assignAll(latest);
    favorites.assignAll(favoriteList);
    period.value = current;
    debtTotals.value = DebtSummary.totals(people, obligations);
    dueObligation.value = DebtSummary.mostUrgent(obligations, _clock());
    summary.value = BalanceCalculator.calculate(
        period: current, transactions: all, movements: movements);
    urgentBudget.value = BudgetCalculator.mostUrgent(BudgetCalculator.calculate(
      period: current,
      budgets: budgetList,
      categoriesById: byId,
      transactions: all,
    ));
    monthEndOffer.value = MonthEndCheck.leftoverToOffer(
      current: current,
      lastPromptedKey: settings.settings.value.lastMonthEndPromptPeriod,
      transactions: all,
      movements: movements,
    );
  }

  /// Adds today's transaction from [favorite]. Returns it (for Undo), or null
  /// when saving failed.
  Future<TransactionRecord?> addFavorite(QuickTemplate favorite) async {
    try {
      return await transactions.add(TransactionRecord(
        kind: favorite.kind,
        amount: favorite.amount,
        categoryId: favorite.categoryId,
        date: DateKeys.dateOnly(_clock()),
        note: favorite.label,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            DateTime.now().millisecondsSinceEpoch),
      ));
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر حفظ العملية، حاول مرة أخرى');
      return null;
    }
  }

  Future<void> undoFavorite(TransactionRecord record) async {
    try {
      await transactions.delete(record.id!);
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر حذف العملية، حاول مرة أخرى');
    }
  }

  void openAdd() => Get.toNamed(Routes.transactionForm);

  void openEdit(TransactionRecord t) =>
      Get.toNamed(Routes.transactionForm, arguments: t.id);

  void openAll() => Get.offAllNamed(Routes.transactions);

  void openBudgets() => Get.offAllNamed(Routes.budgets);

  void openFavorites() => Get.toNamed(Routes.templates);

  /// Answers "not now" for last period's leftover; it is not offered again.
  Future<void> skipMonthEnd() async {
    final previous = settings.currentPeriod(_clock()).previous;
    try {
      await settings.update(settings.settings.value
          .copyWith(lastMonthEndPromptPeriod: previous.key));
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر حفظ اختيارك');
    }
  }

  void openMonthEnd() => Get.toNamed(Routes.monthEnd);

  void toggleSettled() => showSettled.toggle();

  void openDebts([DebtsTab tab = DebtsTab.people]) =>
      Get.toNamed(Routes.debts, arguments: tab);

  void openSavings() => Get.toNamed(Routes.savings);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
