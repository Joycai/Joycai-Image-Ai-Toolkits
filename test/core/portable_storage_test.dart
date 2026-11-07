import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/portable_storage.dart';
import 'package:joycai_image_ai_toolkits/core/windows_package_identity.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory executable;
  late File marker;
  setUp(() async {
    executable = await Directory.systemTemp.createTemp('joycai-portable-test-');
    marker = File(p.join(executable.path, '.portable'));
  });
  tearDown(() async => executable.delete(recursive: true));

  PortableStorage storage(WindowsPackageIdentity identity, {bool windows = true}) =>
      PortableStorage(isWindows: windows, identity: identity, executableDirectory: executable.path);

  for (final identity in [WindowsPackageIdentity.packaged, WindowsPackageIdentity.unknown]) {
    test('$identity ignores stale markers and never creates or deletes one', () async {
      final paths = storage(identity);
      expect(paths.supported, isFalse);
      await paths.setEnabled(true);
      expect(await marker.exists(), isFalse);
      await marker.writeAsString('preserve');
      expect(await paths.isEnabled(), isFalse);
      expect(await paths.dataDirectory(() async => 'user-support'), 'user-support');
      await paths.setEnabled(false);
      expect(await marker.readAsString(), 'preserve');
    });
  }

  test('unpackaged Windows retains portable enable, restart discovery and disable', () async {
    final paths = storage(WindowsPackageIdentity.unpackaged);
    expect(paths.supported, isTrue);
    expect(await paths.dataDirectory(() async => 'user-support'), 'user-support');
    await paths.setEnabled(true);
    final restarted = storage(WindowsPackageIdentity.unpackaged);
    expect(await restarted.isEnabled(), isTrue);
    expect(
      await restarted.dataDirectory(() => throw StateError('must not consult support')),
      executable.path,
    );
    await restarted.setEnabled(false);
    expect(await marker.exists(), isFalse);
    expect(await restarted.dataDirectory(() async => 'user-support'), 'user-support');
  });

  test('other platforms never support portable mode', () async {
    final paths = storage(WindowsPackageIdentity.unpackaged, windows: false);
    expect(paths.supported, isFalse);
    await paths.setEnabled(true);
    expect(await marker.exists(), isFalse);
  });
}
