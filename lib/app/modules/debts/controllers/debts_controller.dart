import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/logic/debt_summary.dart';
import '../../../core/utils/currencies.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/debt_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

enum DebtsTab { people, obligations }

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

  bool _isSaving = false;
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
    final balances = await debts.personBalances();
    final peopleList = await debts.getPeople();
    final obligations = await debts.getObligations();
    final paidTotals = await debts.paidTotals();
    final ordered = DebtSummary.people(peopleList, balances);
    final statuses = DebtSummary.obligations(obligations, paidTotals);
    people.assignAll(ordered);
    unpaid.assignAll(statuses.where((s) => !s.isPaid));
    paid.assignAll(statuses.where((s) => s.isPaid));
    totals.value = DebtSummary.totals(ordered, statuses);
  }

  /// Returns null on success, otherwise the message to show.
  Future<String?> addPerson(String name) async {
    if (_isSaving) return null;
    _isSaving = true;
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
      _isSaving = false;
    }
  }

  void openPerson(PersonBalance p) =>
      Get.toNamed(Routes.debtPerson, arguments: p.person.id);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
