import 'package:get/get.dart';

import '../controllers/recurring_form_controller.dart';

class RecurringFormBinding extends Bindings {
  @override
  void dependencies() {
    final args = Get.arguments;
    Get.lazyPut(() => RecurringFormController(
          recurring: Get.find(),
          categories: Get.find(),
          settings: Get.find(),
          editId: args is int ? args : null,
        ));
  }
}
