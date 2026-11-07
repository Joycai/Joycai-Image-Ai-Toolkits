import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/windows_package_identity.dart';

void main() {
  test('distinguishes package identity from absence and query failures', () {
    expect(WindowsPackage.detect(query: () => 122), WindowsPackageIdentity.packaged);
    expect(WindowsPackage.detect(query: () => 15700), WindowsPackageIdentity.unpackaged);
    for (final error in [0, 5, 87]) {
      expect(WindowsPackage.detect(query: () => error), WindowsPackageIdentity.unknown);
    }
    expect(
      WindowsPackage.detect(query: () => throw StateError('unavailable')),
      WindowsPackageIdentity.unknown,
    );
  });

  test('native Windows query resolves the test process identity', () {
    expect(WindowsPackage.identity, isNot(WindowsPackageIdentity.unknown));
  }, skip: !Platform.isWindows);
}
