import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// App commands only. AppKit keeps ownership of editing and system actions.
class NativeMenuService {
  NativeMenuService({required this.onCommand}) {
    if (supported) _channel.setMethodCallHandler(_handle);
  }

  static const _channel = MethodChannel('joycai/native_menu');
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  final ValueChanged<String> onCommand;
  bool _disposed = false;

  Future<Object?> _handle(MethodCall call) async {
    if (!_disposed && call.method == 'undoState') {
      final client = UndoManager.client;
      return {'undo': client?.canUndo ?? false, 'redo': client?.canRedo ?? false};
    }
    if (!_disposed && call.method == 'command' && call.arguments is String) {
      final command = call.arguments as String;
      if (command == 'undo') {
        UndoManager.client?.undo();
      } else if (command == 'redo') {
        UndoManager.client?.redo();
      } else {
        onCommand(command);
      }
    }
    return null;
  }

  Future<void> update({
    required Map<String, String> labels,
    required List<Map<String, Object>> commands,
  }) async {
    if (!supported || _disposed) return;
    try {
      await _channel.invokeMethod<void>('update', {'labels': labels, 'commands': commands});
    } on MissingPluginException {
      // Widget tests and older runners have no native menu bridge.
    } on PlatformException catch (error) {
      debugPrint('Native menu update failed: ${error.code}');
    }
  }

  void dispose() {
    _disposed = true;
    if (supported) {
      _channel.setMethodCallHandler(null);
      // Leave system/edit commands intact; stale application actions are disabled.
      updateDisabled();
    }
  }

  Future<void> updateDisabled() async {
    try {
      await _channel.invokeMethod<void>('disable');
    } on MissingPluginException {
      // No native host in widget tests.
    } on PlatformException catch (error) {
      debugPrint('Native menu teardown failed: ${error.code}');
    }
  }
}
