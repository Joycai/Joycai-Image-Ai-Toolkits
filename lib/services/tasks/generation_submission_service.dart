import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/app_paths.dart';
import '../../core/image_magic.dart';
import '../../core/safety_settings.dart';
import '../../models/llm_model.dart';
import '../db/database_service.dart';
import '../db/repositories/mcp_request_repository.dart';
import '../db/repositories/task_repository.dart';
import '../llm/generation/generation_preferences.dart';
import '../llm/generation/generation_profile_store.dart';
import '../llm/generation/generation_request.dart';
import '../llm/generation/generation_schema.dart';
import '../llm/generation/generation_value.dart';
import '../llm/llm_config_resolver.dart';
import '../llm/llm_dispatcher.dart';
import '../llm/model_routes.dart';
import 'external_generation_files.dart';
import 'generation_submission_error.dart';
import 'task_queue_service.dart';

/// Non-UI generation API. No workbench selection/draft is mutated by a caller.
class GenerationSubmissionService {
  GenerationSubmissionService({
    required this.queue,
    DatabaseService? database,
    this.stagingRoot,
    required this.allowedRoots,
  }) : _db = database ?? DatabaseService();
  final DatabaseService _db;
  final TaskQueueService queue;
  final String? stagingRoot;
  final List<String> Function() allowedRoots;
  Future<void> _submissionTail = Future.value();
  int _waiting = 0;

  Future<({LLMModel model, RoutedChannel route, GenerationSchema schema})> _resolve(int id) async {
    final model = (await _db.getModels()).where((m) => m.id == id).firstOrNull;
    if (model == null || model.channelId == null) {
      throw const GenerationSubmissionError(
        'modelNotFound',
        'The configured model no longer exists.',
      );
    }
    final channel = await _db.getChannel(model.channelId!);
    if (channel == null) {
      throw const GenerationSubmissionError(
        'channelNotFound',
        'Configure a channel for this model.',
      );
    }
    final route = RoutedChannel.forModel(channel, model);
    if (route.missing) {
      throw const GenerationSubmissionError('routeMissing', 'The model route is not configured.');
    }
    final schema = LLMDispatcher.generationSchemaFor(
      channelType: route.channelType,
      modelId: model.modelId,
      tag: model.tag,
      wireProtocol: route.wireProtocol,
      profile: await GenerationProfileStore.read(_db, id),
    );
    if (!schema.capabilities.isImageGenerator || schema.isVideo) {
      throw const GenerationSubmissionError(
        'unsupportedModel',
        'Choose an image generation model. Video and text-only models are not supported.',
      );
    }
    try {
      await LLMConfigResolver(database: _db).resolveConfig(id);
    } on LLMConfigException {
      throw const GenerationSubmissionError(
        'credentialsMissing',
        'Configure credentials for this model in the application.',
      );
    }
    return (model: model, route: route, schema: schema);
  }

  Future<Map<String, dynamic>> listModels() async {
    final result = <Map<String, dynamic>>[];
    for (final model in await _db.getModels()) {
      try {
        final resolved = await _resolve(model.id!);
        result.add({
          'modelId': model.id,
          'name': model.modelName,
          'upstreamModel': model.modelId,
          'channelId': model.channelId,
          'supportsReferences': resolved.schema.capabilities.supportsReferenceImages,
          'ready': resolved.schema.configurationDiagnostics.isEmpty,
          'diagnostics': [for (final d in resolved.schema.configurationDiagnostics) d.code],
        });
      } on GenerationSubmissionError catch (e) {
        if (e.code != 'unsupportedModel') {
          result.add({
            'modelId': model.id,
            'name': model.modelName,
            'ready': false,
            'error': e.toJson(),
          });
        }
      }
    }
    return {'models': result};
  }

  Future<Map<String, dynamic>> modelSchema(int id) async {
    final resolved = await _resolve(id);
    final schema = resolved.schema;
    return {
      'modelId': id,
      'schemaVersion': GenerationSchema.version,
      'operations': [
        'text-to-image',
        if (schema.capabilities.supportsReferenceImages) 'reference/edit',
      ],
      'maxReferenceImages': schema.capabilities.maxReferenceImages,
      'applicationReferenceLimit': 16,
      'diagnostics': [for (final d in schema.configurationDiagnostics) d.code],
      'parameters': [
        for (final param in schema.params)
          if (param.key != 'imageTask')
            {
              'key': param.key,
              'type': param.valueType.name,
              'default': param.defaultValue.toJson(),
              'choices': [
                for (final choice in param.legacy.options) param.decode(choice.value).toJson(),
              ],
              if (param.legacy.min != null) 'minimum': param.legacy.min,
              if (param.legacy.max != null) 'maximum': param.legacy.max,
              if (param.legacy.sizeRules case final rules?)
                'sizeRules': {
                  'edgeStep': rules.edgeStep,
                  'minEdge': rules.minEdge,
                  'maxEdge': rules.maxEdge,
                  'maxRatio': rules.maxRatio,
                  'minPixels': rules.minPixels,
                  'maxPixels': rules.maxPixels,
                },
            },
      ],
      'parameterEncoding': 'Values use {"kind":"choice","value":"..."}, or integer/boolean/size/decimal; unset and auto have no value. Use the advertised choices.',
    };
  }

  /// Serializes the short acceptance phase, never the paid generation itself.
  Future<Map<String, dynamic>> submit(Map<String, dynamic> args) async {
    if (_waiting >= 16) {
      throw const GenerationSubmissionError('busy', 'Too many submissions; retry later.');
    }
    _waiting++;
    final previous = _submissionTail;
    final done = Completer<void>();
    _submissionTail = done.future;
    try {
      await previous;
      return await _submit(args);
    } finally {
      _waiting--;
      done.complete();
    }
  }

  Future<Map<String, dynamic>> _submit(Map<String, dynamic> args) async {
    await queue.ready;
    const keys = {'requestId', 'modelId', 'prompt', 'parameters', 'references', 'defaults'};
    if (args.keys.any((key) => !keys.contains(key))) {
      throw const GenerationSubmissionError('invalidArguments', 'Unknown generation argument.');
    }
    final key = args['requestId'];
    final id = args['modelId'];
    final prompt = args['prompt'];
    if (key is! String ||
        key.isEmpty ||
        key.length > 128 ||
        id is! int ||
        prompt is! String ||
        prompt.trim().isEmpty ||
        prompt.length > 32000) {
      throw const GenerationSubmissionError(
        'invalidArguments',
        'Provide requestId (1–128 characters), modelId and a nonempty prompt (at most 32000 characters).',
      );
    }
    final mode = args['defaults'] ?? 'model';
    if (mode != 'model' && mode != 'saved') {
      throw const GenerationSubmissionError('invalidDefaults', 'defaults must be model or saved.');
    }
    final digest = sha256.convert(utf8.encode(jsonEncode(_canonical(args)))).toString();
    final requests = McpRequestRepository(db: _db);
    final existing = await requests.find(key);
    if (existing != null) {
      if (existing['digest'] != digest) {
        throw const GenerationSubmissionError(
          'requestConflict',
          'This requestId was already used with different inputs.',
        );
      }
      return status(existing['task_id']! as String);
    }
    if (queue.queue
            .where((t) => t.status == TaskStatus.pending || t.status == TaskStatus.processing)
            .length >=
        100) {
      throw const GenerationSubmissionError(
        'queueFull',
        'The generation queue is full. Retry later.',
      );
    }
    final resolved = await _resolve(id);
    final schema = resolved.schema;
    final refs = args['references'] ?? <dynamic>[];
    if (refs is! List || refs.length > 16) {
      throw const GenerationSubmissionError(
        'invalidReferences',
        'references must be an array with at most 16 images.',
      );
    }
    final operation = refs.isEmpty
        ? GenerationOperation.textImage
        : schema.contract.subjectReferences
        ? GenerationOperation.subjectImage
        : GenerationOperation.editImage;
    final values = <String, GenerationValue>{};
    Map<String, dynamic> saved = {};
    if (mode == 'saved') {
      final raw = await _db.getSetting('workbench_image_params');
      if (raw != null) saved = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    }
    final family = LLMDispatcher.descriptorFor(
      channelType: resolved.route.channelType,
      modelId: resolved.model.modelId,
      tag: resolved.model.tag,
      wireProtocol: resolved.route.wireProtocol,
    ).family.name;
    final base = GenerationPreferences.base(
      model: id,
      channel: resolved.model.channelId,
      protocol: schema.protocol?.id,
    );
    for (final param in schema.params) {
      final stored =
          saved[GenerationPreferences.key(base, operation, param.key)] ??
          saved['$family.${param.key}'];
      values[param.key] = stored is String && param.legacy.isValid(stored)
          ? param.decode(stored)
          : param.defaultValue;
      // Only ordinary image generation is exposed in stage one.
      if (param.key == 'imageTask') values[param.key] = param.defaultValue;
    }
    final overrides = args['parameters'] ?? <String, dynamic>{};
    if (overrides is! Map) {
      throw const GenerationSubmissionError('invalidParameter', 'parameters must be an object.');
    }
    for (final entry in overrides.entries) {
      final param = schema.params
          .where((p) => p.key == entry.key && p.key != 'imageTask')
          .firstOrNull;
      if (param == null ||
          entry.value is! Map ||
          (entry.value as Map).keys.any((k) => k != 'kind' && k != 'value')) {
        throw GenerationSubmissionError(
          'invalidParameter',
          'Unsupported parameter or value representation.',
          field: entry.key.toString(),
        );
      }
      try {
        final value = GenerationValue.fromJson(Map<String, dynamic>.from(entry.value as Map));
        if (!param.accepts(value)) throw const FormatException();
        values[param.key] = value;
      } catch (_) {
        throw GenerationSubmissionError(
          'invalidParameter',
          'Value is not allowed by this model schema.',
          field: param.key,
        );
      }
    }
    final media = [
      for (var i = 0; i < refs.length; i++)
        const GenerationMedia(GenerationMediaRole.reference, ''),
    ];
    final diagnostics = schema.validate(values, media);
    if (diagnostics.isNotEmpty) {
      throw GenerationSubmissionError(
        diagnostics.first.code,
        'Generation inputs do not satisfy the model schema.',
        field: diagnostics.first.field,
      );
    }
    final taskId = const Uuid().v4();
    final root = stagingRoot ?? p.join(await AppPaths.getDataDirectory(), 'mcp-inputs');
    final directory = Directory(p.join(root, taskId));
    var accepted = false;
    try {
      final paths = <String>[];
      for (var i = 0; i < refs.length; i++) {
        final ref = refs[i];
        if (ref is! Map) {
          throw const GenerationSubmissionError(
            'invalidReference',
            'Each reference needs path, or taskId and outputId.',
          );
        }
        String source;
        var registered = false;
        if (ref.keys.length == 1 && ref['path'] is String) {
          source = ref['path'] as String;
          if (!p.isAbsolute(source)) {
            throw const GenerationSubmissionError(
              'invalidReference',
              'Reference paths must be absolute.',
            );
          }
        } else if (ref.keys.length == 2 && ref['taskId'] is String && ref['outputId'] is int) {
          source = await outputPath(ref['taskId'] as String, ref['outputId'] as int);
          registered = true;
        } else {
          throw const GenerationSubmissionError(
            'invalidReference',
            'Use path, or taskId and outputId.',
          );
        }
        paths.add(
          await ExternalGenerationFiles.stage(
            source,
            allowedRoots(),
            directory,
            i,
            registeredOutput: registered,
          ),
        );
      }
      final request = GenerationRequest(
        prompt: prompt,
        operation: operation,
        values: schema.effective(values, operation),
        media: [for (final path in paths) GenerationMedia(GenerationMediaRole.reference, path)],
        modelId: resolved.model.modelId,
        modelRowId: id,
        channelRowId: resolved.model.channelId,
        channelType: resolved.route.channelType,
        protocolId: schema.protocol?.id,
        profileId: schema.profileId,
      );
      final rawSafety = await _db.getSetting('safety_thresholds');
      final task = TaskItem(
        id: taskId,
        imagePaths: paths,
        modelId: resolved.model.modelName,
        modelDbId: id,
        parameters: {
          GenerationRequest.taskKey: request.toJson(),
          'origin': 'mcp',
          'imagePrefix': await _db.getSetting('image_prefix') ?? 'result',
          'outputDirectory': await _db.getSetting('output_directory'),
          'retryCount': int.tryParse(await _db.getSetting('retry_count') ?? '') ?? 0,
          'saveGenerationText': await _db.getSetting('save_generation_text') == 'true',
          'compressReferenceImages':
              await _db.getSetting('workbench_compress_reference_images') == 'true',
          SafetySettings.paramKey: rawSafety == null
              ? SafetySettings.defaults()
              : SafetySettings.normalize(jsonDecode(rawSafety) as Map),
        },
        useStream: await _db.getSetting('workbench_use_stream') != 'false',
      );
      await requests.insert(key, digest, task);
      accepted = true;
      await queue.enqueuePersistedTask(task);
      return await status(taskId);
    } on FileSystemException {
      throw const GenerationSubmissionError(
        'fileUnavailable',
        'A reference image or staging folder could not be read or written.',
      );
    } finally {
      if (!accepted && await directory.exists()) await directory.delete(recursive: true);
    }
  }

  Future<TaskItem> task(String id) async {
    final task = await TaskRepository(db: _db).getTask(id);
    if (task == null || task.parameters['origin'] != 'mcp') {
      throw const GenerationSubmissionError(
        'taskNotFound',
        'This MCP generation is unavailable or its history was removed.',
      );
    }
    return task;
  }

  Future<Map<String, dynamic>> status(String id) async {
    final item = await task(id);
    final request = GenerationRequest.fromTask(item.parameters)!;
    return {
      'taskId': id,
      'status': item.status.name,
      'modelId': item.modelDbId,
      'operation': request.operation.name,
      'parameters': {for (final e in request.values.entries) e.key: e.value.toJson()},
      'outputs': [
        for (var i = 0; i < item.resultPaths.length; i++)
          await _describeOutput(id, i, item.resultPaths[i]),
      ],
      'warnings': item.warnings,
      'error': item.error,
      if (item.status == TaskStatus.cancelled)
        'cancellationNotice':
            'Saved outputs are retained. Cancellation does not imply an upstream refund.',
    };
  }

  Future<Map<String, dynamic>> _describeOutput(String id, int index, String path) async {
    final result = <String, dynamic>{
      'outputId': index,
      'path': path,
      'uri': 'joycai://generations/$id/images/$index',
    };
    try {
      final safePath = await outputPath(id, index);
      final bytes = await ExternalGenerationFiles.read(safePath);
      result.addAll({
        'available': true,
        'byteLength': bytes.length,
        'mimeType': imageMimeFromBytes(bytes),
        ...await ExternalGenerationFiles.dimensions(bytes),
      });
    } on GenerationSubmissionError catch (e) {
      result.addAll({'available': false, 'error': e.toJson()});
    } on FileSystemException {
      result.addAll({
        'available': false,
        'error': {'code': 'outputUnavailable', 'message': 'The output file is no longer readable.'},
      });
    }
    return result;
  }

  Future<Map<String, dynamic>> cancel(String id) async {
    await task(id);
    await queue.cancelTask(id);
    return status(id);
  }

  Future<String> outputPath(String id, int output) async {
    final item = await task(id);
    if (output < 0 || output >= item.resultPaths.length) {
      throw const GenerationSubmissionError(
        'outputNotFound',
        'No such output exists for this generation.',
      );
    }
    final path = item.resultPaths[output];
    if (await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.file) {
      throw const GenerationSubmissionError(
        'outputUnavailable',
        'The output was moved, removed or replaced by a link.',
      );
    }
    if (await File(path).resolveSymbolicLinks() != p.normalize(p.absolute(path))) {
      throw const GenerationSubmissionError(
        'outputUnavailable',
        'The output path was replaced by a link.',
      );
    }
    return path;
  }

  Future<Map<String, dynamic>> readImage(String id, int output, {bool preview = true}) async {
    final bytes = await ExternalGenerationFiles.read(await outputPath(id, output));
    await ExternalGenerationFiles.dimensions(bytes);
    final mime = imageMimeFromBytes(bytes);
    if (mime == null) {
      throw const GenerationSubmissionError(
        'invalidImage',
        'The output is no longer a valid image.',
      );
    }
    final content = preview ? await ExternalGenerationFiles.preview(bytes) : bytes;
    final dimensions = await ExternalGenerationFiles.dimensions(content);
    return {
      'taskId': id,
      'outputId': output,
      ...dimensions,
      'mimeType': preview ? 'image/jpeg' : mime,
      'data': base64Encode(content),
      'preview': preview,
    };
  }

  static dynamic _canonical(dynamic value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }
}
