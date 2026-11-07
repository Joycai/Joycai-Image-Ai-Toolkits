import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/model_repository.dart';
import 'package:joycai_image_ai_toolkits/services/security/credential_protection.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

// Opaque test handles, deliberately not a cryptographic implementation.
class MemoryProtection implements CredentialProtection {
  final values = <String, String>{};
  bool unavailable = false;
  int? failAfter;
  int writes = 0;
  final preparations = <bool>[];

  @override
  Future<void> prepare({required bool allowCreate}) async {
    preparations.add(allowCreate);
  }

  @override
  Future<String> seal(String plaintext) async {
    if (unavailable || writes == failAfter) throw const CredentialProtectionException();
    final handle = '${CredentialProtection.prefix}${++writes}';
    values[handle] = plaintext;
    return handle;
  }

  @override
  Future<String> open(String envelope) async {
    if (unavailable || !values.containsKey(envelope)) throw const CredentialProtectionException();
    return values[envelope]!;
  }
}

LLMChannel channel(String key, {int? id, String name = 'Synthetic'}) => LLMChannel(
  id: id,
  displayName: name,
  endpoint: 'https://example.invalid',
  apiKey: key,
  type: 'openai-api-rest',
);

void main() {
  sqfliteFfiInit();
  late DatabaseService plain;
  late DatabaseService protected;
  late Database raw;
  late MemoryProtection vault;

  setUp(() async {
    plain = await openTestDatabase();
    raw = await plain.database;
    vault = MemoryProtection();
    protected = DatabaseService.forDatabase(raw, credentialProtection: vault);
  });
  tearDown(() => closeTestDatabase(plain));

  test('migration handles PRAGMA result rows on the Darwin database adapter', () async {
    await plain.addChannel(channel('darwin-original'));
    await protected.migrateCredentials(_DarwinExecuteDatabase(raw));
    expect((await protected.getChannels()).single.apiKey, 'darwin-original');
    expect(
      (await raw.query('llm_channels')).single['api_key'],
      startsWith(CredentialProtection.prefix),
    );
    expect((await raw.rawQuery('PRAGMA secure_delete')).single.values.single, 1);
  });

  test('migrates all three credentials, verifies on restart, remains idempotent', () async {
    final id = await plain.addChannel(channel('synthetic-api'));
    await plain.saveSetting('proxy_password', 'synthetic-proxy');
    await plain.saveSetting('mcp_token', 'synthetic-mcp');
    await protected.migrateCredentials(raw);
    expect(
      (await raw.query('llm_channels')).single['api_key'],
      startsWith(CredentialProtection.prefix),
    );
    expect(await protected.getSetting('proxy_password'), 'synthetic-proxy');
    expect(await protected.getSetting('mcp_token'), 'synthetic-mcp');
    final restarted = DatabaseService.forDatabase(raw, credentialProtection: vault);
    await restarted.migrateCredentials(raw);
    expect((await restarted.getChannel(id))!.apiKey, 'synthetic-api');
    expect(vault.writes, 3);
    expect(vault.preparations, [true, false]);
  });

  test('migration failure rolls back every plaintext row and can retry', () async {
    await plain.addChannel(channel('original-api'));
    await plain.saveSetting('proxy_password', 'original-proxy');
    vault.failAfter = 1;
    await expectLater(
      protected.migrateCredentials(raw),
      throwsA(isA<CredentialProtectionException>()),
    );
    expect((await plain.getChannels()).single.apiKey, 'original-api');
    expect(await plain.getSetting('proxy_password'), 'original-proxy');
    vault.failAfter = null;
    await protected.migrateCredentials(raw);
    expect((await protected.getChannels()).single.apiKey, 'original-api');
  });

  test('SQLite read-back mismatch rolls back the entire migration', () async {
    await plain.addChannel(channel('original'));
    await raw.execute('''CREATE TRIGGER corrupt_credential AFTER UPDATE OF api_key ON llm_channels
      BEGIN UPDATE llm_channels SET api_key = 'corrupt' WHERE id = NEW.id; END''');
    await expectLater(
      protected.migrateCredentials(raw),
      throwsA(isA<CredentialProtectionException>()),
    );
    expect((await plain.getChannels()).single.apiKey, 'original');
  });

  test('new writes and rotations store opaque values; failed rotation preserves old key', () async {
    final id = await protected.addChannel(channel('first-api'));
    await protected.saveSetting('mcp_token', 'first-token');
    await protected.updateChannel(id, channel('second-api', id: id));
    await protected.saveSetting('mcp_token', 'second-token');
    expect((await protected.getChannel(id))!.apiKey, 'second-api');
    expect(await protected.getSetting('mcp_token'), 'second-token');
    final before = (await raw.query('llm_channels')).single['api_key'];
    vault.unavailable = true;
    await expectLater(
      protected.updateChannel(id, channel('lost', id: id)),
      throwsA(isA<CredentialProtectionException>()),
    );
    await expectLater(
      protected.saveSetting('mcp_token', 'lost'),
      throwsA(isA<CredentialProtectionException>()),
    );
    expect((await raw.query('llm_channels')).single['api_key'], before);
    vault.unavailable = false;
    expect(await protected.getSetting('mcp_token'), 'second-token');
  });

  test('missing Keychain fails closed, including an unprotected distribution', () async {
    final id = await protected.addChannel(channel('secret'));
    vault.values.clear();
    await expectLater(protected.getChannel(id), throwsA(isA<CredentialProtectionException>()));
    await expectLater(plain.getChannel(id), throwsA(isA<CredentialProtectionException>()));
    await expectLater(
      protected.migrateCredentials(raw),
      throwsA(isA<CredentialProtectionException>()),
    );
    expect((await raw.query('llm_channels')).single['api_key'], isNotEmpty);
  });

  test(
    'direct builds reject Windows and future envelopes on reads, writes and backup import',
    () async {
      for (final envelope in ['joycai-secret:win-dpapi:v1:foreign', 'joycai-secret:v99:future']) {
        await expectLater(
          plain.protectCredential(envelope),
          throwsA(isA<CredentialProtectionException>()),
        );
        await expectLater(
          plain.revealCredential(envelope),
          throwsA(isA<CredentialProtectionException>()),
        );
        await expectLater(
          protected.revealCredential(envelope),
          throwsA(isA<CredentialProtectionException>()),
        );
      }
    },
  );

  test('backup redacts ciphertext and restores existing credentials despite renumbering', () async {
    await protected.addChannel(channel('backup-api'));
    await protected.saveSetting('proxy_password', 'backup-proxy');
    await protected.saveSetting('mcp_token', 'backup-mcp');
    final backup = await protected.getAllDataRaw();
    final encoded = jsonEncode(backup);
    expect(encoded, isNot(contains(CredentialProtection.prefix)));
    for (final value in ['backup-api', 'backup-proxy', 'backup-mcp']) {
      expect(encoded, isNot(contains(value)));
    }
    await protected.restoreBackup(backup);
    expect((await protected.getChannels()).single.apiKey, 'backup-api');
    expect(await protected.getSetting('proxy_password'), 'backup-proxy');
    expect(await protected.getSetting('mcp_token'), 'backup-mcp');
  });

  test('legacy backup imports encrypt; foreign envelopes roll back restore', () async {
    await protected.addChannel(channel('before'));
    final backup = await protected.getAllDataRaw();
    (backup['llm_channels'] as List).single['api_key'] = 'legacy-import';
    (backup['settings'] as List).add({'key': 'proxy_password', 'value': 'legacy-password'});
    await protected.restoreBackup(backup);
    expect((await protected.getChannels()).single.apiKey, 'legacy-import');
    expect(await protected.getSetting('proxy_password'), 'legacy-password');
    expect(
      (await raw.query('llm_channels')).single['api_key'],
      startsWith(CredentialProtection.prefix),
    );
    (backup['llm_channels'] as List).single['api_key'] = '${CredentialProtection.prefix}foreign';
    await expectLater(
      protected.restoreBackup(backup),
      throwsA(isA<CredentialProtectionException>()),
    );
    expect((await protected.getChannels()).single.apiKey, 'legacy-import');
  });

  test('merge, deletion and reset retain transactional credential ownership', () async {
    final keep = await protected.addChannel(channel('keep'));
    final absorb = await protected.addChannel(channel('absorb', name: 'Other'));
    await ModelRepository(db: protected).mergeChannels(
      channel: channel('merged', id: keep),
      updates: [],
      deletes: [],
      absorbedChannelId: absorb,
    );
    expect((await protected.getChannels()).single.apiKey, 'merged');
    expect(
      (await raw.query('llm_channels')).single['api_key'],
      startsWith(CredentialProtection.prefix),
    );
    await protected.deleteChannel(keep);
    expect(await raw.query('llm_channels'), isEmpty);
    await protected.saveSetting('mcp_token', 'reset-me');
    await protected.resetAllSettings();
    expect(await protected.getSetting('mcp_token'), isNull);
  });
}

/// FMDB's executeUpdate rejects statements yielding SQLITE_ROW; SQLite FFI's
/// execute accepts them. Model that native boundary while using real SQLite for
/// the transaction and data so a successful FFI-only migration cannot hide it.
class _DarwinExecuteDatabase implements Database {
  _DarwinExecuteDatabase(this.inner);
  final Database inner;

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    final rows = await inner.rawQuery(sql, arguments);
    if (rows.isNotEmpty) throw StateError('Darwin execute received SQLITE_ROW');
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) =>
      inner.rawQuery(sql, arguments);

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) =>
      inner.transaction(action, exclusive: exclusive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
