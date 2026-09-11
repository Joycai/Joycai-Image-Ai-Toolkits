import 'package:flutter/material.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/file_utils.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/knowledge_base_service.dart';
import '../../../services/prompt_optimizer_agent.dart';
import '../../../widgets/app_search_field.dart';
import 'optimizer_context_card.dart';

/// Row, field and inset sizes for the three places this column is drawn:
/// inline on desktop (`A3b 1a`), the tablet drawer (`1c`) and the phone
/// drawer (`1d`). The drawers are touched rather than clicked, so their rows
/// grow and their header becomes a title rather than a caption.
typedef _TreeDensity = ({
  double row,
  double field,
  double rowGap,
  double headerGap,
  EdgeInsets header,
  EdgeInsets footer,
  bool titled,
  bool large,
});

_TreeDensity _densityOf(BuildContext context) {
  if (Responsive.isMobile(context)) {
    return (
      row: 40.0,
      field: 40.0,
      rowGap: 8.0,
      headerGap: 8.0,
      header: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      footer: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      titled: true,
      large: true,
    );
  }
  if (Responsive.isTablet(context)) {
    return (
      row: 36.0,
      field: 36.0,
      rowGap: 6.0,
      headerGap: 8.0,
      header: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      footer: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      titled: true,
      large: false,
    );
  }
  return (
    row: 30.0,
    // The pointer control height, two over the row: the search is an input
    // beside the column's other 32px controls, not a tree row.
    field: AppSize.control,
    rowGap: 6.0,
    headerGap: 6.0,
    header: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    footer: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    titled: false,
    large: false,
  );
}

/// The library-edit mode's left column — `A3b 1a` / `1c` / `1d`.
///
/// It replaces the reference-image strip while that mode is on: an agent
/// rearranging the knowledge base is not looking at pictures, and what the
/// user needs beside the conversation is which documents exist and which ones
/// are about to change.
///
/// Read-only. Everything actionable about a staged edit lives on its card in
/// the transcript and in the right panel's pending list; this is the map, and
/// a third place to press Write would be a third place to get it wrong.
class KnowledgeTreePanel extends StatefulWidget {
  /// The configured knowledge-base root, or null when there is none.
  final String? kbPath;

  /// Edits the agent has staged and the user has not answered. Drives the
  /// per-row badges, which folders start open, and the footer count.
  final List<OptimizerChatEntry> pendingKbEdits;

  const KnowledgeTreePanel({
    super.key,
    required this.kbPath,
    this.pendingKbEdits = const [],
  });

  @override
  State<KnowledgeTreePanel> createState() => _KnowledgeTreePanelState();
}

class _KnowledgeTreePanelState extends State<KnowledgeTreePanel> {
  final TextEditingController _searchCtrl = TextEditingController();

  List<KbTreeEntry>? _entries;
  bool _scanning = false;

  /// Set when the walk itself failed, so the empty view can say *that*
  /// instead of "no knowledge base is configured" — which is a different
  /// problem, and sends the user off to re-pick a folder that is already set.
  bool _scanFailed = false;

  /// Folders the user has opened. Seeded on the first successful scan with the
  /// folders on the way to a staged edit, and grown as new edits are staged —
  /// the rest start closed. A fully expanded base is a scroll view of forty
  /// rows in a 220px column, and the folders worth being open are exactly the
  /// ones with something waiting inside them.
  final Set<String> _expanded = {};
  bool _seededExpansion = false;

  String _query = '';

  /// Where a root row starts, one nesting level, and the chevron's box — which
  /// every row reserves, open, closed or a file, so names never shift sideways
  /// as folders toggle (`A3b` 「根 8 · 一级 24 · 二级 40」).
  static const double _rootIndent = 8;
  static const double _indentStep = 16;
  static const double _chevronBox = 14;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(KnowledgeTreePanel old) {
    super.didUpdateWidget(old);
    // An edit staged after the first scan opens the path to it too. Only new
    // ones: a folder the user has since closed stays closed for edits it
    // already held.
    if (_seededExpansion) {
      final before = {for (final e in old.pendingKbEdits) e.targetPath};
      for (final e in widget.pendingKbEdits) {
        if (!before.contains(e.targetPath)) _expanded.addAll(_ancestorsOf(e.targetPath ?? ''));
      }
    }
    // A different base is a different tree. A changed pending list is not —
    // staging an edit does not touch disk, so re-walking the folder there
    // would be synchronous IO for a tree that cannot have changed.
    // …except when an edit is *answered*, which is when a create appears on
    // disk. Cheap to detect: the pending count only ever falls that way.
    if (widget.kbPath != old.kbPath ||
        old.pendingKbEdits.length > widget.pendingKbEdits.length) {
      _load();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Walks the folder off the build path — [KnowledgeBaseService.walkTree] is
  /// synchronous file IO, and a large base walked during build drops frames.
  Future<void> _load() async {
    final root = widget.kbPath;
    // Blank counts as unset, not as a folder to go looking for: an empty
    // setting string is how "no knowledge base" is stored, and walking it
    // would resolve to the working directory and then fail — which reports a
    // *read failure*, a different and wrong thing to say.
    if (root == null || root.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _entries = null;
          _scanFailed = false;
        });
      }
      return;
    }
    setState(() {
      _scanning = true;
      _scanFailed = false;
    });
    try {
      final entries = await Future(() => KnowledgeBaseService().walkTree(root));
      if (!mounted) return;
      setState(() {
        _entries = entries;
        if (!_seededExpansion) {
          _seededExpansion = true;
          for (final edit in widget.pendingKbEdits) {
            _expanded.addAll(_ancestorsOf(edit.targetPath ?? ''));
          }
        }
      });
    } catch (_) {
      // A folder that vanished mid-walk, or one the app may no longer read.
      // The right panel's knowledge card reports the cause; this column only
      // has room to say that the tree is not what failed to be configured.
      if (mounted) {
        setState(() {
          _entries = null;
          _scanFailed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// Every folder above [relPath], outermost first. Paths from
  /// [KnowledgeBaseService.listFiles] always use `/`, whatever the host.
  static Iterable<String> _ancestorsOf(String relPath) sync* {
    for (int i = relPath.indexOf('/'); i >= 0; i = relPath.indexOf('/', i + 1)) {
      yield relPath.substring(0, i);
    }
  }

  /// Staged edits by target path, so a row can find its own in one lookup
  /// rather than scanning the list per row.
  Map<String, OptimizerChatEntry> get _editsByPath => {
        for (final e in widget.pendingKbEdits)
          if (e.targetPath != null) e.targetPath!: e,
      };

  /// The scanned tree plus the files the agent has proposed creating.
  ///
  /// A create does not exist on disk, so the walk cannot see it — and a
  /// pending create is exactly the row the badges exist for. Without this the
  /// tree quietly omits half of what is about to change, which is worse than
  /// not drawing badges at all. Missing parent folders come along too: an edit
  /// can propose `04_模板/04b_…md` in a folder that is not there yet.
  List<KbTreeEntry> _withPendingCreates(List<KbTreeEntry> scanned) {
    final creates = <String>[
      for (final e in widget.pendingKbEdits)
        if (e.oldContent == null && (e.targetPath ?? '').isNotEmpty) e.targetPath!,
    ]..sort();
    if (creates.isEmpty) return scanned;

    final rows = <KbTreeEntry>[...scanned];
    for (final path in creates) {
      // Outermost first, so each insert finds its parent already present.
      for (final dir in _ancestorsOf(path)) {
        _insertRow(rows, dir, isDir: true);
      }
      _insertRow(rows, path, isDir: false);
    }
    return rows;
  }

  /// Splices one row into the flat tree where the walk would have put it:
  /// inside its parent's block, before the first sibling that sorts after it.
  static void _insertRow(List<KbTreeEntry> rows, String relPath, {required bool isDir}) {
    if (rows.any((r) => r.relPath == relPath)) return;

    final cut = relPath.lastIndexOf('/');
    final parent = cut < 0 ? '' : relPath.substring(0, cut);
    final depth = cut < 0 ? 0 : '/'.allMatches(relPath).length;

    int start = 0;
    int end = rows.length;
    if (parent.isNotEmpty) {
      final parentIndex = rows.indexWhere((r) => r.relPath == parent);
      // A parent that is not there means an ancestor insert was skipped, which
      // cannot happen from [_withPendingCreates]; appending is still a row in
      // the right order relative to nothing rather than a dropped one.
      if (parentIndex >= 0) {
        start = parentIndex + 1;
        end = start;
        while (end < rows.length && rows[end].relPath.startsWith('$parent/')) {
          end++;
        }
      }
    }

    int at = end;
    for (int i = start; i < end; i++) {
      // Only direct siblings decide the position — a deeper row belongs to
      // whichever sibling precedes it, and stepping over it keeps that
      // subtree whole.
      if (rows[i].depth != depth) continue;
      if (rows[i].relPath.compareTo(relPath) > 0) {
        at = i;
        break;
      }
    }

    rows.insert(
      at,
      KbTreeEntry(
        relPath: relPath,
        name: cut < 0 ? relPath : relPath.substring(cut + 1),
        isDir: isDir,
        depth: depth,
      ),
    );
  }

  /// The rows actually drawn.
  ///
  /// While searching, folders are not collapsible at all: a hit three levels
  /// down is useless if the search also has to be told to open the three
  /// folders above it. Every ancestor of a match comes along.
  List<KbTreeEntry> _visibleRows(List<KbTreeEntry> all) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return [
        for (final e in all)
          if (_ancestorsOf(e.relPath).every(_expanded.contains)) e,
      ];
    }

    final keep = <String>{};
    for (final e in all) {
      if (e.isDir) continue;
      if (!e.relPath.toLowerCase().contains(query)) continue;
      keep.add(e.relPath);
      keep.addAll(_ancestorsOf(e.relPath));
    }
    return [
      for (final e in all)
        if (keep.contains(e.relPath)) e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final density = _densityOf(context);
    final entries = _entries;
    // Merged once per build, and counted after the merge, so the header
    // number and the rows agree — a create the tree shows but the count leaves
    // out reads as a rendering fault.
    final merged = entries == null ? null : _withPendingCreates(entries);

    final Widget? count = merged == null
        ? null
        : Text(
            l10n.optKbDocCount(merged.where((e) => !e.isDir).length),
            style: textTheme.labelSmall?.mono.copyWith(
              fontWeight: FontWeight.w400,
              color: colorScheme.onSurfaceVariant,
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: density.header,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (density.titled)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.knowledgeBase,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: AppSpace.s6),
                      count,
                    ],
                  ],
                )
              else
                OptimizerPanelCaption(l10n.knowledgeBase, trailing: count),
              if (entries != null && entries.isNotEmpty) ...[
                SizedBox(height: density.headerGap),
                // The panel ground under the theme's hairline box: the field
                // sits on the column and has to read as a well in it.
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: AppSearchField(
                    controller: _searchCtrl,
                    hint: l10n.optKbSearchDocs,
                    compact: !density.large,
                    height: density.field,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(child: _buildBody(merged, density, l10n, colorScheme, textTheme)),
        if (widget.pendingKbEdits.isNotEmpty) _buildFooter(density, l10n, colorScheme, textTheme),
      ],
    );
  }

  Widget _buildBody(
    List<KbTreeEntry>? all,
    _TreeDensity density,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    if (all == null) {
      if (_scanning) {
        return const Center(
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
      return _scanFailed
          ? _stateCard(
              colorScheme,
              textTheme,
              icon: Icons.error_outline,
              iconColor: colorScheme.error,
              title: l10n.optKbTreeScanFailed,
            )
          : _stateCard(
              colorScheme,
              textTheme,
              icon: Icons.folder_open_outlined,
              iconColor: colorScheme.outline,
              title: l10n.optKbNotConfiguredShort,
              body: l10n.optKbNotConfigured,
            );
    }

    final rows = _visibleRows(all);
    if (rows.isEmpty) {
      return _stateCard(
        colorScheme,
        textTheme,
        icon: _query.isEmpty ? Icons.folder_off_outlined : Icons.search_off,
        iconColor: colorScheme.outline,
        title: _query.isEmpty ? l10n.optKbTreeEmpty : l10n.optKbTreeNoMatch,
      );
    }

    final edits = _editsByPath;
    // The folders on the way to something waiting, drawn in the deep ink so
    // the path reads down to the badge at its end.
    final onPendingPath = <String>{
      for (final e in widget.pendingKbEdits) ..._ancestorsOf(e.targetPath ?? ''),
    };
    return ListView.builder(
      padding: const EdgeInsets.only(top: 2, bottom: AppSpace.s6),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final entry = rows[index];
        return _buildRow(
          entry,
          edits[entry.relPath],
          onPendingPath.contains(entry.relPath),
          density,
          l10n,
          colorScheme,
          textTheme,
        );
      },
    );
  }

  /// `A3b 1d`'s empty / no-match / unreadable / not-configured cards: the
  /// panel ground, a hairline, r10, a 28px glyph over one or two lines.
  Widget _stateCard(
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required IconData icon,
    required Color iconColor,
    String? title,
    String? body,
  }) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpace.s16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: iconColor),
              const SizedBox(height: AppSpace.s4),
              if (title != null)
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              if (body != null)
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: AppType.proseHeight,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(
    KbTreeEntry entry,
    OptimizerChatEntry? edit,
    bool onPendingPath,
    _TreeDensity density,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final semantic = context.semantic;
    final changed = edit != null;
    final isCreate = edit != null && edit.oldContent == null;
    final open = _expanded.contains(entry.relPath);

    // Files in the secondary ink; a changed file in the colour of its badge,
    // so the glyph and the label say the same thing twice rather than two
    // different things.
    final IconData icon;
    final Color iconColor;
    if (entry.isDir) {
      icon = open ? Icons.folder_open_outlined : Icons.folder_outlined;
      iconColor = colorScheme.onSurfaceVariant;
    } else if (!changed) {
      icon = Icons.description_outlined;
      iconColor = colorScheme.onSurfaceVariant;
    } else if (isCreate) {
      icon = Icons.note_add_outlined;
      iconColor = semantic.success;
    } else {
      icon = Icons.edit_document;
      iconColor = semantic.info;
    }
    final accented = changed || onPendingPath;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
      child: Material(
        // The pending change itself wears the wash; the folders above it only
        // the deep ink.
        color: changed ? colorScheme.accentTint : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: entry.isDir
              ? () => setState(() {
                    if (!_expanded.remove(entry.relPath)) _expanded.add(entry.relPath);
                  })
              : () => _openFile(entry.relPath),
          child: SizedBox(
            height: density.row,
            child: Padding(
              padding: EdgeInsets.only(left: _rootIndent + entry.depth * _indentStep, right: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: _chevronBox,
                    child: entry.isDir
                        ? Icon(
                            open ? Icons.expand_more : Icons.chevron_right,
                            size: _chevronBox,
                            color: colorScheme.outline,
                          )
                        : null,
                  ),
                  SizedBox(width: density.rowGap),
                  Icon(icon, size: AppSize.iconMd, color: iconColor),
                  SizedBox(width: density.rowGap),
                  Expanded(
                    child: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (density.large ? textTheme.bodyMedium : textTheme.bodySmall)?.copyWith(
                        color: accented ? colorScheme.onAccentTint : colorScheme.onSurface,
                        fontWeight: accented || entry.isDir ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (changed) ...[
                    const SizedBox(width: AppSpace.s6),
                    OptimizerTagBadge(
                      mono: true,
                      label: isCreate ? l10n.optKbTreeAdded : l10n.optKbTreeChanged,
                      background: isCreate ? semantic.successContainer : semantic.infoContainer,
                      foreground: isCreate ? semantic.onSuccessContainer : semantic.onInfoContainer,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The count of what is waiting on the user, on the accent wash under a
  /// hairline — the column's one reminder that the tree is not the whole story.
  Widget _buildFooter(
    _TreeDensity density,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Container(
      width: double.infinity,
      padding: density.footer,
      decoration: BoxDecoration(
        color: colorScheme.accentTint,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.pending_actions, size: AppSize.iconMd, color: colorScheme.primary),
          const SizedBox(width: AppSpace.s6),
          Flexible(
            child: Text(
              l10n.optKbTreePending(widget.pendingKbEdits.length),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (density.large ? textTheme.bodyMedium : textTheme.bodySmall)?.copyWith(
                fontWeight: FontWeight.w500,
                color: colorScheme.onAccentTint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Hands the document to whatever the OS opens `.md` with.
  ///
  /// The app has no markdown viewer of its own, and building one so the tree
  /// has somewhere to go would be a second editor beside the one the user
  /// already keeps their knowledge base in.
  Future<void> _openFile(String relPath) async {
    final root = widget.kbPath;
    if (root == null) return;
    try {
      await FileUtils.openPath(KnowledgeBaseService().resolvePath(root, relPath));
    } on KbPathException {
      // The tree is built from listFiles, so this cannot normally happen —
      // and a path the service refuses to resolve is one this panel has no
      // business opening anyway.
    }
  }
}
