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
          ],
        );
      }),
      bottomNavigationBar: const AppBottomNav(current: Routes.settings),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(text,
          style: const TextStyle(
              color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }
}
