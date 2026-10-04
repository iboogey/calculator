import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Moving files in and out of the app. An interface so tests can use a fake.
abstract class FileExchangeProvider {
  /// Opens the system share sheet (Files, Drive, email…) for [path].
  /// Returns false when the user closed it without sharing.
  Future<bool> shareFile(String path, {required String subject});

  /// Lets the user pick a JSON file; returns its text, or null if cancelled.
  Future<String?> pickJsonText();

  /// A folder for temporary files.
  Future<String> tempDirectory();
}

/// [FileExchangeProvider] using the device's share sheet and file picker.
/// The app itself never uploads anything.
class DeviceFileExchangeProvider implements FileExchangeProvider {
  @override
  Future<bool> shareFile(String path, {required String subject}) async {
    final result = await SharePlus.instance.share(ShareParams(
      files: [XFile(path, mimeType: 'application/json')],
      subject: subject,
    ));
    return result.status != ShareResultStatus.dismissed;
  }

  @override
  Future<String?> pickJsonText() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty) return null;
    return utf8.decode(await files.first.readAsBytes());
  }

  @override
  Future<String> tempDirectory() async => (await getTemporaryDirectory()).path;
}
