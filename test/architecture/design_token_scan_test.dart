import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces that `lib/screens/` and `lib/widgets/` consume theme roles and
/// design tokens rather than stray hardcoded Material colours, hex literals,
/// raw font sizes, or raw corner radii.
///
/// Existing palette/identity modules and documented micro-geometry exceptions
/// are explicitly ratcheted: no new file may join them, and removing an entry
/// here requires deleting the last remaining literal in that file.
void main() {
  final lineComment = RegExp(r'(^|\s)//.*$');

  String normalizePath(File file) => file.path.replaceAll(r'\', '/');

  List<File> uiDartFiles() {
    final out = <File>[];
    for (final root in const ['lib/screens', 'lib/widgets']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          out.add(entity);
        }
      }
    }
    out.sort((a, b) => normalizePath(a).compareTo(normalizePath(b)));
    return out;
  }

  Map<String, List<String>> scanPattern(RegExp pattern) {
    final hits = <String, List<String>>{};
    for (final file in uiDartFiles()) {
      final path = normalizePath(file);
      final lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final code = lines[i].replaceFirst(lineComment, '');
        if (pattern.hasMatch(code)) {
          (hits[path] ??= <String>[]).add('$path:${i + 1}  ${code.trim()}');
        }
      }
    }
    return hits;
  }

  void assertRatchet({
    required String rule,
    required RegExp pattern,
    required Set<String> allowlist,
  }) {
    final hits = scanPattern(pattern);
    final hitFiles = hits.keys.toSet();
    final unexpected = hitFiles.difference(allowlist).toList()..sort();
    final stale = allowlist.difference(hitFiles).toList()..sort();

    expect(
      unexpected,
      isEmpty,
      reason:
          '$rule violation in non-allowlisted UI files:\n'
          '  ${unexpected.expand((f) => hits[f]!).join('\n  ')}',
    );
    expect(
      stale,
      isEmpty,
      reason:
          'Remove resolved files from the $rule allowlist in design_token_scan_test.dart:\n'
          '  ${stale.join('\n  ')}',
    );
  }

  test('no stray Color(0x...) literals in screens or widgets', () {
    assertRatchet(
      rule: 'Color(0x...)',
      pattern: RegExp(r'\bColor\(0x'),
      allowlist: const {
        'lib/screens/browser/widgets/file_card.dart',
        'lib/screens/metrics/widgets/usage_palette.dart',
        'lib/screens/settings/settings_identity.dart',
        'lib/screens/workbench/assistant/context_usage_palette.dart',
        'lib/screens/workbench/widgets/gallery/image_card.dart',
        'lib/widgets/glass/app_glass.dart',
        'lib/widgets/models/context_window_slider.dart',
        'lib/widgets/models/model_edit_controls/model_edit_track_slider.dart',
        'lib/widgets/shell/app_window_frame.dart',
        'lib/widgets/ui/app_side_panel.dart',
      },
    );
  });

  test('no stray Colors.<named> literals in screens or widgets', () {
    assertRatchet(
      rule: 'Colors.<named>',
      pattern: RegExp(r'\bColors\.(?!transparent\b|white\d*\b|black\d*\b)\w+'),
      allowlist: const {
        'lib/screens/workbench/widgets/mask/mask_editor_toolbar.dart',
        'lib/screens/workbench/widgets/mask/mask_editor_view.dart',
      },
    );
  });

  test('no new raw numeric fontSize literals in screens or widgets', () {
    assertRatchet(
      rule: 'fontSize: <num>',
      pattern: RegExp(r'\bfontSize:\s*[0-9]'),
      allowlist: const {
        'lib/screens/workbench/assistant/result_feedback_dialog.dart',
        'lib/screens/workbench/widgets/size_picker/size_picker_panel.dart',
        'lib/screens/workbench/widgets/size_picker/size_picker_parts.dart',
        'lib/widgets/models/context_window_slider.dart',
        'lib/widgets/models/model_edit_controls/model_edit_track_slider.dart',
        'lib/widgets/settings/dual_tone_swatch.dart',
        'lib/widgets/ui/app_markdown.dart',
        'lib/widgets/ui/markdown_editor.dart',
      },
    );
  });

  test('no new raw numeric BorderRadius.circular literals in screens or widgets', () {
    assertRatchet(
      rule: 'BorderRadius.circular(<num>)',
      pattern: RegExp(r'BorderRadius\.circular\(\s*[0-9]'),
      allowlist: const {
        'lib/screens/wizard/setup_wizard.dart',
        'lib/screens/workbench/assistant/optimizer/optimizer_feedback_card.dart',
        'lib/screens/workbench/assistant/result_feedback_dialog.dart',
        'lib/screens/workbench/widgets/config/prompt_history_sheet.dart',
        'lib/screens/workbench/widgets/config/prompt_library_sheet.dart',
        'lib/screens/workbench/widgets/layers/layer_canvas_page.dart',
        'lib/screens/workbench/widgets/preview/media_preview_dialog.dart',
        'lib/screens/workbench/widgets/size_picker/size_picker_panel.dart',
        'lib/screens/workbench/widgets/size_picker/size_picker_parts.dart',
        'lib/widgets/models/chat_model_selector.dart',
        'lib/widgets/settings/theme_accent/custom_accent_pair.dart',
        'lib/widgets/shell/nav_lens_group.dart',
        'lib/widgets/tasks/task_capsule_monitor.dart',
        'lib/widgets/ui/app_markdown.dart',
        'lib/widgets/ui/markdown_editor.dart',
        'lib/widgets/ui/panel_resizer.dart',
      },
    );
  });
}
