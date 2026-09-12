import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/runtime_info.dart';

/// `RuntimeInfo`: what the About page's 「运行信息」 block reports, and the block
/// the Copy button puts on the clipboard (`E1 · 2a`).
void main() {
  const String windowsDart =
      '3.13.2 (stable) (Tue Sep 9 2026) on "windows_x64"';
  const String macDart = '3.13.2 (stable) (Tue Sep 9 2026) on "macos_arm64"';

  group('describeEngine', () {
    test('keeps the version number and drops the channel and target', () {
      expect(RuntimeInfo.describeEngine(windowsDart), 'Dart 3.13.2');
    });

    test('survives a version string it cannot read', () {
      expect(RuntimeInfo.describeEngine(''), 'Dart');
      expect(RuntimeInfo.describeEngine('   '), 'Dart');
    });
  });

  group('describePlatform', () {
    test('does not repeat an OS that already names itself', () {
      expect(
        RuntimeInfo.describePlatform(
          operatingSystem: 'windows',
          operatingSystemVersion: '"Windows 11 Pro" 10.0 (Build 26200)',
          dartVersion: windowsDart,
        ),
        'Windows 11 Pro 10.0 (Build 26200) · x64',
      );
    });

    test('names one that does not, and drops macOS\'s bare "Version"', () {
      expect(
        RuntimeInfo.describePlatform(
          operatingSystem: 'macos',
          operatingSystemVersion: 'Version 15.3 (Build 24D60)',
          dartVersion: macDart,
        ),
        'macOS 15.3 (Build 24D60) · arm64',
      );
    });

    test('leaves the architecture off when the target does not carry one', () {
      expect(
        RuntimeInfo.describePlatform(
          operatingSystem: 'linux',
          operatingSystemVersion: '6.8.0-generic',
          dartVersion: '3.13.2 (stable)',
        ),
        'Linux 6.8.0-generic',
      );
    });

    test('an OS with no version is still named', () {
      expect(
        RuntimeInfo.describePlatform(
          operatingSystem: 'android',
          operatingSystemVersion: '',
          dartVersion: '3.13.2 (stable) on "android_arm64"',
        ),
        'Android · arm64',
      );
    });
  });

  group('the copied block', () {
    const info = RuntimeInfo(
      version: '4.0.0',
      buildNumber: '0',
      engine: 'Dart 3.13.2',
      platform: 'Windows 11 Pro 10.0 (Build 26200) · x64',
      dataDirectory: r'C:\Users\me\AppData\Roaming\Joycai',
    );

    test('is the four lines an issue needs, labelled in English', () {
      expect(info.report, '''
Version: 4.0.0 (build 0)
Engine: Dart 3.13.2
Platform: Windows 11 Pro 10.0 (Build 26200) · x64
Data directory: C:\\Users\\me\\AppData\\Roaming\\Joycai'''
          .trim());
    });

    test('a platform reporting no build number says the version alone', () {
      expect(
        const RuntimeInfo(
          version: '4.0.0',
          buildNumber: '',
          engine: 'Dart 3.13.2',
          platform: 'iOS 18.3',
          dataDirectory: '/var/mobile',
        ).versionLine,
        '4.0.0',
      );
    });

    test('version line carries the build where there is one', () {
      expect(info.versionLine, '4.0.0 (build 0)');
    });
  });
}
