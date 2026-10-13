import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../tasks/generation_submission_error.dart';
import '../tasks/generation_submission_service.dart';

/// The SDK owns protocol negotiation and transport; the app owns every tool's
/// business rules. Task handles are ordinary tool results, not MCP task extensions.
class ImageMcpServer {
  ImageMcpServer({required this.generation});
  final GenerationSubmissionService generation;
  StreamableMcpServer? _transport;
  int? get port => _transport?.boundPort;

  Future<void> start({required int port, required String token}) async {
    if (_transport != null) throw StateError('MCP server already running');
    if (token.trim().isEmpty) throw ArgumentError('MCP requires a nonempty bearer token');
    final server = StreamableMcpServer(
      serverFactory: (_) => createServer(),
      host: '127.0.0.1',
      port: port,
      path: '/mcp',
      enableJsonResponse: true,
      allowedHosts: const {'127.0.0.1', 'localhost'},
      // Browser clients are not enabled in stage one. Authentication below
      // also rejects every Origin, including the SDK's loopback default.
      allowedOrigins: const {},
      authenticator: (request) {
        if (request.headers.value('origin') != null) return false;
        if (request.method == 'POST' &&
            (request.contentLength < 0 || request.contentLength > 1024 * 1024)) {
          return false;
        }
        return _sameSecret(request.headers.value('authorization') ?? '', 'Bearer $token');
      },
    );
    await server.start();
    _transport = server;
  }

  Future<void> stop() async {
    final transport = _transport;
    _transport = null;
    await transport?.stop();
  }

  static bool _sameSecret(String a, String b) {
    var difference = a.length ^ b.length;
    for (var i = 0; i < b.length; i++) {
      difference |= (i < a.length ? a.codeUnitAt(i) : 0) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }

  McpServer createServer() {
    final server = McpServer(
      const Implementation(name: 'joycai-images', version: '1.0.0'),
      options: const McpServerOptions(protocol: McpProtocol.stable),
    );
    void tool(
      String name,
      String description,
      Map<String, dynamic> properties,
      List<String> required,
      Future<Map<String, dynamic>> Function(Map<String, dynamic>) run, {
      bool readOnly = true,
      bool image = false,
    }) {
      server.registerTool(
        name,
        description: description,
        inputSchema: ToolInputSchema.fromJson({
          'type': 'object',
          'properties': properties,
          'required': required,
          'additionalProperties': false,
        }),
        annotations: ToolAnnotations(
          readOnlyHint: readOnly,
          destructiveHint: false,
          idempotentHint: true,
          openWorldHint: !readOnly,
        ),
        callback: (args, extra) async {
          try {
            final result = await run(args);
            if (image) {
              final data = result.remove('data') as String;
              return CallToolResult(
                structuredContent: result,
                content: [
                  TextContent(text: jsonEncode(result)),
                  ImageContent(data: data, mimeType: result['mimeType'] as String),
                ],
              );
            }
            return CallToolResult.fromStructuredContent(result);
          } on GenerationSubmissionError catch (e) {
            return _failure(e);
          } catch (_) {
            return _failure(
              const GenerationSubmissionError(
                'operationFailed',
                'The operation could not be completed. Check application settings and retry the same requestId.',
              ),
            );
          }
        },
      );
    }

    const task = {'type': 'string', 'minLength': 1, 'maxLength': 128};
    const model = {'type': 'integer', 'minimum': 1};
    tool(
      'list_models',
      'List configured image models. Use modelId, not the provider model name.',
      {},
      [],
      (_) => generation.listModels(),
    );
    tool(
      'get_model_schema',
      'Discover valid typed parameters, defaults, pixel constraints and reference/edit limits before generation.',
      {'modelId': model},
      ['modelId'],
      (args) => generation.modelSchema(args['modelId'] as int),
    );
    tool(
      'generate_image',
      'Queue text-to-image or reference/edit generation. This can incur provider charges. '
          'Inspect get_model_schema first. Reuse requestId for retries; poll get_generation for results. '
          'Parameters are request-local. Video, layers and transparent editing are not exposed.',
      {
        'requestId': task,
        'modelId': model,
        'prompt': {'type': 'string', 'minLength': 1, 'maxLength': 32000},
        'defaults': {
          'type': 'string',
          'enum': ['model', 'saved'],
          'default': 'model',
        },
        'parameters': {
          'type': 'object',
          'description':
              'Map schema keys to typed values, e.g. {"quality":{"kind":"choice","value":"high"}}.',
        },
        'references': {
          'type': 'array',
          'maxItems': 16,
          'items': {
            'oneOf': [
              {
                'type': 'object',
                'properties': {
                  'path': {'type': 'string'},
                },
                'required': ['path'],
                'additionalProperties': false,
              },
              {
                'type': 'object',
                'properties': {
                  'taskId': task,
                  'outputId': {'type': 'integer', 'minimum': 0},
                },
                'required': ['taskId', 'outputId'],
                'additionalProperties': false,
              },
            ],
          },
        },
      },
      ['requestId', 'modelId', 'prompt'],
      generation.submit,
      readOnly: false,
    );
    tool(
      'get_generation',
      'Poll a durable generation. Failed or cancelled tasks may still contain usable outputs.',
      {'taskId': task},
      ['taskId'],
      (args) => generation.status(args['taskId'] as String),
    );
    tool(
      'cancel_generation',
      'Stop queued or running generation. Retains saved outputs; does not guarantee a provider refund.',
      {'taskId': task},
      ['taskId'],
      (args) => generation.cancel(args['taskId'] as String),
      readOnly: false,
    );
    tool(
      'read_generation_image',
      'Read a registered output. Defaults to a 1024px preview; preview=false returns original bytes up to 20 MiB.',
      {
        'taskId': task,
        'outputId': {'type': 'integer', 'minimum': 0},
        'preview': {'type': 'boolean', 'default': true},
      },
      ['taskId', 'outputId'],
      (args) => generation.readImage(
        args['taskId'] as String,
        args['outputId'] as int,
        preview: args['preview'] as bool? ?? true,
      ),
      image: true,
    );
    server.registerResourceTemplate(
      'generated-image',
      ResourceTemplateRegistration(
        'joycai://generations/{taskId}/images/{outputId}',
        listCallback: null,
      ),
      (description: 'Original image output from an MCP generation.', mimeType: null),
      (uri, variables, extra) async {
        try {
          final segments = uri.pathSegments;
          final result = await generation.readImage(
            segments[0],
            int.parse(segments[2]),
            preview: false,
          );
          return ReadResourceResult(
            contents: [
              BlobResourceContents(
                uri: uri.toString(),
                blob: result['data'] as String,
                mimeType: result['mimeType'] as String,
              ),
            ],
          );
        } on GenerationSubmissionError catch (e) {
          throw McpError(ErrorCode.invalidParams.value, e.message);
        } catch (_) {
          throw McpError(ErrorCode.internalError.value, 'The output image could not be read.');
        }
      },
    );
    return server;
  }

  static CallToolResult _failure(GenerationSubmissionError error) => CallToolResult(
    isError: true,
    structuredContent: {'error': error.toJson()},
    content: [
      TextContent(text: jsonEncode({'error': error.toJson()})),
    ],
  );
}
