// Secrets kept in the Android Keystore / iOS Keychain: sign-in tokens, the database key and the device id.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class Vault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureVault implements Vault {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryVault implements Vault {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

String randomSecret([int bytes = 32]) {
  final r = Random.secure();
  return base64UrlEncode(List<int>.generate(bytes, (_) => r.nextInt(256)));
}

/// The database key: generated on this phone the first time, never sent anywhere.
Future<String> databaseKey(Vault v) async {
  final existing = await v.read('dbKey');
  if (existing != null) return existing;
  final k = randomSecret();
  await v.write('dbKey', k);
  return k;
}

Future<String> deviceId(Vault v) async {
  final existing = await v.read('deviceId');
  if (existing != null) return existing;
  final id = 'phone-${randomSecret(12).replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}';
  await v.write('deviceId', id);
  return id;
}
