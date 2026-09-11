import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Which in-app drag is in flight (`00d · 1c` 「可放」).
///
/// A drop zone the pointer has not reached yet has no [DragTarget] callback
/// to learn that a drag started somewhere else on screen, so every in-app
/// [Draggable] whose payload a zone may accept reports itself here: [begin]
/// from `onDragStarted`, [end] from `onDragEnd`. Zones listen to [current]
/// and light their 1px accent edge while the payload is one they take.
///
/// Drags from the operating system never appear here — `desktop_drop` only
/// tells the zone the pointer is over — so a zone shows 「可放」 for in-app
/// drags alone.
class AppDragSession {
  AppDragSession._();

  static final ValueNotifier<Object?> _current = ValueNotifier<Object?>(null);

  /// The payload of the drag in flight, or null.
  static ValueListenable<Object?> get current => _current;

  static void begin(Object payload) => _current.value = payload;

  static void end() => _current.value = null;
}

/// Whether the copy modifier is held during a drag (`00d` 复制 vs 移动):
/// Ctrl, or ⌥ on macOS, as Finder has it.
///
/// A listenable rather than a getter, because the design switches the follower
/// and the target row the moment the key goes down or up — without waiting for
/// the pointer to move. The keyboard handler is installed only while someone
/// listens.
class AppCopyModifier extends ChangeNotifier implements ValueListenable<bool> {
  AppCopyModifier._();

  static final AppCopyModifier instance = AppCopyModifier._();

  /// Read once, at the moment it matters (a drop), where listening would be
  /// pointless.
  static bool get isDown => defaultTargetPlatform == TargetPlatform.macOS
      ? HardwareKeyboard.instance.isAltPressed
      : HardwareKeyboard.instance.isControlPressed;

  bool _value = false;

  @override
  bool get value => _value;

  bool _handle(KeyEvent event) {
    final down = isDown;
    if (down != _value) {
      _value = down;
      notifyListeners();
    }
    return false;
  }

  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) {
      _value = isDown;
      HardwareKeyboard.instance.addHandler(_handle);
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) HardwareKeyboard.instance.removeHandler(_handle);
  }
}
