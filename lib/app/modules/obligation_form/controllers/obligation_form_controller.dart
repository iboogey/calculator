import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/obligation.dart';
import '../../../data/repositories/debt_repository.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';
import '../../../widgets/money_text.dart';

/// Create an obligation, or edit/delete the one with [editId].
class ObligationFormController extends GetxController {
  ObligationFormController({
    required this.debts,
    required this.settings,
    this.editId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DebtRepository debts;
  final SettingsService settings;
  final int? editId;
  final DateTime Function() _clock;

  /// The amount field's text; [amountText] follows it.
  final amountController = TextEditingController();
  final amountText = ''.obs;
  final titleController = TextEditingController();
  final _title = ''.obs;
  final noteController = TextEditingController();
  final dueDate = Rxn<DateTime>();

  /// Up to 5 distinct titles used before, newest first.
  final recentTitles = <String>[].obs;
  final isEditing = false.obs;
  final isSaving = false.obs;

  Obligation? _editing;

  /// Fraction digits of the edited amount, so a 3-decimal amount saved
  /// before a switch to a 2-decimal currency stays editable.
  int _editingDecimals = 0;

  /// Completes when recent titles (and the edited obligation) are loaded.
  late final Future<void> ready;

  Currency get currency => settings.currency;
  DateTime get today => _clock();

  /// Fraction digits the amount field accepts.
  int get inputDecimals => max(currency.decimals, _editingDecimals);

  int? get amount => Money.parse(amountText.value, decimals: inputDecimals);

  bool get canSave =>
      !isSaving.value && amount != null && _title.value.trim().isNotEmpty;

  @override
  void onInit() {
    super.onInit();
    amountController
        .addListener(() => amountText.value = amountController.text);
    titleController.addListener(() => _title.value = titleController.text);
    ready = _load();
  }

  Future<void> _load() async {
    try {
      recentTitles.assignAll(await debts.recentTitles());
      if (editId == null) return;
      final o = await debts.getObligation(editId!);
      if (o == null) return;
      _editing = o;
      isEditing.value = true;
      final editable = Money.toEditable(o.amount);
      final dot = editable.indexOf('.');
      _editingDecimals = dot == -1 ? 0 : editable.length - dot - 1;
      amountController.text = editable;
      titleController.text = o.title;
      noteController.text = o.note ?? '';
      dueDate.value = o.dueDate;
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر تحميل الالتزام، حاول مرة أخرى');
    }
  }

  void useTitle(String title) {
    titleController.text = title;
    titleController.selection =
        TextSelection.collapsed(offset: titleController.text.length);
  }

  void setDueDate(DateTime? value) =>
      dueDate.value = value == null ? null : DateKeys.dateOnly(value);

  /// Saves the form. Returns false (and saves nothing) when it is incomplete,
  /// a save is already running, the amount is below what was paid, or the
  /// database fails (a message is shown).
  Future<bool> save() async {
    if (!canSave) return false;
    final value = amount!;
    final note = noteController.text.trim();
    final editing = _editing;
    final o = Obligation(
      id: editing?.id,
      title: _title.value.trim(),
      amount: value,
      dueDate: dueDate.value,
      note: note.isEmpty ? null : note,
      createdAt: editing?.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(_clock().millisecondsSinceEpoch),
    );
    isSaving.value = true;
    try {
      if (editing == null) {
        await debts.addObligation(o);
      } else {
        await debts.updateObligation(o);
      }
      return true;
    } on AmountBelowPaidException catch (e) {
      Get.find<MessageService>().showError(
          'لا يمكن أن يقل المبلغ عن المدفوع (${MoneyText.label(e.paid, currency)})');
      return false;
    } on ArgumentError {
      return false;
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر حفظ الالتزام، حاول مرة أخرى');
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  /// Deletes the edited obligation with its payments. Returns false when
  /// there is nothing to delete, a save is running, or the database fails.
  Future<bool> delete() async {
    final id = _editing?.id;
    if (id == null || isSaving.value) return false;
    isSaving.value = true;
    try {
      await debts.deleteObligation(id);
      return true;
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر الحذف، حاول مرة أخرى');
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  @override
  void onClose() {
    amountController.dispose();
    titleController.dispose();
    noteController.dispose();
    super.onClose();
  }
}
