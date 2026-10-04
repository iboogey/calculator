import 'package:get/get.dart';

import '../controllers/transactions_controller.dart';

class TransactionsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => TransactionsController(
          transactions: Get.find(),
          categories: Get.find(),
          settings: Get.find(),
          database: Get.find(),
        ));
  }
}
