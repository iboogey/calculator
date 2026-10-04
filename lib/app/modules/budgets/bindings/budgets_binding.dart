import 'package:get/get.dart';

import '../controllers/budgets_controller.dart';

class BudgetsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => BudgetsController(
          budgets: Get.find(),
          categories: Get.find(),
          transactions: Get.find(),
          recurring: Get.find(),
          settings: Get.find(),
          database: Get.find(),
        ));
  }
}
