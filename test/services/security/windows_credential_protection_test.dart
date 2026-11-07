import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/windows_package_storage.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/security/credential_protection.dart';
import 'package:joycai_image_ai_toolkits/services/security/windows_credential_protection.dart';

import '../../support/in_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const protection = WindowsCredentialProtection();
  tearDown(() => messenger.setMockMethodCallHandler(WindowsPackageStorage.channel, null));

  test('foreign/unknown envelopes and malformed bytes fail closed', () async {
    for (final value in [
      'joycai-secret:v1:old-mac',
      'joycai-secret:v99:unknown',
      '${WindowsCredentialProtection.prefix}not base64!',
    ]) {
      await expectLater(protection.open(value), throwsA(isA<CredentialProtectionException>()));
    }
    messenger.setMockMethodCallHandler(WindowsPackageStorage.channel, (_) async {
      throw PlatformException(code: 'denied', message: 'private diagnostic');
    });
    await expectLater(protection.seal('synthetic'), throwsA(isA<CredentialProtectionException>()));
    expect(const CredentialProtectionException().toString(), isNot(contains('private diagnostic')));
  });

  final executable = Platform.environment['JOYCAI_WINDOWS_NATIVE_TEST_EXE'];
  test(
    'native DPAPI migration, restart, rotation, tamper, rollback, backup and foreign import',
    () async {
      var failSeal = false;
      messenger.setMockMethodCallHandler(WindowsPackageStorage.channel, (call) async {
        if (failSeal && call.method == 'seal') throw PlatformException(code: 'synthetic_failure');
        final process = await Process.start(executable!, [call.method]);
        final output = process.stdout.fold<List<int>>([], (bytes, part) => bytes..addAll(part));
        final errors = process.stderr.drain<void>();
        process.stdin.add(call.arguments as Uint8List);
        await process.stdin.close();
        final result = await output;
        await errors;
        if (await process.exitCode != 0) throw PlatformException(code: 'dpapi_failed');
        return Uint8List.fromList(result);
      });
      final plain = await openTestDatabase();
      addTearDown(() => closeTestDatabase(plain));
      final raw = await plain.database;
      final id = await plain.addChannel(
        LLMChannel(
          displayName: 'Synthetic',
          endpoint: 'https://example.invalid',
          apiKey: 'synthetic-key-你好',
          type: 'openai-api-rest',
        ),
      );
      await plain.saveSetting('proxy_password', 'synthetic-proxy');
      await plain.saveSetting('mcp_token', 'synthetic-token');
      final protected = DatabaseService.forDatabase(raw, credentialProtection: protection);
      failSeal = true;
      await expectLater(
        protected.migrateCredentials(raw),
        throwsA(isA<CredentialProtectionException>()),
      );
      expect((await plain.getChannel(id))!.apiKey, 'synthetic-key-你好');
      failSeal = false;
      await protected.migrateCredentials(raw);
      final envelope = (await raw.query('llm_channels')).single['api_key'] as String;
      expect(envelope, startsWith(WindowsCredentialProtection.prefix));
      await expectLater(plain.getChannel(id), throwsA(isA<CredentialProtectionException>()));
      final restarted = DatabaseService.forDatabase(
        raw,
        credentialProtection: const WindowsCredentialProtection(),
      );
      await restarted.migrateCredentials(raw);
      expect((await restarted.getChannel(id))!.apiKey, 'synthetic-key-你好');
      expect(await restarted.getSetting('proxy_password'), 'synthetic-proxy');
      expect(await restarted.getSetting('mcp_token'), 'synthetic-token');
      await restarted.saveSetting('mcp_token', 'rotated');
      expect(await restarted.getSetting('mcp_token'), 'rotated');
      final before = (await raw.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['mcp_token'],
      )).single['value'];
      failSeal = true;
      await expectLater(
        restarted.saveSetting('mcp_token', 'lost'),
        throwsA(isA<CredentialProtectionException>()),
      );
      expect(
        (await raw.query('settings', where: 'key = ?', whereArgs: ['mcp_token'])).single['value'],
        before,
      );
      failSeal = false;
      final backup = await restarted.getAllDataRaw();
      expect(jsonEncode(backup), isNot(contains('joycai-secret:')));
      (backup['llm_channels'] as List).single['api_key'] = envelope;
      await expectLater(
        restarted.restoreBackup(backup),
        throwsA(isA<CredentialProtectionException>()),
      );
      final corrupt = base64Decode(envelope.substring(WindowsCredentialProtection.prefix.length));
      corrupt[corrupt.length - 1] ^= 1;
      await raw.update('llm_channels', {
        'api_key': '${WindowsCredentialProtection.prefix}${base64Encode(corrupt)}',
      });
      await expectLater(
        restarted.migrateCredentials(raw),
        throwsA(isA<CredentialProtectionException>()),
      );
    },
    skip: !Platform.isWindows || executable == null,
  );
}
