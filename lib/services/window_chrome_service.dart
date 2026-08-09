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

  /// Whether this platform has a caption this service can recolour.
  static bool get isSupported => !kIsWeb && Platform.isWindows;

  /// Paints the caption to match [colorScheme]'s canvas.
  ///
  /// Safe to call on every theme rebuild — repeat calls with unchanged
  /// colours return without touching the channel.
  static Future<void> applyTheme(ColorScheme colorScheme) async {
    if (!isSupported) return;

    // surfaceContainer, not surface: it is the colour of the canvas the nav
    // rail and top bar float on, so the caption continues the same plane
    // rather than introducing a third tone above them.
    final caption = _toArgb(colorScheme.surfaceContainer);
    final text = _toArgb(colorScheme.onSurface);
    if (caption == _lastCaption && text == _lastText) return;

    _lastCaption = caption;
    _lastText = text;

    try {
      await _channel.invokeMethod<void>('setCaptionColors', {
        'caption': caption,
        'text': text,
        'dark': colorScheme.brightness == Brightness.dark,
      });
    } on PlatformException {
      // An older Windows rejects the colour attributes. The caption keeps the
      // OS theme, which is the behaviour this app shipped with — not worth
      // surfacing to the user.
    } on MissingPluginException {
      // Running against a runner built before the channel existed.
    }
  }

  /// Forces the next [applyTheme] to reach the platform even if the colours
  /// match — for a window that was recreated and has lost its caption colour.
  @visibleForTesting
  static void resetCache() {
    _lastCaption = null;
    _lastText = null;
  }

  static int _toArgb(Color color) =>
      (color.a * 255).round() << 24 |
      (color.r * 255).round() << 16 |
      (color.g * 255).round() << 8 |
      (color.b * 255).round();
}
