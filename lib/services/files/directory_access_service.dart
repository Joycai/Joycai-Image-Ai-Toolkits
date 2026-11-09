import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// OS authorization is independent of application path settings and MCP rules.
/// Native grants stay on this Mac, outside the application's backup database.
/// The runner owns one scope per root for watchers/background tasks until exit.
enum DirectoryAccessStatus { available, needsAuthorization, unavailable, moved }

class DirectoryAccessService {
  DirectoryAccessService({MethodChannel? channel, bool? useNative})
    : _channel = channel ?? const MethodChannel('joycai/directory_access'),
      _useNative = useNative ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS);

  static final instance = DirectoryAccessService();
  final MethodChannel _channel;
  final bool _useNative;

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
      return FilePicker.getDirectoryPath(
        initialDirectory: initialDirectory,
        dialogTitle: dialogTitle,
      );
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

  static DirectoryAccessStatus _status(String? value) => DirectoryAccessStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => DirectoryAccessStatus.unavailable,
  );
}
