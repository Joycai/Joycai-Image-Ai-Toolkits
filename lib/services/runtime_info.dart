import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/app_paths.dart';

/// What the About page's 「运行信息」 block reports — `E1 · 2a`.
///
/// The four lines a bug report needs and nobody can read off the screen:
/// which build is running, on what engine, on what machine, and where its
/// data lives. [report] is the same four as one block, which is what the
/// Copy button puts on the clipboard.
@immutable
class RuntimeInfo {
  const RuntimeInfo({
    required this.version,
    required this.buildNumber,
    required this.engine,
    required this.platform,
    required this.dataDirectory,
  });

  /// The semantic version, as `pubspec.yaml` spells it.
  final String version;

  /// The build suffix (`+B`). Empty where the platform reports none.
  final String buildNumber;

  final String engine;

  /// The operating system, its version, and the ABI the app was built for.
  final String platform;

  final String dataDirectory;

  /// `4.0.0 (build 0)`.
  String get versionLine =>
      buildNumber.isEmpty ? version : '$version (build $buildNumber)';

  /// The block the Copy button writes.
  ///
  /// English labels, untranslated by intent: it is pasted into an issue,
  /// where it is read by whoever fixes the bug rather than by the person who
  /// copied it — the same reason the editor prints token counts in mono
  /// rather than in words.
  String get report => <String>[
        'Version: $versionLine',
        'Engine: $engine',
        'Platform: $platform',
        'Data directory: $dataDirectory',
      ].join('\n');

  /// Reads the running app.
  static Future<RuntimeInfo> load() async {
    final info = await PackageInfo.fromPlatform();
    return RuntimeInfo(
      version: info.version,
      buildNumber: info.buildNumber,
      engine: describeEngine(Platform.version),
      platform: describePlatform(
        operatingSystem: Platform.operatingSystem,
        operatingSystemVersion: Platform.operatingSystemVersion,
        dartVersion: Platform.version,
      ),
      dataDirectory: await AppPaths.getDataDirectory(),
    );
  }

  /// `Dart 3.11.0` out of `Platform.version`, which trails the channel, the
  /// build date and the target after it.
  ///
  /// The Flutter version is deliberately absent: nothing reports it at run
  /// time, and a constant written beside it in the source would say whatever
  /// it said the day someone last edited this file.
  static String describeEngine(String dartVersion) {
    final number = dartVersion.trim().split(RegExp(r'\s+')).first;
    return number.isEmpty ? 'Dart' : 'Dart $number';
  }

  /// `Windows 10 Pro 10.0 (Build 26200) · x64`, `macOS 15.3 (Build 24D60) · arm64`.
  ///
  /// `operatingSystemVersion` is free-form per platform: Windows quotes its
  /// edition and names itself, macOS opens with a bare `Version`. Both are
  /// normalised rather than parsed — a string this one cannot read still
  /// reaches the report intact, which is what a bug report wants.
  static String describePlatform({
    required String operatingSystem,
    required String operatingSystemVersion,
    required String dartVersion,
  }) {
    final String name = _osNames[operatingSystem] ?? operatingSystem;
    String version = operatingSystemVersion.replaceAll('"', '').trim();
    if (version.startsWith('Version ')) {
      version = version.substring('Version '.length).trim();
    }
    final bool namesItself = version.toLowerCase().contains(name.toLowerCase());
    final String described = (namesItself ? version : '$name $version').trim();
    final String? abi = _abiOf(dartVersion);
    return abi == null ? described : '$described · $abi';
  }

  static const Map<String, String> _osNames = {
    'windows': 'Windows',
    'macos': 'macOS',
    'linux': 'Linux',
    'android': 'Android',
    'ios': 'iOS',
  };

  /// The architecture half of Dart's `on "windows_x64"` tail.
  static String? _abiOf(String dartVersion) {
    final match = RegExp(r'on "([^"]+)"').firstMatch(dartVersion);
    if (match == null) return null;
    final target = match.group(1)!;
    final int cut = target.indexOf('_');
    final String abi = cut < 0 ? target : target.substring(cut + 1);
    return abi.isEmpty ? null : abi;
  }
}
