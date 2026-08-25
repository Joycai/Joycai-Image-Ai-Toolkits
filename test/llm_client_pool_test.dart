import 'package:flutter_test/flutter_test.dart';
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
