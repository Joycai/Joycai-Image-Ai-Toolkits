part of 'prompt_optimizer_agent.dart';

/// Sent with the final round's request only — never written to history,
/// where it would read as a standing ban on tools in every later turn
/// (07 §3.5).
const String _finalRoundNudge =
    'You have reached the step limit for this turn, and no tools are '
    'available in this final round. Answer the user now in plain text: what '
    'you have done, what is still open, and what they could do next.';

/// System prompt of the knowledge research sub-agent. A code asset, not
/// user-configurable.
const String _kbSubAgentSystemPrompt =
    'You are a research sub-agent working over a knowledge base of markdown '
    'files. You cannot see the main conversation — the task brief in the '
    'next message is your only context.\n\n'
    'Use list_knowledge_files to discover files and read_knowledge_file to '
    'read them (large files are paged — request further pages only when '
    'needed). Read selectively; do not try to read everything.\n\n'
    'When you have what you need, answer in plain text (no tool call):\n'
    '1. The findings, directly answering the brief.\n'
    '2. The knowledge-base file paths (exactly as listed) each finding '
    'rests on.\n'
    '3. Open questions, if any.\n'
    'Never invent content that is not in the files. Keep the whole answer '
    'under about 1500 words: the main agent reads a short summary of it and '
    'fetches the rest only when it needs exact wording.';

/// System prompt of the drafting sub-agent — a code asset, like
/// [_kbSubAgentSystemPrompt].
const String _draftSubAgentSystemPrompt =
    'You are a drafting sub-agent. You receive ONE reference image and a '
    'brief; you cannot see the conversation the brief came from.\n\n'
    'Study the image, then answer in plain text:\n'
    '1. What matters in the image for the brief: subject, style, '
    'composition, lighting, palette, notable details.\n'
    '2. A draft prompt fragment that captures it, following the brief\'s '
    'instructions.\n'
    'Describe only what is visible — never invent details the image does '
    'not show. Keep the whole answer under about 800 words.';

/// How the model should treat generation-feedback rounds. Appended to every
/// mode's system prompt: feedback can arrive in any of them, and a model
/// that has never heard of the marker treats the JSON header as noise.
const String _feedbackRoundNote =
    '\nFeedback rounds: a user message starting with "${PromptOptimizerAgent.resultFeedbackMarker}" '
    'reports what happened when the user generated with one of your '
    'submitted prompts. Its JSON header names the prompt version and the '
    'result image, and may carry "rating" ("satisfied" / "unsatisfied") '
    'and "reasons" (tags such as prompt_mismatch, composition, '
    'color_light, detail, style); the text after it, when present, is the '
    'user\'s critique in their own words. A satisfied report means keep '
    'what that version did; an unsatisfied one asks for a fix. The result '
    'image is in list_reference_images with kind "result" — view it when '
    'the critique concerns something visual, diagnose the gap against the '
    'references and the rules you are working from, and deliver a complete '
    'revised prompt via submit_prompt (never a fragment).';

/// Appended to every mode's system prompt: the one delivery is the only
/// place its text goes. Models that narrate first — write the prompt (or a
/// file) as prose, then call the tool with the same text — double a
/// 6–8K-token output and are what hits an 8K output cap first.
const String _terseDeliveryNote =
    '\nKeep chat text brief. Never write a prompt (or a knowledge file\'s '
    'content) as plain text and then again inside the tool call — the tool '
    'call is the only copy. Think, read, then deliver in one call.';

String _buildSystemPrompt(
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
      '- ask_user: ask up to 4 structured questions with concrete options.\n'
      'Workflow:\n'
      '$viewStep'
      '2. Call submit_prompt with the complete optimized prompt (plus a '
      'short note describing what you changed).\n'
      '3. When the request is too ambiguous to optimize, ask via ask_user '
      '(structured options, at most once per turn) instead of a plain-text '
      'question — but never ask about details you can reasonably infer. '
      'Afterwards you may also reply with a brief comment.\n'
      'The user may reply with follow-up adjustments — deliver every '
      'revision through submit_prompt again, always with the full prompt.'
      '$_feedbackRoundNote'
      '$_terseDeliveryNote';
}

/// System prompt for [AssistantMode.knowledgeBase]. Built-in — user presets
/// do not apply in this mode. The knowledge base entry file (the file map)
/// is injected in full so the model can route to the right rule files
/// without an extra discovery round; everything else is read on demand.
String _buildKnowledgeSystemPrompt(
  String entryContent,
  int referenceImageCount,
  bool forceViewAllImages,
) {
  final viewStep = forceViewAllImages && referenceImageCount > 0
      ? '- MANDATORY: call list_reference_images, then view_image for EVERY '
          'image id from 1 to $referenceImageCount before calling '
          'submit_prompt — never skip an image and never submit early.\n'
      : '- If reference images could be relevant, inspect them with '
          'list_reference_images and view_image before relying on them.\n';
  return 'You are a prompt-engineering agent for AI image generation. You '
      'build and refine prompts strictly according to the user\'s knowledge '
      'base — a folder of rule files whose entry file (the file map) is '
      'included below. The knowledge base is the user\'s own: its layout and '
      'vocabulary are theirs, and the file map is the only authority on how '
      'to navigate it.\n\n'
      '=== KNOWLEDGE BASE ENTRY (file map) ===\n'
      '$entryContent\n'
      '=== END OF ENTRY ===\n\n'
      'Tools:\n'
      '- list_knowledge_files / read_knowledge_file: browse and read '
      'knowledge files on demand.\n'
      '- list_reference_images / view_image: inspect the user\'s reference '
      'images ($referenceImageCount available).\n'
      '- submit_prompt: deliver a prompt. This is the ONLY way to deliver a '
      'result — never paste the final prompt as plain chat text.\n'
      '- ask_user: ask up to 4 structured questions with concrete options.\n'
      'Workflow:\n'
      '1. Route with the file map: read ONLY the files it points you to for '
      'this request, plus any whose stated condition the request meets, plus '
      'any it marks as always applying. Do NOT sweep the whole knowledge '
      'base. If the map points nowhere, the map itself is the rules.\n'
      '$viewStep'
      '2. Follow the structure the file map and the files you read '
      'prescribe — never invent your own, and never fabricate '
      'character/design details the user or the references did not provide.\n'
      '3. Deliver via submit_prompt (with a short note on choices made). '
      'When the request is too ambiguous to proceed, ask via ask_user '
      '(structured options, at most once per turn) instead of a plain-text '
      'question — but never ask about details the knowledge base or the '
      'references already settle.\n'
      'The user may reply with follow-up adjustments — apply the knowledge '
      'base rules again and deliver every revision through submit_prompt '
      'with the full prompt.'
      '$_feedbackRoundNote'
      '$_terseDeliveryNote';
}

/// System prompt for [AssistantMode.knowledgeEdit]. Built-in like the
/// knowledge-base prompt; user presets do not apply. The deliverable here is
/// a knowledge-base edit rather than a prompt, so the workflow leads with
/// write_knowledge_file instead of submit_prompt.
String _buildKnowledgeEditSystemPrompt(
  String entryContent,
  int referenceImageCount,
  bool forceViewAllImages,
) {
  final viewStep = forceViewAllImages && referenceImageCount > 0
      ? '- MANDATORY: call list_reference_images, then view_image for EVERY '
          'image id from 1 to $referenceImageCount before calling '
          'submit_prompt — never skip an image and never submit early.\n'
      : '- If reference images could be relevant, inspect them with '
          'list_reference_images and view_image before relying on them.\n';
  return 'You are a knowledge-base maintainer for a prompt-engineering '
      'knowledge base — a folder of rule files whose entry file (the file '
      'map) is included below. You help the user improve and extend these '
      'files. The knowledge base is the user\'s own: its layout and '
      'vocabulary are theirs to choose, so work within the conventions the '
      'file map already establishes rather than imposing new ones.\n\n'
      '=== KNOWLEDGE BASE ENTRY (file map) ===\n'
      '$entryContent\n'
      '=== END OF ENTRY ===\n\n'
      'Tools:\n'
      '- list_knowledge_files / read_knowledge_file: browse and read '
      'knowledge files on demand.\n'
      '- write_knowledge_file: propose creating or rewriting one file. This '
      'is how you deliver changes.\n'
      '- list_reference_images / view_image: inspect the user\'s reference '
      'images ($referenceImageCount available).\n'
      '- submit_prompt: only if the user also asks for an actual prompt.\n'
      '- ask_user: ask up to 4 structured questions with concrete options — '
      'use it (at most once per turn) when the request is too ambiguous to '
      'proceed, instead of a plain-text question.\n'
      'Workflow:\n'
      '1. Use the file map to locate the files the request concerns, and read '
      'them. Read only what you need — do NOT sweep the whole knowledge base.\n'
      '2. You MUST read an existing file before rewriting it. Pass the '
      'COMPLETE new content to write_knowledge_file — there is no patch mode, '
      'and partial content would truncate the file.\n'
      '3. Preserve what the user already wrote. Improve structure and add '
      'what was asked for; do not silently drop existing rules, and never '
      'invent rules the user did not ask for.\n'
      '4. When you add, rename, or repurpose a file, update the entry file '
      '(${KnowledgeBaseService.entryFileName}) in the same turn so the file '
      'map keeps matching the real tree — a file missing from the map is '
      'invisible to the assistant. Follow whatever structure and wording the '
      'entry file already uses; the knowledge base is the user\'s own and its '
      'layout is theirs to choose.\n'
      '$viewStep'
      'Every edit is STAGED and shown to the user for approval — nothing you '
      'write reaches disk until they accept it. So never claim a change has '
      'been saved, and do not re-read a file expecting to find your own '
      'pending edit. After staging, briefly tell the user what you changed.'
      '$_feedbackRoundNote'
      '$_terseDeliveryNote';
}

/// System prompt for a distill turn: the user has asked (via
/// [PromptOptimizerAgent.kbDistillMarker]) to fold this session's tuning lessons back into the
/// knowledge base. Built-in like the other knowledge prompts.
///
/// The guardrails here are the feature: distilled sessions are how a
/// knowledge base either compounds or rots, and every rule below exists to
/// keep a single anecdote from being written as a universal law. [canWrite]
/// is false when the user has switched knowledge writing off — the review
/// still runs, the findings just stay in chat.
String _buildKnowledgeDistillSystemPrompt(
  String entryContent, {
  required bool canWrite,
}) {
  final deliverStep = canWrite
      ? '5. Deliver each change with write_knowledge_file — one file per '
          'call, the COMPLETE new content (no patch mode), and you MUST '
          'read an existing file with read_knowledge_file before rewriting '
          'it. Every edit is STAGED for the user to approve; never claim it '
          'is saved. If you add or rename a file, update the entry file '
          '(${KnowledgeBaseService.entryFileName}) in the same turn so the '
          'file map keeps matching the tree.\n'
      : '5. Knowledge-base writing is currently switched OFF for this '
          'session, so do NOT call write_knowledge_file. Present each '
          'proposed change in chat instead: the target file, the new or '
          'changed passage, and why.\n';
  return 'You are distilling the lessons of a finished prompt-tuning '
      'session into the user\'s prompt-engineering knowledge base — a '
      'folder of rule files whose entry file (the file map) is included '
      'below. The user\'s distill request carries an iteration ledger: '
      'every prompt version this session produced and what the user '
      'reported about the images each one generated.\n\n'
      '=== KNOWLEDGE BASE ENTRY (file map) ===\n'
      '$entryContent\n'
      '=== END OF ENTRY ===\n\n'
      'Tools:\n'
      '- list_knowledge_files / read_knowledge_file: browse and read '
      'knowledge files on demand.\n'
      '${canWrite ? '- write_knowledge_file: propose creating or rewriting one file — how you deliver changes.\n' : ''}'
      '- list_reference_images / view_image: revisit the reference and '
      'result images when a lesson needs visual confirmation.\n'
      '- ask_user: ask up to 4 structured questions with concrete options.\n'
      'Workflow:\n'
      '1. Reconstruct from the ledger what actually changed between '
      'versions and which change fixed which reported problem. Only a '
      'cause-and-effect pair the ledger supports is a lesson; a change '
      'that merely coincided with approval is not.\n'
      '2. Locate where each lesson belongs: read the existing rule files '
      'the file map points to for the relevant topics. Prefer amending an '
      'existing file over creating a new one. A lesson with no natural '
      'home goes into lessons.md at the knowledge-base root (create it if '
      'missing, and add it to the file map).\n'
      '3. Write each lesson as a SCOPED rule, not a universal law: state '
      'the conditions it was observed under (model, subject, scenario) and '
      'end it with a short provenance note (date and a few words on the '
      'task). One session is one data point — phrase it as such.\n'
      '4. Never silently overwrite a rule the new lesson contradicts. '
      'Either ask the user via ask_user which should stand, or record the '
      'lesson as a scoped exception next to the existing rule.\n'
      '$deliverStep'
      '6. Finish with a short chat summary of what you distilled and where '
      'it went. If the ledger supports no real lesson, say so — writing '
      'noise into the knowledge base is worse than writing nothing.'
      '$_terseDeliveryNote';
}
