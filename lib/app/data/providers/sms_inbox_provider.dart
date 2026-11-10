import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

/// One text message from the phone's inbox. Only the time and the text are
/// ever read; the sender and every other column stay on the device.
class SmsMessage {
  final DateTime date;
  final String body;

  const SmsMessage({required this.date, required this.body});
}

/// The phone's SMS inbox. An interface so tests can use a fake.
abstract class SmsInboxProvider {
  bool get isSupported;

  Future<bool> hasPermission();

  Future<bool> requestPermission();

  /// Messages with a date strictly after [after], oldest first.
  Future<List<SmsMessage>> readInbox({required DateTime after});
}

/// [SmsInboxProvider] backed by the Android SMS content provider. Everything
/// is read on the device; nothing uses the network.
class DeviceSmsInboxProvider implements SmsInboxProvider {
  static const _channel = MethodChannel('masarifi/sms');

  @override
  bool get isSupported => GetPlatform.isAndroid;

  @override
  Future<bool> hasPermission() => Permission.sms.isGranted;

  @override
  Future<bool> requestPermission() async =>
      (await Permission.sms.request()).isGranted;

  @override
  Future<List<SmsMessage>> readInbox({required DateTime after}) async {
    final rows = await _channel.invokeListMethod<Map>('readInbox', {
          'after': after.millisecondsSinceEpoch,
        }) ??
        const <Map>[];
    return [
      for (final row in rows)
        SmsMessage(
          date: DateTime.fromMillisecondsSinceEpoch(row['date'] as int),
          body: row['body'] as String,
        ),
    ];
  }
}
