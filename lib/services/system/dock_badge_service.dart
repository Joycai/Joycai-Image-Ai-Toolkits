import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../tasks/task_queue_service.dart';

/// Keeps the macOS Dock / Windows taskbar badge in sync with actively processing tasks.
/// Pending and finished tasks do not contribute to the badge.
class DockBadgeService {
  DockBadgeService(this._queue) {
    if (!_supported) return;
    _queue.addListener(_sync);
    _sync();
  }

  static const _channel = MethodChannel('joycai/dock_badge');
  final TaskQueueService _queue;
  final bool _supported =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);
  int? _lastCount;

  void _sync() {
    final count = _queue.queue.where((task) => task.status == TaskStatus.processing).length;
    if (_lastCount == count) return;
    _lastCount = count;
    unawaited(_setCount(count));
  }

  Future<void> _setCount(int count) async {
    try {
      await _channel.invokeMethod<void>('setCount', count);
    } on MissingPluginException {
      // A test host or an older runner may not provide this optional channel.
    } on PlatformException catch (error) {
      debugPrint('Dock badge update failed: $error');
    }
  }

  void dispose() {
    if (!_supported) return;
    _queue.removeListener(_sync);
    unawaited(_setCount(0));
  }
}
