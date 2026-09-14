import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_debug_logger.dart';

/// Response bodies and stream lines are written to the API debug log raw, and
/// image surfaces put megabytes of base64 in them. Every line is sanitised in
/// the logger itself: a base64 run of 2048+ chars becomes `<base64 N chars>`.
void main() {
  final threshold = LLMDebugLogger.base64RunThreshold;
  String b64(int n) => ('iVBORw0KGgoAAAANSUhEUgAA' * (n ~/ 24 + 1)).substring(0, n);

  test('a bare b64_json payload in a response body is collapsed', () {
    final payload = b64(5000);
    final line = 'Body: {"data":[{"b64_json":"$payload"}]}';
    final out = LLMDebugLogger.sanitizeLine(line);
    expect(out, 'Body: {"data":[{"b64_json":"<base64 5000 chars>"}]}');
  });

  test('a data: URL is collapsed with its prefix', () {
    final payload = b64(3000);
    final url = 'data:image/png;base64,$payload==';
    final out = LLMDebugLogger.sanitizeLine('url: $url end');
    expect(out, 'url: <base64 ${url.length} chars> end');
  });

  test('a Gemini inlineData stream line is collapsed, the rest kept', () {
    final payload = b64(4096);
    final line = 'data: {"candidates":[{"content":{"parts":[{"inlineData":'
        '{"mimeType":"image/png","data":"$payload"}}]}}],'
        '"usageMetadata":{"promptTokenCount":7}}';
    final out = LLMDebugLogger.sanitizeLine(line);
    expect(out, contains('"data":"<base64 4096 chars>"'));
    expect(out, contains('"promptTokenCount":7'));
    expect(out.length, lessThan(300));
  });

  test('runs just below the threshold are left alone', () {
    final payload = b64(threshold - 1);
    final line = 'Body: "$payload"';
    expect(LLMDebugLogger.sanitizeLine(line), line);
  });

  test('exactly the threshold is collapsed', () {
    final payload = b64(threshold);
    expect(LLMDebugLogger.sanitizeLine('"$payload"'),
        '"<base64 $threshold chars>"');
  });

  test('long prose is never touched', () {
    final prose = 'The model answered at length, with spaces. ' * 200;
    expect(LLMDebugLogger.sanitizeLine(prose), prose);
  });
}
