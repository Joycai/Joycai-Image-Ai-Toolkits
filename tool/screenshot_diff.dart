import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Snapshots and compares UI screenshot PNGs before/after a change and produces
/// a self-contained HTML side-by-side + diff report.
///
/// Usage:
///   dart run tool/screenshot_diff.dart snapshot [--from build/ui-screenshots] [--to build/ui-screenshots-baseline]
///   dart run tool/screenshot_diff.dart compare [--baseline build/ui-screenshots-baseline] [--current build/ui-screenshots] [--out build/ui-screenshots-diff]
void main(List<String> args) {
  exitCode = runScreenshotDiff(args);
}

/// Runs the screenshot diff CLI and returns the process exit code.
int runScreenshotDiff(List<String> args) {
  if (args.isEmpty) {
    _printUsage();
    return 64;
  }

  final String command = args.first;
  final Map<String, String> opts = _parseArgs(args.skip(1).toList());

  switch (command) {
    case 'snapshot':
      return _runSnapshot(
        fromDir: Directory(opts['from'] ?? 'build/ui-screenshots'),
        toDir: Directory(opts['to'] ?? 'build/ui-screenshots-baseline'),
      );
    case 'compare':
      _runCompare(
        baselineDir: Directory(opts['baseline'] ?? 'build/ui-screenshots-baseline'),
        currentDir: Directory(opts['current'] ?? 'build/ui-screenshots'),
        outDir: Directory(opts['out'] ?? 'build/ui-screenshots-diff'),
      );
      return 0;
    default:
      stderr.writeln('Unknown subcommand: $command');
      _printUsage();
      return 64;
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage:\n'
    '  dart run tool/screenshot_diff.dart snapshot '
    '[--from build/ui-screenshots] [--to build/ui-screenshots-baseline]\n'
    '  dart run tool/screenshot_diff.dart compare '
    '[--baseline build/ui-screenshots-baseline] [--current build/ui-screenshots] '
    '[--out build/ui-screenshots-diff]',
  );
}

Map<String, String> _parseArgs(List<String> args) {
  final Map<String, String> out = <String, String>{};
  for (int i = 0; i < args.length; i++) {
    final String arg = args[i];
    if (!arg.startsWith('--')) continue;
    final String trimmed = arg.substring(2);
    final int eq = trimmed.indexOf('=');
    if (eq >= 0) {
      out[trimmed.substring(0, eq)] = trimmed.substring(eq + 1);
    } else if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      out[trimmed] = args[++i];
    }
  }
  return out;
}

Map<String, File> _listPngs(Directory dir) {
  if (!dir.existsSync()) return <String, File>{};
  final Map<String, File> out = <String, File>{};
  for (final FileSystemEntity entity in dir.listSync()) {
    if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
      out[p.basename(entity.path)] = entity;
    }
  }
  return out;
}

int _runSnapshot({required Directory fromDir, required Directory toDir}) {
  final Map<String, File> sources = _listPngs(fromDir);
  if (sources.isEmpty) {
    stderr.writeln('No PNG files found in ${fromDir.path}.');
    return 1;
  }
  if (toDir.existsSync()) {
    toDir.deleteSync(recursive: true);
  }
  toDir.createSync(recursive: true);

  for (final MapEntry<String, File> entry in sources.entries) {
    entry.value.copySync(p.join(toDir.path, entry.key));
  }
  stdout.writeln('Snapshotted ${sources.length} PNG(s) → ${toDir.path}');
  return 0;
}

enum _DiffKind { changed, added, removed, identical }

class _DiffEntry {
  _DiffEntry({
    required this.name,
    required this.kind,
    required this.diffPixels,
    required this.totalPixels,
    required this.sizeMismatch,
    this.baselineRel,
    this.currentRel,
    this.diffRel,
  });

  final String name;
  final _DiffKind kind;
  final int diffPixels;
  final int totalPixels;
  final bool sizeMismatch;
  final String? baselineRel;
  final String? currentRel;
  final String? diffRel;

  double get diffPercent => totalPixels == 0 ? 0 : (diffPixels / totalPixels) * 100.0;
}

void _runCompare({
  required Directory baselineDir,
  required Directory currentDir,
  required Directory outDir,
}) {
  final Map<String, File> baseMap = _listPngs(baselineDir);
  final Map<String, File> currMap = _listPngs(currentDir);
  final Set<String> allNames = <String>{...baseMap.keys, ...currMap.keys};

  if (outDir.existsSync()) {
    outDir.deleteSync(recursive: true);
  }
  final Directory baseOut = Directory(p.join(outDir.path, 'baseline'))..createSync(recursive: true);
  final Directory currOut = Directory(p.join(outDir.path, 'current'))..createSync(recursive: true);
  final Directory diffOut = Directory(p.join(outDir.path, 'diffs'))..createSync(recursive: true);

  final List<_DiffEntry> entries = <_DiffEntry>[];
  final List<String> sortedNames = allNames.toList()..sort();

  for (final String name in sortedNames) {
    final File? baseFile = baseMap[name];
    final File? currFile = currMap[name];

    if (baseFile == null && currFile != null) {
      currFile.copySync(p.join(currOut.path, name));
      entries.add(
        _DiffEntry(
          name: name,
          kind: _DiffKind.added,
          diffPixels: 0,
          totalPixels: 0,
          sizeMismatch: false,
          currentRel: 'current/$name',
        ),
      );
      continue;
    }

    if (baseFile != null && currFile == null) {
      baseFile.copySync(p.join(baseOut.path, name));
      entries.add(
        _DiffEntry(
          name: name,
          kind: _DiffKind.removed,
          diffPixels: 0,
          totalPixels: 0,
          sizeMismatch: false,
          baselineRel: 'baseline/$name',
        ),
      );
      continue;
    }

    final img.Image? baseImg = img.decodePng(baseFile!.readAsBytesSync());
    final img.Image? currImg = img.decodePng(currFile!.readAsBytesSync());
    if (baseImg == null || currImg == null) continue;

    final ({int diffPixels, int totalPixels, bool sizeMismatch, img.Image diffImage}) result =
        _diffImages(baseImg, currImg);

    if (result.diffPixels == 0 && !result.sizeMismatch) {
      entries.add(
        _DiffEntry(
          name: name,
          kind: _DiffKind.identical,
          diffPixels: 0,
          totalPixels: result.totalPixels,
          sizeMismatch: false,
        ),
      );
      continue;
    }

    baseFile.copySync(p.join(baseOut.path, name));
    currFile.copySync(p.join(currOut.path, name));
    File(p.join(diffOut.path, name)).writeAsBytesSync(img.encodePng(result.diffImage));

    entries.add(
      _DiffEntry(
        name: name,
        kind: _DiffKind.changed,
        diffPixels: result.diffPixels,
        totalPixels: result.totalPixels,
        sizeMismatch: result.sizeMismatch,
        baselineRel: 'baseline/$name',
        currentRel: 'current/$name',
        diffRel: 'diffs/$name',
      ),
    );
  }

  final File reportFile = File(p.join(outDir.path, 'index.html'));
  reportFile.writeAsStringSync(_renderHtml(entries));

  final int changed = entries.where((e) => e.kind == _DiffKind.changed).length;
  final int added = entries.where((e) => e.kind == _DiffKind.added).length;
  final int removed = entries.where((e) => e.kind == _DiffKind.removed).length;
  final int identical = entries.where((e) => e.kind == _DiffKind.identical).length;

  stdout.writeln(
    'Screenshot diff complete: $changed changed, $added added, '
    '$removed removed, $identical identical.\n'
    'Report → ${reportFile.absolute.path}',
  );
}

({int diffPixels, int totalPixels, bool sizeMismatch, img.Image diffImage}) _diffImages(
  img.Image base,
  img.Image curr,
) {
  final int width = math.max(base.width, curr.width);
  final int height = math.max(base.height, curr.height);
  final bool sizeMismatch = base.width != curr.width || base.height != curr.height;
  final img.Image diff = img.Image(width: width, height: height, numChannels: 4);

  int diffPixels = 0;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final bool inBase = x < base.width && y < base.height;
      final bool inCurr = x < curr.width && y < curr.height;

      if (!inBase || !inCurr) {
        diffPixels++;
        diff.setPixelRgba(x, y, 255, 64, 160, 255);
        continue;
      }

      final img.Pixel bp = base.getPixel(x, y);
      final img.Pixel cp = curr.getPixel(x, y);
      final int dr = (bp.r.toInt() - cp.r.toInt()).abs();
      final int dg = (bp.g.toInt() - cp.g.toInt()).abs();
      final int db = (bp.b.toInt() - cp.b.toInt()).abs();
      final int da = (bp.a.toInt() - cp.a.toInt()).abs();
      final int maxDelta = math.max(math.max(dr, dg), math.max(db, da));

      if (maxDelta > 2) {
        diffPixels++;
        diff.setPixelRgba(x, y, 255, 45, 145, 255);
      } else {
        diff.setPixelRgba(
          x,
          y,
          (cp.r.toInt() * 0.35).round(),
          (cp.g.toInt() * 0.35).round(),
          (cp.b.toInt() * 0.35).round(),
          255,
        );
      }
    }
  }

  return (
    diffPixels: diffPixels,
    totalPixels: width * height,
    sizeMismatch: sizeMismatch,
    diffImage: diff,
  );
}

String _renderHtml(List<_DiffEntry> entries) {
  const HtmlEscape esc = HtmlEscape();
  final int changed = entries.where((e) => e.kind == _DiffKind.changed).length;
  final int added = entries.where((e) => e.kind == _DiffKind.added).length;
  final int removed = entries.where((e) => e.kind == _DiffKind.removed).length;
  final int identical = entries.where((e) => e.kind == _DiffKind.identical).length;

  final StringBuffer cards = StringBuffer();
  for (final _DiffEntry entry in entries) {
    if (entry.kind == _DiffKind.identical) continue;
    final String badge = switch (entry.kind) {
      _DiffKind.changed =>
        '${entry.diffPercent.toStringAsFixed(2)}% diff${entry.sizeMismatch ? ' (size changed)' : ''}',
      _DiffKind.added => 'ADDED',
      _DiffKind.removed => 'REMOVED',
      _DiffKind.identical => 'IDENTICAL',
    };
    cards.writeln('''
<section class="card" data-kind="${entry.kind.name}">
  <header>
    <strong>${esc.convert(entry.name)}</strong>
    <span class="badge ${entry.kind.name}">${esc.convert(badge)}</span>
  </header>
  <div class="grid">
    ${entry.baselineRel != null ? '<figure><figcaption>Baseline</figcaption><img src="${esc.convert(entry.baselineRel!)}"></figure>' : ''}
    ${entry.currentRel != null ? '<figure><figcaption>Current</figcaption><img src="${esc.convert(entry.currentRel!)}"></figure>' : ''}
    ${entry.diffRel != null ? '<figure><figcaption>Diff</figcaption><img src="${esc.convert(entry.diffRel!)}"></figure>' : ''}
  </div>
</section>''');
  }

  return '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Joycai Screenshot Diff Report</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 24px; background: #141413; color: #eceae4; }
    h1 { margin: 0 0 8px; font-size: 20px; }
    .summary { color: #a9a69e; margin-bottom: 20px; }
    .card { background: #1f1f1c; border: 1px solid #33322e; border-radius: 12px; padding: 16px; margin-bottom: 16px; }
    .card header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; }
    .badge { padding: 3px 8px; border-radius: 6px; font-size: 12px; font-weight: 600; }
    .badge.changed { background: #4a2033; color: #ff8bb8; }
    .badge.added { background: #173a24; color: #4fb86f; }
    .badge.removed { background: #452220; color: #f28b82; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 12px; }
    figure { margin: 0; }
    figcaption { font-size: 12px; color: #a9a69e; margin-bottom: 6px; }
    img { width: 100%; height: auto; border: 1px solid #33322e; border-radius: 8px; background: #121210; }
  </style>
</head>
<body>
  <h1>Screenshot Diff Report</h1>
  <div class="summary">$changed changed · $added added · $removed removed · $identical identical</div>
  ${cards.isEmpty ? '<p>No visual differences detected.</p>' : cards.toString()}
</body>
</html>
''';
}
