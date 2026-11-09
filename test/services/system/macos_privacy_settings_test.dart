import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/system/macos_privacy_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final result in [true, false, PlatformException(code: 'unavailable')]) {
    test('settings navigation reports launch result $result without granting access', () async {
      final urls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'launch');
        urls.add(call.arguments['url'] as String);
        if (result is Exception) throw result;
        return result;
      });
      expect(await MacOSPrivacySettings.openFullDiskAccess(), result == true);
      expect(urls, ['x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles']);
    });
  }
}
