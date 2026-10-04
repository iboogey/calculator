import 'package:get/get.dart';

import '../controllers/transaction_form_controller.dart';

class TransactionFormBinding extends Bindings {
  @override
  void dependencies() {
    final args = Get.arguments;
    Get.lazyPut(() => TransactionFormController(
          transactions: Get.find(),
          categories: Get.find(),
          settings: Get.find(),
          editId: args is int ? args : null,
        ));
  }
}
