import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Desktop task notifications, backed by flutter_local_notifications
/// (replaces the unmaintained local_notifier, which never gained Swift
/// Package Manager support on macOS).
///
/// Kept desktop-only for behavioral parity with the previous plugin; the
/// backing plugin also supports Android/iOS if we ever want mobile
/// notifications (Android would additionally need an icon + permissions).
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  int _nextId = 0;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<void> init() async {
    if (_initialized || !_isDesktop) return;

    // macOS prompts the user for notification permission on first launch
    // (UNUserNotificationCenter) — local_notifier's NSUserNotification API
    // did not, so this dialog appearing once after the upgrade is expected.
    const settings = InitializationSettings(
      macOS: DarwinInitializationSettings(),
      linux: LinuxInitializationSettings(defaultActionName: 'Open'),
      windows: WindowsInitializationSettings(
        appName: 'Joycai Image AI Toolkits',
        appUserModelId: 'Joycai.JoycaiImageAIToolkits',
        // Arbitrary but stable GUID identifying this app's notifications.
        guid: '7f4b7a44-90c1-4b58-8be7-2f383cd89547',
      ),
    );

    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? subtitle,
    bool silent = false,
  }) async {
    if (!_isDesktop) return;
    if (!_initialized) await init();

    final details = NotificationDetails(
      macOS: DarwinNotificationDetails(
        subtitle: subtitle,
        presentSound: !silent,
      ),
      linux: const LinuxNotificationDetails(),
      windows: const WindowsNotificationDetails(),
    );

    await _plugin.show(
      id: _nextId++,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }
}
