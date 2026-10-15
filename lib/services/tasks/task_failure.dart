import 'dart:async';
import 'dart:io';

import '../llm/llm_config_resolver.dart';
import '../llm/llm_errors.dart';

class ImageGenerationFailure implements Exception {
  const ImageGenerationFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Small, persisted public error contract. Unknown failures never expose a stack,
/// credential, signed URL or filesystem exception to an external client.
Map<String, dynamic> taskFailure(Object error) {
  final code = switch (error) {
    TimeoutException() => 'timeout',
    SocketException() => 'connectionFailed',
    ImageGenerationFailure() => 'noUsableImage',
    LLMApiException(isContentBlocked: true) => 'contentBlocked',
    LLMApiException(statusCode: 401 || 403) => 'providerAuthentication',
    LLMApiException(statusCode: 429) => 'rateLimited',
    LLMApiException() => 'providerError',
    LLMConfigException() => 'configurationChanged',
    FileSystemException() => 'fileError',
    _ => 'generationFailed',
  };
  return {
    'code': code,
    'message': switch (code) {
      'timeout' => 'The provider request timed out. It may still have been processed upstream.',
      'connectionFailed' => 'Could not connect to the configured provider.',
      'noUsableImage' => 'The provider returned no usable image. It may have replied with text or refused the request.',
      'contentBlocked' => 'The provider blocked this request.',
      'providerAuthentication' => 'The provider rejected the configured credentials.',
      'rateLimited' => 'The provider rate limit was reached.',
      'configurationChanged' =>
        'The configured model or generation route is unavailable or changed.',
      'fileError' => 'An input or output file could not be read or written.',
      _ => 'Generation failed. Check the task log in the application for provider details.',
    },
    if (error case LLMApiException(:final statusCode?)) 'upstreamStatus': statusCode,
    'retrySafe': false,
  };
}
