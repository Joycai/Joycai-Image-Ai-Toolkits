import 'dart:io';

import 'package:path/path.dart' as p;

/// A folder grant, optionally restricted to direct children with a trailing `/*`.
/// Plain folders retain the original recursive behavior; `/**` makes it explicit.
class ReferenceFolderRule {
  ReferenceFolderRule._(this.directory, this.suffix);

  final String directory;
  final String suffix;

  static ReferenceFolderRule parse(String value) {
    final leaf = p.basename(value);
    final suffix = leaf == '*' || leaf == '**' ? leaf : '';
    final directory = suffix.isEmpty ? value : p.dirname(value);
    if (!p.isAbsolute(directory) || directory.contains('*')) {
      throw const FormatException('Use an absolute folder with an optional /* or /** suffix.');
    }
    return ReferenceFolderRule._(p.normalize(directory), suffix);
  }

  Future<String> canonicalSetting() async {
    final resolved = await Directory(directory).resolveSymbolicLinks();
    if (!await Directory(resolved).exists()) throw const FormatException('Folder required.');
    return suffix.isEmpty ? resolved : p.join(resolved, suffix);
  }

  Future<bool> allows(String canonicalFile) async {
    final resolved = await Directory(directory).resolveSymbolicLinks();
    // A saved grant must not change scope when its directory becomes a symlink.
    if (resolved != directory) return false;
    return suffix == '*'
        ? p.equals(p.dirname(canonicalFile), resolved)
        : p.isWithin(resolved, canonicalFile);
  }
}
