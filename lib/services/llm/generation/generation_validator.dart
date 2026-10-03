import 'dart:isolate';

import 'package:image/image.dart' as img;

import '../llm_types.dart';
import '../protocols/protocol.dart' show readAttachmentBytes;
import 'generation_request.dart';
import 'generation_schema.dart';
import 'generation_value.dart';

/// Shared non-UI guard, before transport can discard or reinterpret inputs.
Future<Map<String, dynamic>?> validateGeneration(
  GenerationSchema schema,
  List<LLMMessage> history,
  Map<String, dynamic>? options,
) async {
  if (schema.configurationDiagnostics.isNotEmpty) {
    throw LLMApiException('Generation input invalid: incompatibleProfile. Nothing was sent.');
  }
  if (!schema.capabilities.isImageGenerator && !schema.isVideo) return options;
  if ((options ?? const {}).keys.any(
    (key) =>
        GenerationSchema.semanticKeys.contains(key) &&
        !schema.params.any((param) => param.key == key),
  )) {
    throw LLMApiException('Generation input invalid: invalidParameter. Nothing was sent.');
  }
  final user = history.where((m) => m.role == LLMRole.user).lastOrNull;
  final attachments = user?.attachments ?? const <LLMAttachment>[];
  final media = [
    for (final attachment in attachments)
      GenerationMedia(switch (attachment.referenceType) {
        LLMReferenceType.firstFrame => GenerationMediaRole.firstFrame,
        LLMReferenceType.lastFrame => GenerationMediaRole.lastFrame,
        _ => GenerationMediaRole.reference,
      }, attachment.path ?? ''),
  ];
  final Map<String, GenerationValue> draft;
  try {
    draft = schema.readLegacy(options ?? const {});
  } on FormatException {
    throw LLMApiException('Generation input invalid: invalidParameter. Nothing was sent.');
  }
  final operation = schema.operation(draft, media);
  final effective = schema.effective(draft, operation);
  final request = GenerationRequest.fromTask(options ?? const {});
  if (request != null &&
      (request.operation != operation ||
          request.media.length != media.length ||
          request.prompt != user?.content ||
          request.values.length != effective.length ||
          effective.entries.any((entry) => request.values[entry.key] != entry.value))) {
    throw LLMApiException(
      'Generation snapshot does not match the submitted input. Nothing was sent.',
    );
  }
  final diagnostics = schema.validate(effective, media);
  if (diagnostics.isNotEmpty) {
    throw LLMApiException(
      'Generation input invalid: ${diagnostics.map((d) => d.code).join(', ')}. Nothing was sent.',
    );
  }
  for (final attachment in attachments) {
    final bytes = await readAttachmentBytes(attachment);
    if (bytes == null || bytes.isEmpty) {
      throw LLMApiException('Generation input invalid: unreadableMedia. Nothing was sent.');
    }
    if (operation == GenerationOperation.transparent) {
      final hasAlpha = await Isolate.run(() => img.decodeImage(bytes)?.hasAlpha == true);
      if (!hasAlpha) {
        throw LLMApiException('Generation input invalid: alphaSourceRequired. Nothing was sent.');
      }
    }
  }
  // Inactive fields must disappear even from legacy caller maps; spreading
  // effective values alone would leave the caller's inactive ratio behind.
  return {
    for (final entry in (options ?? <String, dynamic>{}).entries)
      if (!schema.params.any((p) => p.key == entry.key)) entry.key: entry.value,
    for (final entry in schema.legacyOptions(effective).entries)
      if (options?.containsKey(entry.key) == true ||
          schema.fieldState(entry.key, operation) == GenerationFieldState.fixed)
        entry.key: entry.value,
  };
}
