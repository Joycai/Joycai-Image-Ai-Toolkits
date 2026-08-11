import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps the OS-drawn window title bar in step with the theme chosen inside
/// the app.
///
/// Windows draws the caption itself, and by default picks its colour from the
/// *system* light/dark setting — which has nothing to do with the theme the
/// user picked in this app's settings. A light app under a dark OS therefore
/// gets a black title bar welded onto a white toolbar, and the seam is the
/// first thing you see. This hands the app's own canvas colour down to the
/// runner, which applies it with `DwmSetWindowAttribute`.
///
/// Windows-only. Everywhere else the call is a no-op: macOS and Linux either
/// blend the caption already or leave it to the window manager.
class WindowChromeService {
  WindowChromeService._();

  static const MethodChannel _channel = MethodChannel('joycai/window_chrome');

  /// The colours last handed to the platform, so a rebuild that changes
  /// nothing does not cross the channel. Theme rebuilds are frequent; caption
  /// changes are not.
  static int? _lastCaption;
  static int? _lastText;

  /// Whether the execution log has already been told the channel works.
  ///
  /// A theme change is animated, so this runs once per frame of the
  /// transition — eight or nine times for a single switch, each with an
  /// interpolated colour. Applying every frame is wanted (the caption then
  /// fades along with the UI instead of snapping), but saying so every frame
  /// buries the user's own task output. Success is worth one line, ever;
  /// failures are worth all of them.
  static bool _reportedSuccess = false;

  /// Whether this platform has a caption this service can recolour.
  static bool get isSupported => !kIsWeb && Platform.isWindows;

  /// Paints the caption to match [colorScheme]'s canvas.
  ///
  /// Safe to call on every theme rebuild — repeat calls with unchanged
  /// colours return without touching the channel.
  ///
  /// Returns a one-line account of what the platform did, for the execution
  /// log, or null when there was nothing to do. Whether DWM *accepted* the
  /// colours is not something the app can see by looking at itself, and a
  /// silent no-op here is indistinguishable from the feature not existing —
  /// which is how it went unnoticed through three releases. So it says so.
  static Future<String?> applyTheme(ColorScheme colorScheme) async {
    if (!isSupported) return null;

    // surfaceContainer, not surface: it is the colour of the canvas the nav
    // rail and top bar float on, so the caption continues the same plane
    // rather than introducing a third tone above them.
    //
    // Both are opaque, so both always exceed 0x7FFFFFFF and reach the runner
    // as an int64 rather than an int32 — see the runner's own note.
    final caption = colorScheme.surfaceContainer.toARGB32();
    final text = colorScheme.onSurface.toARGB32();
    if (caption == _lastCaption && text == _lastText) return null;

    try {
      final applied = await _channel.invokeMapMethod<String, int>('setCaptionColors', {
        'caption': caption,
        'text': text,
        'dark': colorScheme.brightness == Brightness.dark,
      });
      // Recorded only once the platform has taken them. Caching before the
      // await meant a rejected call was also a permanent one: the next theme
      // change saw its own colours already "sent" and returned early.
      _lastCaption = caption;
      _lastText = text;

      final refused = (applied ?? const {}).entries.where((e) => e.value != 0).toList();
      if (refused.isEmpty && _reportedSuccess) return null;
      _reportedSuccess = true;
      return _describe(caption, text, colorScheme.brightness, applied);
    } on PlatformException catch (error, stack) {
      // Reported, not dropped. The runner errors here only on arguments it
      // cannot read, which is a defect in this file rather than a property of
      // the machine — a Windows too old for the attributes fails silently on
      // the native side and never reaches this handler. Swallowing it hid
      // exactly such a defect for three releases: every colour crossed as an
      // int64 while the runner would only accept an int32, so the caption was
      // never once recoloured.
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'window_chrome_service',
        context: ErrorDescription('applying the window caption colours'),
      ));
      return 'Window caption rejected the colours: ${error.code} ${error.message}';
    } on MissingPluginException {
      // Running against a runner built before the channel existed.
      return 'Window caption channel is missing — the runner predates it.';
    }
  }

  /// Each DWM attribute reports its own HRESULT; 0 is S_OK. They are shown
  /// individually because they fail independently: Windows 10 takes the
  /// dark-mode flag and refuses the two colours.
  static String _describe(int caption, int text, Brightness brightness, Map<String, int>? applied) {
    String hex(int v) => '#${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final summary = 'caption ${hex(caption)}, text ${hex(text)}, ${brightness.name}';
    if (applied == null) return 'Window caption set ($summary) — runner returned nothing.';

    final failures = applied.entries.where((e) => e.value != 0).toList();
    if (failures.isEmpty) return 'Window caption applied: $summary.';
    final detail = failures.map((e) => '${e.key}=0x${e.value.toUnsigned(32).toRadixString(16)}').join(', ');
    return 'Window caption partly refused by DWM ($summary) — $detail';
  }

  /// Forces the next [applyTheme] to reach the platform even if the colours
  /// match — for a window that was recreated and has lost its caption colour.
  @visibleForTesting
  static void resetCache() {
    _lastCaption = null;
    _lastText = null;
    _reportedSuccess = false;
  }
}
