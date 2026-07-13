import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'llm/llm_service.dart';
import 'llm/llm_types.dart';

/// Kinds of entries shown in the optimizer chat transcript.
enum OptimizerEntryKind { user, assistant, tool, prompt, error }

/// One rendered line of the optimizer conversation.
class OptimizerChatEntry {
  final OptimizerEntryKind kind;
  final String text;

  /// For [OptimizerEntryKind.prompt]: 1-based version number of the staged prompt.
  final int? version;

  /// For [OptimizerEntryKind.prompt]: the model's short note about this revision.
  final String? note;

  /// For [OptimizerEntryKind.tool]: which tool ran ('list_reference_images' /
  /// 'view_image').
  final String? toolName;

  OptimizerChatEntry({
    required this.kind,
    required this.text,
    this.version,
    this.note,
    this.toolName,
  });
}

/// Conversation state for one prompt-optimization session.
///
/// Holds both the UI transcript and the raw LLM history (including tool
/// calls/results) so follow-up turns keep full context. Sessions live in
/// memory only — a task restored from the database after an app restart can
/// no longer resolve its session and fails gracefully.
class PromptOptimizerSession extends ChangeNotifier {
  static int _counter = 0;

  final String id =
      'opt_${DateTime.now().millisecondsSinceEpoch}_${_counter++}';

  List<OptimizerChatEntry> _transcript = [];
  List<OptimizerChatEntry> get transcript => _transcript;

  /// Full LLM conversation (system message excluded — it is supplied per turn
  /// so the user can switch presets mid-conversation).
  final List<LLMMessage> history = [];

  /// Paths of reference images the model has already viewed (drives the
  /// "viewed" badge in the reference panel and avoids re-attaching).
  Set<String> _viewedImagePaths = {};
  Set<String> get viewedImagePaths => _viewedImagePaths;

  /// The most recently staged optimized prompt.
  String? refinedPrompt;
  int promptVersions = 0;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  void addUserTurn(String text) {
    history.add(LLMMessage(role: LLMRole.user, content: text));
    _addEntry(OptimizerChatEntry(kind: OptimizerEntryKind.user, text: text));
  }

  void _addEntry(OptimizerChatEntry entry) {
    _transcript = [..._transcript, entry];
    notifyListeners();
  }

  void _markViewed(String path) {
    _viewedImagePaths = {..._viewedImagePaths, path};
    notifyListeners();
  }

  void _stagePrompt(String prompt, String? note) {
    refinedPrompt = prompt;
    promptVersions++;
    _addEntry(OptimizerChatEntry(
      kind: OptimizerEntryKind.prompt,
      text: prompt,
      version: promptVersions,
      note: (note == null || note.trim().isEmpty) ? null : note.trim(),
    ));
  }

  void _setRunning(bool running) {
    if (_isRunning == running) return;
    _isRunning = running;
    notifyListeners();
  }
}

/// Interactive prompt-optimization agent (tool-use loop).
///
/// The model is given three tools:
///  * `list_reference_images` — metadata of the user's reference images.
///  * `view_image`            — attach one reference image on demand, so
///                              images cost tokens only when actually needed.
///  * `submit_prompt`         — deliver an optimized prompt (the only channel
///                              for results; keeps chat text and deliverable
///                              cleanly separated).
///
/// Unlike [AiRenameAgent] this is conversational: the session accumulates
/// turns and the user can iterate ("make it more cinematic") with full
/// context preserved.
class PromptOptimizerAgent {
  static const int _maxTurns = 12;

  /// Live sessions by id, so the task-queue executor can resolve the session
  /// referenced by a queued task.
  static final Map<String, PromptOptimizerSession> sessions = {};

  static final List<LLMTool> _tools = [
    LLMTool(
      name: 'list_reference_images',
      description: 'List the reference images the user attached to this '
          'session. Returns a JSON array of {id, name, size_kb} objects.',
      parameters: {
        'type': 'object',
        'properties': <String, dynamic>{},
      },
    ),
    LLMTool(
      name: 'view_image',
      description: 'Look at one reference image, identified by its id from '
          'list_reference_images. The image is attached to the conversation '
          'right after this call. Call it once per image you need to see.',
      parameters: {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'integer',
            'description': 'The image id exactly as returned by list_reference_images.',
          },
        },
        'required': ['id'],
      },
    ),
    LLMTool(
      name: 'submit_prompt',
      description: 'Deliver an optimized prompt to the user. This is the ONLY '
          'way to deliver a result — never paste the final prompt as plain '
          'chat text. Call it again with a full revised prompt whenever the '
          'user asks for changes.',
      parameters: {
        'type': 'object',
        'properties': {
          'prompt': {
            'type': 'string',
            'description': 'The complete optimized prompt text.',
          },
          'note': {
            'type': 'string',
            'description': 'Optional one-sentence summary of what was changed or emphasized.',
          },
        },
        'required': ['prompt'],
      },
    ),
  ];

  /// Runs one agent turn: consumes the pending user message already appended
  /// to [session.history] and loops on tool calls until the model stops.
  ///
  /// [referenceImages] entries must contain `path` and `name`; ids exposed to
  /// the model are their 1-based positions in this list.
  ///
  /// [forceViewAllImages] (per-model setting) makes viewing every reference
  /// image a hard requirement before submit_prompt — for small local models
  /// that otherwise look at one image and stop.
  static Future<void> runTurn({
    required PromptOptimizerSession session,
    required dynamic modelIdentifier,
    String? systemPrompt,
    required List<Map<String, String>> referenceImages,
    bool forceViewAllImages = false,
    String? contextId,
    void Function(String message)? onLog,
    bool Function()? isCancelled,
  }) async {
    session._setRunning(true);
    // Weak local models tend to issue a single tool call per turn, so viewing
    // every reference image one by one needs list + N views + submit turns.
    final maxTurns = _maxTurns > referenceImages.length + 4
        ? _maxTurns
        : referenceImages.length + 4;
    try {
      for (int turn = 0; turn < maxTurns; turn++) {
        if (isCancelled?.call() ?? false) return;

        final LLMResponse response;
        try {
          response = await LLMService().request(
            modelIdentifier: modelIdentifier,
            messages: [
              LLMMessage(
                role: LLMRole.system,
                content: _buildSystemPrompt(
                  systemPrompt,
                  referenceImages.length,
                  forceViewAllImages,
                ),
              ),
              ...session.history,
            ],
            tools: _tools,
            contextId: contextId,
            useStream: false,
          );
        } catch (e) {
          session._addEntry(OptimizerChatEntry(
            kind: OptimizerEntryKind.error,
            text: e.toString(),
          ));
          rethrow;
        }

        if (response.toolCalls.isEmpty) {
          // Model is done: plain text is a chat reply (comment, clarifying
          // question, ...), never the deliverable itself.
          final text = response.text.trim();
          if (text.isNotEmpty) {
            session.history.add(LLMMessage(role: LLMRole.assistant, content: text));
            session._addEntry(OptimizerChatEntry(kind: OptimizerEntryKind.assistant, text: text));
          }
          return;
        }

        // Echo the assistant turn (with its tool calls) back into history.
        session.history.add(LLMMessage(
          role: LLMRole.assistant,
          content: response.text,
          toolCalls: response.toolCalls,
        ));
        if (response.text.trim().isNotEmpty) {
          session._addEntry(OptimizerChatEntry(
            kind: OptimizerEntryKind.assistant,
            text: response.text.trim(),
          ));
        }

        // Images requested this turn; attached after all tool results so the
        // history stays valid for providers whose tool results are text-only.
        final pendingViews = <Map<String, String>>[];

        for (final call in response.toolCalls) {
          if (isCancelled?.call() ?? false) return;
          final result = _executeTool(
              call, referenceImages, session, pendingViews, forceViewAllImages, onLog);
          session.history.add(LLMMessage(
            role: LLMRole.tool,
            content: jsonEncode(result),
            toolCallId: call.id,
            toolName: call.name,
          ));
        }

        for (final view in pendingViews) {
          session.history.add(LLMMessage(
            role: LLMRole.user,
            content: '[view_image result] Reference image #${view['id']} (${view['name']}) is attached.',
            attachments: [
              LLMAttachment.fromFile(File(view['path']!), _mimeTypeFor(view['path']!)),
            ],
          ));
        }
      }
      onLog?.call('Reached the maximum of $maxTurns agent turns — stopping.');
    } finally {
      session._setRunning(false);
    }
  }

  static Map<String, dynamic> _executeTool(
    LLMToolCall call,
    List<Map<String, String>> referenceImages,
    PromptOptimizerSession session,
    List<Map<String, String>> pendingViews,
    bool forceViewAllImages,
    void Function(String message)? onLog,
  ) {
    switch (call.name) {
      case 'list_reference_images':
        onLog?.call('Tool call: list_reference_images (${referenceImages.length} images)');
        session._addEntry(OptimizerChatEntry(
          kind: OptimizerEntryKind.tool,
          text: '',
          toolName: 'list_reference_images',
        ));
        if (referenceImages.isEmpty) {
          return {'images': [], 'note': 'The user attached no reference images.'};
        }
        return {
          'images': [
            for (int i = 0; i < referenceImages.length; i++)
              {
                'id': i + 1,
                'name': referenceImages[i]['name'],
                'size_kb': _fileSizeKb(referenceImages[i]['path']),
              }
          ],
        };

      case 'view_image':
        // Accept both a JSON number and a numeric string — smaller models
        // often quote integer arguments.
        final rawId = call.arguments['id'];
        final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
        if (id == null || id < 1 || id > referenceImages.length) {
          onLog?.call('Tool call rejected: unknown image id "$rawId"');
          return {
            'status': 'error',
            'message': 'Unknown id. Use an id exactly as returned by '
                'list_reference_images (1..${referenceImages.length}).',
          };
        }
        final image = referenceImages[id - 1];
        final path = image['path']!;
        onLog?.call('Tool call: view_image #$id (${image['name']})');
        final alreadyAttached = pendingViews.any((v) => v['path'] == path);
        if (session.viewedImagePaths.contains(path) || alreadyAttached) {
          return {
            'status': 'ok',
            'note': 'Image #$id was already attached earlier in this '
                'conversation — refer to that attachment.',
          };
        }
        if (!File(path).existsSync()) {
          return {
            'status': 'error',
            'message': 'Image #$id no longer exists on disk.',
          };
        }
        pendingViews.add({'id': '$id', 'name': image['name'] ?? '', 'path': path});
        session._markViewed(path);
        session._addEntry(OptimizerChatEntry(
          kind: OptimizerEntryKind.tool,
          text: image['name'] ?? '',
          toolName: 'view_image',
        ));
        final unviewed = [
          for (int i = 0; i < referenceImages.length; i++)
            if (!session.viewedImagePaths.contains(referenceImages[i]['path']))
              i + 1,
        ];
        return {
          'status': 'ok',
          'note': 'Image #$id is attached in the next message.',
          if (forceViewAllImages && unviewed.isNotEmpty)
            'reminder': 'Still unviewed image ids: ${unviewed.join(', ')}. '
                'View them all before calling submit_prompt.',
        };

      case 'submit_prompt':
        final prompt = call.arguments['prompt']?.toString() ?? '';
        if (prompt.trim().isEmpty) {
          return {
            'status': 'error',
            'message': 'The prompt argument must not be empty.',
          };
        }
        onLog?.call('Tool call: submit_prompt (v${session.promptVersions + 1}, ${prompt.length} chars)');
        session._stagePrompt(prompt, call.arguments['note']?.toString());
        return {
          'status': 'ok',
          'message': 'Prompt v${session.promptVersions} staged and shown to the user.',
        };

      default:
        return {
          'status': 'error',
          'message': 'Unknown tool "${call.name}". Available tools: '
              'list_reference_images, view_image, submit_prompt.',
        };
    }
  }

  static String _buildSystemPrompt(
    String? template,
    int referenceImageCount,
    bool forceViewAllImages,
  ) {
    final base = (template == null || template.trim().isEmpty)
        ? 'You are an expert prompt engineer for AI image and video generation.'
        : template.trim();
    // Per-model setting: smaller local models look at one image and submit
    // straight away, so viewing every image can be made a hard requirement.
    final viewStep = forceViewAllImages && referenceImageCount > 0
        ? '1. MANDATORY: first call list_reference_images, then call '
            'view_image for EVERY image id from 1 to $referenceImageCount, '
            'one call per image. You must have viewed ALL '
            '$referenceImageCount reference image(s) before calling '
            'submit_prompt — never skip an image and never submit early.\n'
        : '1. If reference images could be relevant, inspect them with '
            'list_reference_images and view_image first.\n';
    return '$base\n\n'
        '---\n'
        'You are working inside an interactive prompt-optimization chat. The '
        'user gives you a rough idea or an existing prompt and you produce a '
        'refined, high-quality prompt. There are currently '
        '$referenceImageCount reference image(s) available.\n'
        'Tools:\n'
        '- list_reference_images: list the attached reference images.\n'
        '- view_image: look at one reference image before relying on it.\n'
        '- submit_prompt: deliver an optimized prompt. This is the ONLY way to '
        'deliver a result — never paste the final prompt as plain chat text.\n'
        'Workflow:\n'
        '$viewStep'
        '2. Call submit_prompt with the complete optimized prompt (plus a '
        'short note describing what you changed).\n'
        '3. Afterwards you may reply with a brief comment, or ask one '
        'clarifying question when the request is too ambiguous to optimize.\n'
        'The user may reply with follow-up adjustments — deliver every '
        'revision through submit_prompt again, always with the full prompt.';
  }

  static int _fileSizeKb(String? path) {
    if (path == null) return 0;
    try {
      return (File(path).lengthSync() / 1024).round();
    } catch (_) {
      return 0;
    }
  }

  static String _mimeTypeFor(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.png') return 'image/png';
    if (ext == '.webp') return 'image/webp';
    if (ext == '.gif') return 'image/gif';
    return 'image/jpeg';
  }
}
