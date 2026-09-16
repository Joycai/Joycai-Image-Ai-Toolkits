import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reports which graphics adapter the app is rendering on.
///
/// Read-only by design. The app used to carry a "prefer high-performance GPU"
/// switch that wrote the per-app entry under
/// `HKCU\Software\Microsoft\DirectX\UserGpuPreferences`, and a runner that
/// forced the low-power adapter whenever that entry was absent — so the same
/// choice lived in two places with different defaults, and the app's copy
/// silently overrode "let Windows decide". The choice now belongs to Windows
/// alone (Settings > System > Display > Graphics); this only says where it
/// landed.
///
/// The answer comes from the graphics stack rather than from the registry: the
/// runner creates a device on the default adapter — the same call, and so the
/// same adapter, the engine's own device uses — and reports its name. A
/// registry read would instead report a wish, saying nothing when no entry
/// exists and still naming a card that has since been disabled.
///
/// Windows-only; the adapter is fixed for the life of the process, so one call
/// per launch is enough.
class GpuInfoService {
  static const MethodChannel _channel = MethodChannel('joycai/gpu');

  /// Whether this platform can be asked. macOS and Linux have no equivalent
  /// per-app adapter choice, and the settings row hides itself there.
  bool get isSupported => !kIsWeb && Platform.isWindows;

  /// Name of the active adapter ("NVIDIA GeForce RTX 4080"), or null when the
  /// platform has no answer — an unsupported OS, or a graphics stack that
  /// refused the query. Callers show that as "unavailable", not as an error.
  Future<String?> activeGpuName() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('activeGpu');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // An older runner, or a platform whose runner has no such channel.
      return null;
    }
  }
}
