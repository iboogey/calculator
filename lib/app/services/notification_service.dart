import 'package:get/get.dart';

import '../core/logic/budget_status.dart';
import '../data/providers/notification_provider.dart';
import 'settings_service.dart';

/// The daily reminder (spec §6.7) and budget alerts (§6.6).
class NotificationService extends GetxService {
  NotificationService(this._provider, this._settings);

  static const reminderId = 1;

  final NotificationProvider _provider;
  final SettingsService _settings;

  /// False when the user refused notifications; Settings shows a hint.
  final permissionGranted = false.obs;

  Worker? _syncOnChange;

  Future<NotificationService> init() async {
    try {
      await _provider.init();
      permissionGranted.value = await _provider.requestPermission();
    } catch (_) {
      permissionGranted.value = false;
    }
    await syncReminder();
    _syncOnChange ??= ever(_settings.settings, (_) => syncReminder());
    return this;
  }

  /// Schedules or cancels the reminder to match the current settings.
  Future<void> syncReminder() async {
    final settings = _settings.settings.value;
    try {
      if (!settings.reminderEnabled || !permissionGranted.value) {
        await _provider.cancel(reminderId);
        return;
      }
      await _provider.scheduleDaily(
        id: reminderId,
        hour: settings.reminderMinutes ~/ 60,
        minute: settings.reminderMinutes % 60,
        title: 'مصاريفي',
        body: 'سجّلت مصاريف اليوم؟',
      );
    } catch (_) {
      // A notification failure must never break the app.
    }
  }

  Future<void> showBudgetAlert(BudgetStatus status, int threshold) async {
    if (!permissionGranted.value) return;
    final name = status.category.name;
    final over = threshold >= 100;
    try {
      await _provider.show(
        id: 1000 + status.category.id! * 10 + (over ? 1 : 0),
        title: over ? 'تجاوزت ميزانية $name' : 'قرّبت تخلص ميزانية $name',
        body: 'صرفت ${status.percent}% من ميزانية هالشهر.',
      );
    } catch (_) {
      // Ignore: the in-app banner still shows the warning.
    }
  }

  @override
  void onClose() {
    _syncOnChange?.dispose();
    super.onClose();
  }
}
