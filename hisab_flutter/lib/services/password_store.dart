/// Statement passwords, kept in the platform keystore (never the database).
/// Mirrors KeychainHelper.swift.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hisab_core/hisab_core.dart';

class PasswordStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String _key(Source source) => 'statement-password-${source.rawValue}';

  static Future<String?> password(Source source) async {
    try {
      return await _storage.read(key: _key(source));
    } catch (_) {
      return null;
    }
  }

  static Future<void> setPassword(Source source, String password) async {
    try {
      await _storage.write(key: _key(source), value: password);
    } catch (_) {
      // Best effort: the user just re-types it next time.
    }
  }
}
