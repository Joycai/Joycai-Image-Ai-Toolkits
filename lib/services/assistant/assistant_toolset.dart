part of 'prompt_optimizer_agent.dart';

final List<LLMTool> _tools = [
  LLMTool(
    name: 'list_reference_images',
    description:
        'List the reference images the user attached to this '
        'session. Returns a JSON array of {id, name, size_kb} objects.',
    parameters: {'type': 'object', 'properties': <String, dynamic>{}},
  ),
  LLMTool(
    name: 'view_image',
    description:
        'Look at one reference image, identified by its id from '
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
    description:
        'Deliver an optimized prompt to the user. This is the ONLY '
        'way to deliver a result — never paste the final prompt as plain '
        'chat text. Call it again with a full revised prompt whenever the '
        'user asks for changes.',
    parameters: {
      'type': 'object',
      'properties': {
        'prompt': {'type': 'string', 'description': 'The complete optimized prompt text.'},
        'note': {
          'type': 'string',
          'description': 'Optional one-sentence summary of what was changed or emphasized.',
        },
      },
      'required': ['prompt'],
    },
  ),
  LLMTool(
    name: 'ask_user',
    description:
        'Ask the user 1-4 structured clarifying questions and STOP. '
        'The turn pauses until the user answers; their choices arrive as '
        'this tool\'s result. Use it only when ambiguity genuinely blocks '
        'the work — prefer it over guessing, but never ask what you can '
        'infer. Offer concrete options. It must be the ONLY tool call in the '
        'message: a question batched with any other call is rejected and '
        'never reaches the user.',
    parameters: {
      'type': 'object',
      'properties': {
        'questions': {
          'type': 'array',
          'description': '1 to 4 questions.',
          'items': {
            'type': 'object',
            'properties': {
              'header': {
                'type': 'string',
                'description': 'Very short label (2-3 words) shown as the question title.',
              },
              'question': {'type': 'string', 'description': 'The full question text.'},
              'multi_select': {
                'type': 'boolean',
                'description': 'Allow choosing several options. Default false.',
              },
              'options': {
                'type': 'array',
                'description':
                    '2 to 4 concrete choices. The user can always add free text instead.',
                'items': {
                  'type': 'object',
                  'properties': {
                    'label': {'type': 'string', 'description': 'Short choice text.'},
                    'description': {
                      'type': 'string',
                      'description': 'Optional one-line explanation of this choice.',
                    },
                  },
                  'required': ['label'],
                },
              },
            },
            'required': ['header', 'question', 'options'],
          },
        },
      },
      'required': ['questions'],
    },
  ),
];

final List<LLMTool> _knowledgeTools = [
  LLMTool(
    name: 'list_knowledge_files',
    description:
        'List knowledge-base markdown files and subdirectories. '
        'Returns {files:[{path, size_kb, is_dir}]}. Pass "dir" (a relative '
        'path from a previous listing) to descend into a subdirectory.',
    parameters: {
      'type': 'object',
      'properties': {
        'dir': {
          'type': 'string',
          'description': 'Optional subdirectory (relative path). Omit for the root.',
        },
      },
    },
  ),
  LLMTool(
    name: 'read_knowledge_file',
    description:
        'Read one knowledge file by its relative path. A file that '
        'fits the remaining context comes back whole (total_pages: 1); a '
        'larger one is split, and the result carries page/total_pages — '
        'request further pages only when you actually need them. How much '
        'fits depends on how full the conversation already is, so total_pages '
        'may differ between reads of the same file. Read selectively: '
        'list_knowledge_files reports size_kb, and loading rules you do not '
        'need costs context you will want later. Never re-read a page that is '
        'already in the conversation.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'Relative path exactly as shown by list_knowledge_files or the file map.',
        },
        'page': {'type': 'integer', 'description': '1-based page number, defaults to 1.'},
      },
      'required': ['path'],
    },
  ),
];

/// Write tools, added only in [AssistantMode.knowledgeEdit].
///
/// Deliberately just one tool, and no delete: the mode's invariant is that it
/// can only add or replace content, always behind a user-approved preview,
/// and can never destroy data.
final List<LLMTool> _knowledgeWriteTools = [
  LLMTool(
    name: 'write_knowledge_file',
    description:
        'Propose creating, rewriting or extending one knowledge-base '
        'markdown file. The edit is STAGED for the user to review and approve '
        '— it is NOT written to disk by this call. Three modes: '
        '"replace_section" (default choice for changing existing rules) '
        'replaces ONE section — the heading line you name in "section" and '
        'everything under it up to the next heading of the same or higher '
        'level — with "content"; "append" adds "content" at the end of that '
        'section, or at the end of the file when "section" is omitted; '
        '"replace_file" replaces the whole file and needs the COMPLETE new '
        'content — use it only for a new file or a restructure. Omitting '
        '"mode" means replace_section when "section" is given, replace_file '
        'otherwise. Before touching an existing file you '
        'must read it first with read_knowledge_file. Whenever you add or '
        'rename a file, also update the entry file (README.md) so the file '
        'map keeps matching the real tree.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'Relative path from the knowledge base root. Must end in .md.',
        },
        'content': {
          'type': 'string',
          'description':
              'For replace_file: the complete new file. For '
              'replace_section: the complete new section, heading line '
              'included (omit the heading to keep the original one). For '
              'append: the lines to add.',
        },
        'mode': {
          'type': 'string',
          'enum': ['replace_file', 'replace_section', 'append'],
          'description':
              'What "content" replaces. Omitted: replace_section '
              'when "section" is given, else replace_file.',
        },
        'section': {
          'type': 'string',
          'description':
              'For replace_section (required) and append '
              '(optional): the heading line exactly as the file spells it, '
              'e.g. "## Lighting".',
        },
        'note': {
          'type': 'string',
          'description': 'Optional one-sentence summary of what this edit changes and why.',
        },
      },
      'required': ['path', 'content'],
    },
  ),
];

final List<LLMTool> _noteTools = [
  LLMTool(
    name: 'read_note',
    description:
        'Read back the full findings of an earlier delegate run in '
        'this conversation. Large notes are paged — request further pages '
        'only when needed. The summary you already have is usually enough; '
        'read the note when you need exact wording or details it omitted.',
    parameters: {
      'type': 'object',
      'properties': {
        'note_id': {'type': 'integer', 'description': 'The note_id a delegate result returned.'},
        'page': {'type': 'integer', 'description': '1-based page number, defaults to 1.'},
      },
      'required': ['note_id'],
    },
  ),
];
