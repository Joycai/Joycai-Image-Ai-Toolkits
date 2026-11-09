import 'package:url_launcher/url_launcher.dart';

/// Opens settings only; macOS and the user retain control of authorization.
abstract final class MacOSPrivacySettings {
  static final fullDiskAccess = Uri.parse(
    'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
  );

  static Future<bool> openFullDiskAccess() async {
    try {
      return await launchUrl(fullDiskAccess, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
