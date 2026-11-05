/// Explicit non-store builds. GitHub artifacts set this on every platform.
/// On macOS, also select the native direct configuration (outside App Sandbox).
abstract final class AppDistribution {
  static const direct = bool.fromEnvironment('JOYCAI_DIRECT_DISTRIBUTION');
}
