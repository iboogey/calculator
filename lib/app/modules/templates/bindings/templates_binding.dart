import 'package:get/get.dart';

import '../controllers/templates_controller.dart';

class TemplatesBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => TemplatesController(
          templates: Get.find(),
          categories: Get.find(),
          settings: Get.find(),
          database: Get.find(),
        ));
  }
}
