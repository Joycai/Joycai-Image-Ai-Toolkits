/// The direct-download macOS package deliberately runs outside App Sandbox.
/// Set only together with the native direct-distribution build configuration.
abstract final class AppDistribution {
  static const direct = bool.fromEnvironment('JOYCAI_DIRECT_DISTRIBUTION');
}
