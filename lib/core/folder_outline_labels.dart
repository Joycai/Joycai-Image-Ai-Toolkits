/// The chip text for each folder of an outline: the basename, and where two
/// folders share one, as many parent segments as it takes to tell them apart
/// — `out / a` beside `tmp / a`, then `x / out / a` beside `y / out / a`.
///
/// One label per path, in the order given. Two identical paths stay
/// identical: there is nothing left to disambiguate them with.
List<String> folderOutlineLabels(List<String> paths) {
  // Both separators, whatever the host: the paths come from the user's
  // own disk, and a test on Linux CI still sees Windows paths.
  final separators = RegExp(r'[\\/]+');
  final segments = [
    for (final path in paths)
      path.split(separators).where((s) => s.isNotEmpty).toList(growable: false),
  ];
  // How many trailing segments each label shows; grows while it collides.
  final depth = List<int>.filled(paths.length, 1);

  bool collides(int i, int j) => _tail(segments[i], depth[i]) == _tail(segments[j], depth[j]);

  var changed = true;
  while (changed) {
    changed = false;
    for (var i = 0; i < paths.length; i++) {
      for (var j = i + 1; j < paths.length; j++) {
        if (!collides(i, j)) continue;
        // The same folder twice cannot be told apart; leave both bare.
        if (_tail(segments[i], segments[i].length) == _tail(segments[j], segments[j].length)) {
          continue;
        }
        // Deepen whichever side still has segments to give; a side already
        // showing its whole path cannot grow.
        final canI = depth[i] < segments[i].length;
        final canJ = depth[j] < segments[j].length;
        if (!canI && !canJ) continue;
        if (canI) depth[i]++;
        if (canJ) depth[j]++;
        changed = true;
      }
    }
  }
  return [
    for (var i = 0; i < paths.length; i++)
      segments[i].isEmpty
          ? paths[i]
          : segments[i].sublist(segments[i].length - depth[i]).join(' / '),
  ];
}

String _tail(List<String> segments, int depth) =>
    segments.sublist(segments.length - depth.clamp(0, segments.length)).join('/').toLowerCase();
