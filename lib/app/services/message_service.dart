import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Shows short error messages from anywhere (spec §11).
class MessageService extends GetxService {
  /// The last message, kept so tests can check it.
  final lastMessage = RxnString();

  void showError(String message) {
    lastMessage.value = message;
    if (Get.overlayContext == null) return;
    Get.snackbar(
      'صار خطأ',
      message,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
    );
  }
}
