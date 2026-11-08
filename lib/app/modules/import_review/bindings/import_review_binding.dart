import 'package:get/get.dart';

import '../controllers/import_review_controller.dart';

class ImportReviewBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => ImportReviewController(
          imports: Get.find(),
          categories: Get.find(),
          recurring: Get.find(),
          transactions: Get.find(),
          settings: Get.find(),
          database: Get.find(),
        ));
  }
}
