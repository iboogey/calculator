import 'package:get/get.dart';

import '../controllers/import_review_controller.dart';
import '../controllers/voice_controller.dart';

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
          debts: Get.find(),
          openVoice: Get.arguments == ImportReviewController.voiceArgument,
        ));
    Get.lazyPut(() => VoiceController(
          speech: Get.find(),
          ai: Get.find(),
          imports: Get.find(),
          categories: Get.find(),
          debts: Get.find(),
          settings: Get.find(),
        ));
  }
}
