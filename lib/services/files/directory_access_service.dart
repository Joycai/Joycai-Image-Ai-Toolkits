import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// OS authorization is independent of application path settings and MCP rules.
/// Native grants stay on this Mac, outside the application's backup database.
/// The runner owns one scope per root for watchers/background tasks until exit.
enum DirectoryAccessStatus { available, needsAuthorization, unavailable, moved }

@immutable
class DirectoryGrant {
  const DirectoryGrant({required this.path, required this.readOnly});

  final String path;
  final bool readOnly;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectoryGrant && path == other.path && readOnly == other.readOnly;

  @override
  int get hashCode => Object.hash(path, readOnly);
}

class DirectoryAccessService {
  DirectoryAccessService({MethodChannel? channel, bool? useNative})
    : _channel = channel ?? const MethodChannel('joycai/directory_access'),
      _useNativeOverride = useNative;

  static final instance = DirectoryAccessService();
  final MethodChannel _channel;
  final bool? _useNativeOverride;

  bool get _useNative =>
      _useNativeOverride ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS);

  Future<Map<String, DirectoryAccessStatus>> restoreAll() async {
    if (!_useNative) return const {};
    try {
      final states = await _channel.invokeMapMethod<String, String>('restoreAll') ?? {};
      return states.map((path, status) => MapEntry(path, _status(status)));
    } on PlatformException catch (error) {
      debugPrint('Directory authorization store unavailable: ${error.code}');
      return const {};
    }
  }

  /// No prompts on launch or background retries. Offline/corrupt grants remain
  /// stored so a later retry or explicit selection can recover them.
  Future<DirectoryAccessStatus> restore(String path) async {
    if (!_useNative) return DirectoryAccessStatus.available;
    try {
      return _status(await _channel.invokeMethod<String>('restore', {'path': path}));
    } on PlatformException {
      return DirectoryAccessStatus.unavailable;
    }
  }

  Future<String?> pickDirectory({
    String? initialDirectory,
    String? dialogTitle,
    bool readOnly = false,
    String? requiredPath,
  }) async {
    if (!_useNative) {
      final uri = await FilePicker.pickDirectory(
        initialDirectory: initialDirectory,
        dialogTitle: dialogTitle,
      );
      return normalizePickedDirectoryUri(uri);
    }
    return _channel.invokeMethod<String>('pick', {
      'initialDirectory': initialDirectory,
      'title': dialogTitle,
      'readOnly': readOnly,
      'requiredPath': requiredPath,
    });
  }

  /// Used for text-entered MCP roots: selecting a different directory cannot
  /// accidentally grant the requested rule. Cancellation leaves settings intact.
  Future<bool> authorizeReadOnly(String path) async {
    if (!_useNative || await restore(path) == DirectoryAccessStatus.available) return true;
    try {
      return await pickDirectory(
            initialDirectory: path,
            dialogTitle: path,
            readOnly: true,
            requiredPath: path,
          ) !=
          null;
    } on PlatformException {
      return false;
    }
  }

  /// Lists persisted security-scoped directory grants on macOS without exposing
  /// raw bookmark data. Throws [PlatformException] if the native store cannot be read.
  Future<List<DirectoryGrant>> listGrants() async {
    if (!_useNative) return const [];
    final raw = await _channel.invokeListMethod<dynamic>('list') ?? const [];
    return [
      for (final entry in raw)
        if (entry is Map)
          DirectoryGrant(
            path: entry['path'] as String? ?? '',
            readOnly: entry['readOnly'] as bool? ?? false,
          ),
    ];
  }

  /// Revokes a single persisted security-scoped directory bookmark on macOS.
  Future<bool> revoke(String path) async {
    if (!_useNative) return false;
    return (await _channel.invokeMethod<bool>('revoke', {'path': path})) == true;
  }

  /// Revokes all persisted security-scoped directory bookmarks on macOS.
  Future<int> revokeAll() async {
    if (!_useNative) return 0;
    return await _channel.invokeMethod<int>('revokeAll') ?? 0;
  }

  @visibleForTesting
  static String? normalizePickedDirectoryUri(Uri? uri, {bool? windows}) {
    if (uri == null || !uri.isScheme('file')) return null;
    final isWindows = windows ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows);
    final context = p.Context(style: isWindows ? p.Style.windows : p.Style.posix);
    return context.normalize(uri.toFilePath(windows: isWindows));
  }

  static DirectoryAccessStatus _status(String? value) => DirectoryAccessStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => DirectoryAccessStatus.unavailable,
  );
}
