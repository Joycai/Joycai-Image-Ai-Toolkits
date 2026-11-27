import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/system/proxy_probe_service.dart';

void main() {
  group('ProxyProbeService.parseEndpoint', () {
    test('parses host:port, http/https scheme, trailing slash, and IPv6 literals', () {
      final plain = ProxyProbeService.parseEndpoint('127.0.0.1:7890');
      expect(plain?.host, '127.0.0.1');
      expect(plain?.port, 7890);

      final withScheme = ProxyProbeService.parseEndpoint('  https://proxy.example.com:8443/  ');
      expect(withScheme?.host, 'proxy.example.com');
      expect(withScheme?.port, 8443);

      final ipv6 = ProxyProbeService.parseEndpoint('[::1]:1080');
      expect(ipv6?.host, '::1');
      expect(ipv6?.port, 1080);
    });

    test('rejects empty, missing port, invalid port, or path/userinfo inputs', () {
      expect(ProxyProbeService.parseEndpoint(''), isNull);
      expect(ProxyProbeService.parseEndpoint('127.0.0.1'), isNull);
      expect(ProxyProbeService.parseEndpoint('127.0.0.1:0'), isNull);
      expect(ProxyProbeService.parseEndpoint('127.0.0.1:70000'), isNull);
      expect(ProxyProbeService.parseEndpoint('127.0.0.1:7890/path'), isNull);
      expect(ProxyProbeService.parseEndpoint('user@127.0.0.1:7890'), isNull);
      expect(ProxyProbeService.parseEndpoint('127.0.0.1 :7890'), isNull);
    });
  });

  group('ProxyProbeService.test', () {
    test('returns invalidAddress without invoking connector', () async {
      var called = false;
      final service = ProxyProbeService(
        connector: (host, port, timeout) async {
          called = true;
        },
      );

      final result = await service.test('not-a-proxy');
      expect(called, isFalse);
      expect(result.status, ProxyProbeStatus.invalidAddress);
      expect(result.isReachable, isFalse);
    });

    test('returns reachable and passes normalized host, port, and timeout', () async {
      String? seenHost;
      int? seenPort;
      Duration? seenTimeout;
      final service = ProxyProbeService(
        timeout: const Duration(seconds: 2),
        connector: (host, port, timeout) async {
          seenHost = host;
          seenPort = port;
          seenTimeout = timeout;
        },
      );

      final result = await service.test('http://127.0.0.1:7890/');
      expect(seenHost, '127.0.0.1');
      expect(seenPort, 7890);
      expect(seenTimeout, const Duration(seconds: 2));
      expect(result.status, ProxyProbeStatus.reachable);
      expect(result.isReachable, isTrue);
      expect(result.latencyMs, isNonNegative);
    });

    test('maps TimeoutException to timedOut', () async {
      final service = ProxyProbeService(
        connector: (host, port, timeout) async {
          throw TimeoutException('timed out');
        },
      );

      final result = await service.test('127.0.0.1:7890');
      expect(result.status, ProxyProbeStatus.timedOut);
    });

    test('maps connection refused SocketException to refused and others to failed', () async {
      final refused = ProxyProbeService(
        connector: (host, port, timeout) async {
          throw const SocketException(
            'Connection refused',
            osError: OSError('Connection refused', 61),
          );
        },
      );
      expect((await refused.test('127.0.0.1:7890')).status, ProxyProbeStatus.refused);

      final failed = ProxyProbeService(
        connector: (host, port, timeout) async {
          throw const SocketException('Network unreachable');
        },
      );
      expect((await failed.test('127.0.0.1:7890')).status, ProxyProbeStatus.failed);
    });
  });
}
