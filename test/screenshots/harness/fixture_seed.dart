// Seed data for the screenshot harness.
//
// Fidelity is the whole point: an empty database photographs as a wall of empty
// states, which would be barely more useful than not having the harness. So
// this fills in enough of every table that each screen has something to lay out.
//
// Everything here talks to `DatabaseService()` directly and never touches
// `AppState()` — the singleton must still be unbuilt when this returns.

import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
import 'package:joycai_image_ai_toolkits/models/prompt.dart';
import 'package:joycai_image_ai_toolkits/models/prompt_history_entry.dart';
import 'package:joycai_image_ai_toolkits/models/tag.dart';
import 'package:joycai_image_ai_toolkits/models/task_item.dart';
import 'package:joycai_image_ai_toolkits/services/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/knowledge_base_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:path/path.dart' as p;

import 'fixture_env.dart';

/// The anchor every seeded timestamp is measured back from.
///
/// Deliberately the real clock, not a fixed date: the task list and usage
/// screens render *relative* times ("今天", elapsed "0:26"), so a pinned anchor
/// drifts out of the present and photographs as nonsense like "-234:-16".
/// Captured once per run so all fixtures stay consistent with each other.
final DateTime kSeedNow = DateTime.now();

Future<void> seedFixtures(FixtureEnv env) async {
  final DatabaseService db = DatabaseService();

  // Image files first: task rows reference them by path.
  final _Images images = await _writeImages(env);

  await _seedSettings(db, env);
  await _seedKnowledgeBase(db, env);
  await db.addSourceDirectory(env.sourceDir.path);
  final _Catalog catalog = await _seedCatalog(db);
  await _seedPrompts(db);
  await _seedTasks(db, catalog, images);
  await _seedUsage(db, catalog);
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

Future<void> _seedSettings(DatabaseService db, FixtureEnv env) async {
  // The first saveSetting resolves DatabaseService.database, which creates the
  // schema and runs syncPresets() — so the prompt library picks up the real
  // assets/presets/prompts/*.json content for free.
  await db.saveSetting('setup_completed', 'true');

  // Without the row above, AppState.loadSettings sets setupCompleted = false
  // (app_state.dart:277) and _checkFirstRun pushes SetupWizard over every
  // screen — every shot would be the wizard.

  await db.saveSetting('locale', 'zh');
  await db.saveSetting('theme_mode', 'light');
  await db.saveSetting('is_console_expanded', 'true');
  await db.saveSetting('is_sidebar_expanded', 'true');
  // `A1 16a`'s folder column. Seeded rather than left to the default so the
  // shot pins the width the frame was drawn at.
  await db.saveSetting('sidebar_width', '236');
  await db.saveSetting('console_height', '160');
  await db.saveSetting('thumbnail_size', '150');
  await db.saveSetting('image_prefix', 'result');
  await db.saveSetting('output_directory', env.outputDir.path);
  await db.saveSetting('browser_source_directories', env.browserDir.path);
  await db.saveSetting('browser_active_directories', env.browserDir.path);
  await db.saveSetting(
    'last_prompt',
    '把这张人像换成纯白背景的证件照风格，\n'
        '保留原有的发型与面部细节，衣着改为深色正装，\n'
        '光线均匀柔和，不要产生明显的边缘锯齿。',
  );
  await db.saveSetting('last_video_prompt', '镜头缓慢推近，背景虚化，暖色调黄昏光线。');

  // Deliberately NOT seeded: `concurrency_limit`. AppState.loadSettings only
  // calls taskQueue.updateConcurrency when that row exists (app_state.dart:280),
  // and that path runs _attemptNextExecution() — which would fire real LLM
  // requests for the pending tasks seeded below.
}

// ---------------------------------------------------------------------------
// Channels / pricing groups / models
// ---------------------------------------------------------------------------

class _Catalog {
  _Catalog(this.modelIds, this.modelPks);

  /// Provider-facing model ids, for `token_usage.model_id`.
  final List<String> modelIds;

  /// Primary keys, for `token_usage.model_pk` and `TaskItem.modelDbId`.
  final List<int> modelPks;
}

Future<_Catalog> _seedCatalog(DatabaseService db) async {
  final int googleId = await db.addChannel(LLMChannel(
    displayName: 'Google AI Studio',
    endpoint: 'https://generativelanguage.googleapis.com',
    apiKey: 'fixture-key-google',
    type: Vendors.googleRest,
    tag: '官方',
    tagColor: 0xFF4285F4,
  ).toMap(includeId: false));

  final int openaiId = await db.addChannel(LLMChannel(
    displayName: '中转 · OpenAI 兼容',
    endpoint: 'https://api.example-relay.com/v1',
    apiKey: 'fixture-key-relay',
    type: Vendors.openAIRest,
    tag: '中转',
    tagColor: 0xFF00897B,
  ).toMap(includeId: false));

  final int flashFee = await db.addPricingGroup(PricingGroup(
    name: 'Gemini Flash',
    inputPrice: 0.075,
    cacheInputPrice: 0.01875,
    outputPrice: 0.30,
  ).toMap(includeId: false));

  final int proFee = await db.addPricingGroup(PricingGroup(
    name: 'Gemini Pro',
    inputPrice: 1.25,
    outputPrice: 10.0,
  ).toMap(includeId: false));

  final int perImageFee = await db.addPricingGroup(PricingGroup(
    name: '按次计费 · 图片',
    billingMode: 'request',
    requestPrice: 0.04,
  ).toMap(includeId: false));

  final List<LLMModel> models = <LLMModel>[
    LLMModel(
      modelId: 'gemini-2.5-flash-image',
      modelName: 'Nano Banana 图像生成',
      tag: ModelTag.image.value,
      channelId: googleId,
      feeGroupId: perImageFee,
      contextWindow: 1048576,
      sortOrder: 0,
    ),
    LLMModel(
      modelId: 'gemini-2.5-flash',
      modelName: 'Gemini 2.5 Flash',
      tag: ModelTag.multimodal.value,
      channelId: googleId,
      feeGroupId: flashFee,
      contextWindow: 1048576,
      sortOrder: 1,
    ),
    LLMModel(
      modelId: 'gemini-2.5-pro',
      modelName: 'Gemini 2.5 Pro',
      tag: ModelTag.refiner.value,
      channelId: googleId,
      feeGroupId: proFee,
      contextWindow: 2097152,
      sortOrder: 2,
    ),
    LLMModel(
      modelId: 'veo-3.1-generate-preview',
      modelName: 'Veo 3.1 视频生成',
      tag: ModelTag.video.value,
      channelId: googleId,
      feeGroupId: perImageFee,
      sortOrder: 3,
    ),
    LLMModel(
      modelId: 'gpt-5-chat',
      modelName: 'GPT-5 Chat',
      tag: ModelTag.chat.value,
      channelId: openaiId,
      feeGroupId: proFee,
      contextWindow: 400000,
      sortOrder: 4,
    ),
  ];

  final List<int> pks = <int>[];
  for (final LLMModel model in models) {
    pks.add(await db.addModel(model.toMap(includeId: false)));
  }
  return _Catalog(models.map((LLMModel m) => m.modelId).toList(), pks);
}

// ---------------------------------------------------------------------------
// Prompts
// ---------------------------------------------------------------------------

Future<void> _seedPrompts(DatabaseService db) async {
  final int portraitTag = await db.addPromptTag(
      PromptTag(name: '人像', color: 0xFF8E24AA, sortOrder: 0).toMap(includeId: false));
  final int productTag = await db.addPromptTag(
      PromptTag(name: '电商', color: 0xFF1E88E5, sortOrder: 1).toMap(includeId: false));
  final int styleTag = await db.addPromptTag(
      PromptTag(name: '风格化', color: 0xFFF4511E, sortOrder: 2).toMap(includeId: false));

  final List<(String, String, List<int>)> prompts = <(String, String, List<int>)>[
    (
      '证件照换底色',
      '将人物背景替换为纯白色，保留头发丝级别的边缘细节，'
          '衣着改为深色正装，光线均匀无阴影。',
      <int>[portraitTag],
    ),
    (
      '电商白底图',
      '去除背景并替换为纯白 #FFFFFF，商品居中，'
          '保留自然投影，输出方形构图，留白 8%。',
      <int>[productTag],
    ),
    (
      '胶片质感调色',
      '模拟 Portra 400 的色彩响应：肤色偏暖，'
          '高光柔和滚降，暗部保留青色倾向，加入细腻颗粒。',
      <int>[styleTag],
    ),
    (
      '人像磨皮但保留质感',
      '均匀肤色与瑕疵，但必须保留毛孔与皮肤纹理，'
          '不要产生塑料感，眼神光保持原样。',
      <int>[portraitTag, styleTag],
    ),
    (
      '批量生成场景变体',
      '保持主体不变，仅替换环境：咖啡馆、海边栈道、'
          '城市夜景霓虹，各输出一张。',
      <int>[productTag, styleTag],
    ),
  ];

  for (int i = 0; i < prompts.length; i++) {
    final (String title, String content, List<int> tags) = prompts[i];
    await db.addPrompt(
      Prompt(title: title, content: content, sortOrder: i).toMap(includeId: false),
      tagIds: tags,
    );
  }

  // Refiner system prompts. These are what the assistant's system-prompt mode
  // picks from, and without any the whole `10g` card photographs empty — an
  // unselected picker over a blank editor, which is the one arrangement that
  // says nothing about the layout.
  final List<(String, String, List<int>)> systemPrompts = <(String, String, List<int>)>[
    (
      '通用摄影增强 v3',
      '你是 Joycai 的提示词优化助手。用户会给出粗略想法或草稿提示词，'
          '你负责将其改写为可直接用于图像模型的结构化提示词。\n\n'
          '## 输出结构\n'
          '1. 任务 —— 一句话说明要生成什么。\n'
          '2. 主体设定 —— 人物 / 物体的外观、材质、姿态。\n'
          '3. 场景与镜头 —— 环境、光线、机位、焦段。\n'
          '4. 风格与画质 —— 参考风格、渲染质感、负面约束。\n\n'
          '## 规则\n'
          '- 参考图一律用文件名引用，不要描述为「图一」。\n'
          '- 保留用户明确写出的专有名词，不擅自替换。',
      <int>[portraitTag],
    ),
    (
      '电商主图规范',
      '改写为电商主图提示词：纯白底、主体居中、留白 8%，'
          '保留自然投影，禁止添加文字与水印。',
      <int>[productTag],
    ),
    (
      '风格化改写',
      '在保持构图与主体不变的前提下，把用户的想法改写成一段有明确'
          '风格参照的提示词，风格词写在最后一段。',
      <int>[styleTag],
    ),
  ];

  for (int i = 0; i < systemPrompts.length; i++) {
    final (String title, String content, List<int> tags) = systemPrompts[i];
    await db.addSystemPrompt(
      SystemPrompt(title: title, content: content, type: 'refiner', sortOrder: i)
          .toMap(includeId: false),
      tagIds: tags,
    );
  }

  for (final String entry in <String>[
    '把背景换成纯白，主体不变',
    '增加一点暖色调，模拟黄昏光线',
    '保留原始构图，只提升清晰度和对比度',
  ]) {
    await db.addPromptHistory(PromptHistoryType.image, entry);
  }
  await db.addPromptHistory(PromptHistoryType.video, '镜头缓慢推近，背景虚化');
}

// ---------------------------------------------------------------------------
// Knowledge base
// ---------------------------------------------------------------------------

/// A real folder of markdown for the assistant to read and `10h`'s tree to
/// draw. Nested two levels deep on purpose — a flat folder would photograph a
/// tree with nothing to expand, which is most of what the column does.
Future<void> _seedKnowledgeBase(DatabaseService db, FixtureEnv env) async {
  const Map<String, String> docs = <String, String>{
    'README.md': '# 知识库\n\n这是提示词助手读取的规则库。每个目录一类约束，README 是目录地图。\n',
    '01_基础规则/01a_光照与材质.md': '# 光照与材质\n\n主光方向、色温、材质反射率的写法约定。\n',
    '01_基础规则/01b_镜头语言.md': '# 镜头语言\n\n机位、焦段、景深的固定表述。\n',
    '04_模板/04_cosplay照片模版.md': '# Cosplay 照片模版\n\n四段结构：任务 / 模特设定 / 服装 / 画面要求。\n',
    '05_服装分层与材质.md': '# 服装分层与材质\n\n由外到内描述服装层次，材质写在层次之后。\n',
    '06_场景动作镜头组合库.md': '# 场景动作镜头组合库\n\n常用的场景与动作搭配，按主题分组。\n',
    '07_footwear/07a_鞋型与材质.md': '# 鞋型与材质\n\n鞋型、鞋跟高度与材质的写法。\n',
    '07_footwear/07b_叠穿袜子与高跟鞋.md': '# 叠穿袜子与高跟鞋\n\n## 二、叠穿组合\n  - 白色过膝袜 + 玛丽珍鞋：适合校园与制服主题。\n  - 黑色短袜 + 高跟鞋：注意脚踝处袜口不要压出褶皱。\n',
    '08_易错结构与修正方案.md': '# 易错结构与修正方案\n\n模型常见的误解与对应的改写方式。\n',
    '09_负面词表.md': '# 负面词表\n\n按题材分组的负面提示词。\n',
  };

  for (final MapEntry<String, String> doc in docs.entries) {
    final File file = File(p.join(env.knowledgeDir.path, doc.key));
    await file.parent.create(recursive: true);
    await file.writeAsString(doc.value);
  }

  await db.saveSetting(KnowledgeBaseService.settingKey, env.knowledgeDir.path);
}

// ---------------------------------------------------------------------------
// Tasks
// ---------------------------------------------------------------------------

Future<void> _seedTasks(DatabaseService db, _Catalog catalog, _Images images) async {
  // TaskQueueService._loadRecentTasks only reads the newest 10 rows, so keep
  // the total at or under that or the older ones simply never appear.
  final List<TaskItem> tasks = <TaskItem>[
    _task(
      id: 'fixture-task-1',
      catalog: catalog,
      modelIndex: 0,
      status: TaskStatus.completed,
      imagePaths: images.source.take(2).toList(),
      resultPaths: images.output.take(2).toList(),
      startedMinutesAgo: 240,
      durationSeconds: 47,
    ),
    _task(
      id: 'fixture-task-2',
      catalog: catalog,
      modelIndex: 0,
      status: TaskStatus.completed,
      imagePaths: images.source.skip(2).take(1).toList(),
      resultPaths: images.output.skip(2).take(1).toList(),
      startedMinutesAgo: 180,
      durationSeconds: 31,
    ),
    _task(
      id: 'fixture-task-3',
      catalog: catalog,
      modelIndex: 1,
      status: TaskStatus.failed,
      imagePaths: images.source.skip(3).take(1).toList(),
      startedMinutesAgo: 120,
      durationSeconds: 12,
      error: '429 RESOURCE_EXHAUSTED: 配额已用尽，请稍后重试',
    ),
    _task(
      id: 'fixture-task-4',
      catalog: catalog,
      modelIndex: 3,
      type: TaskType.videoGenerate,
      status: TaskStatus.completed,
      imagePaths: images.source.skip(4).take(1).toList(),
      startedMinutesAgo: 90,
      durationSeconds: 186,
    ),
    _task(
      id: 'fixture-task-5',
      catalog: catalog,
      modelIndex: 2,
      type: TaskType.promptRefine,
      status: TaskStatus.cancelled,
      imagePaths: const <String>[],
      startedMinutesAgo: 60,
      durationSeconds: 8,
    ),
    _task(
      id: 'fixture-task-6',
      catalog: catalog,
      modelIndex: 0,
      status: TaskStatus.pending,
      imagePaths: images.source.skip(5).take(3).toList(),
    ),
    _task(
      id: 'fixture-task-7',
      catalog: catalog,
      modelIndex: 0,
      status: TaskStatus.pending,
      imagePaths: images.source.skip(8).take(2).toList(),
    ),
  ];

  for (final TaskItem task in tasks) {
    await db.saveTask(task.toMap());
  }
}

TaskItem _task({
  required String id,
  required _Catalog catalog,
  required int modelIndex,
  required TaskStatus status,
  required List<String> imagePaths,
  TaskType type = TaskType.imageProcess,
  List<String> resultPaths = const <String>[],
  int? startedMinutesAgo,
  int durationSeconds = 0,
  String? error,
}) {
  final DateTime? start = startedMinutesAgo == null
      ? null
      : kSeedNow.subtract(Duration(minutes: startedMinutesAgo));
  final TaskItem task = TaskItem(
    id: id,
    type: type,
    imagePaths: imagePaths,
    modelId: catalog.modelIds[modelIndex],
    modelDbId: catalog.modelPks[modelIndex],
    channelTag: modelIndex == 4 ? '中转' : '官方',
    channelColor: modelIndex == 4 ? 0xFF00897B : 0xFF4285F4,
    parameters: <String, dynamic>{
      'prompt': '把背景换成纯白，主体保持不变，保留发丝细节',
      'aspect_ratio': '1:1',
    },
    status: status,
    resultPaths: List<String>.from(resultPaths),
    startTime: start,
    endTime: start?.add(Duration(seconds: durationSeconds)),
    logs: _logLines(status, error),
  );
  return task;
}

List<String> _logLines(TaskStatus status, String? error) {
  final List<String> lines = <String>[
    '[14:02:11] 任务已加入队列',
    '[14:02:11] 解析模型配置：channel=官方',
    '[14:02:12] 读取输入图片 (3 张)',
    '[14:02:12] 压缩参考图：2.8MB → 940KB',
    '[14:02:13] 构建请求负载 (inline_data ×3)',
    '[14:02:13] POST /v1beta/models/gemini-2.5-flash-image:streamGenerateContent',
    '[14:02:15] 收到首个响应块',
    '[14:02:19] 已接收 12 个文本块',
    '[14:02:24] 收到图像数据 (1024×1024, PNG)',
    '[14:02:25] 写入输出目录',
  ];
  switch (status) {
    case TaskStatus.completed:
      lines.add('[14:02:25] 任务完成，用时 47.2s');
    case TaskStatus.failed:
      lines.add('[14:02:23] ERROR ${error ?? '未知错误'}');
      lines.add('[14:02:23] 任务失败');
    case TaskStatus.cancelled:
      lines.add('[14:02:19] 用户取消了任务');
    case TaskStatus.pending:
    case TaskStatus.processing:
      return lines.take(2).toList();
  }
  return lines;
}

/// Flips one pending task to "running" in memory.
///
/// It cannot be seeded through the database: TaskQueueService's constructor
/// calls cleanupStuckTasks(), which rewrites every `processing` row to `failed`
/// (task_repository.dart:26-33).
void markOneTaskRunning(AppState appState) {
  final List<TaskItem> queue = appState.taskQueue.queue;
  final int index = queue.indexWhere((TaskItem t) => t.status == TaskStatus.pending);
  if (index == -1) return;
  queue[index]
    ..status = TaskStatus.processing
    ..progress = 0.42
    ..startTime = kSeedNow.subtract(const Duration(seconds: 26))
    ..logs = <String>[
      '[14:29:34] 任务已加入队列',
      '[14:29:35] 构建请求负载 (inline_data ×3)',
      '[14:29:36] 已接收 8 个文本块…',
    ];
  // notifyListeners() only — it does not call _attemptNextExecution
  // (task_queue_service.dart:185-187), so nothing actually executes.
  appState.taskQueue.refreshQueue();
}

/// Refills the execution-log console.
///
/// Called per shot after `clearLogs()`: logs otherwise accumulate across shots,
/// so the console strip would differ run to run for reasons unrelated to layout.
void seedLogs(AppState appState) {
  appState.addLog('Loading settings from database...');
  appState.addLog('已加载 5 个模型 / 2 个渠道');
  appState.addLog('扫描来源目录：找到 12 张图片');
  appState.addLog('任务 fixture-task-1 完成，用时 47.2s');
  appState.addLog('429 RESOURCE_EXHAUSTED: 配额已用尽，请稍后重试', level: 'ERROR');
  appState.addLog('任务 fixture-task-6 已加入队列');
}

// ---------------------------------------------------------------------------
// Workbench tabs
// ---------------------------------------------------------------------------

/// Puts a picture in the crop editor.
///
/// Without this the tab photographs as its empty state, which is how three
/// rounds of design work on the crop screen went unphotographed: the harness
/// only ever shot workbench tab 0.
void seedCropSource(AppState appState) {
  final AppImage? image = _firstGalleryImage(appState);
  if (image == null) return;
  appState.workbenchUIState.setCropResizeSourceImage(image);
}

/// Puts a picture in the mask editor.
void seedMaskSource(AppState appState) {
  final AppImage? image = _firstGalleryImage(appState);
  if (image == null) return;
  appState.workbenchUIState.setMaskEditorSourceImage(image);
}

/// Loads two different pictures into the comparator.
///
/// Two, not one: the whole screen is a pair, and a fixture holding one image
/// photographs a half-empty canvas that says nothing about how the pair reads.
void seedComparatorPair(AppState appState) {
  final List<AppImage> images = _galleryImages(appState).take(2).toList();
  if (images.isEmpty) return;
  appState.workbenchUIState.sendToComparator(images.first.path);
  appState.workbenchUIState.sendToComparator(images.last.path, isAfter: true);
}

/// Selects the first few gallery images, so the config panel's reference strip
/// has something to number.
void seedImageSelection(AppState appState, {int count = 2}) {
  for (final AppImage image in _galleryImages(appState).take(count)) {
    appState.toggleImageSelection(image);
  }
}

/// A finished knowledge-base conversation: a question, a run of tool calls, a
/// submitted prompt and a closing reply.
///
/// Built as an [LLMMessage] history and handed to
/// [PromptOptimizerSession.fromStored] rather than as a hand-made transcript —
/// the transcript is derived, and a fixture that bypassed the derivation would
/// photograph a layout the app cannot actually produce.
void seedOptimizerSession(AppState appState) {
  final List<AppImage> images = _galleryImages(appState).take(2).toList();
  if (images.isEmpty) return;

  // Deliberately past `_promptFoldChars` (600) in `prompt_optimizer_view.dart`:
  // below it the card renders in full and the folded branch — the one that has
  // to clip a long prompt without laying it out inside the fold height — never
  // appears in a screenshot at all. A real refined prompt is this long anyway.
  const String refined = '任务：修复并增强这张人像照片的画质，并按下列设定重绘服装。\n\n'
      '**模特设定**\n'
      '· **面部与眼镜：**严格继承参考图的面部特征、神态与笑容，保留黑色圆框眼镜。\n'
      '· **发型：**青蓝色直发，额前平刘海，发梢自然内扣，避免出现结块与锯齿边缘。\n'
      '· **体态：**身形与站姿保持参考图原样，不做拉伸、瘦身或比例调整。\n\n'
      '**服装**\n'
      '· 上衣：参考图 2 的深色立领外套，保留肩线结构与金属扣件的层次。\n'
      '· 下装：同参考图 2 的直筒长裤，褶皱走向随站姿自然生成。\n'
      '· 鞋履：黑色短靴，袜口露出约两指宽，与裤脚衔接自然。\n\n'
      '**画面要求**\n'
      '· 保持原始构图与全部画面内容不变，只做修复与替换而非重绘整张图。\n'
      '· 去除噪点与轻微模糊，保留毛孔与皮肤纹理，不要磨皮成塑料质感。\n'
      '· 光线均匀柔和，主光来自左前方，阴影过渡自然，不要产生明显的边缘锯齿。\n'
      '· 背景保持原样并轻微降噪，不要引入新的物件、文字或水印。\n\n'
      '**镜头与构图**\n'
      '· 视角与参考图一致，齐腰构图，人物居中略偏左，头顶留白约一成。\n'
      '· 景深浅但不过度，背景虚化程度以能辨认环境轮廓为准。\n'
      '· 不要添加边框、暗角或任何后期滤镜风格。\n\n'
      '**输出**\n'
      '· 分辨率不低于原图，格式 PNG，不要附加任何说明文字。\n'
      '· 若某项设定与参考图冲突，以参考图为准并在结果中保持一致。\n'
      '· 一次只输出一张成品图，不要给出多个候选版本、过程图或对比拼图。\n'
      '· 保留原始 EXIF 方向信息，导出前不要旋转或镜像画面。';

  final List<LLMMessage> history = <LLMMessage>[
    LLMMessage(role: LLMRole.user, content: '让图片 1 中的人物穿上图片 2 中角色的服装'),
    LLMMessage(
      role: LLMRole.assistant,
      content: '',
      toolCalls: <LLMToolCall>[
        LLMToolCall(id: 'c1', name: 'view_image', arguments: <String, dynamic>{'id': '1'}),
        LLMToolCall(id: 'c2', name: 'view_image', arguments: <String, dynamic>{'id': '2'}),
        LLMToolCall(
          id: 'c3',
          name: 'read_knowledge_file',
          arguments: <String, dynamic>{'path': '04_cosplay照片模版.md'},
        ),
        LLMToolCall(
          id: 'c4',
          name: 'read_knowledge_file',
          arguments: <String, dynamic>{'path': '07_footwear/07b_叠穿袜子与高跟鞋.md'},
        ),
        LLMToolCall(
          id: 'c5',
          name: 'read_knowledge_file',
          arguments: <String, dynamic>{'path': '06_场景动作镜头组合库.md'},
        ),
      ],
    ),
    for (final String id in <String>['c1', 'c2', 'c3', 'c4', 'c5'])
      LLMMessage(role: LLMRole.tool, content: 'ok', toolCallId: id, toolName: 'read_knowledge_file'),
    LLMMessage(
      role: LLMRole.assistant,
      content: '',
      toolCalls: <LLMToolCall>[
        LLMToolCall(
          id: 'c6',
          name: 'submit_prompt',
          arguments: <String, dynamic>{
            'prompt': refined,
            'note': '已根据 D 类模版提取图 1 的面部与眼镜特征，还原图 2 的全套服装细节。',
          },
        ),
      ],
    ),
    LLMMessage(role: LLMRole.tool, content: 'ok', toolCallId: 'c6', toolName: 'submit_prompt'),
    LLMMessage(
      role: LLMRole.assistant,
      content: '已完成图 1 与图 2 的融合，重点保留了眼镜与五官继承、服装分层与环境融合规则。'
          '如需微调细节，直接告诉我。',
    ),
  ];

  final PromptOptimizerSession session = PromptOptimizerSession.fromStored(
    id: 'fixture-assistant-1',
    mode: AssistantMode.knowledgeBase,
    title: 'Cosplay 服装融合',
    history: history,
  );

  // What the last request's fixed costs were. Restoring a session cannot know
  // them (only a live turn records them), and without them the context card
  // photographs with two of its four rows reading '—' — the one state that
  // says least about the layout.
  session.recordRequestBasis(systemPromptChars: 4820, toolSchemaChars: 1960);

  appState.workbenchUIState.adoptOptimizerSession(session, images);
}

/// The assistant mid-turn — `10i`.
///
/// The same conversation as [seedOptimizerSession], cut off after three tool
/// results and with nothing submitted: the timeline card is the row that is
/// still moving, so the shot has to end inside one rather than after it. The
/// running flag is set through the session's test hook because the only other
/// way in is to actually call a model.
void seedOptimizerRunning(AppState appState) {
  final List<AppImage> images = _galleryImages(appState).take(2).toList();
  if (images.isEmpty) return;

  final List<LLMMessage> history = <LLMMessage>[
    LLMMessage(role: LLMRole.user, content: '让图片 1 中的人物穿上图片 2 中角色的服装'),
    LLMMessage(
      role: LLMRole.assistant,
      content: '',
      toolCalls: <LLMToolCall>[
        LLMToolCall(id: 'r1', name: 'view_image', arguments: <String, dynamic>{'id': '1'}),
        LLMToolCall(id: 'r2', name: 'view_image', arguments: <String, dynamic>{'id': '2'}),
        LLMToolCall(
          id: 'r3',
          name: 'read_knowledge_file',
          arguments: <String, dynamic>{'path': '04_cosplay照片模版.md'},
        ),
      ],
    ),
    for (final String id in <String>['r1', 'r2', 'r3'])
      LLMMessage(role: LLMRole.tool, content: 'ok', toolCallId: id, toolName: 'read_knowledge_file'),
  ];

  final PromptOptimizerSession session = PromptOptimizerSession.fromStored(
    id: 'fixture-assistant-running',
    mode: AssistantMode.knowledgeBase,
    title: 'Cosplay 服装融合',
    history: history,
  );
  session.recordRequestBasis(systemPromptChars: 4820, toolSchemaChars: 1960);
  session.setRunningForTest(true);

  appState.workbenchUIState.adoptOptimizerSession(session, images);
}

/// The assistant in system-prompt mode — `10g`.
///
/// An empty conversation on purpose: this frame is about the right panel, and
/// the transcript is the same one every other assistant shot already carries.
/// The template is picked here rather than left to the screen's own first-load
/// default, which runs before the fixture database is queried.
void seedOptimizerSystemPrompt(AppState appState) {
  final List<AppImage> images = _galleryImages(appState).take(2).toList();
  final PromptOptimizerSession session = PromptOptimizerSession(
    id: 'fixture-assistant-sysprompt',
    mode: AssistantMode.systemPrompt,
  );
  appState.workbenchUIState.adoptOptimizerSession(session, images);
}

/// The assistant in library-edit mode with changes staged — `10h`.
///
/// Two edits, deliberately of both kinds: an update, which is the only one
/// that has a diff to draw, and a create, which has not. The update's before
/// and after differ in one paragraph inside a longer document, because that is
/// the case the diff exists for — a wholesale replacement would look the same
/// under the old "show the whole file" card.
void seedOptimizerKbEdit(AppState appState) {
  final List<AppImage> images = _galleryImages(appState).take(2).toList();

  const String header = '# 07b 叠穿袜子与高跟鞋\n'
      '\n'
      '## 一、适用场景\n'
      '- 制服 / 校园主题的半身与全身构图。\n'
      '- 需要在脚踝处形成断色的写实摄影。\n'
      '\n'
      '## 二、叠穿组合\n'
      '  - 白色过膝袜 + 玛丽珍鞋：适合校园与制服主题。\n';
  const String footer = '\n'
      '## 三、常见问题\n'
      '- 袜口过紧会在脚踝留下压痕，写提示词时明确「无压痕」。\n'
      '- 网袜的孔径要写具体尺寸，否则模型会给出装饰性花纹。\n';

  const String before = '$header'
      '  - 黑色短袜 + 高跟鞋：注意脚踝处袜口不要压出褶皱。\n'
      '$footer';
  const String after = '$header'
      '  - 黑色短袜 + 高跟鞋：袜口停在踝骨上方 2–3 cm，避免压出褶皱；\n'
      '    袜口与鞋帮之间留出一段裸露皮肤，形成断色。\n'
      '  - 网袜叠穿纯色短袜：先写外层网袜的孔径，再写内层袜色。\n'
      '\n'
      '提示：叠穿写法一律「由外到内」，与服装分层规则保持一致。\n'
      '$footer';

  const String created = '# 04b 证件照模版\n'
      '\n'
      '## 用途\n'
      '一寸 / 二寸证件照的标准化提示词模版。\n'
      '\n'
      '## 结构\n'
      '1. 主体 —— 正面免冠，肩线水平，视线平视镜头。\n'
      '2. 背景 —— 纯色，无渐变、无投影、无纹理。\n'
      '3. 光线 —— 双侧柔光，鼻下无明显阴影。\n'
      '4. 输出 —— 不裁切、不磨皮、不做美颜。\n';

  final List<LLMMessage> history = <LLMMessage>[
    LLMMessage(
      role: LLMRole.user,
      content: '把刚才那条 cosplay 提示词里关于袜子叠穿的经验补进知识库，并给证件照单独建一个模版。',
    ),
    LLMMessage(
      role: LLMRole.assistant,
      content: '',
      toolCalls: <LLMToolCall>[
        LLMToolCall(
          id: 'e1',
          name: 'read_knowledge_file',
          arguments: <String, dynamic>{'path': '07_footwear/07b_叠穿袜子与高跟鞋.md'},
        ),
        LLMToolCall(
          id: 'e2',
          name: 'read_knowledge_file',
          arguments: <String, dynamic>{'path': '04_模板/04_cosplay照片模版.md'},
        ),
      ],
    ),
    for (final String id in <String>['e1', 'e2'])
      LLMMessage(role: LLMRole.tool, content: 'ok', toolCallId: id, toolName: 'read_knowledge_file'),
  ];

  final PromptOptimizerSession session = PromptOptimizerSession.fromStored(
    id: 'fixture-assistant-kbedit',
    mode: AssistantMode.knowledgeEdit,
    title: '补充袜子叠穿经验',
    history: history,
  );
  session.recordRequestBasis(systemPromptChars: 5240, toolSchemaChars: 3100);

  session.stageKbEditForTest(
    relPath: '07_footwear/07b_叠穿袜子与高跟鞋.md',
    oldContent: before,
    newContent: after,
    note: '把「无褶皱」这条写成可执行的距离，并补上网袜叠穿的写法。',
  );
  session.stageKbEditForTest(
    relPath: '04_模板/04b_证件照模版.md',
    newContent: created,
    note: '证件照与 cosplay 的约束几乎不重叠，单独建一篇比塞进现有模版清楚。',
  );

  appState.workbenchUIState.adoptOptimizerSession(session, images);
}

/// Whatever the gallery is actually showing, so a seeded selection matches the
/// tiles in the same shot rather than some other folder's files.
List<AppImage> _galleryImages(AppState appState) =>
    appState.galleryState.currentViewImages;

AppImage? _firstGalleryImage(AppState appState) {
  final List<AppImage> images = _galleryImages(appState);
  return images.isEmpty ? null : images.first;
}

// ---------------------------------------------------------------------------
// Token usage
// ---------------------------------------------------------------------------

Future<void> _seedUsage(DatabaseService db, _Catalog catalog) async {
  int seed = 7;
  int next(int max) {
    // Deterministic LCG — Random() without a seed would make every run differ.
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    return seed % max;
  }

  for (int day = 29; day >= 0; day--) {
    final int rowsToday = 1 + next(3);
    for (int r = 0; r < rowsToday; r++) {
      final int m = next(catalog.modelPks.length);
      final DateTime ts = kSeedNow
          .subtract(Duration(days: day))
          .subtract(Duration(hours: next(10), minutes: next(60)));
      final int inputTokens = 800 + next(9000);
      final int cacheTokens = next(2) == 0 ? 0 : next(3000);
      final int outputTokens = 200 + next(2500);
      await db.recordTokenUsage(<String, dynamic>{
        'task_id': 'fixture-usage-$day-$r',
        'model_id': catalog.modelIds[m],
        'model_pk': catalog.modelPks[m],
        'timestamp': ts.toIso8601String(),
        'input_tokens': inputTokens,
        'cache_tokens': cacheTokens,
        'output_tokens': outputTokens,
        'input_price': 0.075,
        'cache_price': 0.01875,
        'output_price': 0.30,
        'request_count': 1,
        'request_price': 0.04,
        'billing_mode': m == 0 || m == 3 ? 'request' : 'token',
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Image fixtures
// ---------------------------------------------------------------------------

class _Images {
  _Images(this.source, this.output);
  final List<String> source;
  final List<String> output;
}

/// Generates PNGs rather than committing binary fixtures.
///
/// Aspect ratios are deliberately mixed: they drive the gallery grid's layout,
/// so a set of uniform squares would hide exactly the bugs worth catching.
Future<_Images> _writeImages(FixtureEnv env) async {
  const List<(int, int)> shapes = <(int, int)>[
    (512, 512),
    (768, 512),
    (512, 896),
    (640, 640),
    (896, 512),
    (512, 768),
  ];

  Future<List<String>> writeSet(Directory dir, String prefix, int count) async {
    final List<String> paths = <String>[];
    for (int i = 0; i < count; i++) {
      final (int w, int h) = shapes[i % shapes.length];
      paths.add(await _writePng(env, dir, '${prefix}_${i + 1}', w, h, i));
    }
    return paths;
  }

  final List<String> source = await writeSet(env.sourceDir, 'source', 12);
  final List<String> output = await writeSet(env.outputDir, 'result', 6);
  await writeSet(env.resultCacheDir, 'cached', 6);
  await writeSet(env.browserDir, 'photo', 8);

  // Non-image types so the browser's category filters and icon fallbacks are
  // actually exercised. These are stubs; they are meant to be listed, not played.
  for (final String name in <String>['clip_a.mp4', 'clip_b.mov', 'notes.txt', 'voice.mp3']) {
    File(p.join(env.browserDir.path, name))
        .writeAsBytesSync(utf8.encode('fixture placeholder for $name'));
  }

  return _Images(source, output);
}

/// A flat colour block with its own name burned in, so a screenshot makes it
/// obvious which fixture landed where.
Future<String> _writePng(
  FixtureEnv env,
  Directory dir,
  String name,
  int width,
  int height,
  int index,
) async {
  const List<int> palette = <int>[
    0xFF4285F4,
    0xFF00897B,
    0xFFF4511E,
    0xFF8E24AA,
    0xFF43A047,
    0xFFFB8C00,
  ];
  final int argb = palette[index % palette.length];
  final img.Image image = img.Image(width: width, height: height);
  img.fill(
    image,
    color: img.ColorRgb8((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF),
  );
  img.drawString(
    image,
    '$name\n$width×$height',
    font: img.arial24,
    x: 16,
    y: 16,
    color: img.ColorRgb8(255, 255, 255),
  );

  final File file = File(p.join(dir.path, '$name.png'));
  await file.writeAsBytes(img.encodePng(image));
  env.fixtureImagePaths.add(file.path);
  return file.path;
}
