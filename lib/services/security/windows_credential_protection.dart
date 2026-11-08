import 'dart:convert';
import 'dart:typed_data';

import '../../core/windows_package_storage.dart';
import 'credential_protection.dart';

/// DPAPI uses the signed-in Windows user's OS-managed master keys.
class WindowsCredentialProtection implements CredentialProtection {
  const WindowsCredentialProtection();
  static const prefix = 'joycai-secret:win-dpapi:v1:';

  Future<Uint8List> _call(String method, Uint8List bytes) async {
    try {
      final result = await WindowsPackageStorage.channel.invokeMethod<Uint8List>(method, bytes);
      if (result == null || result.isEmpty) throw const CredentialProtectionException();
      // Engine platform-message buffers can be read-only. Own a writable copy
      // so open() can clear its temporary plaintext without failing in finally.
      return Uint8List.fromList(result);
    } catch (_) {
      throw const CredentialProtectionException();
    }
  }

  @override
  Future<void> prepare({required bool allowCreate}) async {
    // There is no application wrapping key to create. Verify DPAPI availability;
    // existing rows are independently opened before database publication.
    await seal('Joycai credential storage probe');
  }

  @override
  Future<String> seal(String plaintext) async {
    final bytes = Uint8List.fromList(utf8.encode(plaintext));
    try {
      final sealed = '$prefix${base64Encode(await _call('seal', bytes))}';
      if (await open(sealed) != plaintext) throw const CredentialProtectionException();
      return sealed;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Future<String> open(String envelope) async {
    Uint8List? plaintext;
    try {
      if (!envelope.startsWith(prefix)) throw const CredentialProtectionException();
      plaintext = await _call('open', base64Decode(envelope.substring(prefix.length)));
      return utf8.decode(plaintext);
    } catch (_) {
      throw const CredentialProtectionException();
    } finally {
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }
}
