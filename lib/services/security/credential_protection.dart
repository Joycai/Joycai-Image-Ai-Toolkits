import 'package:flutter/services.dart';

/// Storage boundary only; callers always exchange plaintext credentials.
/// The versioned envelope is private to SQLite, never a portable backup format.
abstract class CredentialProtection {
  static const prefix = 'joycai-secret:v1:';
  static const settingKeys = {'proxy_password', 'mcp_token'};

  /// Only bootstrap may create a key, and only if no encrypted rows exist.
  Future<void> prepare({required bool allowCreate});
  Future<String> seal(String plaintext);
  Future<String> open(String envelope);
}

class CredentialProtectionException implements Exception {
  const CredentialProtectionException();

  @override
  String toString() => 'Credential storage unavailable. Check Keychain access and retry.';
}

/// Apple CryptoKit encryption backed by the app's data-protection Keychain.
class MacCredentialProtection implements CredentialProtection {
  const MacCredentialProtection();
  static const _channel = MethodChannel('joycai/credential_protection');

  Future<String> _call(String method, Object value) async {
    try {
      final result = await _channel.invokeMethod<String>(method, value);
      if (result == null) throw const CredentialProtectionException();
      return result;
    } catch (_) {
      // Neither native error details nor credentials may enter logs/UI errors.
      throw const CredentialProtectionException();
    }
  }

  @override
  Future<void> prepare({required bool allowCreate}) async {
    await _call('prepare', allowCreate);
  }

  @override
  Future<String> seal(String plaintext) async {
    final sealed = await _call('seal', plaintext);
    if (!sealed.startsWith(CredentialProtection.prefix) || await open(sealed) != plaintext) {
      throw const CredentialProtectionException();
    }
    return sealed;
  }

  @override
  Future<String> open(String envelope) => _call('open', envelope);
}
