import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/windows_package_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(WindowsPackageStorage.channel, null));

  test('uses the native package path and creates its data directory', () async {
    final root = await Directory.systemTemp.createTemp('joycai-package-path-');
    addTearDown(() => root.delete(recursive: true));
    final target = p.join(root.path, 'package-local', 'Joycai');
    messenger.setMockMethodCallHandler(WindowsPackageStorage.channel, (call) async {
      expect(call.method, 'dataPath');
      return target;
    });
    expect(await WindowsPackageStorage.supportDirectory(), target);
    expect(await Directory(target).exists(), isTrue);
  });

  test('missing, relative or failed native paths never fall back to direct data', () async {
    for (final value in [null, '', 'relative']) {
      messenger.setMockMethodCallHandler(WindowsPackageStorage.channel, (_) async => value);
      await expectLater(WindowsPackageStorage.supportDirectory(), throwsStateError);
    }
    messenger.setMockMethodCallHandler(WindowsPackageStorage.channel, (_) async {
      throw PlatformException(code: 'storage_unavailable');
    });
    await expectLater(WindowsPackageStorage.supportDirectory(), throwsA(isA<PlatformException>()));
  });
}
