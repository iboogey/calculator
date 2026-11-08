import 'package:get/get.dart';

import '../controllers/debts_controller.dart';

class DebtsBinding extends Bindings {
  @override
  void dependencies() {
    final argument = Get.arguments;
    Get.lazyPut(() => DebtsController(
          debts: Get.find(),
          categories: Get.find(),
          settings: Get.find(),
          database: Get.find(),
          initialTab: argument is DebtsTab ? argument : DebtsTab.people,
        ));
  }
}
