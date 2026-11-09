/// Explicit non-store builds. GitHub artifacts set this on every platform.
/// Distribution policy is independent of macOS App Sandbox; both builds use it.
abstract final class AppDistribution {
  static const direct = bool.fromEnvironment('JOYCAI_DIRECT_DISTRIBUTION');
}
