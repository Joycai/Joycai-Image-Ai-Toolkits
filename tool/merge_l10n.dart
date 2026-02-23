import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() async {
  final l10nDir = p.join('lib', 'l10n');
  final srcDir = p.join(l10nDir, 'src');

  for (final lang in ['en', 'zh', 'zh_Hant', 'ja']) {
    final langDir = Directory(p.join(srcDir, lang));
    if (!await langDir.exists()) continue;

    final Map<String, dynamic> merged = {};
    
    // Sort files to ensure stable output (common first is good practice)
    final files = await langDir.list().toList();
    files.sort((a, b) => a.path.compareTo(b.path));

    for (final entity in files) {
      if (entity is File && entity.path.endsWith('.arb')) {
        final Map<String, dynamic> content = jsonDecode(await entity.readAsString());
        merged.addAll(content);
      }
    }

    final outputFile = File(p.join(l10nDir, 'app_$lang.arb'));
    final encoder = const JsonEncoder.withIndent('  ');
    await outputFile.writeAsString(encoder.convert(merged));
    // ignore: avoid_print
    print('Generated ${outputFile.path}');
  }
}
