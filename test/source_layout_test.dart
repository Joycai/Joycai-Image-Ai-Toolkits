import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The layering of `lib/`, asserted against the imports themselves.
///
/// Three directory-level cycles used to sit in here, and each one was a
/// handful of imports against hundreds going the other way — 18 of
/// `services -> state` against 28 back, 5 of `widgets -> screens` against
/// 310, 3 of `core -> services` against 22. None of them broke a build or a
/// test, which is exactly why they survived: a cycle is invisible from inside
/// any one file, and the minority direction always looks like a shortcut at
/// the point you write it.
///
/// So the shape is pinned here rather than left to review. What each module
/// may import is a *rank*: a file may import its own module and anything of
/// strictly lower rank, nothing else. That is stronger than "no cycles" and
/// says more — it fixes the direction, not just the absence of a loop.
///
/// Adding an edge means moving the file to the layer it belongs in, or
/// deliberately re-ranking here and saying why. `docs/architecture/` holds the
/// reasoning for the layers inside `services/llm/`; this test is otherwise
/// about the top-level directories, with two exceptions it also pins: that
/// `widgets/` and `services/` stay grouped rather than drifting back to one
/// flat root, and that the design system under `widgets/` stays free of the
/// app's domain.
void main() {
  /// Lower rank may not import higher. Equal rank means the same module.
  const rank = <String, int>{
    // Foundation. `core` is breakpoints, paths, constants and design tokens;
    // `l10n` is generated. Neither imports anything else in lib/.
    'core': 0,
    'l10n': 0,
    // Plain data.
    'models': 1,
    // Business logic. CLAUDE.md: "Business logic belongs in lib/services/,
    // not in widgets or screens."
    'services': 2,
    // The ChangeNotifier singletons, which drive services.
    'state': 3,
    // Shared UI.
    'widgets': 4,
    // Features. Everything above is fair game; nothing may import back.
    'screens': 5,
    // The inert benchmark harness (`RBENCH=1`), which mounts real widgets.
    'bench': 6,
    // `main.dart`, which wires everything together — including `bench`, so it
    // has to sit above it rather than beside it.
    '<root>': 7,
  };

  final libDir = Directory('lib');

  /// The top-level module a file under `lib/` belongs to.
  String moduleOf(String path) {
    final parts = p.split(p.relative(path, from: 'lib'));
    return parts.length == 1 ? '<root>' : parts.first;
  }

  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => p.normalize(f.path))
      .where((f) => f.endsWith('.dart'))
      .toList()
    ..sort();

  // A directive URI as written, with the line it was written on.
  final directive = RegExp(r"^\s*(?:import|export|part)\s+'([^']+)'", multiLine: true);

  /// Every intra-`lib` directive, as (file, line, uri, resolved target).
  final edges = <({String from, int line, String uri, String to})>[];
  final overDeep = <String>[];

  setUpAll(() {
    for (final file in dartFiles) {
      final dir = p.dirname(file);
      final source = File(file).readAsStringSync();
      for (final match in directive.allMatches(source)) {
        final uri = match.group(1)!;
        if (uri.startsWith('package:') || uri.startsWith('dart:')) continue;

        final line = source.substring(0, match.start).split('\n').length;

        // Dart normalises a directive URI before resolving it, and `..`
        // clamps at the root: from `lib/widgets/`, `../../l10n/x.dart` and
        // `../../../../l10n/x.dart` both land on `lib/l10n/x.dart`. That makes
        // an over-deep prefix silent, so catch it here instead.
        final ups = RegExp(r'^(?:\.\./)+').firstMatch(uri)?.group(0);
        final depth = p.split(p.relative(dir, from: 'lib')).where((s) => s != '.').length;
        if (ups != null && (ups.length ~/ 3) > depth) {
          overDeep.add("$file:$line  '$uri' climbs ${ups.length ~/ 3} "
              'but sits $depth level(s) below lib/');
        }

        final target = p.normalize(p.join(dir, uri));
        if (!p.isWithin('lib', target)) continue;
        edges.add((from: file, line: line, uri: uri, to: target));
      }
    }
  });

  test('every module in lib/ is ranked', () {
    final modules = dartFiles.map(moduleOf).toSet();
    final unranked = modules.difference(rank.keys.toSet());
    expect(
      unranked,
      isEmpty,
      reason: 'new top-level director${unranked.length == 1 ? 'y' : 'ies'} under lib/ '
          '($unranked) — decide where they sit in the layering and add them to `rank`',
    );
  });

  test('no import points at a higher layer', () {
    final violations = <String>[];
    for (final edge in edges) {
      final from = moduleOf(edge.from);
      final to = moduleOf(edge.to);
      if (from == to) continue;
      final fromRank = rank[from]!;
      final toRank = rank[to]!;
      if (toRank >= fromRank) {
        violations.add('${edge.from}:${edge.line}  $from (rank $fromRank) -> '
            "$to (rank $toRank)   import '${edge.uri}'");
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'these imports run against the layering:\n  ${violations.join('\n  ')}\n\n'
          'Move the file to the layer it belongs in — a shared widget that needs a '
          'feature screen usually wants the dependency injected instead.',
    );
  });

  test('the module graph is acyclic', () {
    // Redundant while the rank test passes, and deliberately so: it is the
    // property that actually matters, and it keeps holding if the ranks are
    // ever loosened.
    final graph = <String, Set<String>>{};
    for (final edge in edges) {
      final from = moduleOf(edge.from);
      final to = moduleOf(edge.to);
      if (from != to) (graph[from] ??= <String>{}).add(to);
    }

    final cycles = <String>[];
    void walk(String node, List<String> path, Set<String> seen) {
      for (final next in graph[node] ?? const <String>{}) {
        if (path.contains(next)) {
          cycles.add([...path.sublist(path.indexOf(next)), next].join(' -> '));
        } else if (seen.add(next)) {
          walk(next, [...path, next], seen);
        }
      }
    }

    for (final node in graph.keys) {
      walk(node, [node], {node});
    }
    expect(cycles.toSet(), isEmpty, reason: 'dependency cycle between top-level modules');
  });

  test('core and l10n import nothing else in lib/', () {
    final leaked = edges
        .where((e) => const {'core', 'l10n'}.contains(moduleOf(e.from)))
        .where((e) => moduleOf(e.to) != moduleOf(e.from))
        .map((e) => "${e.from}:${e.line}  -> '${e.uri}'")
        .toList();
    expect(
      leaked,
      isEmpty,
      reason: 'the foundation layer reached upwards:\n  ${leaked.join('\n  ')}\n\n'
          'A presentation helper that needs a service type is not foundational — '
          '`backup_error_text`, `context_usage_palette` and `task_type_glyph` all '
          'moved to lib/widgets/ for this reason.',
    );
  });

  test('no relative directive climbs past lib/', () {
    expect(
      overDeep,
      isEmpty,
      reason: 'Dart clamps `..` at the package root, so these resolve anyway and '
          'will keep resolving however many are added — but they claim a depth the '
          'file does not have:\n  ${overDeep.join('\n  ')}',
    );
  });

  /// Directories that are grouped by domain, and so may not hold loose files.
  ///
  /// Both had flat roots — 44 files in `widgets/`, 31 in `services/` — mixing
  /// the design system with feature components and five service domains with
  /// each other. Nothing is wrong with a flat directory as such: `core/`,
  /// `models/` and `state/` are flat and readable, because each is one kind of
  /// thing. These two are not, and one loose file is how the flat root comes
  /// back: it names no domain, so the next one has somewhere to land beside it.
  const grouped = {'widgets', 'services'};

  /// The design system: the spec's own controls, materials and affordances.
  ///
  /// What makes them a group is a property rather than a naming convention —
  /// none of them knows anything about this app. They may draw on the
  /// foundation and on each other, and that is all, so a screen taking a
  /// button does not also take `AppState`. `widgets/ui/app_snackbar.dart`
  /// asking `PhoneDock` how tall it is was how the shell, the global notifier
  /// and the task queue got behind every toast; the dock's dimensions are
  /// `AppDock` in `core/design_tokens.dart` now, for exactly this reason.
  const designSystem = {'widgets/ui', 'widgets/glass', 'widgets/drag'};

  /// The folder a file sits in, relative to `lib/`, as a `/`-joined path.
  String folderOf(String path) {
    final rel = p.relative(p.dirname(path), from: 'lib');
    return rel == '.' ? '<root>' : p.split(rel).join('/');
  }

  test('the grouped directories have nothing loose in their root', () {
    final loose = dartFiles
        .where((f) => grouped.contains(moduleOf(f)) && folderOf(f) == moduleOf(f))
        .toList();
    expect(
      loose,
      isEmpty,
      reason: 'these sit in a grouped directory\'s root:\n  ${loose.join('\n  ')}\n\n'
          'Put the file in the folder whose domain it belongs to, or add a '
          'folder and say in the commit what it is for. A shared widget used by '
          'exactly one screen is not shared — it belongs under that screen.',
    );
  });

  test('the design system imports only core, l10n and itself', () {
    final violations = <String>[];
    for (final edge in edges) {
      if (!designSystem.contains(folderOf(edge.from))) continue;
      final toFolder = folderOf(edge.to);
      if (designSystem.contains(toFolder)) continue;
      if (const {'core', 'l10n'}.contains(moduleOf(edge.to))) continue;
      violations.add("${edge.from}:${edge.line}  -> $toFolder   import '${edge.uri}'");
    }
    expect(
      violations,
      isEmpty,
      reason: 'the design system reached outside the foundation:\n'
          '  ${violations.join('\n  ')}\n\n'
          'Either the primitive is not one — move it to the feature folder that '
          'owns it — or the thing it needs belongs lower down. `TagAvatar` came '
          'out of `widgets/models/channel_avatar.dart` because the picker only '
          'ever needed the bare-string half.',
    );
  });

  test('every relative directive resolves to a file that exists', () {
    final missing = edges
        .where((e) => !File(e.to).existsSync())
        .map((e) => "${e.from}:${e.line}  '${e.uri}' -> ${e.to}")
        .toList();
    expect(missing, isEmpty, reason: 'dangling directive:\n  ${missing.join('\n  ')}');
  });
}
