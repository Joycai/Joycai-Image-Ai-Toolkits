import 'dart:async';

import 'llm_dispatcher.dart';
import 'llm_types.dart';

/// What a channel probe concluded.
enum ChannelProbeStatus {
  /// `/models` answered: reachable, authenticated, and [ChannelProbeResult
  /// .modelCount] models listed.
  ok,

  /// No `/models`, but the API surface itself answered a completion probe
  /// with a protocol-shaped response. A relay without `/models` is a normal
  /// configuration, not a broken one — the wording must say so, or the user
  /// reads it as "my key is wrong".
  connectedNoModels,

  /// The endpoint answered 401/403: reachable, key rejected.
  authFailed,

  /// The endpoint returned something that is not this API (HTML error page,
  /// login page, CDN interstitial) — the base URL points at the wrong thing.
  notAnApi,

  /// Nothing answered: DNS, refused connection, timeout.
  unreachable,

  /// The endpoint answered and did not reject the key, but refused *for now*:
  /// rate-limited (429) or a server error (5xx). Distinct from [unreachable],
  /// whose advice is "check the URL, proxy and network" — exactly the wrong
  /// errand for a healthy channel behind a busy relay.
  upstreamError,

  /// This channel type has no meaningful probe (Midjourney: discovery is a
  /// built-in catalog, and a real request would start a paid generation).
  notSupported,
}

class ChannelProbeResult {
  final ChannelProbeStatus status;
  final int? modelCount;

  /// Provider/exception text for the failure states, already safe to show.
  final String? detail;

  const ChannelProbeResult(this.status, {this.modelCount, this.detail});
}

/// Configuration-time connectivity probe for a channel (playbook 6.31-6.35):
/// `/models` first — when it exists, one free request answers "reachable"
/// and "authenticated" at once — then, for endpoints that don't serve it, a
/// completion probe judged by the *shape* of the rejection rather than its
/// success.
class ChannelProbeService {
  ChannelProbeService({LLMDispatcher? dispatcher})
      : _dispatcher = dispatcher ?? LLMDispatcher();

  final LLMDispatcher _dispatcher;

  /// Probe model id: impossible on purpose. The connection test runs before
  /// the user has picked a model, and a real model name would bill one real
  /// generation on endpoints that accept it.
  static const String probeModelId = '__connection_probe__';

  /// `/models` missing in the "server does not serve this path" sense —
  /// distinct from 401/429/500, which mean the path was served and refused.
  static const Set<int> _endpointAbsent = {404, 405, 501};

  static const Duration _stepTimeout = Duration(seconds: 15);

  /// Payment Required: the account behind the key has no credit. Seen live on
  /// a relay that answers *any* real request this way before it even resolves
  /// the model — with a complete, protocol-shaped JSON error, which is exactly
  /// what [_completionProbe] reads as "the endpoint speaks this API". It does
  /// — but the channel cannot run a single request, and a probe that says
  /// "connected" about it sends the user off to debug their model list. Not
  /// an auth failure either: the key is valid, the wallet is empty. Reported
  /// as unreachable with the provider's own words.
  static const int _paymentRequired = 402;

  static bool _isQuotaExhausted(LLMApiException e) =>
      e.statusCode == _paymentRequired;

  /// 429 or a 5xx outside [_endpointAbsent]: the host is there and served the
  /// path, it just will not answer right now.
  static bool _isUpstreamRefusal(LLMApiException e) {
    final code = e.statusCode;
    if (code == null || _endpointAbsent.contains(code)) return false;
    return code == 429 || (code >= 500 && code < 600);
  }

  /// Output cap for the completion probe. The probe names an impossible model
  /// so nothing bills — but some relays route unknown names to a default
  /// model, and that one then generates. One token caps that surprise.
  static const int _probeMaxTokens = 1;

  Future<ChannelProbeResult> probe(LLMModelConfig config) async {
    if (!_dispatcher.discoveryUsesNetwork(config)) {
      return const ChannelProbeResult(ChannelProbeStatus.notSupported);
    }
    try {
      final models =
          await _dispatcher.discoverModels(config).timeout(_stepTimeout);
      return ChannelProbeResult(ChannelProbeStatus.ok,
          modelCount: models.length);
    } on LLMApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        return ChannelProbeResult(ChannelProbeStatus.authFailed,
            detail: e.message);
      }
      if (_isQuotaExhausted(e)) {
        return ChannelProbeResult(ChannelProbeStatus.unreachable,
            detail: e.message);
      }
      if (e.isNonJsonBody) {
        return ChannelProbeResult(ChannelProbeStatus.notAnApi,
            detail: e.message);
      }
      if (e.statusCode != null && _endpointAbsent.contains(e.statusCode)) {
        return _completionProbe(config);
      }
      // Rate limit / server error: reachable and authenticated as far as
      // anyone can tell, just not answering now. Reported as such, with the
      // provider's words — "unreachable" sent users to check their DNS.
      if (_isUpstreamRefusal(e)) {
        return ChannelProbeResult(ChannelProbeStatus.upstreamError,
            detail: e.message);
      }
      // Any other served-but-refused answer (an error envelope): the
      // provider said why — pass that on rather than re-guessing.
      return ChannelProbeResult(ChannelProbeStatus.unreachable,
          detail: e.message);
    } on TimeoutException {
      return const ChannelProbeResult(ChannelProbeStatus.unreachable,
          detail: 'timed out');
    } catch (e) {
      return ChannelProbeResult(ChannelProbeStatus.unreachable,
          detail: '$e');
    }
  }

  /// Judges the completion surface by the shape of its answer. What comes
  /// back for an impossible model tells everything: a protocol-shaped JSON
  /// error means the endpoint speaks this API (connected); 401/403 means
  /// auth; HTML means the URL points at something else entirely.
  Future<ChannelProbeResult> _completionProbe(LLMModelConfig config) async {
    final probeConfig = LLMModelConfig(
      id: config.id,
      modelId: probeModelId,
      channelType: config.channelType,
      endpoint: config.endpoint,
      apiKey: config.apiKey,
      proxyEnabled: config.proxyEnabled,
      proxyUrl: config.proxyUrl,
      proxyUsername: config.proxyUsername,
      proxyPassword: config.proxyPassword,
    );
    try {
      await _dispatcher.generate(
        probeConfig,
        [LLMMessage(role: LLMRole.user, content: 'ping')],
        // Capped: a relay that routes the impossible name to a default model
        // must not bill a full generation for a connection test.
        options: const {'maxTokens': _probeMaxTokens},
      ).timeout(_stepTimeout);
      // Some relays route unknown model names to a default — a billed
      // surprise, but proof of connectivity.
      return const ChannelProbeResult(ChannelProbeStatus.connectedNoModels);
    } on LLMApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        return ChannelProbeResult(ChannelProbeStatus.authFailed,
            detail: e.message);
      }
      // Ahead of the "protocol-shaped rejection" rule below, which it would
      // otherwise satisfy: a 402 is a well-formed JSON error from an endpoint
      // that speaks this API and will run nothing.
      if (_isQuotaExhausted(e)) {
        return ChannelProbeResult(ChannelProbeStatus.unreachable,
            detail: e.message);
      }
      // Also ahead of the connected rule: a 429 or a 5xx is protocol-shaped
      // too, but says nothing about whether this endpoint would run a request.
      if (_isUpstreamRefusal(e)) {
        return ChannelProbeResult(ChannelProbeStatus.upstreamError,
            detail: e.message);
      }
      if (e.isNonJsonBody) {
        return ChannelProbeResult(ChannelProbeStatus.notAnApi,
            detail: e.message);
      }
      // Any protocol-shaped rejection (400 unknown model, an error envelope):
      // the endpoint speaks this API. That is what the probe asked.
      return const ChannelProbeResult(ChannelProbeStatus.connectedNoModels);
    } on TimeoutException {
      return const ChannelProbeResult(ChannelProbeStatus.unreachable,
          detail: 'timed out');
    } catch (e) {
      return ChannelProbeResult(ChannelProbeStatus.unreachable, detail: '$e');
    }
  }
}
