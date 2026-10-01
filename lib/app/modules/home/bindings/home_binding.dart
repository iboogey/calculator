import 'package:get/get.dart';

import '../controllers/home_controller.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => HomeController(
          transactions: Get.find(),
          categories: Get.find(),
          savings: Get.find(),
          settings: Get.find(),
          database: Get.find(),
        ));
  }
}
