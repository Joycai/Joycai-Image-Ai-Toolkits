import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Outcome of probing a configured HTTP/SOCKS proxy socket address.
enum ProxyProbeStatus { reachable, invalidAddress, timedOut, refused, failed }

/// Result returned by [ProxyProbeService.test].
@immutable
class ProxyProbeResult {
  const ProxyProbeResult._({required this.status, this.latencyMs});

  const ProxyProbeResult.reachable({required int latencyMs})
    : this._(status: ProxyProbeStatus.reachable, latencyMs: latencyMs);

  const ProxyProbeResult.invalidAddress() : this._(status: ProxyProbeStatus.invalidAddress);

  const ProxyProbeResult.timedOut() : this._(status: ProxyProbeStatus.timedOut);

  const ProxyProbeResult.refused() : this._(status: ProxyProbeStatus.refused);

  const ProxyProbeResult.failed() : this._(status: ProxyProbeStatus.failed);

  final ProxyProbeStatus status;
  final int? latencyMs;

  bool get isReachable => status == ProxyProbeStatus.reachable;
}

/// Opens and closes a TCP socket to verify [host]:[port] reachability.
typedef ProxySocketConnector = Future<void> Function(String host, int port, Duration timeout);

/// Parsed proxy host and port pair.
@immutable
class ParsedProxyEndpoint {
  const ParsedProxyEndpoint({required this.host, required this.port});

  final String host;
  final int port;
}

/// Checks whether a configured proxy endpoint accepts TCP connections without
/// transmitting AI requests or user credentials.
class ProxyProbeService {
  const ProxyProbeService({
    ProxySocketConnector? connector,
    this.timeout = const Duration(seconds: 4),
  }) : _connector = connector ?? _defaultConnect;

  final ProxySocketConnector _connector;
  final Duration timeout;

  /// Normalizes and parses a `host:port` (or `http(s)://host:port/`) string
  /// matching [LLMModelConfig.buildClient] rules. Returns `null` if invalid.
  static ParsedProxyEndpoint? parseEndpoint(String raw) {
    var cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    if (cleaned.startsWith('http://')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('https://')) {
      cleaned = cleaned.substring(8);
    }
    if (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    if (cleaned.isEmpty || cleaned.contains(RegExp(r'\s')) || cleaned.contains('@')) {
      return null;
    }

    final uri = Uri.tryParse('http://$cleaned');
    if (uri == null || !uri.hasPort) return null;
    if (uri.path.isNotEmpty || uri.hasQuery || uri.hasFragment) return null;

    final host = uri.host.trim();
    final port = uri.port;
    if (host.isEmpty || port < 1 || port > 65535) return null;
    return ParsedProxyEndpoint(host: host, port: port);
  }

  /// Tests TCP reachability of [proxyUrl] and returns latency in milliseconds.
  Future<ProxyProbeResult> test(String proxyUrl) async {
    final parsed = parseEndpoint(proxyUrl);
    if (parsed == null) {
      return const ProxyProbeResult.invalidAddress();
    }

    final stopwatch = Stopwatch()..start();
    try {
      await _connector(parsed.host, parsed.port, timeout);
      stopwatch.stop();
      return ProxyProbeResult.reachable(latencyMs: stopwatch.elapsedMilliseconds);
    } on TimeoutException {
      return const ProxyProbeResult.timedOut();
    } on SocketException catch (error) {
      final code = error.osError?.errorCode;
      final message = error.message.toLowerCase();
      if (code == 61 || code == 111 || code == 10061 || message.contains('refused')) {
        return const ProxyProbeResult.refused();
      }
      return const ProxyProbeResult.failed();
    } catch (_) {
      return const ProxyProbeResult.failed();
    }
  }

  static Future<void> _defaultConnect(String host, int port, Duration timeout) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.destroy();
  }
}
