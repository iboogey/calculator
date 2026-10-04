import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/app_bottom_nav.dart';
import '../controllers/settings_controller.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: Obx(() {
        final settings = controller.settings;
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            const _SectionTitle('الشهر المالي'),
            Card(
              child: ListTile(
                title: const Text('يبدأ الشهر يوم'),
                subtitle: const Text('مثلاً يوم نزول الراتب'),
                trailing: DropdownButton<int>(
                  value: settings.periodStartDay,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (var day = 1; day <= 28; day++)
                      DropdownMenuItem(value: day, child: Text('$day')),
                  ],
                  onChanged: (day) {
                    if (day != null) controller.setStartDay(day);
                  },
                ),
              ),
            ),
            const _SectionTitle('العملة'),
            Card(
              child: ListTile(
                title: const Text('العملة'),
                trailing: DropdownButton<String>(
                  value: settings.currencyCode,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final currency in Currencies.all)
                      DropdownMenuItem(
                        value: currency.code,
                        child: Text('${currency.name} (${currency.symbol})'),
                      ),
                  ],
                  onChanged: (code) {
                    if (code != null) controller.setCurrency(code);
                  },
                ),
              ),
            ),
            const _SectionTitle('التذكير اليومي'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('ذكّرني أسجّل مصاريفي'),
                    value: settings.reminderEnabled,
                    onChanged: controller.setReminderEnabled,
                  ),
                  ListTile(
                    enabled: settings.reminderEnabled,
                    title: const Text('الساعة'),
                    trailing: Text(
                      controller.reminderLabel,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () => _pickTime(context, settings.reminderMinutes),
                  ),
                  if (!controller.permissionGranted)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        'الإشعارات مطفية للتطبيق. فعّلها من إعدادات الجهاز لتوصلك التذكيرات وتنبيهات الميزانية.',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const _SectionTitle('إدارة'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.event_repeat_outlined),
                    title: const Text('المصاريف الثابتة'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: controller.openRecurring,
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.star_outline),
                    title: const Text('المفضّلة'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: controller.openFavorites,
                  ),
                ],
              ),
            ),
            const _SectionTitle('النسخ الاحتياطي'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('نسخة احتياطية الآن'),
                    subtitle: Text(
                      controller.lastBackupLabel,
                      style: TextStyle(
                          color: controller.backupOverdue
                              ? AppColors.warning
                              : AppColors.muted),
                    ),
                    onTap: controller.exportBackup,
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.restore),
                    title: const Text('استرجاع من ملف'),
                    onTap: () => _restore(context),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
      bottomNavigationBar: const AppBottomNav(current: Routes.settings),
    );
  }

  Future<void> _restore(BuildContext context) async {
    final summary = await controller.pickBackup();
    if (summary == null || !context.mounted) return;
    final when = summary.exportedAt;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استرجاع النسخة؟'),
        content: Text(
          'رح تنمسح بياناتك الحالية وتنحط مكانها نسخة '
          '${when.day}/${when.month}/${when.year}: '
          '${summary.transactionCount} عملية و ${summary.goalCount} أهداف.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('استرجاع'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final restored = await controller.restore(summary);
    if (restored && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('انسترجعت النسخة')));
    }
  }

  Future<void> _pickTime(BuildContext context, int minutes) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked != null) controller.setReminderTime(picked.hour, picked.minute);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
