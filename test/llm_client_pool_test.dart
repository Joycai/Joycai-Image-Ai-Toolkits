import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';

/// Pins connection reuse.
///
/// A client per request is a TCP connection per request — a TLS handshake and
/// a fresh slow-start ramp for every upload, paid a dozen or more times in one
/// agent turn. Nothing throws when this regresses; requests just get slower,
/// which is indistinguishable from a slow model.
void main() {
  LLMModelConfig config({
    String endpoint = 'https://api.example.com/v1',
    String apiKey = 'k',
    bool proxyEnabled = false,
    String? proxyUrl,
  }) =>
      LLMModelConfig(
        modelId: 'm',
        channelType: 'openai-api-rest',
        endpoint: endpoint,
        apiKey: apiKey,
        proxyEnabled: proxyEnabled,
        proxyUrl: proxyUrl,
      );

  setUp(LLMClientPool.disposeAll);
  tearDown(LLMClientPool.disposeAll);

  test('the same endpoint is served by one client', () {
    config().createClient();
    config().createClient();
    config().createClient();

    expect(LLMClientPool.liveClients, 1);
  });

  test('a different API key still shares the connection', () {
    // The key is a header, not part of the connection. Two channels against
    // the same relay have no reason to open separate sockets.
    config(apiKey: 'one').createClient();
    config(apiKey: 'two').createClient();

    expect(LLMClientPool.liveClients, 1);
  });

  test('a different endpoint gets its own', () {
    config(endpoint: 'https://a.example.com/v1').createClient();
    config(endpoint: 'https://b.example.com/v1').createClient();

    expect(LLMClientPool.liveClients, 2);
  });

  test('a proxy is part of the connection identity', () {
    config().createClient();
    config(proxyEnabled: true, proxyUrl: '127.0.0.1:7890').createClient();

    expect(LLMClientPool.liveClients, 2);
  });

  test('editing a channel takes a new client without an invalidation hook', () {
    // The reason the key is derived rather than stored: there is no "channel
    // was edited" callback to forget to wire up.
    config(endpoint: 'https://old.example.com/v1').createClient();
    config(endpoint: 'https://new.example.com/v1').createClient();

    expect(LLMClientPool.liveClients, 2);
  });

  test('closing a handle does not close the shared client', () {
    // Every protocol closes its client in a finally. That is right for a
    // private client and fatal for a shared one, so the handle swallows it.
    final first = config().createClient();
    first.close();

    // Still usable, and still the same pooled entry.
    config().createClient();
    expect(LLMClientPool.liveClients, 1);
  });

  test('the pool is capped, evicting least recently used', () {
    for (var i = 0; i < 12; i++) {
      config(endpoint: 'https://host$i.example.com/v1').createClient();
    }

    expect(LLMClientPool.liveClients, lessThanOrEqualTo(8));
  });

  test('eviction does not tear down a request still in flight', () async {
    // The failure this pins is not slowness, it is a dead request. Closing an
    // IOClient is `close(force: true)`: it does not drain, it drops the
    // sockets. A video poll loop or an SSE stream mid-transfer when a ninth
    // endpoint pushes its client past the cap would die with a
    // ClientException — and one multi-face channel occupies three connection
    // keys on its own, so the cap is an ordinary session, not a corner.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final endpoint = 'http://127.0.0.1:${server.port}';

    final secondHalf = Completer<void>();
    server.listen((request) async {
      request.response.bufferOutput = false;
      request.response.write('first');
      await request.response.flush();
      await secondHalf.future;
      request.response.write('second');
      await request.response.close();
    });

    final client = config(endpoint: endpoint).createClient();
    final response =
        await client.send(http.Request('GET', Uri.parse(endpoint)));
    final body = response.stream.bytesToString();

    // Eight more endpoints: enough to push the in-flight one out of the cap.
    for (var i = 0; i < 8; i++) {
      config(endpoint: 'https://evictor$i.example.com/v1').createClient();
    }
    expect(LLMClientPool.liveClients, lessThanOrEqualTo(8));

    secondHalf.complete();
    expect(await body, 'firstsecond');
  });

  test('a handle held across polls survives eviction between requests', () async {
    // The gap the lease exists for: an async job loop takes one client for
    // submit + polls with sleeps in between. Between polls nothing is
    // mid-transfer, and a count that only tracked transfers read that as
    // "safe to close" — the next poll then died with ClientException and the
    // already-billed job was abandoned.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final endpoint = 'http://127.0.0.1:${server.port}';

    server.listen((request) async {
      request.response.write('ok');
      await request.response.close();
    });

    final client = config(endpoint: endpoint).createClient();
    // First "poll", fully drained — the idle moment follows.
    expect((await client.get(Uri.parse(endpoint))).body, 'ok');

    // Eight more endpoints push the idle client out of the cap.
    for (var i = 0; i < 8; i++) {
      config(endpoint: 'https://evictor$i.example.com/v1').createClient();
    }

    // Next poll on the same handle must still work: the lease held from
    // createClient() to close() is what defers the actual teardown.
    expect((await client.get(Uri.parse(endpoint))).body, 'ok');
    client.close();
  });

  test('a lease is counted from take to close', () {
    final key = config().connectionKey;
    final first = config().createClient();
    expect(LLMClientPool.inFlightFor(key), 1);

    final second = config().createClient();
    expect(LLMClientPool.inFlightFor(key), 2);

    first.close();
    first.close(); // Idempotent — a double close must not free someone else's lease.
    expect(LLMClientPool.inFlightFor(key), 1);

    second.close();
    expect(LLMClientPool.inFlightFor(key), 0);
  });

  test('a body nobody listened to is released by close', () async {
    // The throw-on-non-200 paths never subscribe to the response stream, and
    // a transfer retain that waits for a listener that never comes held the
    // count above zero forever — an evicted client (and its sockets) could
    // then never close. The protocol's finally-guaranteed close() settles it.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final endpoint = 'http://127.0.0.1:${server.port}';

    server.listen((request) async {
      request.response.statusCode = 429;
      request.response.write('{"error":"rate limited"}');
      await request.response.close();
    });

    final key = config(endpoint: endpoint).connectionKey;
    final client = config(endpoint: endpoint).createClient();
    final response =
        await client.send(http.Request('GET', Uri.parse(endpoint)));
    expect(response.statusCode, 429);

    // Throw-path shape: the body stream is abandoned, the handle closed.
    client.close();
    expect(LLMClientPool.inFlightFor(key), 0,
        reason: 'the unlistened transfer must not outlive the handle');
  });

  test('a hit refreshes recency, so a busy channel is not evicted', () {
    const busy = 'https://busy.example.com/v1';
    config(endpoint: busy).createClient();

    // Seven more fills the pool exactly; touching `busy` in between keeps it
    // the most recently used, so the next insert evicts something else.
    for (var i = 0; i < 7; i++) {
      config(endpoint: 'https://other$i.example.com/v1').createClient();
      config(endpoint: busy).createClient();
    }
    config(endpoint: 'https://last.example.com/v1').createClient();

    final before = LLMClientPool.liveClients;
    config(endpoint: busy).createClient();
    expect(LLMClientPool.liveClients, before,
        reason: 'busy must still be pooled, not re-created');
  });
}
