import 'package:get/get.dart';

import '../controllers/savings_controller.dart';

class SavingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => SavingsController(
          savings: Get.find(),
          settings: Get.find(),
          database: Get.find(),
        ));
  }
}
