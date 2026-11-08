import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../data/repositories/recurring_repository.dart';
import 'database_service.dart';
import 'sms_import_service.dart';

/// Work that happens when the app starts or comes back to the foreground
/// (spec §8.4): create due recurring entries, then refresh every screen so a
/// newly started period shows up.
class StartupService extends GetxService with WidgetsBindingObserver {
  StartupService({
    required this.recurring,
    required this.database,
    required this.smsImport,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RecurringRepository recurring;
  final DatabaseService database;
  final SmsImportService smsImport;
  final DateTime Function() _clock;

  /// Creates due recurring entries before the app shows; the SMS scan (which
  /// may wait on several AI calls) runs in the background and refreshes the
  /// screens when it is done.
  Future<StartupService> init() async {
    await _applyDue();
    database.notifyChanged();
    unawaited(_scan());
    WidgetsBinding.instance.addObserver(this);
    return this;
  }

  /// Creates due recurring entries and refreshes every screen, then scans
  /// the SMS inbox; the returned future also waits for the scan.
  Future<void> refresh() async {
    await _applyDue();
    database.notifyChanged();
    await _scan();
  }

  Future<void> _applyDue() async {
    try {
      await recurring.applyDue(_clock());
    } on DatabaseException {
      // Try again on the next resume.
    }
  }

  /// Never throws: a failed scan must never stop the app; the next resume
  /// retries.
  Future<void> _scan() async {
    try {
      await smsImport.scan(_clock());
    } catch (_) {
      // Retried on the next resume.
    }
    database.notifyChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }
}
