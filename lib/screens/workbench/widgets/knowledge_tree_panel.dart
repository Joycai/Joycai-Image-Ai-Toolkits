import 'package:flutter/material.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/knowledge_base_service.dart';
import '../../../services/prompt_optimizer_agent.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/app_search_field.dart';
import '../../../widgets/app_section_label.dart';

/// The library-edit mode's left column — `A2 10h`.
///
/// It replaces the reference-image strip while that mode is on, which is the
/// design's call and a defensible one: an agent rearranging the knowledge base
/// is not looking at pictures, and what the user needs beside the conversation
/// is which documents exist and which ones are about to change.
///
/// Read-only. Everything actionable about a staged edit lives on its card in
/// the transcript and in the right panel's pending list; this is the map, and
/// a third place to press 写入 would be a third place to get it wrong.
class KnowledgeTreePanel extends StatefulWidget {
  /// The configured knowledge-base root, or null when there is none.
  final String? kbPath;

  /// Edits the agent has staged and the user has not answered. Drives the
  /// per-row badges and the footer count.
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

  /// Folders the user has opened. Seeded once, on the first successful scan,
  /// with the folders on the way to a staged edit — the rest start closed. A
  /// fully expanded 33-document base is a scroll view of forty rows in a 236px
  /// column, and the folders worth being open are exactly the ones with
  /// something waiting inside them.
  final Set<String> _expanded = {};
  bool _seededExpansion = false;

  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(KnowledgeTreePanel old) {
    super.didUpdateWidget(old);
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
    // would resolve to the working directory and then fail — which now
    // reports a *read failure*, a different and wrong thing to say.
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
    final entries = _entries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionLabel(
          l10n.knowledgeBase,
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
          trailing: entries == null
              ? null
              : Text(
                  // Counted after the merge, so the number and the rows agree
                  // — a create the tree shows but the count leaves out reads
                  // as a rendering fault.
                  l10n.optKbDocCount(
                    _withPendingCreates(entries).where((e) => !e.isDir).length,
                  ),
                  style: textTheme.labelMedium?.mono.copyWith(color: colorScheme.outline),
                ),
        ),
        if (entries != null && entries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SizedBox(
              height: AppSize.compact,
              child: AppSearchField(
                controller: _searchCtrl,
                hint: l10n.optKbSearchDocs,
                compact: true,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ),
        Expanded(child: _buildBody(entries, l10n, colorScheme, textTheme)),
        if (widget.pendingKbEdits.isNotEmpty)
          _buildFooter(l10n, colorScheme, textTheme),
      ],
    );
  }

  Widget _buildBody(
    List<KbTreeEntry>? entries,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    if (entries == null) {
      return Center(
        child: _scanning
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : AppEmptyState(
                compact: true,
                icon: _scanFailed
                    ? Icons.folder_off_outlined
                    : Icons.menu_book_outlined,
                label: _scanFailed
                    ? l10n.optKbTreeScanFailed
                    : l10n.optKbNotConfigured,
              ),
      );
    }

    final rows = _visibleRows(_withPendingCreates(entries));
    if (rows.isEmpty) {
      return Center(
        child: AppEmptyState(
          compact: true,
          icon: _query.isEmpty ? Icons.menu_book_outlined : Icons.search_off,
          label: _query.isEmpty ? l10n.optKbTreeEmpty : l10n.optKbTreeNoMatch,
        ),
      );
    }

    final edits = _editsByPath;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: rows.length,
      itemBuilder: (context, index) =>
          _buildRow(rows[index], edits[rows[index].relPath], l10n, colorScheme, textTheme),
    );
  }

  Widget _buildRow(
    KbTreeEntry entry,
    OptimizerChatEntry? edit,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final semantic = context.semantic;
    final isCreate = edit != null && edit.oldContent == null;
    final open = _expanded.contains(entry.relPath);

    // The tint is the badge's own colour at the wash alpha, so a row and its
    // label say the same thing twice rather than two different things.
    final Color? tint = edit == null
        ? null
        : (isCreate ? semantic.success : semantic.warning).withValues(alpha: AppAlpha.tint);

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      onTap: entry.isDir
          ? () => setState(() {
                if (!_expanded.remove(entry.relPath)) _expanded.add(entry.relPath);
              })
          : () => _openFile(entry.relPath),
      child: Container(
        height: _rowHeight,
        // The indent is the depth, and files sit one step further in than the
        // folder glyph above them so a folder's contents read as its contents.
        padding: EdgeInsets.only(left: 6 + entry.depth * _indentStep + (entry.isDir ? 0 : 16), right: 6),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Row(
          children: [
            if (entry.isDir) ...[
              Icon(
                open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                size: 14,
                color: colorScheme.outline,
              ),
              const SizedBox(width: 2),
              Icon(Icons.folder_outlined, size: 13, color: colorScheme.onSurfaceVariant),
            ] else
              Icon(Icons.description_outlined, size: 13, color: colorScheme.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // Folders in the sans face at a heavier weight, files in the
                // mono one: the same split the transcript's step rows use, and
                // what lets a name be recognised as a filename at 11px.
                style: entry.isDir
                    ? textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      )
                    : textTheme.labelSmall?.mono.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            if (edit != null) ...[
              const SizedBox(width: 6),
              Text(
                isCreate ? l10n.optKbTreeAdded : l10n.optKbTreeChanged,
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isCreate ? semantic.success : semantic.warning,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final semantic = context.semantic;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 12),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: semantic.warning, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              l10n.optKbTreePending(widget.pendingKbEdits.length),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(color: semantic.warning),
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

  /// `10h` draws every row of the tree at 24px, folders and files alike.
  static const double _rowHeight = 24;

  /// One nesting level, in pixels.
  static const double _indentStep = 10;
}
