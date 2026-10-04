import 'package:get/get.dart';

import '../controllers/settings_controller.dart';

class SettingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => SettingsController(
        settingsService: Get.find(),
        notifications: Get.find(),
        backup: Get.find(),
        files: Get.find()));
  }
}
