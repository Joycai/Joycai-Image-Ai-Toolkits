import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../db/database_service.dart';

/// A versioned recipient scope, without credentials or request content.
class AiConsentScope {
  final String key;
  final String recipient;
  final String service;
  final String proxy;
  const AiConsentScope(this.key, this.recipient, this.service, this.proxy);

  factory AiConsentScope.forRequest({
    required String endpoint,
    required Uri destination,
    String? proxy,
  }) {
    final recipient = origin(destination);
    final service = origin(Uri.parse(endpoint));
    final proxyOrigin = proxy == null || proxy.isEmpty
        ? ''
        : origin(Uri.parse(proxy.contains('://') ? proxy : 'http://$proxy'));
    final key = sha256
        .convert(utf8.encode(jsonEncode([2, recipient, service, proxyOrigin])))
        .toString();
    return AiConsentScope(key, recipient, service, proxyOrigin);
  }

  static String origin(Uri uri) {
    if (!{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      throw const AiConsentRequired();
    }
    return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null).toString();
  }

  Map<String, Object> toJson() => {
    'key': key,
    'recipient': recipient,
    'service': service,
    'proxy': proxy,
  };
}

class AiConsentDecision {
  final AiConsentScope scope;
  final bool allowed;
  const AiConsentDecision(this.scope, this.allowed);
}

/// Typed, terminal denial: never treat this as a provider/network failure.
class AiConsentRequired implements Exception {
  const AiConsentRequired([
    this.message = 'AI data sharing is blocked. Review permission in Settings > About, then retry.',
  ]);
  final String message;
  @override
  String toString() => message;
}

/// Only the local UI can supply [requestConsent]. Missing UI/storage fails closed.
/// Decisions are not portable: backups and installation imports exclude this key.
class AiConsentService extends ChangeNotifier {
  static const settingKey = 'ai_data_sharing_consent_v1';
  static AiConsentService instance = AiConsentService();

  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  Future<bool> Function(AiConsentScope)? requestConsent;
  String denialMessage = const AiConsentRequired().message;
  AiConsentRequired denied() => AiConsentRequired(denialMessage);
  Map<String, AiConsentDecision> _decisions = {};
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  Future<void> _prompts = Future.value();
  int _revision = 0;
  final Set<String> _pendingGrants = {};

  AiConsentService({DatabaseService? database})
    : _read = (() => (database ?? DatabaseService()).getSetting(settingKey)),
      _write = ((value) => (database ?? DatabaseService()).saveSetting(settingKey, value));

  @visibleForTesting
  AiConsentService.withStore({required this._read, required this._write});

  // Older records were keyed by route/vendor. Reuse their disclosed recipient
  // scope too; a remembered refusal takes precedence over an older grant.
  AiConsentDecision? _decisionFor(AiConsentScope scope) {
    AiConsentDecision? found;
    for (final decision in _decisions.values) {
      if (!_sameRecipient(decision.scope, scope)) continue;
      if (!decision.allowed) return decision;
      found = decision;
    }
    return found;
  }

  bool isAllowed(AiConsentScope scope) {
    final decision = _decisionFor(scope);
    return decision?.allowed == true && !_pendingGrants.contains(decision!.scope.key);
  }

  List<AiConsentDecision> get decisions => List.unmodifiable(_decisions.values);

  /// One visible control for all route scopes with the same disclosed parties.
  List<AiConsentDecision> get recipientDecisions {
    final grouped = <String, AiConsentDecision>{};
    for (final decision in _decisions.values) {
      final key = jsonEncode([
        decision.scope.recipient,
        decision.scope.service,
        decision.scope.proxy,
      ]);
      if (grouped[key]?.allowed != false) grouped[key] = decision;
    }
    return List.unmodifiable(grouped.values);
  }

  Future<void> load() => _loading ??= _load().onError((Object error, StackTrace stack) {
    _loading = null;
    Error.throwWithStackTrace(error, stack);
  });
  Future<void> _load() async {
    final raw = await _read();
    if (raw == null || raw.isEmpty) return;
    try {
      final rows = jsonDecode(raw) as List;
      final parsed = <String, AiConsentDecision>{};
      for (final row in rows) {
        final scope = AiConsentScope(
          row['key'] as String,
          row['recipient'] as String,
          row['service'] as String,
          row['proxy'] as String,
        );
        parsed[scope.key] = AiConsentDecision(scope, row['allowed'] == true);
      }
      _decisions = parsed;
    } on Object {
      // Malformed storage never grants permission.
      _decisions = {};
    }
    notifyListeners();
  }

  Future<void> require(AiConsentScope scope) async {
    await load();
    // An unrelated unanswered prompt must not stall already-authorized jobs.
    final known = _decisionFor(scope);
    if (known != null && !_pendingGrants.contains(known.scope.key)) {
      if (!known.allowed) throw denied();
      return;
    }
    final revision = _revision;
    final previous = _prompts;
    final done = Completer<void>();
    _prompts = done.future;
    try {
      await previous;
      if (revision != _revision) throw denied();
      var decision = _decisionFor(scope);
      if (decision == null) {
        final presenter = requestConsent;
        if (presenter == null) throw denied();
        final allowed = await presenter(scope);
        if (revision != _revision) throw denied();
        decision = AiConsentDecision(scope, allowed);
        await _store(decision);
      }
      if (revision != _revision || !decision.allowed) throw denied();
    } finally {
      done.complete();
    }
  }

  bool _sameRecipient(AiConsentScope a, AiConsentScope b) =>
      a.recipient == b.recipient && a.service == b.service && a.proxy == b.proxy;

  Future<void> revoke(AiConsentScope scope) async {
    ++_revision; // Invalidates pending prompts before any disk await.
    _decisions = {
      for (final entry in _decisions.entries)
        entry.key: _sameRecipient(entry.value.scope, scope)
            ? AiConsentDecision(entry.value.scope, false)
            : entry.value,
      scope.key: AiConsentDecision(scope, false),
    };
    notifyListeners();
    await _persist();
  }

  /// Re-enable the *prompt*, never grant access from a settings toggle.
  Future<void> askAgain(AiConsentScope scope) async {
    ++_revision;
    _decisions = {..._decisions}..removeWhere((_, value) => _sameRecipient(value.scope, scope));
    notifyListeners();
    await _persist();
  }

  Future<void> _store(AiConsentDecision decision) async {
    _pendingGrants.add(decision.scope.key);
    _decisions = {..._decisions, decision.scope.key: decision};
    notifyListeners();
    try {
      await _persist();
    } catch (_) {
      _decisions = {..._decisions, decision.scope.key: AiConsentDecision(decision.scope, false)};
      notifyListeners();
      rethrow;
    } finally {
      _pendingGrants.remove(decision.scope.key);
    }
  }

  Future<void> _persist() {
    final raw = jsonEncode([
      for (final d in _decisions.values) {...d.scope.toJson(), 'allowed': d.allowed},
    ]);
    final write = _writes.then((_) => _write(raw));
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }
}
