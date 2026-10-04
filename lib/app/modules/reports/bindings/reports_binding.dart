import 'package:get/get.dart';

import '../controllers/reports_controller.dart';

class ReportsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => ReportsController(
          transactions: Get.find(),
          categories: Get.find(),
          settings: Get.find(),
          database: Get.find(),
        ));
  }
}
