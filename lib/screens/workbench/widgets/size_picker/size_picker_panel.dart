import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/app_semantic_colors.dart';
import '../../../../core/app_theme.dart';
import '../../../../core/design_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/spec_rate.dart';
import '../../../../services/billing/spec_billing.dart';
import '../../../../services/llm/image_size_rules.dart';
import '../../../../services/llm/image_size_vocabulary.dart';
import '../../../../services/llm/model_capabilities.dart';
import '../../../../widgets/ui/app_button.dart';
import '../../../../widgets/ui/app_icon_button.dart';
import '../../../../widgets/ui/app_segmented_control.dart';
import 'size_picker_parts.dart';
import 'size_picker_texts.dart';

/// Geometry that changes with the host (`A1c · 30h`): desktop popover,
/// tablet drawer popover, phone inline section.
class SizePickerDensity {
  const SizePickerDensity({required this.control, required this.preview, this.showUnits = true});

  /// Desktop: 32-high controls, a 104 preview.
  static const desktop = SizePickerDensity(control: AppSize.control, preview: 104);

  /// Tablet drawer: controls grow to 40, the preview shrinks to 84, and the
  /// `px` label gives its room to the width.
  static const tablet = SizePickerDensity(control: AppSize.large, preview: 84, showUnits: false);

  /// Phone sheet: 44 touch targets, a 76 preview.
  static const phone = SizePickerDensity(control: AppSize.touch, preview: 76, showUnits: false);

  final double control;
  final double preview;
  final bool showUnits;
}

/// The size picker's content (`A1c · 30b`): the sentinel row, the ratio axis,
/// the tier axis with the long edge, the preview and its one-line summary,
/// width × height for fine work, and the rules in one line.
///
/// Changes apply as they are made ([onChanged], `即时生效`) whenever the size
/// is legal and nothing is mid-typing; an illegal size is never written, and
/// Esc puts back the value the picker opened on.
class SizePickerPanel extends StatefulWidget {
  const SizePickerPanel({
    super.key,
    required this.spec,
    required this.value,
    required this.modelName,
    required this.onChanged,
    required this.onClose,
    this.rates,
    this.density = SizePickerDensity.desktop,
    this.showHeader = true,
  });

  /// A `customSize` spec: it declares both [ParamSpec.sizeRules] and
  /// [ParamSpec.sizeVocabulary].
  final ParamSpec spec;
  final String value;
  final String modelName;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  /// The model's spec-billing rate table, or null — then no billing tier is
  /// named anywhere (`30d`: no placeholder, no "unknown").
  final List<SpecRate>? rates;
  final SizePickerDensity density;

  /// Off on the phone, where the field above is the header (`30h`).
  final bool showHeader;

  @override
  State<SizePickerPanel> createState() => _SizePickerPanelState();
}

enum _Field { long, width, height, ratio }

class _SizePickerPanelState extends State<SizePickerPanel> {
  /// The recommendation table's open state lives for the session, not on
  /// disk (`30b`: 「展开状态记在会话里，不持久化」).
  static bool _tableOpen = false;

  late final String _opening = widget.value;
  late String _written = widget.value;

  /// The value the picker currently stands on — a sentinel, a keyword or
  /// `WxH` — whether or not it is legal.
  late String _value;

  late AspectRatioSpec _ratio;

  /// The chip label [_ratio] came from, or null when it is custom.
  String? _ratioChip;

  /// How a custom ratio reads — typed (`21:9`) or derived (`2.50:1`).
  String? _customRatioLabel;
  bool _ratioDerived = false;
  bool _editingRatio = false;
  bool _ratioParseError = false;

  late int _w;
  late int _h;
  bool _linked = true;
  _Field? _typing;

  final _longCtrl = TextEditingController();
  final _wCtrl = TextEditingController();
  final _hCtrl = TextEditingController();
  final _ratioCtrl = TextEditingController();
  final _longFocus = FocusNode();
  final _wFocus = FocusNode();
  final _hFocus = FocusNode();
  final _ratioFocus = FocusNode();

  /// The last correction, worded, and which boxes it touched.
  String? _notice;
  IconData _noticeIcon = Icons.straighten;
  Set<_Field> _flash = const {};
  Timer? _flashTimer;

  ImageSizeRules get _rules => widget.spec.sizeRules!;
  ImageSizeVocabulary get _vocab => widget.spec.sizeVocabulary!;

  String? get _sentinel =>
      widget.spec.options.map((o) => o.value).where((v) => v == 'auto' || v == 'not_set').firstOrNull;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
    final parsed = SizeValue.parse(widget.value, sentinel: _sentinel, tiers: _vocab.tiers);
    switch (parsed) {
      case SizeDimsValue(:final width, :final height):
        _w = width;
        _h = height;
        _adoptRatioOf(width, height);
      case SizeTierValue(:final tier):
        final sq = keywordSquare(tier) ?? (width: 1024, height: 1024);
        _w = sq.width;
        _h = sq.height;
        _ratio = const AspectRatioSpec(1, false);
        _ratioChip = _vocab.ratios.contains('1:1') ? '1:1' : null;
      case SizeSentinelValue():
        final (w, h) = tierSize(const AspectRatioSpec(1, false), _vocab.tiers.first, _rules, _vocab);
        _w = w;
        _h = h;
        _ratio = const AspectRatioSpec(1, false);
        _ratioChip = _vocab.ratios.contains('1:1') ? '1:1' : null;
    }
    _syncControllers();
    for (final (node, field) in [
      (_longFocus, _Field.long),
      (_wFocus, _Field.width),
      (_hFocus, _Field.height),
      (_ratioFocus, _Field.ratio),
    ]) {
      node.addListener(() {
        if (!node.hasFocus && (_typing == field || field == _Field.ratio)) _settle(field);
      });
    }
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    for (final c in [_longCtrl, _wCtrl, _hCtrl, _ratioCtrl]) {
      c.dispose();
    }
    for (final f in [_longFocus, _wFocus, _hFocus, _ratioFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  // --- State ---------------------------------------------------------------

  /// Takes the ratio from a size. A size near a chip adopts the chip's exact
  /// ratio, so the tier axis finds upstream's cell again (2688×1536 is the
  /// 16:9 cell at 2K although it is 1.75).
  void _adoptRatioOf(int w, int h) {
    _ratio = ratioOf(w, h);
    _ratioChip = _chipFor(_ratio);
    if (_ratioChip != null) _ratio = parseAspectRatio(_ratioChip!)!;
    _customRatioLabel = _ratioChip == null ? ratioLabel(w, h) : null;
    _ratioDerived = _ratioChip == null;
  }

  String? _chipFor(AspectRatioSpec r) => nearestChip(r, _vocab.ratios);

  void _syncControllers({Set<_Field> except = const {}}) {
    if (!except.contains(_Field.long)) _longCtrl.text = '${math.max(_w, _h)}';
    if (!except.contains(_Field.width)) _wCtrl.text = '$_w';
    if (!except.contains(_Field.height)) _hCtrl.text = '$_h';
  }

  bool get _isSentinel => _value == _sentinel;

  /// A *chosen* ratio (a chip, or one typed) that no size can satisfy
  /// (`30e` 无解). A ratio derived from typed edges is not this: those edges
  /// are the thing to fix (`30f` 「改成 3200 × 400」).
  bool get _ratioImpossible => !_ratioDerived && _ratio.longOverShort > _rules.maxRatio + 1e-9;

  /// Legal: a sentinel or keyword always is; a size must pass every rule.
  bool get _legal {
    if (_isSentinel || _vocab.tiers.contains(_value)) return true;
    return !_ratioImpossible && _rules.passes(_w, _h);
  }

  String? get _currentTier {
    if (_vocab.tiers.contains(_value)) return _value;
    if (_isSentinel) return null;
    return tierOfSize(_w, _h, _ratio, _rules, _vocab);
  }

  void _write() {
    if (_typing != null || !_legal) return;
    if (_value == _written) return;
    _written = _value;
    widget.onChanged(_value);
  }

  void _setDims(int w, int h, {Set<_Field> flash = const {}, String? notice, IconData? noticeIcon}) {
    setState(() {
      _w = w;
      _h = h;
      _value = '${w}x$h';
      _notice = notice;
      if (noticeIcon != null) _noticeIcon = noticeIcon;
      _syncControllers();
      _flashFields(flash);
    });
    _write();
  }

  void _flashFields(Set<_Field> fields) {
    _flashTimer?.cancel();
    _flash = fields;
    if (fields.isEmpty) return;
    _flashTimer = Timer(const Duration(milliseconds: 600) + AppMotion.state, () {
      if (mounted) setState(() => _flash = const {});
    });
  }

  /// A click on a chip, tier or the sentinel replaces a half-typed edge. A
  /// click does not take focus from the box, so without this the edge would
  /// stay "typing" and hold back every write until the box was left.
  void _dropTyping() {
    if (_typing == null) return;
    _typing = null;
    _syncControllers();
  }

  // S1
  void _chooseSentinel() {
    final s = _sentinel;
    if (s == null) return;
    setState(() {
      _dropTyping();
      _value = s;
      _notice = null;
    });
    _write();
  }

  // S2 — a new ratio keeps the tier the size is on, else the long edge.
  void _chooseRatio(AspectRatioSpec r, {String? chip, String? customLabel}) {
    final tier = _currentTier;
    setState(() {
      _dropTyping();
      _ratio = r;
      _ratioChip = chip;
      _customRatioLabel = customLabel;
      _ratioDerived = false;
      _editingRatio = false;
      _ratioParseError = false;
    });
    if (_ratioImpossible) {
      // `30e` 无解: the shape is drawn straight, nothing is written.
      final long = math.max(_w, _h);
      final short = math.max(_rules.edgeStep, (long / r.longOverShort).round());
      setState(() {
        _w = r.portrait ? short : long;
        _h = r.portrait ? long : short;
        _value = '${_w}x$_h';
        _syncControllers();
      });
      return;
    }
    if (tier != null) {
      _chooseTier(tier);
      return;
    }
    _solveFromLong(math.max(_w, _h));
  }

  // S3
  void _chooseTier(String tier) {
    final (w, h) = tierSize(_ratio, tier, _rules, _vocab);
    final value = tierValue(_ratio, tier, _rules, _vocab);
    setState(() {
      _typing = null;
      _w = w;
      _h = h;
      _value = value;
      _notice = null;
      _syncControllers();
    });
    _write();
  }

  // S4 — the long edge, solved at the current ratio; a correction shows.
  void _solveFromLong(int typed) {
    final (w, h) = _rules.sizeFor(_ratio, typed);
    final got = math.max(w, h);
    final snapped = _rules.snapEdge(typed);
    final l10n = AppLocalizations.of(context)!;
    String? notice;
    IconData icon = Icons.straighten;
    if (got != snapped) {
      final short = (typed / _ratio.longOverShort).round();
      final mp = megapixels(typed * short);
      final label = _ratioChip ?? _customRatioLabel ?? ratioLabel(w, h);
      if (got < snapped) {
        icon = Icons.south_west;
        notice = l10n.imageSizeClampedDown('$typed', label, mp, megapixels(_rules.maxPixels), _rules.edgeStep, '$got');
      } else {
        icon = Icons.north_east;
        notice = l10n.imageSizeClampedUp('$typed', label, mp, megapixels(_rules.minPixels), _rules.edgeStep, '$got');
      }
    } else if (got != typed) {
      notice = l10n.imageSizeSnapped(_rules.edgeStep, '$typed', '$got');
    }
    _setDims(w, h, flash: got != typed ? {_Field.long} : const {}, notice: notice, noticeIcon: icon);
  }

  // S5 — while typing, only the other side follows (with the lock on).
  void _typed(_Field field, String text) {
    setState(() => _typing = field);
    if (!_linked || field == _Field.long) return;
    final n = int.tryParse(text);
    if (n == null || n <= 0) return;
    final wIsLong = !_ratio.portrait;
    final other = switch (field) {
      _Field.width => wIsLong ? n / _ratio.longOverShort : n * _ratio.longOverShort,
      _ => wIsLong ? n * _ratio.longOverShort : n / _ratio.longOverShort,
    }.round();
    if (field == _Field.width) {
      _hCtrl.text = '$other';
    } else {
      _wCtrl.text = '$other';
    }
  }

  void _settle(_Field field) {
    switch (field) {
      case _Field.ratio:
        if (_editingRatio) _submitRatio(_ratioCtrl.text);
        return;
      case _Field.long:
        final n = int.tryParse(_longCtrl.text);
        setState(() => _typing = null);
        if (n != null && n > 0) {
          _solveFromLong(n);
        } else {
          setState(_syncControllers);
        }
        return;
      case _Field.width:
      case _Field.height:
        final w = int.tryParse(_wCtrl.text);
        final h = int.tryParse(_hCtrl.text);
        setState(() => _typing = null);
        if (w == null || h == null || w <= 0 || h <= 0) {
          setState(_syncControllers);
          return;
        }
        final sw = _snapFree(w);
        final sh = _snapFree(h);
        final changed = <_Field>{if (sw != w) _Field.width, if (sh != h) _Field.height};
        if (!_linked) {
          setState(() => _adoptRatioOf(sw, sh));
        }
        final l10n = AppLocalizations.of(context)!;
        _setDims(
          sw,
          sh,
          flash: changed,
          notice: changed.isEmpty ? null : l10n.imageSizeSnapped(_rules.edgeStep, '$w × $h', '$sw × $sh'),
          noticeIcon: Icons.straighten,
        );
        if (_linked) setState(() => _adoptRatioOf(sw, sh));
    }
  }

  /// A typed edge onto the grid, without clamping it into range — an edge
  /// out of range should *fail* its rule and offer the fix, not be moved.
  int _snapFree(int raw) {
    final step = _rules.edgeStep;
    return math.max(step, ((raw + step ~/ 2) ~/ step) * step);
  }

  // S6
  void _submitRatio(String text) {
    final r = parseAspectRatio(text);
    if (r == null) {
      setState(() => _ratioParseError = true);
      return;
    }
    final chip = _chipFor(r);
    final label = chip ?? _normaliseRatio(text, r);
    _chooseRatio(r, chip: chip, customLabel: chip == null ? label : null);
  }

  String _normaliseRatio(String text, AspectRatioSpec r) {
    final m = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*[:xX×/]\s*(\d+(?:\.\d+)?)\s*$').firstMatch(text);
    if (m != null) return '${m.group(1)}:${m.group(2)}';
    final v = r.portrait ? 1 / r.longOverShort : r.longOverShort;
    return '${v.toStringAsFixed(2)}:1';
  }

  void _applyFix(SizeFix fix) {
    final size = fix.size;
    if (size != null) {
      final (w, h) = size;
      setState(() => _adoptRatioOf(w, h));
      _setDims(w, h, flash: {_Field.width, _Field.height});
      return;
    }
    final fixed = parseAspectRatio(fix.ratio!)!;
    final chip = _chipFor(fixed);
    _chooseRatio(fixed, chip: chip, customLabel: chip == null ? fix.ratio : null);
  }

  // S10
  void _revertAndClose() {
    if (_written != _opening) widget.onChanged(_opening);
    widget.onClose();
  }

  void _done() {
    final field = _typing;
    if (field != null) _settle(field);
    if (_editingRatio) _submitRatio(_ratioCtrl.text);
    if (!_legal) return;
    widget.onClose();
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    const gap = SizedBox(height: 9);

    final showTable = _vocab.hasOfficialTable && _tableOpen;
    final blocked = !_legal;
    final typing = _typing != null;

    final children = <Widget>[
      if (widget.showHeader) ...[_header(l10n, scheme, text), gap],
      if (_sentinel != null) ...[_sentinelRow(l10n, scheme, text), gap],
      if (showTable) ...[
        _tableToggle(l10n, scheme, text),
        gap,
        _recommendTable(l10n, scheme, text),
      ] else ...[
        _ratioSection(l10n, scheme),
        gap,
        _tierSection(l10n, scheme, text),
        gap,
        SizePreview(
          width: _w,
          height: _h,
          referenceEdge: areaReferenceEdge(_rules),
          referenceLabel: l10n.imageSizeAreaRef(areaReferenceEdge(_rules)),
          boxHeight: widget.density.preview,
          invalid: blocked,
          dimmed: typing,
        ),
      ],
      gap,
      if (blocked) _blockedBox(l10n, scheme, text) else _summary(l10n, scheme, text, dimmed: typing),
      gap,
      _dimsRow(l10n, scheme, blocked: blocked),
      gap,
      SizeRuleLine(
        parts: sizeRuleParts(
          _rules,
          maxEdgeLabel: l10n.imageSizeRuleMaxEdgeShort,
          minEdgeLabel: l10n.imageSizeRuleMinEdgeShort,
          ratioLimit: maxRatioLabel(_rules),
          check: typing ? null : (_w, _h),
        ),
        status: typing
            ? l10n.imageSizeRulesPending
            : blocked
            ? null
            : l10n.imageSizeRulesAllPass,
        failLabel: l10n.imageSizeRuleFails,
      ),
      if (_vocab.hasOfficialTable && !showTable) ...[gap, _tableToggle(l10n, scheme, text)],
      gap,
      _footer(l10n, scheme, text, blocked: blocked, typing: typing),
    ];

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _revertAndClose},
      // Autofocus in the popover: its route's scope otherwise holds focus
      // until a box is typed in, and Esc reaches the route's own dismiss —
      // it closes, keeping what was chosen, instead of reverting.
      child: FocusScope(
        autofocus: widget.showHeader,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }

  Widget _header(AppLocalizations l10n, ColorScheme scheme, TextTheme text) {
    return Row(
      children: [
        Text(l10n.imageSizeTitle, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: AppSpace.s6),
        Expanded(
          child: Text(
            widget.modelName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.mono.copyWith(color: scheme.outline),
          ),
        ),
        AppIconButton(
          icon: Icons.close,
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          size: AppSize.compact,
          onPressed: _done,
        ),
      ],
    );
  }

  Widget _sentinelRow(AppLocalizations l10n, ColorScheme scheme, TextTheme text) {
    final selected = _isSentinel;
    final (title, hint) = sentinelTexts(l10n, _vocab.sentinel, long: true);
    return Material(
      color: selected ? scheme.accentTint : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: _chooseSentinel,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: widget.density.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s6),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: AppSize.iconMd,
                  color: selected ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: AppSpace.s6),
                Text(
                  title,
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected ? scheme.accentText : scheme.onSurface,
                  ),
                ),
                const SizedBox(width: AppSpace.s10),
                Expanded(
                  child: Text(hint, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ratioSection(AppLocalizations l10n, ColorScheme scheme) {
    final String? note = _ratioDerived
        ? l10n.imageSizeRatioDerived
        : (_ratioChip == null && _customRatioLabel != null ? l10n.imageSizeRatioAccepted : null);
    final dimmed = _typing == _Field.width || _typing == _Field.height;
    final customSelected = _ratioChip == null && !_isSentinel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizeSectionTitle(label: l10n.imageSizeRatio, icon: Icons.aspect_ratio, note: note),
        const SizedBox(height: AppSpace.s6),
        Wrap(
          spacing: AppSpace.s6,
          runSpacing: AppSpace.s6,
          children: [
            for (final c in _vocab.ratios)
              SizeRatioChip(
                label: c,
                ratio: _chipShape(c),
                selected: !_isSentinel && _ratioChip == c,
                height: widget.density.control,
                onTap: () => _chooseRatio(parseAspectRatio(c)!, chip: c),
              ),
            if (_editingRatio)
              SizedBox(
                width: 96,
                child: SizeNumberInput(
                  controller: _ratioCtrl,
                  focusNode: _ratioFocus,
                  height: widget.density.control,
                  allowRatio: true,
                  error: _ratioParseError || _ratioImpossible,
                  onChanged: (_) => setState(() => _ratioParseError = false),
                  onSubmitted: _submitRatio,
                  semanticsLabel: l10n.imageSizeCustom,
                ),
              )
            else
              SizeRatioChip(
                label: customSelected && _customRatioLabel != null
                    ? '${l10n.imageSizeCustom} ${_customRatioLabel!}'
                    : l10n.imageSizeCustom,
                ratio: customSelected ? (_ratio.portrait ? 1 / _ratio.longOverShort : _ratio.longOverShort) : null,
                icon: Icons.tune,
                selected: customSelected,
                error: customSelected && _ratioImpossible,
                dimmed: dimmed,
                height: widget.density.control,
                onTap: () {
                  setState(() {
                    _editingRatio = true;
                    _ratioCtrl.text = _customRatioLabel ?? _ratioChip ?? '';
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) => _ratioFocus.requestFocus());
                },
              ),
          ],
        ),
        if (_editingRatio || (customSelected && _ratioImpossible)) ...[
          const SizedBox(height: AppSpace.s4),
          Text(
            '16:9 · 16x9 · 16/9 · 1.78',
            style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(color: scheme.outline, fontSize: 10.5),
          ),
        ],
      ],
    );
  }

  double _chipShape(String chip) {
    final r = parseAspectRatio(chip)!;
    return r.portrait ? 1 / r.longOverShort : r.longOverShort;
  }

  /// The tier axis takes the whole row (`A1c` 四语言: each segment needs its
  /// ~82px for 「カスタム」); the long edge sits under it with the last
  /// correction beside it, so the note reads next to the number it moved.
  Widget _tierSection(AppLocalizations l10n, ColorScheme scheme, TextTheme text) {
    const custom = '#custom';
    final tier = _isSentinel ? null : _currentTier;
    final note = switch (_vocab.tierKind) {
      SizeTierKind.areaTarget => l10n.imageSizeTierAreaTarget,
      _ => _vocab.tiers.join(' / '),
    };
    final dimmed = _typing == _Field.width || _typing == _Field.height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizeSectionTitle(label: l10n.imageSizeTierSection, note: note),
        const SizedBox(height: AppSpace.s6),
        Opacity(
          opacity: dimmed ? 0.55 : 1,
          child: AppSegmentedControl<String>(
            segments: [
              for (final t in _vocab.tiers) AppSegment(value: t, label: t),
              AppSegment(value: custom, label: l10n.imageSizeCustom),
            ],
            value: _isSentinel ? '' : (tier ?? custom),
            expand: true,
            compact: true,
            style: AppSegmentStyle.raised,
            onChanged: (v) {
              if (v == custom) {
                _longFocus.requestFocus();
              } else {
                _chooseTier(v);
              }
            },
          ),
        ),
        const SizedBox(height: AppSpace.s6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 104,
              child: SizeNumberInput(
                controller: _longCtrl,
                focusNode: _longFocus,
                height: widget.density.control,
                suffix: l10n.imageSizeLongEdge,
                flash: _flash.contains(_Field.long),
                onChanged: (t) => _typed(_Field.long, t),
                onSubmitted: (_) => _settle(_Field.long),
                semanticsLabel: l10n.imageSizeLongEdge,
              ),
            ),
            if (_notice != null) ...[const SizedBox(width: AppSpace.s10), Expanded(child: _noticeLine(scheme, text))],
          ],
        ),
      ],
    );
  }

  Widget _noticeLine(ColorScheme scheme, TextTheme text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(_noticeIcon, size: AppSize.iconSm, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppSpace.s6),
        Expanded(
          child: Text(_notice!, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }

  Widget _summary(AppLocalizations l10n, ColorScheme scheme, TextTheme text, {required bool dimmed}) {
    final billing = _billing(l10n);
    final label = _isSentinel && _vocab.sentinel == SizeSentinelMeaning.modelDecides
        ? l10n.imageSizeHintGpt
        : '$_w × $_h · ${_ratioChip ?? _customRatioLabel ?? ratioLabel(_w, _h)} · ${megapixels(_w * _h)} MP';
    final mono = text.bodySmall?.mono.copyWith(color: scheme.onSurface);
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Row(
              children: [
                Icon(
                  dimmed ? Icons.edit : Icons.check,
                  size: AppSize.iconSm,
                  color: dimmed ? scheme.outline : context.semantic.success,
                ),
                const SizedBox(width: AppSpace.s6),
                Expanded(
                  child: Text(
                    dimmed ? l10n.imageSizeTypingHint : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dimmed ? text.labelSmall?.copyWith(color: scheme.outline) : mono,
                  ),
                ),
                if (billing != null && !dimmed)
                  _BillingTag(label: l10n.imageSizeBillingTier(billing.tier), crossed: billing.crossed != null),
              ],
            ),
          ),
          if (billing?.crossed != null && !dimmed) ...[
            const SizedBox(height: AppSpace.s6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.sell_outlined, size: AppSize.iconSm, color: scheme.onSurfaceVariant),
                const SizedBox(width: AppSpace.s6),
                Expanded(
                  child: Text(billing!.crossed!, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The tier the current size will be billed at, and — on an area-billed
  /// model past its smallest tier — the sentence saying why (`30c` 越线).
  /// Null without a spec-billed group that names tiers.
  ({String tier, String? crossed})? _billing(AppLocalizations l10n) {
    final rates = widget.rates;
    if (rates == null || _isSentinel && _vocab.sentinel == SizeSentinelMeaning.modelDecides) return null;
    final tier = specRateTierOf('${_w}x$_h', rates);
    if (tier == null) return null;
    String? crossed;
    if (_vocab.tierKind == SizeTierKind.areaTier) {
      final tiers = [
        for (final r in rates)
          if (r.size != null && tierEdge(r.size!) != null) r.size!,
      ]..sort((a, b) => tierEdge(a)!.compareTo(tierEdge(b)!));
      final lowest = tiers.firstOrNull;
      if (lowest != null && lowest != tier) {
        final edge = tierEdge(lowest)!;
        crossed = l10n.imageSizeBillingCrossed(lowest, '$edge² = ${megapixels(edge * edge)} MP', tier);
      }
    }
    return (tier: tier, crossed: crossed);
  }

  Widget _blockedBox(AppLocalizations l10n, ColorScheme scheme, TextTheme text) {
    final String message;
    final SizeFix fix;
    if (_ratioImpossible) {
      message = l10n.imageSizeNoSolution(maxRatioLabel(_rules));
      // Worded on the chosen side: a portrait ratio is fixed to `1:3`.
      final limit = maxRatioLabel(_rules);
      fix = SizeFix.ratio(_ratio.portrait ? limit.split(':').reversed.join(':') : limit);
    } else if (math.max(_w, _h) / math.max(1, math.min(_w, _h)) > _rules.maxRatio) {
      message = l10n.imageSizeRatioOverLimit(ratioLabel(_w, _h), maxRatioLabel(_rules));
      fix = fixFor(_w, _h, _rules);
    } else {
      message = l10n.imageSizeOutOfRange;
      fix = fixFor(_w, _h, _rules);
    }
    final kept = _written == _sentinel ? sentinelTexts(l10n, _vocab.sentinel).$1 : sizeValueText(_written);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s6),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Row(
            children: [
              Icon(Icons.error_outline, size: AppSize.iconSm, color: scheme.onErrorContainer),
              const SizedBox(width: AppSpace.s6),
              Expanded(
                child: Text(message, style: text.labelSmall?.copyWith(color: scheme.onErrorContainer)),
              ),
              const SizedBox(width: AppSpace.s6),
              AppButton(
                label: l10n.imageSizeFixTo(fix.label),
                size: AppButtonSize.compact,
                onPressed: () => _applyFix(fix),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.s6),
        Row(
          children: [
            Icon(Icons.block, size: AppSize.iconSm, color: scheme.outline),
            const SizedBox(width: AppSpace.s6),
            Expanded(
              child: Text(l10n.imageSizeNotWrittenBack(kept), style: text.labelSmall?.copyWith(color: scheme.outline)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dimsRow(AppLocalizations l10n, ColorScheme scheme, {required bool blocked}) {
    final dimsBad = blocked && !_ratioImpossible;
    return Row(
      children: [
        Expanded(
          child: SizeNumberInput(
            controller: _wCtrl,
            focusNode: _wFocus,
            height: widget.density.control,
            prefix: widget.density.showUnits ? l10n.imageSizeWidth : null,
            error: dimsBad,
            flash: _flash.contains(_Field.width),
            onChanged: (t) => _typed(_Field.width, t),
            onSubmitted: (_) => _settle(_Field.width),
            semanticsLabel: l10n.imageSizeWidth,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4),
          child: Icon(Icons.close, size: AppSize.iconSm, color: scheme.outline),
        ),
        Expanded(
          child: SizeNumberInput(
            controller: _hCtrl,
            focusNode: _hFocus,
            height: widget.density.control,
            prefix: widget.density.showUnits ? l10n.imageSizeHeight : null,
            error: dimsBad,
            flash: _flash.contains(_Field.height),
            onChanged: (t) => _typed(_Field.height, t),
            onSubmitted: (_) => _settle(_Field.height),
            semanticsLabel: l10n.imageSizeHeight,
          ),
        ),
        if (widget.density.showUnits) ...[
          const SizedBox(width: AppSpace.s4),
          Text('px', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.outline)),
        ],
        const SizedBox(width: AppSpace.s4),
        SizedBox.square(
          dimension: widget.density.control,
          child: AppIconButton(
            icon: _linked ? Icons.link : Icons.link_off,
            tooltip: l10n.imageSizeLockRatio,
            selected: _linked,
            size: widget.density.control,
            onPressed: () => setState(() => _linked = !_linked),
          ),
        ),
      ],
    );
  }

  Widget _tableToggle(AppLocalizations l10n, ColorScheme scheme, TextTheme text) {
    return InkWell(
      onTap: () => setState(() => _tableOpen = !_tableOpen),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.s4),
        child: Row(
          children: [
            Icon(Icons.table_chart_outlined, size: AppSize.iconSm, color: scheme.accentText),
            const SizedBox(width: AppSpace.s6),
            Text(l10n.imageSizeRecommendTable, style: text.labelSmall?.copyWith(color: scheme.accentText)),
            const Spacer(),
            Icon(_tableOpen ? Icons.expand_less : Icons.expand_more, size: AppSize.iconMd, color: scheme.accentText),
          ],
        ),
      ),
    );
  }

  Widget _recommendTable(AppLocalizations l10n, ColorScheme scheme, TextTheme text) {
    final rows = <(String label, AspectRatioSpec ratio)>[
      ('1:1', const AspectRatioSpec(1, false)),
      for (final r in _vocab.officialTable.values.first.keys)
        if (parseAspectRatio(r) case final spec?)
          ('$r / ${r.split(':').reversed.join(':')}', AspectRatioSpec(spec.longOverShort, _ratio.portrait)),
    ];
    final mono = text.labelSmall?.mono.copyWith(fontSize: 10.5);
    final current = _currentTier;
    Widget cell(String label, {required bool selected, VoidCallback? onTap}) => Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: selected ? scheme.accentTint : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: SizedBox(
            height: 30,
            child: Center(
              child: Text(
                label,
                style: mono?.copyWith(
                  color: selected ? scheme.accentText : scheme.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Table(
          columnWidths: const {0: FlexColumnWidth(1.3)},
          children: [
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpace.s4),
                  child: Text(l10n.imageSizeRecommendCorner, style: text.labelSmall?.copyWith(color: scheme.outline)),
                ),
                for (final t in _vocab.tiers)
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.s4),
                    child: Text(
                      t,
                      textAlign: TextAlign.center,
                      style: mono?.copyWith(color: scheme.outline),
                    ),
                  ),
              ],
            ),
            for (final (label, ratio) in rows)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.s4),
                    child: Text(label, style: mono?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                  for (final t in _vocab.tiers)
                    Builder(
                      builder: (context) {
                        final (w, h) = tierSize(ratio, t, _rules, _vocab);
                        final isSquare = (ratio.longOverShort - 1).abs() < 1e-9;
                        final selected =
                            !_isSentinel && current == t && (ratio.longOverShort - _ratio.longOverShort).abs() < 1e-6;
                        return cell(
                          isSquare ? t : '$w×$h',
                          selected: selected,
                          onTap: () {
                            setState(() {
                              _ratio = ratio;
                              _ratioChip = _chipFor(ratio);
                              _customRatioLabel = null;
                              _ratioDerived = false;
                            });
                            _chooseTier(t);
                          },
                        );
                      },
                    ),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppSpace.s6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: AppSize.iconSm, color: scheme.outline),
            const SizedBox(width: AppSpace.s6),
            Expanded(
              child: Text(l10n.imageSizeRecommendHint, style: text.labelSmall?.copyWith(color: scheme.outline)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _footer(
    AppLocalizations l10n,
    ColorScheme scheme,
    TextTheme text, {
    required bool blocked,
    required bool typing,
  }) {
    final hint = typing
        ? l10n.imageSizeFooterTyping
        : blocked
        ? l10n.imageSizeFooterBlocked
        : l10n.imageSizeFooter;
    return Row(
      children: [
        Expanded(
          child: Text(hint, style: text.labelSmall?.copyWith(color: scheme.outline)),
        ),
        AppButton(label: l10n.imageSizeDone, size: AppButtonSize.compact, onPressed: blocked ? null : _done),
      ],
    );
  }
}

/// `A1c` 计价标签: the tier's name in a small hairline tag — never a price.
class _BillingTag extends StatelessWidget {
  const _BillingTag({required this.label, required this.crossed});

  final String label;

  /// Past the smallest tier: the edge takes the accent (`30c`: 描主色边).
  final bool crossed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.state),
      height: 19,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: crossed ? scheme.primary : scheme.outlineVariant),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: crossed ? scheme.accentText : scheme.onSurfaceVariant, fontSize: 10.5),
      ),
    );
  }
}
