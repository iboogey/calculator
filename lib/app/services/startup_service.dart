import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../data/repositories/recurring_repository.dart';
import 'database_service.dart';

/// Work that happens when the app starts or comes back to the foreground
/// (spec §8.4): create due recurring entries, then refresh every screen so a
/// newly started period shows up.
class StartupService extends GetxService with WidgetsBindingObserver {
  StartupService({
    required this.recurring,
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RecurringRepository recurring;
  final DatabaseService database;
  final DateTime Function() _clock;

  Future<StartupService> init() async {
    await refresh();
    WidgetsBinding.instance.addObserver(this);
    return this;
  }

  Future<void> refresh() async {
    try {
      await recurring.applyDue(_clock());
    } on DatabaseException {
      // Try again on the next resume.
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
