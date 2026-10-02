import 'package:flutter/painting.dart';

/// A file image whose decoded cache entry follows the scanned file version.
///
/// Including the version in the provider also changes ResizeImage's key and
/// makes an already mounted Image resolve a new stream after an external edit.
class VersionedFileImage extends FileImage {
  final String version;

  const VersionedFileImage(super.file, {required this.version, super.scale});

  @override
  bool operator ==(Object other) =>
      other is VersionedFileImage &&
      other.runtimeType == runtimeType &&
      other.file.path == file.path &&
      other.scale == scale &&
      other.version == version;

  @override
  int get hashCode => Object.hash(file.path, scale, version);
}
