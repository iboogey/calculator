import 'package:get/get.dart';

import '../controllers/recurring_controller.dart';

class RecurringBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => RecurringController(
          recurring: Get.find(),
          categories: Get.find(),
          settings: Get.find(),
          database: Get.find(),
        ));
  }
}
