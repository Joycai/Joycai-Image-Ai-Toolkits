import 'package:local_notifier/local_notifier.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    // Add your custom initialization here
    await localNotifier.setup(
      appName: 'Joycai Image AI Toolkits',
    );

    _initialized = true;
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? subtitle,
    bool silent = false,
  }) async {
    if (!_initialized) await init();

    LocalNotification notification = LocalNotification(
      title: title,
      body: body,
      subtitle: subtitle,
      silent: silent,
    );
    
    await notification.show();
  }
}
