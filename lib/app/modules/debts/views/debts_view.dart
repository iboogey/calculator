import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/debts_controller.dart';
import '../widgets/add_person_dialog.dart';
import '../widgets/obligations_tab.dart';
import '../widgets/people_tab.dart';

class DebtsView extends GetView<DebtsController> {
  const DebtsView({super.key});

  Future<void> _addPerson(BuildContext context) => showDialog<String>(
        context: context,
        builder: (_) => AddPersonDialog(onSubmit: controller.addPerson),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الديون')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Obx(() => SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<DebtsTab>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: DebtsTab.people, label: Text('الأشخاص')),
                      ButtonSegment(value: DebtsTab.obligations, label: Text('عليّ')),
                    ],
                    selected: {controller.tab.value},
                    onSelectionChanged: (s) => controller.tab.value = s.first,
                  ),
                )),
          ),
          Expanded(
            child: Obx(() => controller.tab.value == DebtsTab.people
                ? const PeopleTab()
                : const ObligationsTab()),
          ),
        ],
      ),
      floatingActionButton: Obx(() => controller.tab.value == DebtsTab.people
          ? FloatingActionButton.extended(
              onPressed: () => _addPerson(context),
              icon: const Icon(Icons.add),
              label: const Text('إضافة شخص'),
            )
          : FloatingActionButton.extended(
              onPressed: controller.openNewObligation,
              icon: const Icon(Icons.add),
              label: const Text('التزام جديد'),
            )),
    );
  }
}
