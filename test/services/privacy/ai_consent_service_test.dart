import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_model_config.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/privacy/ai_consent_service.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_failure.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

AiConsentScope scope({
  String endpoint = 'https://example.test/v1',
  String destination = 'https://example.test/chat',
  String? proxy,
}) => AiConsentScope.forRequest(
  endpoint: endpoint,
  destination: Uri.parse(destination),
  proxy: proxy,
);

class TestConfig extends LLMModelConfig {
  final http.Client client;
  TestConfig(this.client)
    : super(
        modelId: 'test',
        channelType: 'vendor',
        endpoint: 'https://example.test/v1',
        apiKey: 'secret',
      );
  @override
  http.Client buildClient() => client;
}

void main() {
  sqfliteFfiInit();
  late AiConsentService service;
  late AiConsentService original;
  String? stored;
  test('dismissing consent blocks this request without remembering a refusal', () async {
    service.requestConsent = (_) async => null;
    await expectLater(
      service.require(scope()),
      throwsA(isA<AiConsentRequired>().having((e) => e.reason, 'reason', 'no-decision')),
    );
    expect(service.decisions, isEmpty);
    expect(stored, isNull);
    service.requestConsent = (_) async => true;
    await service.require(scope());
    expect(service.isAllowed(scope()), isTrue);
  });

  test('image CDN denial stays a consent error and does not retry or transmit', () async {
    var sends = 0;
    final config = TestConfig(
      MockClient((_) async {
        sends++;
        return http.Response('ok', 200);
      }),
    );
    service.requestConsent = (recipient) async => recipient.recipient == 'https://example.test';
    final client = config.createClient();
    addTearDown(client.close);
    await client.post(Uri.parse('https://example.test/images'));
    final logs = <String>[];
    try {
      await resolveImageRef(
        'https://cdn.test/image?token=secret',
        client,
        (message, {level = 'INFO'}) => logs.add(message),
        retryDelay: Duration.zero,
      );
      fail('CDN download must require its own consent');
    } on AiConsentRequired catch (error) {
      expect(error.scope!.recipient, 'https://cdn.test');
      expect(error.toString(), contains('https://cdn.test'));
      expect(taskFailure(error)['code'], 'consentRequired');
    }
    expect(sends, 1);
    expect(logs.where((line) => line.startsWith('GET ')), hasLength(1));
    expect(logs.join('\n'), contains('reason=declined'));
    expect(logs.join('\n'), isNot(contains('Retrying')));
    await service.askAgain(scope(destination: 'https://cdn.test/image'));
    service.requestConsent = (_) async => true;
    await client.get(Uri.parse('https://cdn.test/image'));
    expect(sends, 2);
  });
  setUp(() {
    stored = null;
    original = AiConsentService.instance;
    service = AiConsentService.withStore(
      read: () async => stored,
      write: (value) async {
        stored = value;
      },
    );
    AiConsentService.instance = service;
  });
  tearDown(() {
    LLMClientPool.disposeAll();
    AiConsentService.instance = original;
    service.dispose();
  });

  test('no presenter and malformed storage fail closed', () async {
    stored = '{invalid';
    await expectLater(service.require(scope()), throwsA(isA<AiConsentRequired>()));
    expect(service.decisions, isEmpty);
  });

  test('explicit allowance survives restart; decline is remembered', () async {
    var prompts = 0;
    service.requestConsent = (_) async {
      prompts++;
      return true;
    };
    await service.require(scope());
    await service.require(scope());
    expect(prompts, 1);
    final restored = AiConsentService.withStore(read: () async => stored, write: (_) async {});
    addTearDown(restored.dispose);
    await restored.require(scope()); // no UI: uses persisted grant
    await service.revoke(scope());
    await expectLater(service.require(scope()), throwsA(isA<AiConsentRequired>()));
    expect(prompts, 1);
    await service.askAgain(scope());
    service.requestConsent = (_) async {
      prompts++;
      return false;
    };
    await expectLater(service.require(scope()), throwsA(isA<AiConsentRequired>()));
    await expectLater(service.require(scope()), throwsA(isA<AiConsentRequired>()));
    expect(prompts, 2);
    final deniedRestart = AiConsentService.withStore(read: () async => stored, write: (_) async {});
    addTearDown(deniedRestart.dispose);
    await expectLater(deniedRestart.require(scope()), throwsA(isA<AiConsentRequired>()));
  });

  test('routes reuse consent while actual host, port, scheme and proxy require consent', () async {
    var prompts = 0;
    service.requestConsent = (_) async {
      prompts++;
      return true;
    };
    await service.require(scope());
    for (final changed in [
      scope(endpoint: 'https://example.test/other'),
      scope(destination: 'https://uploads.test/file'),
      scope(destination: 'https://example.test:444/chat'),
      scope(destination: 'http://example.test/chat'),
      scope(proxy: 'proxy.test:8080'),
    ]) {
      await service.require(changed);
    }
    expect(prompts, 5);
  });

  test('legacy grants and refusals apply across routes after restart', () async {
    final originalScope = scope();
    stored = jsonEncode([
      {...originalScope.toJson(), 'key': 'legacy-route-key', 'allowed': true},
    ]);
    final other = scope(endpoint: 'https://example.test/images');
    await service.require(other); // No presenter: reuse the legacy decision.
    expect(service.isAllowed(other), true);
    await service.revoke(originalScope);
    await expectLater(service.require(other), throwsA(isA<AiConsentRequired>()));
    await service.askAgain(other);
    var prompts = 0;
    service.requestConsent = (_) async {
      prompts++;
      return true;
    };
    await Future.wait([service.require(other), service.require(originalScope)]);
    expect(prompts, 1);
  });

  test('conflicting legacy records display and enforce the remembered refusal', () async {
    stored = jsonEncode([
      {...scope().toJson(), 'key': 'old-denial', 'allowed': false},
      {...scope().toJson(), 'key': 'old-grant', 'allowed': true},
    ]);
    await service.load();
    expect(service.recipientDecisions.single.allowed, false);
    expect(service.isAllowed(scope()), false);
    await expectLater(service.require(scope()), throwsA(isA<AiConsentRequired>()));
  });

  test('concurrent requests share one prompt; revoke invalidates pending approval', () async {
    var prompts = 0;
    final shown = Completer<void>();
    final answer = Completer<bool>();
    service.requestConsent = (_) {
      prompts++;
      shown.complete();
      return answer.future;
    };
    final a = service.require(scope());
    final b = service.require(scope());
    final checkA = expectLater(a, throwsA(isA<AiConsentRequired>()));
    final checkB = expectLater(b, throwsA(isA<AiConsentRequired>()));
    await shown.future;
    await service.revoke(scope());
    answer.complete(true);
    await Future.wait([checkA, checkB]);
    expect(prompts, 1);
    expect(service.isAllowed(scope()), false);
  });

  test('same-scope concurrent acceptance is stored once', () async {
    var prompts = 0;
    service.requestConsent = (_) async {
      prompts++;
      return true;
    };
    await Future.wait(List.generate(5, (_) => service.require(scope())));
    expect(prompts, 1);
    expect((jsonDecode(stored!) as List).length, 1);
  });

  test('failed persistence never leaves an in-memory grant', () async {
    final broken = AiConsentService.withStore(
      read: () async => null,
      write: (_) async => throw StateError('disk full'),
    )..requestConsent = (_) async => true;
    addTearDown(broken.dispose);
    await expectLater(broken.require(scope()), throwsStateError);
    expect(broken.isAllowed(scope()), false);
  });

  test('records redact credentials, queries and request paths', () async {
    service.requestConsent = (_) async => true;
    await service.require(
      scope(
        endpoint: 'https://user:password@example.test/v1?key=secret',
        destination: 'https://example.test/files/private?token=signed',
        proxy: 'http://proxyuser:proxypass@proxy.test:8080',
      ),
    );
    for (final value in ['password', 'secret', 'signed', 'private', 'proxyuser', 'proxypass']) {
      expect(stored, isNot(contains(value)));
    }
    expect(service.decisions.single.scope.proxy, 'http://proxy.test:8080');
  });

  test('existing client checks every send, blocks after revoke, disables redirects', () async {
    var sends = 0;
    final config = TestConfig(
      MockClient((request) async {
        sends++;
        expect(request.followRedirects, false);
        return http.Response('ok', 200);
      }),
    );
    final client = config.createClient();
    addTearDown(client.close);
    service.requestConsent = (_) async => false;
    await expectLater(
      client.post(Uri.parse('https://example.test/chat'), body: 'private'),
      throwsA(isA<AiConsentRequired>()),
    );
    expect(sends, 0);
    await service.askAgain(service.decisions.single.scope);
    service.requestConsent = (_) async => true;
    await client.post(Uri.parse('https://example.test/chat'), body: 'private');
    expect(sends, 1);
    await service.revoke(service.decisions.single.scope);
    await expectLater(
      client.post(Uri.parse('https://example.test/chat'), body: 'private'),
      throwsA(isA<AiConsentRequired>()),
    );
    expect(sends, 1);
  });

  test('aborted request awaiting consent cannot send after approval', () async {
    var sends = 0;
    final config = TestConfig(
      MockClient((_) async {
        sends++;
        return http.Response('ok', 200);
      }),
    );
    final client = config.createClient();
    addTearDown(client.close);
    final shown = Completer<void>();
    final answer = Completer<bool>();
    final abort = Completer<void>();
    service.requestConsent = (_) {
      shown.complete();
      return answer.future;
    };
    final request = http.AbortableRequest(
      'POST',
      Uri.parse('https://example.test/chat'),
      abortTrigger: abort.future,
    )..body = 'private';
    final check = expectLater(client.send(request), throwsA(isA<http.RequestAbortedException>()));
    await shown.future;
    abort.complete();
    answer.complete(true);
    await check;
    expect(sends, 0);
  });

  test('approved jobs are not held behind another recipient prompt', () async {
    service.requestConsent = (_) async => true;
    await service.require(scope());
    final shown = Completer<void>();
    final answer = Completer<bool>();
    service.requestConsent = (_) {
      shown.complete();
      return answer.future;
    };
    final other = service.require(scope(destination: 'https://other.test'));
    await shown.future;
    await service.require(scope());
    answer.complete(true);
    await other;
  });

  test('a grant cannot be used before its write succeeds', () async {
    final writing = Completer<void>();
    final finish = Completer<void>();
    final slow = AiConsentService.withStore(
      read: () async => null,
      write: (_) {
        writing.complete();
        return finish.future;
      },
    )..requestConsent = (_) async => true;
    addTearDown(slow.dispose);
    final first = slow.require(scope());
    await writing.future;
    var used = false;
    final second = slow.require(scope()).then((_) {
      used = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(used, false);
    finish.complete();
    await Future.wait([first, second]);
    expect(used, true);
  });

  test('one recipient revoke removes grants for every configured route', () async {
    service.requestConsent = (_) async => true;
    final first = scope();
    final otherRoute = scope(endpoint: 'https://example.test/v2');
    await service.require(first);
    await service.require(otherRoute);
    expect(service.recipientDecisions.length, 1);
    await service.revoke(first);
    expect(service.isAllowed(first), false);
    expect(service.isAllowed(otherRoute), false);
  });

  test('SQLite stores decisions and exports redact them', () async {
    final database = await openTestDatabase();
    addTearDown(() => closeTestDatabase(database));
    final first = AiConsentService(database: database)..requestConsent = (_) async => true;
    addTearDown(first.dispose);
    await first.require(scope());
    final restarted = AiConsentService(database: database);
    addTearDown(restarted.dispose);
    await restarted.require(scope());
    final backup = await database.getAllDataRaw();
    final row = (backup['settings'] as List).singleWhere(
      (r) => r['key'] == AiConsentService.settingKey,
    );
    expect(row['value'], '');
    await restarted.revoke(scope());
    final deniedRestart = AiConsentService(database: database);
    addTearDown(deniedRestart.dispose);
    await expectLater(deniedRestart.require(scope()), throwsA(isA<AiConsentRequired>()));
  });

  test('real loopback redirect cannot transmit to the redirected recipient', () async {
    final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => source.close(force: true));
    addTearDown(() => target.close(force: true));
    var targetHits = 0;
    target.listen((request) async {
      targetHits++;
      await request.response.close();
    });
    source.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = 307;
      request.response.headers.set('location', 'http://127.0.0.1:${target.port}/private');
      await request.response.close();
    });
    service.requestConsent = (_) async => true;
    final client = TestConfig(http.Client()).createClient();
    addTearDown(client.close);
    final response = await client.post(
      Uri.parse('http://127.0.0.1:${source.port}/submit'),
      body: 'private',
    );
    expect(response.statusCode, 307);
    expect(targetHits, 0);
    expect(service.decisions.single.scope.recipient, 'http://127.0.0.1:${source.port}');
  });

  test('denial is terminal and has a safe MCP failure code', () {
    const denial = AiConsentRequired();
    expect(LLMService.isRetryable(denial), false);
    expect(taskFailure(denial)['code'], 'consentRequired');
  });
}
