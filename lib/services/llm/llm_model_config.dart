import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../models/spec_rate.dart';
import 'vendors/vendor_profile.dart';

/// The app's own reasoning-intensity vocabulary (playbook 03: never let one
/// vendor's spelling into configuration). Absence — a null wherever this is
/// carried — means *default*: no field is sent at all, and the endpoint does
/// whatever it does on its own.
///
/// Each protocol family owns its translation: ① spells these as
/// `reasoning_effort` values; ④'s budget dialect has no intensity knob, so
/// any level simply means "thinking on" and [off] means the field is not
/// sent. [off] is sent to ① as `"none"` — an endpoint that predates that
/// value rejects it audibly (a 400 naming the field), which beats silently
/// thinking anyway.
enum ReasoningEffort {
  off,
  low,
  medium,
  high,
  max;

  /// Parses a stored name; null/unknown → null (default). Unknown values
  /// come from newer builds via backup restore — degrading to default beats
  /// failing the whole model row.
  static ReasoningEffort? tryParse(String? name) =>
      name == null ? null : ReasoningEffort.values.asNameMap()[name];
}

class LLMModelConfig {
  final int? id; // Database Primary Key
  final String modelId;

  /// The channel's stored vendor id (`llm_channels.type`) — resolved to a
  /// [VendorProfile] by the dispatcher. See `vendors/vendors.dart`.
  final String channelType;

  /// Channel base URL, always without surrounding whitespace or a trailing
  /// slash — normalized here rather than at each call site.
  ///
  /// Protocols append their path to this (`$endpoint/chat/completions`), so a
  /// channel saved as `https://relay.example.com/v1/` used to produce
  /// `/v1//chat/completions`, which fails on gateways that do not collapse
  /// empty path segments. Only the surfaces that happened to call
  /// [trimBaseUrl] were safe — `/models` was, `/chat/completions` was not, so
  /// model discovery succeeded and every request failed. Normalizing on the
  /// way in covers channels already stored with a slash too; no migration.
  final String endpoint;

  final String apiKey;

  /// Per-model opt-in: ask the model to reason before answering.
  ///
  /// Carried on the config rather than passed as a request option because it
  /// is a property of *this model on this channel*, resolved once by
  /// [LLMConfigResolver] — so the assistant, prompt refinement and AI rename
  /// all honor it without each having to remember to pass it along. What the
  /// parameter looks like on the wire is the vendor's business
  /// (`ThinkingDialect`); whether to ask for it at all is this flag's.
  final bool enableThinking;

  /// Per-model reasoning intensity, or null for default (nothing sent).
  /// Prefer [effectiveReasoningEffort], which folds in the legacy flag.
  final ReasoningEffort? reasoningEffort;

  /// The reasoning level requests should honor.
  ///
  /// Falls back to the legacy [enableThinking] flag when no explicit level is
  /// stored: rows written before v35 (and backups restored from older
  /// builds) carry only the boolean, and a ④ model that had thinking on must
  /// keep it on — reading the flag here instead of migrating data keeps that
  /// true for every past and future restore path.
  ReasoningEffort? get effectiveReasoningEffort =>
      reasoningEffort ?? (enableThinking ? ReasoningEffort.medium : null);

  /// Per-model opt-in: let the host run its own web searches during a turn.
  final bool enableWebSearch;

  /// The model's explicit wire-protocol selection (`llm_models.wire_protocol`
  /// verbatim), or null for "auto". Stored as the raw string — the dispatcher
  /// parses and validates it against the vendor's menu, so a value written by
  /// a newer build, or one stranded by a channel-type change, degrades to
  /// auto instead of failing (and survives a save/restore round-trip intact).
  final String? wireProtocol;

  /// The base address of every route on the model's channel, keyed by the
  /// chat wire each route speaks (`ChannelRoutes.faceBases`).
  ///
  /// The dispatcher reads a face's base here before deriving it from
  /// [endpoint] through `VendorProfile.protocolBases`, so a route whose path
  /// the user changed is honored on every call that reaches that face —
  /// chat on the route itself, and model discovery on the channel's chat
  /// route. A face with no route still derives exactly as before. Empty for
  /// a config not built from a stored channel (tests, probes of a form).
  final Map<WireProtocol, String> faceBases;

  /// The model's declared kind (`llm_models.tag` verbatim: chat / image /
  /// video / multimodal), or null when the caller has no model row — which
  /// then routes exactly as it did before the kind was read, by classifying
  /// the id.
  ///
  /// Which surface a model is on is the user's statement, not a guess: a
  /// relay names its models freely, so `nano-banana-pro` classifies as chat
  /// while the user knows it draws. The dispatcher reads this to pick the
  /// protocol menu, and so which [wireProtocol] selections are valid. Same
  /// rule as [wireProtocol]: only [LLMConfigResolver] reads the column.
  final String? tag;

  /// The model's configured context window (`llm_models.context_window`
  /// verbatim — the tri-state `ContextBudget.modeOf` decodes), or null when
  /// unset or when the caller has no model row. Carried for the pre-send
  /// size check (`LLMService.preflightContextSize`); only `ContextBudget`
  /// interprets it.
  final int? contextWindow;

  /// The model's configured output cap (`llm_models.max_output_tokens`
  /// verbatim), or null when unset or when the caller has no model row.
  ///
  /// Read by exactly one place in the protocol layer, `outputCapFor`, which
  /// ranks it below a per-request `options['maxTokens']` (the channel
  /// probe's one token) and above the family's own default. Carried on the
  /// config rather than passed as an option for the same reason as
  /// [enableThinking]: it is a property of this model on this channel, and
  /// every caller — the assistant, refine, rename, the scraper — should honor
  /// it without remembering to pass it along.
  final int? maxOutputTokens;

  final double inputFee;

  /// Rate for cached input tokens, or null when the fee group leaves it unset —
  /// in which case cache hits bill at [inputFee]. Read via [effectiveCacheInputFee].
  final double? cacheInputFee;

  final double outputFee;
  final String billingMode; // 'token', 'request' or 'spec'
  final double requestFee;

  /// Spec billing: what a request counts as and the rate table it is priced
  /// against — see `services/billing/spec_billing.dart`. Empty unless the
  /// fee group's mode is `spec`.
  final OutputUnit outputUnit;
  final List<SpecRate> outputRates;

  // Proxy settings
  final bool proxyEnabled;
  final String? proxyUrl;
  final String? proxyUsername;
  final String? proxyPassword;

  LLMModelConfig({
    this.id,
    required this.modelId,
    required this.channelType,
    required String endpoint,
    required this.apiKey,
    this.enableThinking = false,
    this.reasoningEffort,
    this.enableWebSearch = false,
    this.wireProtocol,
    this.faceBases = const {},
    this.tag,
    this.contextWindow,
    this.maxOutputTokens,
    this.inputFee = 0.0,
    this.cacheInputFee,
    this.outputFee = 0.0,
    this.billingMode = 'token',
    this.requestFee = 0.0,
    this.outputUnit = OutputUnit.image,
    this.outputRates = const [],
    this.proxyEnabled = false,
    this.proxyUrl,
    this.proxyUsername,
    this.proxyPassword,
  }) : endpoint = normalizeEndpoint(endpoint);

  /// This config pointed at a different base URL — used by the dispatcher
  /// when a vendor serves a *generic* protocol on an alternate face (e.g.
  /// DashScope's Anthropic-compatible chat under `/apps/anthropic/v1`), so
  /// the protocol itself stays vendor-blind. Everything else is carried over
  /// verbatim.
  LLMModelConfig withEndpoint(String newEndpoint) =>
      _copy(endpoint: newEndpoint);

  /// This config with the model's web-search switch off, for one call that
  /// must not reach for server-side tools ([llmNoServerToolsKey]).
  LLMModelConfig withoutServerTools() =>
      enableWebSearch ? _copy(enableWebSearch: false) : this;

  LLMModelConfig _copy({String? endpoint, bool? enableWebSearch}) =>
      LLMModelConfig(
        id: id,
        modelId: modelId,
        channelType: channelType,
        endpoint: endpoint ?? this.endpoint,
        apiKey: apiKey,
        enableThinking: enableThinking,
        reasoningEffort: reasoningEffort,
        enableWebSearch: enableWebSearch ?? this.enableWebSearch,
        wireProtocol: wireProtocol,
        faceBases: faceBases,
        tag: tag,
        contextWindow: contextWindow,
        maxOutputTokens: maxOutputTokens,
        inputFee: inputFee,
        cacheInputFee: cacheInputFee,
        outputFee: outputFee,
        billingMode: billingMode,
        requestFee: requestFee,
        outputUnit: outputUnit,
        outputRates: outputRates,
        proxyEnabled: proxyEnabled,
        proxyUrl: proxyUrl,
        proxyUsername: proxyUsername,
        proxyPassword: proxyPassword,
      );

  /// Strips surrounding whitespace and trailing slashes from a base URL.
  /// See [endpoint].
  static String normalizeEndpoint(String raw) {
    var base = raw.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  /// Rate actually charged per cached input token.
  double get effectiveCacheInputFee => cacheInputFee ?? inputFee;

  /// A client for this channel, shared with every other request that would
  /// open the same connection.
  ///
  /// A client per request is a TCP connection per request, which means a TLS
  /// handshake and a fresh slow-start ramp for every upload — paid a dozen or
  /// more times in a single agent turn, against a host that is usually far
  /// away.
  ///
  /// The returned handle's `close()` releases a *lease*, never the shared
  /// client: ownership stays with [LLMClientPool]. Every protocol closes its
  /// client in a `finally`, which is right for a private client and fatal for
  /// a shared one — so the call is repurposed as the lease's end. The lease
  /// is what keeps a poll loop's client alive through the sleeps between
  /// requests, and what lets an evicted client actually close once its last
  /// holder leaves.
  http.Client createClient() => LLMClientPool.take(this);

  /// Everything that determines which connection a request opens.
  ///
  /// The API key is deliberately absent: it travels as a header, so two
  /// channels with different keys against the same endpoint can share a
  /// connection. Endpoint and proxy are what cannot be shared.
  ///
  /// Being derived rather than stored is what removes the invalidation
  /// problem: edit a channel's endpoint and the next request simply computes
  /// a different key and takes a different client.
  String get connectionKey => proxyEnabled && (proxyUrl?.isNotEmpty ?? false)
      ? '$endpoint|$proxyUrl|$proxyUsername|$proxyPassword'
      : endpoint;

  /// Builds the underlying client this config needs. Called by
  /// [LLMClientPool] on a miss, never directly.
  http.Client buildClient() {
    if (!proxyEnabled || proxyUrl == null || proxyUrl!.isEmpty) {
      return http.Client();
    }

    // Clean proxy URL (remove http:// or https:// if present for HttpClient.findProxy)
    String hostPort = proxyUrl!;
    if (hostPort.startsWith('http://')) hostPort = hostPort.substring(7);
    if (hostPort.startsWith('https://')) hostPort = hostPort.substring(8);
    // Remove trailing slash
    if (hostPort.endsWith('/')) hostPort = hostPort.substring(0, hostPort.length - 1);

    final httpClient = HttpClient();
    httpClient.findProxy = (uri) {
      return 'PROXY $hostPort';
    };

    if (proxyUsername != null && proxyUsername!.isNotEmpty && proxyPassword != null) {
      httpClient.authenticateProxy = (host, port, scheme, realm) {
        httpClient.addProxyCredentials(host, port, realm ?? '', HttpClientBasicCredentials(proxyUsername!, proxyPassword!));
        return Future.value(true);
      };
    }

    return IOClient(httpClient);
  }
}

/// Keeps one live [http.Client] per distinct connection, so requests to the
/// same endpoint reuse the same sockets.
///
/// Deliberately keyed and capped rather than lifecycle-managed. There is no
/// "channel was edited" hook to forget to call: a changed endpoint or proxy
/// is a changed [LLMModelConfig.connectionKey], and the stale entry ages out
/// of the cap on its own.
class LLMClientPool {
  /// Small on purpose — a user has a handful of channels, and an entry holds
  /// open sockets. Past this the least-recently-taken client is evicted.
  static const int _maxClients = 8;

  /// Insertion-ordered, and re-inserted on every hit, so `keys.first` is the
  /// least recently used.
  static final Map<String, _PooledClient> _clients = {};

  static http.Client take(LLMModelConfig config) {
    final key = config.connectionKey;
    final cached = _clients.remove(key);
    if (cached != null) {
      _clients[key] = cached; // Re-inserted: now the most recently used.
      return _SharedClient(cached);
    }

    while (_clients.length >= _maxClients) {
      final oldest = _clients.keys.first;
      _clients.remove(oldest)?.evict();
    }

    final client = _PooledClient(config.buildClient());
    _clients[key] = client;
    return _SharedClient(client);
  }

  /// Closes every pooled client. For tests and shutdown; nothing in a normal
  /// session needs to call it.
  static void disposeAll() {
    for (final client in _clients.values) {
      client.evict();
    }
    _clients.clear();
  }

  @visibleForTesting
  static int get liveClients => _clients.length;

  /// The lease-plus-transfer count of the pooled entry for [connectionKey],
  /// or null when nothing is pooled there. Test-only: the count's job is to
  /// gate eviction, and a count that silently sticks above zero is a client
  /// that never closes.
  @visibleForTesting
  static int? inFlightFor(String connectionKey) =>
      _clients[connectionKey]?.inFlight;
}

/// One pooled connection, plus a count of the *leases* still riding on it.
///
/// The count is what makes eviction safe. Eviction and use are unrelated
/// events — a video poll loop or an SSE stream can be mid-work when a
/// ninth endpoint pushes its client past the cap — and closing an
/// [IOClient] is `close(force: true)`: it does not drain, it tears the
/// sockets down, and the in-flight request dies with a `ClientException`.
/// One multi-face channel occupies up to three [LLMModelConfig.connectionKey]s
/// on its own, so the cap is reachable with a handful of channels and this is
/// an ordinary session, not a corner.
///
/// A lease spans a *handle's whole lifetime* — `createClient()` to the
/// protocol's `finally`-guaranteed `close()` — not just each transfer. The
/// distinction is what keeps a poll loop alive: it holds one handle across
/// submit + polls with sleeps in between, and a count that only tracked
/// transfers read those sleeps as "idle, safe to close", killing the
/// already-billed job at its next poll. Per-transfer retains still exist on
/// top (a body can outlive a carelessly early `close()`), but the lease is
/// what eviction actually waits for.
///
/// So eviction drops the *pool's* reference and nothing more; whoever leaves
/// last closes the client.
class _PooledClient {
  final http.Client inner;

  int _inFlight = 0;
  bool _evicted = false;

  _PooledClient(this.inner);

  void retain() => _inFlight++;

  void release() {
    if (--_inFlight <= 0 && _evicted) inner.close();
  }

  /// Drops the pool's reference. Closes now only if nothing is using it.
  void evict() {
    _evicted = true;
    if (_inFlight <= 0) inner.close();
  }

  @visibleForTesting
  int get inFlight => _inFlight;
}

/// A pooled client handle. [close] releases the handle's lease rather than
/// closing the shared client — see [LLMModelConfig.createClient].
class _SharedClient extends http.BaseClient {
  final _PooledClient _pooled;

  /// Transfer releases not yet fired — bodies still (supposedly) being read.
  /// [close] force-releases them: the protocol's `finally` has declared the
  /// request over, and a body nobody listened to (the throw-on-non-200 paths
  /// never subscribe) would otherwise hold its retain forever, leaving the
  /// evicted client — and its sockets — unclosable.
  final Set<void Function()> _pendingTransfers = {};

  bool _closed = false;

  _SharedClient(this._pooled) {
    // The lease. Held from creation to [close], covering the gaps between
    // requests that a per-transfer count cannot see.
    _pooled.retain();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _pooled.retain();
    final http.StreamedResponse response;
    try {
      response = await _pooled.inner.send(request);
    } catch (_) {
      _pooled.release();
      rethrow;
    }

    // Held until the *body* is finished, not until the headers arrive: on a
    // streamed response `send` returns at the first byte, and a stream whose
    // client was closed underneath it is exactly what the count exists to
    // prevent.
    var released = false;
    late final void Function() release;
    release = () {
      if (released) return;
      released = true;
      _pendingTransfers.remove(release);
      _pooled.release();
    };
    _pendingTransfers.add(release);

    return http.StreamedResponse(
      _releaseWhenDone(response.stream, release),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  /// [source] with [done] called once it can carry nothing more: drained, or
  /// cancelled by a caller that gave up — an idle guard tearing down its
  /// subscription is the common one, and `onDone` never fires for it.
  static Stream<List<int>> _releaseWhenDone(
      Stream<List<int>> source, void Function() done) {
    late final StreamController<List<int>> controller;
    StreamSubscription<List<int>>? sub;
    controller = StreamController<List<int>>(
      onListen: () {
        sub = source.listen(
          controller.add,
          onError: controller.addError,
          onDone: () {
            done();
            controller.close();
          },
        );
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () async {
        done();
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Ends this handle's lease. Idempotent; the shared client itself closes
  /// only once every lease and transfer is gone *and* the pool has evicted it.
  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final release in _pendingTransfers.toList()) {
      release();
    }
    _pooled.release();
  }
}
