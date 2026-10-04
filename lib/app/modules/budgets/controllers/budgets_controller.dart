import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/logic/budget_status.dart';
import '../../../core/logic/period.dart';
import '../../../core/logic/recurring_generator.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/recurring_rule.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/repositories/budget_repository.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/recurring_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

class BudgetsController extends GetxController {
  BudgetsController({
    required this.budgets,
    required this.categories,
    required this.transactions,
    required this.recurring,
    required this.settings,
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final BudgetRepository budgets;
  final CategoryRepository categories;
  final TransactionRepository transactions;
  final RecurringRepository recurring;
  final SettingsService settings;
  final DatabaseService database;
  final DateTime Function() _clock;

  final statuses = <BudgetStatus>[].obs;

  /// Expense categories that have no budget yet.
  final unbudgeted = <TransactionCategory>[].obs;
  final rules = <RecurringRule>[].obs;
  final period = Rxn<Period>();

  late final Worker _reloadOnChange;

  Currency get currency => settings.currency;

  DateTime get today => _clock();

  /// Days until the period ends, counting today.
  int get daysLeft {
    final p = period.value;
    if (p == null) return 0;
    return p.end.difference(DateKeys.dateOnly(_clock())).inDays;
  }

  @override
  void onInit() {
    super.onInit();
    _reloadOnChange = ever(database.revision, (_) => load());
    load();
  }

  Future<void> load() async {
    final current = settings.currentPeriod(_clock());
    final all = await budgets.getAll();
    final allCategories = await categories.getAll(includeArchived: true);
    final expenseCategories =
        await categories.getAll(kind: TransactionKind.expense);
    final inPeriod = await transactions.getBetween(current.start, current.end);
    final activeRules = (await recurring.getAll()).where((r) => r.isActive);

    final budgeted = {for (final b in all) b.categoryId};
    period.value = current;
    statuses.assignAll(BudgetCalculator.calculate(
      period: current,
      budgets: all,
      categoriesById: {for (final c in allCategories) c.id!: c},
      transactions: inPeriod,
    ));
    unbudgeted.assignAll(
        expenseCategories.where((c) => !budgeted.contains(c.id)));
    rules.assignAll(activeRules);
  }

  /// Saves the limit typed as [text]. Returns false for an invalid amount or
  /// a database failure.
  Future<bool> setLimit(int categoryId, String text) async {
    final limit = Money.parse(text, decimals: currency.decimals);
    if (limit == null) return false;
    try {
      await budgets.setLimit(categoryId, limit);
      return true;
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ الميزانية');
      return false;
    }
  }

  Future<void> removeLimit(int categoryId) async {
    try {
      await budgets.remove(categoryId);
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحذف الميزانية');
    }
  }

  DateTime nextDue(RecurringRule rule) =>
      RecurringGenerator.nextDueDate(rule, _clock());

  void openRecurring() => Get.toNamed(Routes.recurring);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
