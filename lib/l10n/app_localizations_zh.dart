// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Joycai 图像 AI 工具箱';

  @override
  String get workbench => '工作台';

  @override
  String get tasks => '任务';

  @override
  String get prompts => '提示词';

  @override
  String get usage => '用量';

  @override
  String get models => '模型';

  @override
  String get settings => '设置';

  @override
  String get addFolder => '添加文件夹';

  @override
  String get directories => '目录列表';

  @override
  String get noFolders => '未添加文件夹';

  @override
  String get clickAddFolder => '点击“添加文件夹”开始扫描图像。';

  @override
  String get sourceGallery => '源图库';

  @override
  String get processResults => '处理结果';

  @override
  String get noImagesFound => '未找到图像';

  @override
  String get noResultsYet => '暂无结果';

  @override
  String get selectAll => '全选';

  @override
  String get clear => '清除';

  @override
  String selectedCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String get copyFilename => '复制文件名';

  @override
  String get openInFolder => '打开所在文件夹';

  @override
  String copiedToClipboard(String text) {
    return '已复制: $text';
  }

  @override
  String get modelSelection => '模型选择';

  @override
  String get selectAModel => '选择一个模型';

  @override
  String get aspectRatio => '宽高比';

  @override
  String get resolution => '分辨率';

  @override
  String get prompt => '提示词';

  @override
  String get library => '提示词库';

  @override
  String get refiner => '优化器';

  @override
  String get processPrompt => '处理提示词';

  @override
  String processImages(int count) {
    return '处理 $count 张图像';
  }

  @override
  String get promptHint => '在此输入提示词...';

  @override
  String get taskSubmitted => '任务已提交至队列';

  @override
  String runningCount(int count) {
    return '$count 个正在运行';
  }

  @override
  String plannedCount(int count) {
    return '$count 个已计划';
  }

  @override
  String get selectFromLibrary => '从库中选择';

  @override
  String get close => '关闭';

  @override
  String get queueSettings => '队列设置';

  @override
  String concurrencyLimit(int limit) {
    return '并发限制: $limit';
  }

  @override
  String get aiPromptRefiner => 'AI 提示词优化器';

  @override
  String get refinerModel => '优化模型';

  @override
  String get systemPrompt => '系统提示词';

  @override
  String get currentPrompt => '当前提示词';

  @override
  String get refinedPrompt => '优化后的提示词';

  @override
  String get refine => '优化';

  @override
  String get apply => '应用';

  @override
  String refineFailed(String error) {
    return '优化失败: $error';
  }

  @override
  String get noImagesSelected => '未选择图像';

  @override
  String get selectSourceDirectory => '选择源目录';

  @override
  String get removeFolderTooltip => '移除文件夹';

  @override
  String get removeFolderConfirmTitle => '移除文件夹？';

  @override
  String removeFolderConfirmMessage(String folderName) {
    return '确定要从列表中移除“$folderName”吗？';
  }

  @override
  String get remove => '移除';

  @override
  String get appearance => '外观';

  @override
  String get language => '语言';

  @override
  String get themeAuto => '跟随系统';

  @override
  String get themeLight => '浅色模式';

  @override
  String get themeDark => '深色模式';

  @override
  String get googleGenAiSettings => 'Google GenAI REST 设置';

  @override
  String get openAiApiSettings => 'OpenAI API REST 设置';

  @override
  String get freeModel => '免费模型';

  @override
  String get paidModel => '付费模型';

  @override
  String get standardConfig => '标准配置';

  @override
  String get endpointUrl => '接口地址';

  @override
  String get apiKey => 'API 密钥';

  @override
  String get outputDirectory => '输出目录';

  @override
  String get notSet => '未设置';

  @override
  String get dataManagement => '数据管理';

  @override
  String get exportSettings => '导出设置';

  @override
  String get importSettings => '导入设置';

  @override
  String get resetAllSettings => '重置所有设置';

  @override
  String get confirmReset => '重置所有设置？';

  @override
  String get resetWarning => '这将删除所有配置、模型和已添加的文件夹。此操作无法撤销。';

  @override
  String get cancel => '取消';

  @override
  String get resetEverything => '全部重置';

  @override
  String get settingsExported => '设置导出成功';

  @override
  String get settingsImported => '设置导入成功';

  @override
  String get taskQueueManager => '任务队列管理';

  @override
  String get refresh => '刷新';

  @override
  String get noTasksInQueue => '队列中没有任务';

  @override
  String get submitTaskFromWorkbench => '从工作台提交任务后在此处查看。';

  @override
  String taskId(String id) {
    return '任务 ID: $id';
  }

  @override
  String get cancelTask => '取消任务';

  @override
  String get removeFromList => '从列表中移除';

  @override
  String get model => '模型';

  @override
  String get images => '图像';

  @override
  String filesCount(int count) {
    return '$count 个文件';
  }

  @override
  String get started => '开始时间';

  @override
  String get finished => '完成时间';

  @override
  String get config => '配置';

  @override
  String get latestLog => '最新日志:';

  @override
  String get promptLibrary => '提示词库';

  @override
  String get newPrompt => '新建提示词';

  @override
  String get editPrompt => '编辑提示词';

  @override
  String get noPromptsSaved => '未保存提示词';

  @override
  String get saveFavoritePrompts => '在此保存您常用的提示词或优化器系统提示词';

  @override
  String get createFirstPrompt => '创建第一个提示词';

  @override
  String get deletePromptConfirmTitle => '删除提示词？';

  @override
  String deletePromptConfirmMessage(String title) {
    return '确定要删除“$title”吗？';
  }

  @override
  String get delete => '删除';

  @override
  String get deleteModel => '删除模型';

  @override
  String get title => '标题';

  @override
  String get tagCategory => '标签 (分类)';

  @override
  String get setAsRefiner => '设为优化器';

  @override
  String get promptContent => '提示词内容';

  @override
  String get save => '保存';

  @override
  String get update => '更新';

  @override
  String get tokenUsageMetrics => 'Token 使用统计';

  @override
  String get clearAllUsage => '清除所有使用数据？';

  @override
  String get clearUsageWarning => '这将永久从数据库中删除所有 Token 使用记录。';

  @override
  String get clearAll => '全部清除';

  @override
  String get modelsLabel => '模型: ';

  @override
  String get rangeLabel => '范围: ';

  @override
  String get today => '今天';

  @override
  String get lastWeek => '最近一周';

  @override
  String get lastMonth => '最近一月';

  @override
  String get thisYear => '今年';

  @override
  String get inputTokens => '输入 Token';

  @override
  String get outputTokens => '输出 Token';

  @override
  String get estimatedCost => '预估成本';

  @override
  String clearDataForModel(String modelId) {
    return '清除 $modelId 的数据？';
  }

  @override
  String clearModelDataWarning(String modelId) {
    return '这将删除与模型“$modelId”相关的所有使用记录。';
  }

  @override
  String get clearModelData => '清除模型数据';

  @override
  String get modelManager => '模型管理';

  @override
  String get addModel => '添加模型';

  @override
  String get editModel => '编辑模型';

  @override
  String get noModelsConfigured => '未配置模型';

  @override
  String get addFirstModel => '添加您的第一个 LLM 模型以开始使用';

  @override
  String get addNewModel => '添加新模型';

  @override
  String get deleteModelConfirmTitle => '删除模型？';

  @override
  String deleteModelConfirmMessage(String name) {
    return '确定要删除“$name”吗？';
  }

  @override
  String get addLlmModel => '添加 LLM 模型';

  @override
  String get editLlmModel => '编辑 LLM 模型';

  @override
  String get modelIdLabel => '模型 ID (例如 gemini-pro)';

  @override
  String get displayName => '显示名称';

  @override
  String get type => '类型';

  @override
  String get tag => '标签';

  @override
  String get inputFeeLabel => '输入费用 (\$/M Tokens)';

  @override
  String get outputFeeLabel => '输出费用 (\$/M Tokens)';

  @override
  String get add => '添加';

  @override
  String get executionLogs => '执行日志';

  @override
  String get clickToExpand => '点击展开';

  @override
  String get thumbnailSize => '缩略图大小';
}
