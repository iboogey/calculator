import 'package:get/get.dart';

import '../controllers/debt_person_controller.dart';

class DebtPersonBinding extends Bindings {
  @override
  void dependencies() {
    final personId = Get.arguments as int;
    Get.lazyPut(() => DebtPersonController(
          debts: Get.find(),
          settings: Get.find(),
          database: Get.find(),
          personId: personId,
        ));
  }
}
