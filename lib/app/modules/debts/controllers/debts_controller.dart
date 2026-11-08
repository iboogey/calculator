import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/logic/debt_summary.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/obligation_payment.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/debt_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';
import '../../../widgets/money_text.dart';

enum DebtsTab { people, obligations }

/// What the pay sheet returns. [expenseCategoryId] is null when the payment
/// is not recorded as an expense.
class PayDraft {
  const PayDraft({
    required this.amount,
    required this.date,
    this.expenseCategoryId,
  });

  final int amount;
  final DateTime date;
  final int? expenseCategoryId;
}

class DebtsController extends GetxController {
  DebtsController({
    required this.debts,
    required this.categories,
    required this.settings,
    required this.database,
    this.initialTab = DebtsTab.people,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DebtRepository debts;
  final CategoryRepository categories;
  final SettingsService settings;
  final DatabaseService database;
  final DebtsTab initialTab;
  final DateTime Function() _clock;

  late final tab = initialTab.obs;
  final people = <PersonBalance>[].obs;
  final unpaid = <ObligationStatus>[].obs;
  final paid = <ObligationStatus>[].obs;
  final totals = const DebtTotals(owedToMe: 0, iOwe: 0).obs;
  final showPaid = false.obs;

  /// Active expense categories, for the pay sheet.
  final expenseCategories = <TransactionCategory>[].obs;
  final isSaving = false.obs;

  /// A one-off message for the view to show as a SnackBar, then clear.
  final lastNotice = RxnString();

  late final Worker _reloadOnChange;

  Currency get currency => settings.currency;
  DateTime get today => _clock();

  /// The bills category ('فواتير'), else the first active expense category.
  int? get defaultExpenseCategoryId {
    for (final c in expenseCategories) {
      if (c.iconKey == 'bills') return c.id;
    }
    return expenseCategories.isEmpty ? null : expenseCategories.first.id;
  }

  @override
  void onInit() {
    super.onInit();
    _reloadOnChange = ever(database.revision, (_) => load());
    load();
  }

  /// Sum of what people owe me / what I owe people, without obligations.
  int get peopleOwedToMe =>
      people.fold(0, (sum, p) => p.balance > 0 ? sum + p.balance : sum);

  int get peopleIOwe =>
      people.fold(0, (sum, p) => p.balance < 0 ? sum - p.balance : sum);

  Future<void> load() async {
    final balances = await debts.personBalances();
    final peopleList = await debts.getPeople();
    final obligations = await debts.getObligations();
    final paidTotals = await debts.paidTotals();
    final expense = await categories.getAll(kind: TransactionKind.expense);
    final ordered = DebtSummary.people(peopleList, balances);
    final statuses = DebtSummary.obligations(obligations, paidTotals);
    people.assignAll(ordered);
    unpaid.assignAll(statuses.where((s) => !s.isPaid));
    paid.assignAll(statuses.where((s) => s.isPaid));
    totals.value = DebtSummary.totals(ordered, statuses);
    expenseCategories.assignAll(expense);
  }

  /// Returns null on success, otherwise the message to show.
  Future<String?> addPerson(String name) async {
    if (isSaving.value) return null;
    isSaving.value = true;
    try {
      await debts.addPerson(name);
      return null;
    } on ArgumentError {
      return 'اكتب الاسم';
    } on DuplicateNameException {
      return 'هذا الاسم موجود مسبقًا';
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر حفظ الاسم، حاول مرة أخرى');
      return null;
    } finally {
      isSaving.value = false;
    }
  }

  void openPerson(PersonBalance p) =>
      Get.toNamed(Routes.debtPerson, arguments: p.person.id);

  // ---- Obligations ----

  /// Days left until [s] is due, or null when it has no due date.
  DueInfo? dueOf(ObligationStatus s) {
    final due = s.obligation.dueDate;
    if (due == null) return null;
    return DueInfo(status: s, daysLeft: DebtSummary.daysUntil(due, today));
  }

  /// Records a payment. Returns false when one is already being saved or it
  /// fails (a message is shown). Sets [lastNotice] when it completes [s].
  Future<bool> pay(ObligationStatus s, PayDraft d) async {
    if (isSaving.value) return false;
    isSaving.value = true;
    final o = s.obligation;
    try {
      await debts.pay(
        obligationId: o.id!,
        amount: d.amount,
        date: DateKeys.dateOnly(d.date),
        expenseCategoryId: d.expenseCategoryId,
      );
      final paid = (await debts.paidTotals())[o.id] ?? 0;
      if (paid >= o.amount) lastNotice.value = 'تم سداد ${o.title}';
      return true;
    } on OverpaymentException catch (e) {
      Get.find<MessageService>().showError(
          'المبلغ أكبر من المتبقي (${MoneyText.label(e.remaining, currency)})');
      return false;
    } on DatabaseException {
      Get.find<MessageService>()
          .showError('تعذّر تسجيل التسديد، حاول مرة أخرى');
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  /// Deletes [s] with its payments; the expenses they created stay.
  Future<void> deleteObligation(ObligationStatus s) async {
    try {
      await debts.deleteObligation(s.obligation.id!);
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر الحذف، حاول مرة أخرى');
    }
  }

  /// Newest first; empty (with a message) when loading fails.
  Future<List<ObligationPayment>> paymentsOf(ObligationStatus s) async {
    try {
      return await debts.getPayments(s.obligation.id!);
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر تحميل السجل، حاول مرة أخرى');
      return const [];
    }
  }

  /// Deletes [p] and the expense it created, if any.
  Future<void> deletePayment(ObligationPayment p) async {
    try {
      await debts.deletePayment(p);
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر الحذف، حاول مرة أخرى');
    }
  }

  void openNewObligation() => Get.toNamed(Routes.obligationForm);

  void openEditObligation(ObligationStatus s) =>
      Get.toNamed(Routes.obligationForm, arguments: s.obligation.id);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
