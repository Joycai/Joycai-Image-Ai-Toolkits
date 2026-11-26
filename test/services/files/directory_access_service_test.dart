import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/files/directory_access_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/directory_access');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late DirectoryAccessService access;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    access = DirectoryAccessService(channel: channel, useNative: true);
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('all macOS distributions require sandbox bookmarks', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 'needsAuthorization';
    });
    final configured = DirectoryAccessService(channel: channel);
    expect(await configured.restore('/outside-home'), DirectoryAccessStatus.needsAuthorization);
    expect(calls.length, 1);
  });

  test('restores per-root outcomes without discarding inaccessible locations', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {'/available': 'available', '/offline': 'unavailable', '/moved': 'moved'},
    );
    expect(await access.restoreAll(), {
      '/available': DirectoryAccessStatus.available,
      '/offline': DirectoryAccessStatus.unavailable,
      '/moved': DirectoryAccessStatus.moved,
    });
  });

  test('unavailable grants are retried, not cached as permanent denial', () async {
    var available = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return available ? 'available' : 'unavailable';
    });
    expect(await access.restore('/volume'), DirectoryAccessStatus.unavailable);
    available = true;
    expect(await access.restore('/volume'), DirectoryAccessStatus.available);
    expect(calls.length, 2);
  });

  test('existing authorization does not present another panel', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 'available';
    });
    expect(await access.authorizeReadOnly('/reference'), isTrue);
    expect(calls.map((c) => c.method), ['restore']);
  });

  test('MCP cancellation denies access and binds the picker to the exact root', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'restore' ? 'needsAuthorization' : null;
    });
    expect(await access.authorizeReadOnly('/reference'), isFalse);
    expect(calls.last.arguments['requiredPath'], '/reference');
    expect(calls.last.arguments['readOnly'], isTrue);
  });

  test('native errors and unknown statuses fail closed', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'grant_store');
    });
    expect(await access.restore('/reference'), DirectoryAccessStatus.unavailable);
    expect(await access.authorizeReadOnly('/reference'), isFalse);
    messenger.setMockMethodCallHandler(channel, (call) async => 'future-status');
    expect(await access.restore('/reference'), DirectoryAccessStatus.unavailable);
  });

  test('other platforms do not require the macOS bridge', () async {
    access = DirectoryAccessService(channel: channel, useNative: false);
    messenger.setMockMethodCallHandler(channel, (_) async => throw StateError('Unexpected call'));
    expect(await access.restoreAll(), isEmpty);
    expect(await access.restore('/reference'), DirectoryAccessStatus.available);
    expect(await access.authorizeReadOnly('/reference'), isTrue);
    expect(await access.listGrants(), isEmpty);
    expect(await access.revoke('/reference'), isFalse);
    expect(await access.revokeAll(), 0);
  });

  test('lists, revokes one, and revokes all grants on macOS', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'list' => [
          {'path': '/Users/demo/Output', 'readOnly': false},
          {'path': '/Users/demo/Ref', 'readOnly': true},
        ],
        'revoke' => call.arguments['path'] == '/Users/demo/Ref',
        'revokeAll' => 2,
        _ => null,
      };
    });

    expect(await access.listGrants(), const [
      DirectoryGrant(path: '/Users/demo/Output', readOnly: false),
      DirectoryGrant(path: '/Users/demo/Ref', readOnly: true),
    ]);
    expect(await access.revoke('/Users/demo/Ref'), isTrue);
    expect(await access.revoke('/Users/demo/Missing'), isFalse);
    expect(await access.revokeAll(), 2);
    expect(calls.map((c) => c.method), ['list', 'revoke', 'revoke', 'revokeAll']);
    expect(calls[1].arguments, {'path': '/Users/demo/Ref'});
  });

  test('listGrants, revoke, and revokeAll surface native store errors', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'grant_store');
    });
    await expectLater(access.listGrants(), throwsA(isA<PlatformException>()));
    await expectLater(access.revoke('/Users/demo/Ref'), throwsA(isA<PlatformException>()));
    await expectLater(access.revokeAll(), throwsA(isA<PlatformException>()));
  });

  test('normalizePickedDirectoryUri trims trailing separators and rejects non-file URIs', () {
    expect(DirectoryAccessService.normalizePickedDirectoryUri(null), isNull);
    expect(
      DirectoryAccessService.normalizePickedDirectoryUri(
        Uri.parse('content://com.android.externalstorage.documents/tree/primary%3APictures'),
      ),
      isNull,
    );
    expect(
      DirectoryAccessService.normalizePickedDirectoryUri(
        Uri.directory('/Users/demo/Pictures', windows: false),
        windows: false,
      ),
      '/Users/demo/Pictures',
    );
    expect(
      DirectoryAccessService.normalizePickedDirectoryUri(
        Uri.directory('/', windows: false),
        windows: false,
      ),
      '/',
    );
    expect(
      DirectoryAccessService.normalizePickedDirectoryUri(
        Uri.directory(r'C:\Users\demo\Pictures', windows: true),
        windows: true,
      ),
      r'C:\Users\demo\Pictures',
    );
    expect(
      DirectoryAccessService.normalizePickedDirectoryUri(
        Uri.directory(r'C:\', windows: true),
        windows: true,
      ),
      r'C:\',
    );
  });
}
