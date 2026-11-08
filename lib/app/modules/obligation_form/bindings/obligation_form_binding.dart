import 'package:get/get.dart';

import '../controllers/obligation_form_controller.dart';

class ObligationFormBinding extends Bindings {
  @override
  void dependencies() {
    final args = Get.arguments;
    Get.lazyPut(() => ObligationFormController(
          debts: Get.find(),
          settings: Get.find(),
          editId: args is int ? args : null,
        ));
  }
}
