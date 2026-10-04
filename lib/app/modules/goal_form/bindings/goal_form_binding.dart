import 'package:get/get.dart';

import '../controllers/goal_form_controller.dart';

class GoalFormBinding extends Bindings {
  @override
  void dependencies() {
    final args = Get.arguments;
    Get.lazyPut(() => GoalFormController(
          savings: Get.find(),
          settings: Get.find(),
          editId: args is int ? args : null,
        ));
  }
}
