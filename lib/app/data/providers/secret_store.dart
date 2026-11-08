import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_settings.dart';

/// Secure on-device storage for secrets such as AI API keys. Keys must never
/// go into SQLite, logs or backups. An interface so tests can use a fake.
abstract class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// The storage name of the API key for [provider].
String apiKeyName(AiProviderKind provider) => 'ai_key_${provider.name}';

/// [SecretStore] backed by the platform keystore (Android Keystore / iOS
/// Keychain) through flutter_secure_storage.
class DeviceSecretStore implements SecretStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
