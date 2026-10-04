import 'package:get/get.dart';

import '../modules/budgets/bindings/budgets_binding.dart';
import '../modules/budgets/views/budgets_view.dart';
import '../modules/goal_detail/bindings/goal_detail_binding.dart';
import '../modules/goal_detail/views/goal_detail_view.dart';
import '../modules/goal_form/bindings/goal_form_binding.dart';
import '../modules/goal_form/views/goal_form_view.dart';
import '../modules/home/bindings/home_binding.dart';
import '../modules/home/views/home_view.dart';
import '../modules/month_end/bindings/month_end_binding.dart';
import '../modules/month_end/views/month_end_view.dart';
import '../modules/recurring/bindings/recurring_binding.dart';
import '../modules/recurring/views/recurring_view.dart';
import '../modules/recurring_form/bindings/recurring_form_binding.dart';
import '../modules/recurring_form/views/recurring_form_view.dart';
import '../modules/reports/bindings/reports_binding.dart';
import '../modules/reports/views/reports_view.dart';
import '../modules/savings/bindings/savings_binding.dart';
import '../modules/savings/views/savings_view.dart';
import '../modules/settings/bindings/settings_binding.dart';
import '../modules/settings/views/settings_view.dart';
import '../modules/templates/bindings/templates_binding.dart';
import '../modules/templates/views/templates_view.dart';
import '../modules/transaction_form/bindings/transaction_form_binding.dart';
import '../modules/transaction_form/views/transaction_form_view.dart';
import '../modules/transactions/bindings/transactions_binding.dart';
import '../modules/transactions/views/transactions_view.dart';
import 'app_routes.dart';

abstract final class AppPages {
  static const initial = Routes.home;

  static final pages = [
    GetPage(
      name: Routes.home,
      page: () => const HomeView(),
      binding: HomeBinding(),
      transition: Transition.noTransition,
    ),
    GetPage(
      name: Routes.transactions,
      page: () => const TransactionsView(),
      binding: TransactionsBinding(),
      transition: Transition.noTransition,
    ),
    GetPage(
      name: Routes.reports,
      page: () => const ReportsView(),
      binding: ReportsBinding(),
      transition: Transition.noTransition,
    ),
    GetPage(
      name: Routes.budgets,
      page: () => const BudgetsView(),
      binding: BudgetsBinding(),
      transition: Transition.noTransition,
    ),
    GetPage(
      name: Routes.recurring,
      page: () => const RecurringView(),
      binding: RecurringBinding(),
    ),
    GetPage(
      name: Routes.recurringForm,
      page: () => const RecurringFormView(),
      binding: RecurringFormBinding(),
      fullscreenDialog: true,
    ),
    GetPage(
      name: Routes.templates,
      page: () => const TemplatesView(),
      binding: TemplatesBinding(),
    ),
    GetPage(
      name: Routes.savings,
      page: () => const SavingsView(),
      binding: SavingsBinding(),
    ),
    GetPage(
      name: Routes.goalForm,
      page: () => const GoalFormView(),
      binding: GoalFormBinding(),
      fullscreenDialog: true,
    ),
    GetPage(
      name: Routes.goalDetail,
      page: () => const GoalDetailView(),
      binding: GoalDetailBinding(),
    ),
    GetPage(
      name: Routes.monthEnd,
      page: () => const MonthEndView(),
      binding: MonthEndBinding(),
      fullscreenDialog: true,
    ),
    GetPage(
      name: Routes.settings,
      page: () => const SettingsView(),
      binding: SettingsBinding(),
      transition: Transition.noTransition,
    ),
    GetPage(
      name: Routes.transactionForm,
      page: () => const TransactionFormView(),
      binding: TransactionFormBinding(),
      fullscreenDialog: true,
    ),
  ];
}
