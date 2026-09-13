import '../../core/constants.dart';
import '../llm/model_capabilities.dart';
import '../llm/model_family.dart';
import '../llm/output_spec.dart';
import '../llm/vendors/vendor_profile.dart' show WireProtocol;

/// The values a rate row's conditions can be picked from: the union of every
/// family's parameter tables (`D2b · 21c`), normalised the way the request
/// side normalises them, so a value picked here always equals the value a
/// request carries.
///
/// Read off [ModelCapabilities] rather than typed out, so a family gaining a
/// resolution tier shows up in the picker without anyone remembering this
/// file. The picker also takes free text for relays that spell their own —
/// this is the menu, not the validation.
class SpecKnownValues {
  final List<String> imageSizes;
  final List<String> videoResolutions;
  final List<String> qualities;
  final List<int> seconds;

  const SpecKnownValues({
    required this.imageSizes,
    required this.videoResolutions,
    required this.qualities,
    required this.seconds,
  });

  static SpecKnownValues? _cached;

  static SpecKnownValues collect() => _cached ??= _collect();

  static SpecKnownValues _collect() {
    final imageSizes = <String>{};
    // The video panel's shared resolution dropdown is not a family parameter
    // (Veo is served by it alone), so its vocabulary is read from the enum.
    final videoResolutions = <String>{
      for (final r in VeoResolution.values) ?OutputSpec.normalizeSize(r.value),
    };
    final qualities = <String>{};
    final seconds = <int>{};

    // Every table there is: the ones a family owns, and the ones only a
    // wire protocol reaches (the xAI, DashScope and MiniMax video tables
    // have no family of their own — `forModel` routes to them by id).
    final tables = [
      for (final family in ModelFamily.values) ModelCapabilities.forFamily(family),
      for (final protocol in WireProtocol.values) ModelCapabilities.forProtocol(protocol),
    ];

    for (final caps in tables) {
      for (final param in caps.imageParams) {
        switch (param.key) {
          case 'imageSize':
            imageSizes.addAll(_sizes(param));
          case 'quality':
            qualities.addAll(_qualities(param));
        }
      }
      for (final param in caps.videoParams) {
        switch (param.key) {
          case 'resolution':
            videoResolutions.addAll(_sizes(param));
          case 'quality':
          case 'videoQuality':
            qualities.addAll(_qualities(param));
          case 'seconds':
            for (final o in param.options) {
              final s = OutputSpec.normalizeSeconds(o.value);
              if (s != null) seconds.add(s);
            }
        }
      }
    }

    return SpecKnownValues(
      imageSizes: _sortSizes(imageSizes),
      videoResolutions: _sortSizes(videoResolutions, video: true),
      qualities: _sortQualities(qualities),
      seconds: seconds.toList()..sort(),
    );
  }

  static Iterable<String> _sizes(ParamSpec param) =>
      param.options.map((o) => OutputSpec.normalizeSize(o.value)).nonNulls;

  static Iterable<String> _qualities(ParamSpec param) =>
      param.options.map((o) => OutputSpec.normalizeQuality(o.value)).nonNulls;

  /// `1K` before `2K` before `4K`, then `480p` … `1080p`, then `WxH` by
  /// area, then whatever else as typed — the order a price list reads in.
  /// For video the `p` tiers lead and the `K` ones (MiniMax's 2K, Veo's
  /// legacy 4K) follow.
  static List<String> _sortSizes(Set<String> raw, {bool video = false}) {
    int rank(String s) {
      if (RegExp(r'^\d+K$').hasMatch(s)) return video ? 1 : 0;
      if (RegExp(r'^\d+p$').hasMatch(s)) return video ? 0 : 1;
      if (RegExp(r'^\d+x\d+$').hasMatch(s)) return 2;
      return 3;
    }

    num magnitude(String s) {
      final m = RegExp(r'^(\d+)x(\d+)$').firstMatch(s);
      if (m != null) return int.parse(m.group(1)!) * int.parse(m.group(2)!);
      return int.tryParse(s.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    }

    return raw.toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        final byMagnitude = magnitude(a).compareTo(magnitude(b));
        return byMagnitude != 0 ? byMagnitude : a.compareTo(b);
      });
  }

  static const _qualityOrder = ['low', 'medium', 'high', 'standard'];

  static List<String> _sortQualities(Set<String> raw) => raw.toList()
    ..sort((a, b) {
      final ia = _qualityOrder.indexOf(a);
      final ib = _qualityOrder.indexOf(b);
      if (ia != -1 && ib != -1) return ia.compareTo(ib);
      if (ia != -1) return -1;
      if (ib != -1) return 1;
      return a.compareTo(b);
    });
}
