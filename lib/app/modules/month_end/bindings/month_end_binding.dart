import 'package:get/get.dart';

import '../controllers/month_end_controller.dart';

class MonthEndBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => MonthEndController(
          savings: Get.find(),
          transactions: Get.find(),
          settings: Get.find(),
        ));
  }
}
