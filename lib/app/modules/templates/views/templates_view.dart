import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../widgets/category_avatar.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/money_text.dart';
import '../controllers/templates_controller.dart';

class TemplatesView extends GetView<TemplatesController> {
  const TemplatesView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المفضّلة')),
      body: Obx(() {
        final items = controller.items.toList();
        final categories = Map.of(controller.categoriesById);
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.star_outline,
            message: 'لما تضيف عملية، اختار "احفظها كمفضّلة" لتصير زر بضغطة وحدة بالرئيسية.',
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Card(
              child: Column(
                children: [
                  for (final (index, item) in items.indexed) ...[
                    if (index > 0) const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: categories[item.categoryId] == null
                          ? null
                          : CategoryAvatar(category: categories[item.categoryId]!),
                      title: Text(item.label),
                      subtitle: MoneyText(item.amount, currency: controller.currency),
                      trailing: IconButton(
                        tooltip: 'حذف ${item.label}',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => controller.delete(item),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}
