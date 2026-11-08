import 'package:calculator/app/data/providers/sms_inbox_provider.dart';

/// An in-memory SMS inbox the tests fill with messages.
class FakeSmsInboxProvider implements SmsInboxProvider {
  bool supported = true;
  bool granted = true;
  final messages = <SmsMessage>[];
  int readCount = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<List<SmsMessage>> readInbox({required DateTime after}) async {
    readCount++;
    return messages.where((m) => m.date.isAfter(after)).toList();
  }
}
