part of 'markdown_editor.dart';

/// Which view of the text the pop-out shows. [split] exists only here: the
/// small editor has no room for it.
enum _LargeView { edit, split, preview }

/// The pop-out editor, `A1d`: one header, an unframed body held to a readable
/// measure, and a status footer.
///
/// It is its own layout rather than a [MarkdownEditor] set inside a titled
/// card. That nesting gave it two headers and a field outlined inside a card,
/// and carried over compromises the small editor makes for a 300px panel — none
/// of which a dialog this size needs.
///
/// The text is the caller's controller, so every keystroke is already written
/// back; there is nothing to cancel, and every way out means the same thing.
class _LargeEditor extends StatefulWidget {
  const _LargeEditor({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.isMarkdown,
    required this.onMarkdownChanged,
    required this.onChanged,
    required this.readOnly,
    required this.selectable,
    required this.initiallyPreview,
    required this.onPreviewChanged,
    required this.compact,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool isMarkdown;
  final ValueChanged<bool> onMarkdownChanged;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final bool selectable;
  final bool initiallyPreview;

  /// Reports edit/preview back to the small editor, so it reopens on the view
  /// the pop-out was left in. [_LargeView.split] reports as edit.
  final ValueChanged<bool> onPreviewChanged;

  /// The phone form: fullscreen, touch-sized, with the secondary controls in
  /// an overflow menu.
  final bool compact;

  @override
  State<_LargeEditor> createState() => _LargeEditorState();
}

class _LargeEditorState extends State<_LargeEditor> {
  /// Below this inner width the split view is not offered: two columns of
  /// under 360 each are worse than either view alone.
  static const double _splitMinWidth = 720;

  /// The measure. About 45 CJK or 80 Latin characters a line — the dialog is
  /// wide so the text can breathe, not so a line can run 1000px.
  static const double _measure = 720;
  static const double _splitMeasure = 560;

  late _LargeView _view;
  late bool _markdown;
  bool _copied = false;
  Timer? _copiedTimer;
  final FocusNode _focusNode = FocusNode();

  /// Carries the field's state — undo history, scroll offset — across the
  /// views, which put it at different places in the tree.
  final GlobalKey _fieldKey = GlobalKey();

  /// The text as of the last notification. The controller also notifies for
  /// every caret and selection move, and re-parsing the Markdown for those is
  /// wasted work — as is rebuilding at all while no preview is on screen: in
  /// the edit view only the footer follows the text, and it listens for itself.
  late String _lastText;

  void _onControllerChanged() {
    if (widget.controller.text == _lastText) return;
    _lastText = widget.controller.text;
    if (_view != _LargeView.edit) setState(() {});
  }

  @override
  void didUpdateWidget(_LargeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _lastText = widget.controller.text;
    }
  }

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    widget.controller.addListener(_onControllerChanged);
    _markdown = widget.isMarkdown;
    _view = (widget.readOnly || (widget.initiallyPreview && _markdown)) ? _LargeView.preview : _LargeView.edit;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _copiedTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _rendersMarkdown => _markdown || widget.readOnly;

  void _setView(_LargeView view) {
    final bool backToSource = _view == _LargeView.preview && view != _LargeView.preview;
    // A focused node carried under [ExcludeFocus] by its key keeps the focus
    // it came with, so it is let go by hand.
    if (view == _LargeView.preview) _focusNode.unfocus();
    setState(() => _view = view);
    // `autofocus` only speaks at first mount, and the field was mounted
    // (offstage) all along.
    if (backToSource && !widget.readOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
    widget.onPreviewChanged(view == _LargeView.preview);
  }

  void _setMarkdown(bool value) {
    setState(() {
      _markdown = value;
      if (!value) _view = _LargeView.edit;
    });
    _syncMarkdownHighlight(widget.controller, value);
    widget.onMarkdownChanged(value);
    if (!value) widget.onPreviewChanged(false);
  }

  void _togglePreview() {
    if (!_rendersMarkdown) return;
    _setView(_view == _LargeView.preview ? _LargeView.edit : _LargeView.preview);
  }

  // No snackbar: it would land under the dialog's barrier. The button itself
  // says so instead.
  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: widget.controller.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _close,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _close,
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true, shift: true): _togglePreview,
        const SingleActivator(LogicalKeyboardKey.keyP, control: true, shift: true): _togglePreview,
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool canSplit = !widget.compact && !widget.readOnly && constraints.maxWidth >= _splitMinWidth;
          // A window dragged narrower with the split open falls back to edit.
          final view = (_view == _LargeView.split && !canSplit) ? _LargeView.edit : _view;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, view, canSplit),
              Expanded(child: _buildBody(context, view)),
              _buildFooter(context),
            ],
          );
        },
      ),
    );
  }

  /// `A1d`: every segment at least 56 wide (touch-sized on a phone), all of
  /// them equal. A floor, not a fixed width: 「プレビュー」 does not fit in 56,
  /// and a label cut to 「プレ…」 is worse than a control a little wider.
  static const double _segmentWidth = 56;
  static const double _segmentWidthCompact = 64;

  Widget _buildViewToggle(AppLocalizations l10n, _LargeView view, bool canSplit) {
    final segments = [
      AppSegment(value: _LargeView.edit, label: widget.readOnly ? l10n.editorOriginal : l10n.edit),
      if (canSplit) AppSegment(value: _LargeView.split, label: l10n.editorSplitView),
      AppSegment(value: _LargeView.preview, label: l10n.preview),
    ];
    return ConstrainedBox(
      // Plus the track's 3px inset either side.
      constraints: BoxConstraints(
        minWidth: segments.length * (widget.compact ? _segmentWidthCompact : _segmentWidth) + 6,
      ),
      // With `expand`, the row's intrinsic width is its widest segment times
      // their number — equal segments, none narrower than its label.
      child: IntrinsicWidth(
        child: AppSegmentedControl<_LargeView>(
          segments: segments,
          value: view,
          onChanged: _setView,
          expand: true,
          compact: !widget.compact,
          // Raised for the small editor's reason: this picks a view of the same
          // text, and the accent stays free for the syntax inside it.
          style: AppSegmentStyle.raised,
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, _LargeView view, bool canSplit) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hairline = BorderSide(color: scheme.outlineVariant.withValues(alpha: AppAlpha.edge));
    final rule = SizedBox(height: 18, child: VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant));

    // [Expanded], not a [Flexible] beside a [Spacer]: those two split the
    // slack between them and the title gives its half back unused, which
    // leaves the controls short of the right edge.
    final title = Expanded(
      child: Row(
        children: [
          Flexible(
            child: Text(
              widget.label,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.readOnly) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                l10n.editorReadOnly,
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
          const SizedBox(width: 10),
        ],
      ),
    );

    final List<Widget> children;
    if (widget.compact) {
      children = [
        AppIconButton(icon: Icons.arrow_back, tooltip: l10n.back, onPressed: _close),
        const SizedBox(width: 4),
        title,
        if (_rendersMarkdown) _buildViewToggle(l10n, view, false),
        // The menu that held 「复制全文」 is closed by the time the copy lands,
        // so its button carries the confirmation.
        Builder(
          builder: (anchor) => AppIconButton(
            icon: _copied ? Icons.check : Icons.more_vert,
            tooltip: _copied ? l10n.editorCopied : l10n.more,
            selected: _copied,
            onPressed: () => showAppGlassMenuBelow(
              anchor,
              entries: [
                if (!widget.readOnly)
                  AppGlassMenuItem(
                    label: 'Markdown',
                    checked: _markdown,
                    onSelected: () => _setMarkdown(!_markdown),
                  ),
                AppGlassMenuItem(icon: Icons.content_copy, label: l10n.editorCopyAll, onSelected: _copyAll),
              ],
            ),
          ),
        ),
      ];
    } else {
      children = [
        title,
        // The toggle and its rule come and go together; everything to their
        // right stays where it was, so switching Markdown off moves nothing
        // the pointer is likely to be heading for.
        if (_rendersMarkdown) ...[
          _buildViewToggle(l10n, view, canSplit),
          const SizedBox(width: 10),
        ],
        if (!widget.readOnly) ...[
          if (_rendersMarkdown) ...[rule, const SizedBox(width: 10)],
          Text('Markdown', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(width: 6),
          AppSwitch(value: _markdown, onChanged: _setMarkdown),
          const SizedBox(width: 10),
        ],
        rule,
        const SizedBox(width: 6),
        AppIconButton(
          icon: _copied ? Icons.check : Icons.content_copy,
          tooltip: _copied ? l10n.editorCopied : l10n.editorCopyAll,
          selected: _copied,
          onPressed: _copyAll,
        ),
        // The pair of the `open_in_full` that opened this: the same editor,
        // made small again. An ✕ would read as throwing something away.
        AppIconButton(icon: Icons.close_fullscreen, tooltip: l10n.collapseEditor, onPressed: _close),
      ];
    }

    return Container(
      height: 52,
      padding: widget.compact ? const EdgeInsets.only(left: 4, right: 4) : const EdgeInsets.only(left: 20, right: 10),
      decoration: BoxDecoration(border: Border(bottom: hairline)),
      child: Row(children: children),
    );
  }

  Widget _buildBody(BuildContext context, _LargeView view) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final bool split = view == _LargeView.split;
    final double measure = split ? _splitMeasure : _measure;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view == _LargeView.preview)
          // Kept alive while the preview has the floor, so coming back to the
          // source finds its undo history and scroll offset where they were.
          // Out of the focus tree as well as out of sight — a field that kept
          // the keyboard here would take typing nobody can see.
          ExcludeFocus(
            child: Offstage(
              child: SizedBox(width: _measure, height: 200, child: _buildSource(context, view, _measure)),
            ),
          )
        else
          Expanded(child: _buildSource(context, view, measure, tag: split ? l10n.editorSourceText : null)),
        if (split) VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant.withValues(alpha: AppAlpha.edge)),
        if (view != _LargeView.edit)
          Expanded(child: _buildPreview(context, view, measure, tag: split ? l10n.preview : null)),
      ],
    );
  }

  /// Takes the view being drawn, not [_view]: a split that fell back to edit
  /// for lack of width is laid out as edit.
  EdgeInsets _textPadding(_LargeView view) {
    if (widget.compact) return const EdgeInsets.all(16);
    return view == _LargeView.split ? const EdgeInsets.all(28) : const EdgeInsets.symmetric(horizontal: 32, vertical: 28);
  }

  TextStyle? _textStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: widget.compact ? 15 : 14, height: 1.7);

  Widget _paneTag(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Positioned(
      top: 10,
      right: 14,
      child: IgnorePointer(
        child: Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, letterSpacing: 0.6),
        ),
      ),
    );
  }

  Widget _buildSource(BuildContext context, _LargeView view, double measure, {String? tag}) {
    final style = _textStyle(context);
    final field = TextField(
      key: _fieldKey,
      controller: widget.controller,
      focusNode: _focusNode,
      autofocus: !widget.readOnly,
      expands: true,
      maxLines: null,
      onChanged: widget.onChanged,
      readOnly: widget.readOnly,
      textAlignVertical: TextAlignVertical.top,
      inputFormatters: [SmartMarkdownFormatter(continueLists: _markdown)],
      decoration: InputDecoration(
        hintText: widget.hint,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: _textPadding(view),
      ),
      style: style,
      strutStyle: StrutStyle(fontSize: style?.fontSize, height: 1.7, forceStrutHeight: true),
    );

    // The margins either side of the measure belong to the field too: a click
    // there should land the caret, not fall through to nothing.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _focusNode.requestFocus,
      child: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: measure),
              child: CallbackShortcuts(
                bindings: {
                  // Not when read-only: `readOnly` stops the keyboard, not a
                  // write to the controller.
                  if (!widget.readOnly)
                    const SingleActivator(LogicalKeyboardKey.tab): () =>
                        _insertMarkdownTab(widget.controller, widget.onChanged),
                },
                child: field,
              ),
            ),
          ),
          if (tag != null) _paneTag(context, tag),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context, _LargeView view, double measure, {String? tag}) {
    final scheme = Theme.of(context).colorScheme;
    final style = _textStyle(context);
    Widget text = _rendersMarkdown
        ? MarkdownBody(
            data: widget.controller.text,
            selectable: false, // Handled by SelectionArea
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(p: style),
          )
        : Text(widget.controller.text, style: style);
    if (widget.selectable) text = SelectionArea(child: text);

    return ColoredBox(
      color: scheme.surfaceContainerLowest,
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: measure),
                  child: Padding(
                    padding: _textPadding(view),
                    child: Align(alignment: Alignment.topLeft, child: text),
                  ),
                ),
              ),
            ),
          ),
          if (tag != null) _paneTag(context, tag),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.labelSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    return Container(
      height: widget.compact ? 40 : 44,
      padding: widget.compact ? const EdgeInsets.only(left: 16, right: 8) : const EdgeInsets.only(left: 20, right: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: AppAlpha.edge))),
      ),
      child: Row(
        children: [
          // The count is the only part of the chrome that follows the text.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.controller,
            builder: (context, value, _) => Text(
              l10n.editorCount(value.text.characters.length, '\n'.allMatches(value.text).length + 1),
              style: small?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          // The hint takes the slack itself, right-aligned — beside a [Spacer]
          // it would hand its share back and strand the button mid-row.
          if (!widget.compact && !widget.readOnly) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.editorKeyHint,
                style: small?.copyWith(color: scheme.outline),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
          ] else
            const Spacer(),
          AppButton(
            label: widget.readOnly ? l10n.close : l10n.editorDone,
            onPressed: _close,
            size: AppButtonSize.compact,
          ),
        ],
      ),
    );
  }
}
