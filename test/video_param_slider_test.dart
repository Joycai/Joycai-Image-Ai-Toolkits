import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';

/// Pins the slider half of [ParamSpec].
///
/// The bug this exists for: `isValid` only ever checked the discrete
/// `options` list and an optional `customValidator`. A slider has neither —
/// its range lives in `min`/`max` — so every slider value failed both checks,
/// `normalize` returned `defaultValue` forever, and the control snapped back
/// on the next rebuild. The duration was stuck at its default for MiniMax-H3
/// (5s) and wan3.0-video (5s); grok-imagine-video escaped only because it
/// carried a hand-written validator restating its own bounds.
///
/// Worse than a stuck control: `effectiveVideoParams` reads through the same
/// getter, so the request carried the default too. The user could not change
/// the duration *and* was not told.
void main() {
  ParamSpec slider({int? min, int? max, String defaultValue = '5'}) => ParamSpec(
        key: 'seconds',
        labelKey: 'videoSeconds',
        control: ParamControl.slider,
        defaultValue: defaultValue,
        options: const [],
        min: min,
        max: max,
      );

  group('slider validity', () {
    test('accepts any integer inside the declared range', () {
      final spec = slider(min: 4, max: 15);
      for (final v in ['4', '5', '9', '15']) {
        expect(spec.isValid(v), isTrue, reason: v);
        expect(spec.normalize(v), v, reason: v);
      }
    });

    test('rejects values outside it, falling back to the default', () {
      final spec = slider(min: 4, max: 15);
      for (final v in ['3', '16', '30', '0', '-1']) {
        expect(spec.isValid(v), isFalse, reason: v);
        expect(spec.normalize(v), '5', reason: v);
      }
    });

    test('rejects non-integers rather than passing them to the wire', () {
      final spec = slider(min: 4, max: 15);
      for (final v in ['', 'abc', '7.5', '1e1']) {
        expect(spec.isValid(v), isFalse, reason: '"$v"');
      }
      expect(spec.isValid(null), isFalse);
      // Surrounding whitespace parses in Dart, so it is in range and stays.
      // Not tightened: the store only ever receives round().toString() from
      // the slider, and resolveVideoSeconds parses the same way on the way
      // out — a format check here would guard against nothing.
      expect(spec.isValid(' 7 '), isTrue);
    });

    test('an unbounded slider agrees with what the panel would clamp to', () {
      // The panel renders with `min ?? 1` / `max ?? 15`. If validity used
      // different fallbacks, a value could be "valid" and still un-renderable
      // — the control would show one number while the store held another.
      final spec = slider();
      expect(spec.isValid('1'), isTrue);
      expect(spec.isValid('15'), isTrue);
      expect(spec.isValid('0'), isFalse);
      expect(spec.isValid('16'), isFalse);
    });
  });

  group('the video families that ship a slider', () {
    ParamSpec secondsOf(String modelId) =>
        ModelCapabilities.forModel(modelId)
            .videoParams
            .firstWhere((p) => p.key == 'seconds');

    test('MiniMax-H3 accepts its documented 4-15s window', () {
      final spec = secondsOf('MiniMax-H3');
      expect(spec.normalize('12'), '12', reason: 'the reported bug: stuck at 5');
      expect(spec.normalize('4'), '4');
      expect(spec.normalize('15'), '15');
      // Outside MiniMax's window — clamped by the payload builder anyway, but
      // it must not survive as a UI value either.
      expect(spec.normalize('3'), '5');
      expect(spec.normalize('30'), '5');
    });

    test('wan3.0-video accepts its wider 2-30s window', () {
      // Same latent bug, different family: it was stuck at 5s too.
      final spec = secondsOf('wan3.0-video');
      expect(spec.normalize('30'), '30');
      expect(spec.normalize('2'), '2');
      expect(spec.normalize('31'), '5');
    });

    test('grok-imagine-video keeps working without its own validator', () {
      // It carried `customValidator: isValidGrokImagineVideoDuration`, which
      // only restated min/max. Removed with this fix; the behaviour must not
      // have moved.
      final spec = secondsOf('grok-imagine-video-1.5');
      expect(spec.normalize('1'), '1');
      expect(spec.normalize('15'), '15');
      expect(spec.normalize('16'), '6', reason: 'its default is 6, not 5');
      expect(spec.customValidator, isNull);
    });

    test('the families share one param store, so cross-family values degrade',
        () {
      // The store is keyed by model *family* (app_state_workbench
      // `_familyKey`), and every one of these classifies as openaiVideo — so
      // one `seconds` value is shared across sora / grok / wan3 / H3. A 30s
      // chosen for wan3 must not silently become an out-of-range request for
      // H3; normalize is what makes it degrade to H3's own default instead.
      expect(secondsOf('wan3.0-video').normalize('30'), '30');
      expect(secondsOf('MiniMax-H3').normalize('30'), '5');
    });
  });

  group('non-slider controls are unaffected', () {
    test('a dropdown still validates against its options only', () {
      const spec = ParamSpec(
        key: 'aspectRatio',
        labelKey: 'aspectRatio',
        control: ParamControl.dropdown,
        defaultValue: 'adaptive',
        options: [ParamOption('adaptive'), ParamOption('16:9')],
      );
      expect(spec.isValid('16:9'), isTrue);
      // An integer must not become valid just because the slider branch
      // exists — the branch is gated on the control, not on parseability.
      expect(spec.isValid('9'), isFalse);
      expect(spec.normalize('9'), 'adaptive');
    });

    test('a customValidator still widens a non-slider spec', () {
      // gpt-image-2's arbitrary WxH sizes ride this path; the slider branch
      // must not have displaced it.
      final spec = ModelCapabilities.forModel('gpt-image-2')
          .imageParams
          .firstWhere((p) => p.key == 'imageSize');
      expect(spec.customValidator, isNotNull);
      expect(spec.isValid('1024x1024'), isTrue);
    });
  });
}
