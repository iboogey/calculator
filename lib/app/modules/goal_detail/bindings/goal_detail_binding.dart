import 'package:get/get.dart';

import '../controllers/goal_detail_controller.dart';

class GoalDetailBinding extends Bindings {
  @override
  void dependencies() {
    final goalId = Get.arguments as int;
    Get.lazyPut(() => GoalDetailController(
          savings: Get.find(),
          settings: Get.find(),
          database: Get.find(),
          goalId: goalId,
        ));
  }
}
