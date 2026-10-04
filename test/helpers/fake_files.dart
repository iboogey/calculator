import 'dart:io';

import 'package:calculator/app/data/providers/file_exchange_provider.dart';

/// Records shared files and returns a chosen text when asked to pick one.
class FakeFileExchangeProvider implements FileExchangeProvider {
  final shared = <String>[];
  String? textToPick;
  final _dir = Directory.systemTemp.createTempSync('masarifi_test');

  @override
  Future<void> shareFile(String path, {required String subject}) async =>
      shared.add(path);

  @override
  Future<String?> pickJsonText() async => textToPick;

  @override
  Future<String> tempDirectory() async => _dir.path;
}
