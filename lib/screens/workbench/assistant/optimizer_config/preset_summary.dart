final RegExp _rule = RegExp(r'^([-*_=])\1{2,}$');
final RegExp _marker = RegExp(r'^(?:>+\s*|[-*+]\s+|\d+[.)]\s+)+');
final RegExp _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');
final RegExp _emphasis = RegExp(r'[*_`]+');
final RegExp _space = RegExp(r'\s+');

/// One or two lines saying what a task preset is for (`A3d 4b`).
///
/// Derived from the preset's own text rather than stored beside it: the
/// first paragraph of a well-written instruction already says what it does,
/// and a description column would be a second copy that drifts from the
/// first the moment someone edits one of them.
///
/// Takes the first paragraph that is prose — headings, rules and fences are
/// skipped — and strips the markdown that would otherwise show as symbols.
/// Returns an empty string when the text has no prose line at all.
String presetSummaryOf(String content) {
  final lines = <String>[];
  var inFence = false;
  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('```') || line.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    final structural = line.isEmpty || line.startsWith('#') || _rule.hasMatch(line);
    if (structural) {
      if (lines.isNotEmpty) break;
      continue;
    }
    lines.add(line);
  }
  return lines
      .map(
        (l) => l
            .replaceFirst(_marker, '')
            .replaceAllMapped(_link, (m) => m[1]!)
            .replaceAll(_emphasis, ''),
      )
      .join(' ')
      .replaceAll(_space, ' ')
      .trim();
}
