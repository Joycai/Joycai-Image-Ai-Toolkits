import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_debug_logger.dart';

/// Response bodies and stream lines are written to the API debug log raw, and
/// image surfaces put megabytes of base64 in them. Every line is sanitised in
/// the logger itself: a base64 run of 2048+ chars becomes `<base64 N chars>`.
void main() {
  const threshold = LLMDebugLogger.base64RunThreshold;
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

  test('a multi-megabyte streamed image line is collapsed, not a stack overflow', () {
    // One Gemini image stream line: a 4 MB picture is ~5.6 million base64
    // characters. The RegExp this used to be threw StackOverflowError on it,
    // which escaped the SSE loop and failed a generation that had succeeded.
    final payload = b64(5600000);
    final line = 'data: {"candidates":[{"content":{"parts":[{"inlineData":'
        '{"mimeType":"image/png","data":"$payload"}}]}}]}';
    final out = LLMDebugLogger.sanitizeLine(line);
    expect(out, contains('"data":"<base64 5600000 chars>"'));
    expect(out.length, lessThan(200));
  });

  test('every payload in a line is collapsed, a short data: URL is kept', () {
    final short = 'data:image/png;base64,${b64(40)}';
    final a = b64(threshold);
    final b = b64(threshold + 7);
    final line = '[$short] "$a=" x data:image/jpeg;base64,$b end';
    expect(
      LLMDebugLogger.sanitizeLine(line),
      '[$short] "<base64 ${threshold + 1} chars>" x '
      '<base64 ${'data:image/jpeg;base64,'.length + threshold + 7} chars> end',
    );
  });
}
