import 'dart:io';

/// Reads and writes the per-app GPU preference Windows keeps under
/// `HKCU\Software\Microsoft\DirectX\UserGpuPreferences` — the same store the
/// Settings > Display > Graphics page edits, so the app's toggle and the OS
/// page see each other's changes. Entries are keyed by the exe's full path,
/// which means dev (Debug runner) and installed builds carry independent
/// preferences, and a moved installation starts back at the default.
///
/// Windows reads the value once at process start, so a change only applies on
/// the next launch. The runner also exports the NvOptimusEnablement /
/// AmdPowerXpressRequestHighPerformance hints (see `windows/runner/main.cpp`);
/// this registry entry is the stronger, user-level setting for machines whose
/// drivers ignore those hints.
class GpuPreferenceService {
  static const String _key =
      r'HKCU\Software\Microsoft\DirectX\UserGpuPreferences';

  /// `2` is "High performance" in the Settings page's terms. The trailing
  /// semicolon matches what Windows itself writes.
  static const String _highPerformance = 'GpuPreference=2;';

  /// Per-app GPU preference is a Windows-only concept; every other platform
  /// reports unsupported and the settings UI hides the toggle.
  bool get isSupported => Platform.isWindows;

  String get _exePath => Platform.resolvedExecutable;

  /// Whether this exe currently has a high-performance override registered.
  Future<bool> isHighPerformanceSet() async {
    if (!isSupported) return false;
    final result = await Process.run('reg', ['query', _key, '/v', _exePath]);
    return result.exitCode == 0 &&
        (result.stdout as String).contains('GpuPreference=2');
  }

  /// Registers (or removes) the high-performance preference for this exe.
  /// Returns whether the desired end state holds.
  Future<bool> setHighPerformance(bool enabled) async {
    if (!isSupported) return false;
    if (enabled) {
      final result = await Process.run('reg', [
        'add', _key, '/v', _exePath, '/t', 'REG_SZ', '/d', _highPerformance,
        '/f',
      ]);
      return result.exitCode == 0;
    }
    // "Off" restores Windows' own choice by deleting the entry. reg.exe
    // reports failure when the value is already absent, which is the desired
    // end state — re-query instead of trusting the exit code.
    await Process.run('reg', ['delete', _key, '/v', _exePath, '/f']);
    return !await isHighPerformanceSet();
  }
}
