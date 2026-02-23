// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get fileBrowser => '文件浏览器';

  @override
  String get rename => '重命名';

  @override
  String get renameFile => '重命名文件';

  @override
  String get newFilename => '新文件名';

  @override
  String get renameSuccess => '重命名成功';

  @override
  String renameFailed(String error) {
    return '重命名失败: $error';
  }

  @override
  String get fileAlreadyExists => '同名文件已存在';

  @override
  String get noFilesFound => '未找到文件';

  @override
  String get switchViewMode => '切换视图模式';

  @override
  String get sortBy => '排序方式';

  @override
  String get sortName => '文件名';

  @override
  String get sortDate => '修改日期';

  @override
  String get sortType => '文件类型';

  @override
  String get sortAsc => '正序';

  @override
  String get sortDesc => '倒序';

  @override
  String get catAll => '全部';

  @override
  String get catImages => '图片';

  @override
  String get catVideos => '视频';

  @override
  String get catAudio => '音频';

  @override
  String get catText => '文本';

  @override
  String get catOthers => '其他';

  @override
  String get openWithSystemDefault => '使用系统默认程序打开';

  @override
  String get aiBatchRename => 'AI 批量重命名';

  @override
  String get rulesInstructions => '重命名规则 / 指令';

  @override
  String get generateSuggestions => '生成建议';

  @override
  String get noSuggestions => '尚未生成建议';

  @override
  String get applyRenames => '应用重命名';

  @override
  String get addToSelection => '添加到选中列表';

  @override
  String get removeFromSelection => '从选中列表移除';

  @override
  String imagesSelected(int count) {
    return '已选 $count 项';
  }

  @override
  String get appTitle => 'Joycai 图像 AI 工具箱';

  @override
  String get save => '保存';

  @override
  String get update => '更新';

  @override
  String get cancel => '取消';

  @override
  String get close => '关闭';

  @override
  String get back => '返回';

  @override
  String get next => '下一步';

  @override
  String get finish => '完成';

  @override
  String get exit => '退出';

  @override
  String get add => '添加';

  @override
  String get edit => '编辑';

  @override
  String get delete => '删除';

  @override
  String get remove => '移除';

  @override
  String get clear => '清除';

  @override
  String get refresh => '刷新';

  @override
  String get preview => '预览';

  @override
  String get share => '分享';

  @override
  String get status => '状态';

  @override
  String get started => '开始时间';

  @override
  String get finished => '完成时间';

  @override
  String get config => '配置';

  @override
  String get logs => '日志';

  @override
  String get copyFilename => '复制文件名';

  @override
  String get openInFolder => '打开所在文件夹';

  @override
  String get openInPreview => '在预览窗口打开';

  @override
  String copiedToClipboard(String text) {
    return '已复制: $text';
  }

  @override
  String selectedCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String shareFiles(int count) {
    return '分享选中的项 ($count)';
  }

  @override
  String get comingSoon => '敬请期待';

  @override
  String get viewAll => '查看全部';

  @override
  String get sidebar => '侧边栏';

  @override
  String get white => '白色';

  @override
  String get black => '黑色';

  @override
  String get red => '红色';

  @override
  String get green => '绿色';

  @override
  String get refine => '优化';

  @override
  String get apply => '应用';

  @override
  String get metadata => '元数据';

  @override
  String get filterPrompts => '过滤提示词...';

  @override
  String shareFailed(String error) {
    return '分享失败: $error';
  }

  @override
  String get downloader => '下载器';

  @override
  String get imageDownloader => '图像下载器';

  @override
  String get url => '地址';

  @override
  String get prefix => '前缀';

  @override
  String get websiteUrl => '网站地址';

  @override
  String get websiteUrlHint => 'https://example.com';

  @override
  String get whatToFind => '寻找什么？';

  @override
  String get whatToFindHint => '例如：所有商品详情图';

  @override
  String get analysisModel => '分析模型';

  @override
  String get advancedOptions => '高级选项';

  @override
  String get analyzing => '正在分析...';

  @override
  String get urlRequired => '请输入有效的网站 URL。';

  @override
  String get requirementRequired => '请输入您想要查找的图片描述（需求）。';

  @override
  String get manualHtmlRequired => '手动模式下请先粘贴 HTML 内容。';

  @override
  String get findImages => '寻找图像';

  @override
  String get noImagesDiscovered => '尚未发现图像。';

  @override
  String get enterUrlToStart => '输入网址和需求以开始。';

  @override
  String get addToQueue => '添加到下载队列';

  @override
  String addedToQueue(int count) {
    return '已将 $count 张图像添加到下载队列。';
  }

  @override
  String get setOutputDirFirst => '请先在设置中设置输出目录。';

  @override
  String get cookiesHint => 'Cookie (原始或 Netscape 格式)';

  @override
  String get selectImagesToDownload => '选择要下载的图像';

  @override
  String get importCookieFile => '导入 Cookie 文件';

  @override
  String get cookieFileInvalid => '不支持的 Cookie 文件格式。请使用 Netscape 格式或原始文本。';

  @override
  String cookieImportSuccess(int count) {
    return '成功导入 $count 条 Cookie。';
  }

  @override
  String get saveOriginHtml => '保存原始 HTML';

  @override
  String htmlSavedTo(String path) {
    return 'HTML 已保存至: $path';
  }

  @override
  String get manualHtmlMode => '手动 HTML 模式';

  @override
  String get manualHtmlHint => '在此粘贴已渲染的 HTML (F12 -> 复制外部 HTML)';

  @override
  String get cookieHistory => 'Cookie 历史';

  @override
  String get noCookieHistory => '未保存 Cookie 历史';

  @override
  String get pasteFromClipboard => '从剪贴板粘贴';

  @override
  String get openRawImage => '打开原始图像';

  @override
  String get usage => '用量';

  @override
  String get tokenUsageMetrics => 'Token 使用统计';

  @override
  String get clearAllUsage => '清除所有使用数据？';

  @override
  String get clearUsageWarning => '这将永久从数据库中删除所有 Token 使用记录。';

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
  String get usageByGroup => '按费率组统计';

  @override
  String get clearAll => '清除全部';

  @override
  String get models => '模型';

  @override
  String get modelManagement => '模型管理';

  @override
  String get feeManagement => '费用管理';

  @override
  String get modelsTab => '模型管理';

  @override
  String get channelsTab => '渠道管理';

  @override
  String get addChannel => '添加渠道';

  @override
  String get editChannel => '编辑渠道';

  @override
  String get basicInfo => '基本信息';

  @override
  String get configuration => '配置信息';

  @override
  String get tagAndAppearance => '标签与外观';

  @override
  String get billing => '计费设置';

  @override
  String get channelType => '渠道类型';

  @override
  String get enableDiscovery => '启用模型检索';

  @override
  String get filterModels => '过滤模型...';

  @override
  String get tagColor => '标签颜色';

  @override
  String deleteChannelConfirm(String name) {
    return '确定要删除渠道“$name”吗？这将断开所有关联模型的连接。';
  }

  @override
  String get modelManager => '模型管理';

  @override
  String get name => '名称';

  @override
  String get addModel => '添加模型';

  @override
  String get editModel => '编辑模型';

  @override
  String get noModelsConfigured => '未配置模型';

  @override
  String countModels(int count) {
    return '$count 个模型';
  }

  @override
  String get addFirstModel => '添加您的第一个 LLM 模型以开始使用';

  @override
  String get addNewModel => '添加新模型';

  @override
  String get deleteModel => '删除模型';

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
  String get paidModel => '付费模型';

  @override
  String get freeModel => '免费模型';

  @override
  String get billingMode => '计费模式';

  @override
  String get perToken => '按 Token 计费 (每百万)';

  @override
  String get perRequest => '按次计费';

  @override
  String get requestFeeLabel => '单次费用 (\$/次)';

  @override
  String get requestCount => '请求次数';

  @override
  String get requests => '请求数';

  @override
  String get feeGroups => '费率组';

  @override
  String get feeGroup => '费率组';

  @override
  String get channels => '渠道';

  @override
  String get channel => '渠道';

  @override
  String get noFeeGroup => '无费率组';

  @override
  String get inputPrice => '输入价格 (\$/M Tokens)';

  @override
  String get outputPrice => '输出价格 (\$/M Tokens)';

  @override
  String get requestPrice => '请求价格 (\$/次)';

  @override
  String get priceConfig => '价格配置';

  @override
  String get addFeeGroup => '添加费率组';

  @override
  String get editFeeGroup => '编辑费率组';

  @override
  String deleteFeeGroupConfirm(String name) {
    return '删除费率组“$name”？';
  }

  @override
  String get groupName => '分组名称';

  @override
  String get fetchModels => '获取模型';

  @override
  String get discoveringModels => '正在发现模型...';

  @override
  String get selectModelsToAdd => '选择要添加的模型';

  @override
  String get searchModels => '搜索模型名称或 ID...';

  @override
  String get selectAll => '全选';

  @override
  String get deselectAll => '取消全选';

  @override
  String modelsDiscovered(int count) {
    return '发现 $count 个模型';
  }

  @override
  String addSelected(int count) {
    return '添加所选 ($count)';
  }

  @override
  String get alreadyAdded => '已添加';

  @override
  String get noNewModelsFound => '未发现新模型。';

  @override
  String fetchFailed(String error) {
    return '获取模型失败: $error';
  }

  @override
  String get stepProtocol => '选择协议';

  @override
  String get stepProvider => '选择提供商';

  @override
  String get stepApiKey => 'API 密钥';

  @override
  String get stepConfig => '额外配置';

  @override
  String get stepPreview => '预览';

  @override
  String get protocolOpenAI => 'OpenAI 兼容协议 (REST)';

  @override
  String get protocolOpenAIDesc => '标准 OpenAI REST API 兼容接口';

  @override
  String get protocolGoogle => 'Google GenAI 协议 (REST)';

  @override
  String get protocolGoogleDesc => 'Google Gemini 官方 REST API';

  @override
  String get providerOpenAIOfficial => 'OpenAI 官方';

  @override
  String get providerGoogleOfficial => 'Google GenAI 官方';

  @override
  String get providerGoogleCompatible => 'Google GenAI (OpenAI 兼容)';

  @override
  String get providerGoogleCompatibleDesc => '通过 OpenAI 适配端点访问 Gemini';

  @override
  String get providerCustom => '自定义提供商';

  @override
  String get providerCustomDesc => '自建或第三方 API 服务商';

  @override
  String get customEndpointHint => '请输入自定义端点 URL';

  @override
  String get openaiV1Hint => '提示：OpenAI 兼容接口通常以 \'/v1\' 结尾';

  @override
  String get googleV1BetaHint => '提示：Google GenAI 接口通常以 \'/v1beta\' 结尾';

  @override
  String get enterApiKey => '请输入 API 密钥';

  @override
  String get apiKeyStorageNotice => '您的密钥仅存储在本地，不会发送到我们的服务器。';

  @override
  String get nameHint => '例如：生产环境 API';

  @override
  String get enableDiscoveryDesc => '自动从端点获取可用模型列表';

  @override
  String get tagHint => '例如：GPT4, 核心, 等';

  @override
  String get bindTag => '绑定标签';

  @override
  String get previewReady => '准备好添加此渠道了吗？';

  @override
  String get feeGroupDesc => '定义模型的计费标准，以便准确计算使用成本。';

  @override
  String get noFeeGroups => '尚未创建费率组';

  @override
  String get pricePerMillion => '每百万 Token 价格';

  @override
  String get pricePerRequest => '单次请求价格';

  @override
  String get tokenBilling => 'Token 计费';

  @override
  String get requestBilling => '按次计费';

  @override
  String get model => '模型';

  @override
  String get prompts => '提示词';

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
  String get title => '标题';

  @override
  String get tagCategory => '标签 (分类)';

  @override
  String get setAsRefiner => '设为优化器';

  @override
  String get promptContent => '提示词内容';

  @override
  String get userPrompts => '用户提示词';

  @override
  String get refinerPrompts => '优化器提示词';

  @override
  String get systemTemplates => '系统模板';

  @override
  String get templateType => '模板用途';

  @override
  String get typeRename => '批量重命名';

  @override
  String get typeRefiner => '提示词优化';

  @override
  String get selectRenameTemplate => '选择重命名模板';

  @override
  String get selectCategory => '选择分类';

  @override
  String get categoriesTab => '分类管理';

  @override
  String get addCategory => '添加分类';

  @override
  String get editCategory => '编辑分类';

  @override
  String get library => '提示词库';

  @override
  String get refiner => '优化器';

  @override
  String get settings => '设置';

  @override
  String get appearance => '外观';

  @override
  String get connectivity => '连接设置';

  @override
  String get application => '应用设置';

  @override
  String get proxySettings => '代理设置';

  @override
  String get enableProxy => '启用全局代理';

  @override
  String get proxyUrl => '代理地址 (host:port)';

  @override
  String get proxyUsername => '代理用户名 (可选)';

  @override
  String get proxyPassword => '代理密码 (可选)';

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
  String get openAppDataDirectory => '打开应用数据目录';

  @override
  String get mcpServerSettings => 'MCP 服务器设置';

  @override
  String get enableMcpServer => '启用 MCP 服务器';

  @override
  String get port => '端口';

  @override
  String get resetAllSettings => '重置所有设置';

  @override
  String get confirmReset => '重置所有设置？';

  @override
  String get resetWarning => '这将删除所有配置、模型和已添加的文件夹。此操作无法撤销。';

  @override
  String get resetEverything => '全部重置';

  @override
  String get settingsExported => '设置导出成功';

  @override
  String get settingsImported => '设置导入成功';

  @override
  String get exportOptions => '导出选项';

  @override
  String get includeDirectories => '包含目录配置';

  @override
  String get includeDirectoriesDesc => '工作台/浏览器目录及输出路径';

  @override
  String get includePrompts => '包含提示词';

  @override
  String get includePromptsDesc => '用户及系统提示词库';

  @override
  String get includeUsage => '包含用量统计';

  @override
  String get includeUsageDesc => 'API Token 消耗历史';

  @override
  String get exportNow => '立即导出';

  @override
  String get importNow => '立即导入';

  @override
  String get importOptions => '导入选项';

  @override
  String get notInBackup => '备份文件中不包含此项';

  @override
  String get importSettingsTitle => '导入设置？';

  @override
  String get importSettingsConfirm =>
      '这将替换您当前所有的模型、渠道和分类。\n\n注意：提示词库不受此导入影响。请在提示词页面管理提示词数据。';

  @override
  String get importAndReplace => '导入并替换';

  @override
  String get importMode => '导入模式';

  @override
  String get importModeDesc =>
      '选择导入提示词的方式：\n\n合并：将新项添加到您的库中。\n替换：删除当前库并使用导入的数据。';

  @override
  String get merge => '合并';

  @override
  String get replaceAll => '全部替换';

  @override
  String get applyOverwrite => '应用 (覆盖)';

  @override
  String get applyAppend => '应用 (追加)';

  @override
  String get portableMode => '便携模式';

  @override
  String get portableModeDesc => '在应用程序文件夹中存储数据库和缓存 (需要重启)';

  @override
  String get restartRequired => '需要重启';

  @override
  String get restartMessage => '必须重启应用程序以应用对数据存储位置的更改。';

  @override
  String get enableNotifications => '启用系统通知';

  @override
  String get runSetupWizard => '运行设置向导';

  @override
  String get clearDownloaderCache => '清除下载器缓存';

  @override
  String get enableApiDebug => '开启 API 调试日志';

  @override
  String get apiDebugDesc => '将原始 API 请求和响应记录到文件中以便排查问题。警告：API 密钥等敏感数据可能会被记录。';

  @override
  String get openLogFolder => '打开日志目录';

  @override
  String get iosOutputRecommend => '建议：在 iOS 上保持默认。生成的图片可在“文件”App 中查看。';

  @override
  String get downloaderCacheCleared => '下载器缓存已清除。';

  @override
  String get tasks => '任务';

  @override
  String get taskQueueManager => '任务队列管理';

  @override
  String get noTasksInQueue => '队列中没有任务';

  @override
  String get submitTaskFromWorkbench => '从工作台提交任务后在此处查看。';

  @override
  String taskId(String id) {
    return '任务 ID: $id';
  }

  @override
  String get taskSummary => '任务摘要';

  @override
  String get pendingTasks => '待处理';

  @override
  String get processingTasks => '执行中';

  @override
  String get completedTasks => '已完成';

  @override
  String get failedTasks => '失败';

  @override
  String get clearCompleted => '清除已完成';

  @override
  String get cancelAllPending => '取消所有等待中';

  @override
  String get cancelTask => '取消任务';

  @override
  String get removeFromList => '从列表中移除';

  @override
  String get images => '图像';

  @override
  String filesCount(int count) {
    return '$count 个文件';
  }

  @override
  String runningCount(int count) {
    return '$count 个正在运行';
  }

  @override
  String plannedCount(int count) {
    return '$count 个已计划';
  }

  @override
  String get latestLog => '最新日志:';

  @override
  String get taskCompletedNotification => '任务已完成';

  @override
  String get taskFailedNotification => '任务失败';

  @override
  String taskCompletedBody(String id) {
    return '任务 $id 已成功完成。';
  }

  @override
  String taskFailedBody(String id) {
    return '任务 $id 运行失败。';
  }

  @override
  String get queueSettings => '队列设置';

  @override
  String concurrencyLimit(int limit) {
    return '并发限制: $limit';
  }

  @override
  String retryCount(int count) {
    return '重试次数: $count';
  }

  @override
  String get setupWizardTitle => '欢迎设置向导';

  @override
  String get welcomeMessage => '欢迎使用 Joycai 图像 AI 工具箱！让我们开始设置吧。';

  @override
  String get getStarted => '开始';

  @override
  String get stepAppearance => '外观';

  @override
  String get stepStorage => '存储';

  @override
  String get stepApi => '智能 (API)';

  @override
  String get setupCompleteMessage => '设置完成！尽情创作吧。';

  @override
  String get skip => '跳过';

  @override
  String get storageLocationDesc => '选择生成图像的保存位置。';

  @override
  String get addChannelOptional => '添加您的第一个 AI 渠道（可选）。';

  @override
  String get configureModelOptional => '为新渠道配置一个模型（可选）。';

  @override
  String get googleGenAiFree => 'Google GenAI (免费)';

  @override
  String get googleGenAiPaid => 'Google GenAI (付费)';

  @override
  String get openaiApi => 'OpenAI API';

  @override
  String get filenamePrefix => '文件名前缀';

  @override
  String get openaiEndpointHint => '提示：OpenAI 兼容接口通常以 \'/v1\' 结尾';

  @override
  String get googleEndpointHint =>
      '提示：Google GenAI 接口通常以 \'/v1beta\' 结尾（内部已处理）';

  @override
  String get workbench => '工作台';

  @override
  String get imageProcessing => '图片处理';

  @override
  String get sourceGallery => '源图库';

  @override
  String get sourceExplorer => '源目录浏览器';

  @override
  String get tempWorkspace => '临时工作区';

  @override
  String get processResults => '处理结果';

  @override
  String get resultCache => '结果缓存区';

  @override
  String get directories => '目录列表';

  @override
  String get addFolder => '添加文件夹';

  @override
  String get noFolders => '未添加文件夹';

  @override
  String get clickAddFolder => '点击“添加文件夹”开始扫描图像。';

  @override
  String get noImagesFound => '未找到图像';

  @override
  String get noResultsYet => '暂无结果';

  @override
  String get importFromGallery => '从系统图库导入';

  @override
  String get takePhoto => '拍摄照片';

  @override
  String get clearTempWorkspace => '清空工作区';

  @override
  String get dropFilesHere => '将图片拖放到此处以添加到临时工作区';

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
  String get thumbnailSize => '缩略图大小';

  @override
  String get deleteFile => '删除文件';

  @override
  String get deleteFileConfirmTitle => '删除文件？';

  @override
  String deleteFileConfirmMessage(String filename) {
    return '确定要删除“$filename”吗？';
  }

  @override
  String get moveToTrash => '移至回收站';

  @override
  String get permanentlyDelete => '永久删除';

  @override
  String get deleteSuccess => '删除成功';

  @override
  String deleteFailed(String error) {
    return '删除失败: $error';
  }

  @override
  String get modelSelection => '模型选择';

  @override
  String get selectAModel => '选择一个模型';

  @override
  String get aspectRatio => '比例';

  @override
  String get resolution => '分辨率';

  @override
  String get prompt => '提示词';

  @override
  String get promptHint => '在此输入提示词...';

  @override
  String get prefixHint => '例如：result';

  @override
  String get processPrompt => '处理提示词';

  @override
  String processImages(int count) {
    return '处理 $count 张图像';
  }

  @override
  String get taskSubmitted => '任务已提交至队列';

  @override
  String get comparator => '对比器';

  @override
  String get compareModeSync => '同步模式';

  @override
  String get compareModeSwap => '切换模式';

  @override
  String get sendToComparator => '发送至对比器';

  @override
  String get sendToComparatorRaw => '设置为对比原图';

  @override
  String get sendToComparatorAfter => '设置为对比效果图';

  @override
  String get sendToSelection => '添加到选中列表';

  @override
  String get sendToOptimizer => '发送到提示词优化器';

  @override
  String get optimizePromptWithImage => '以此图优化提示词';

  @override
  String get selectFromLibrary => '从库中选择';

  @override
  String get metadataSelectedNone => '未选中图像元数据';

  @override
  String get labelRaw => '原图';

  @override
  String get labelAfter => '效果图';

  @override
  String get cropAndResize => '裁剪与缩放';

  @override
  String get overwriteSource => '覆盖原图';

  @override
  String get overwriteConfirmTitle => '确定覆盖原图？';

  @override
  String get overwriteConfirmMessage => '此操作将永久修改原始文件，确定要继续吗？';

  @override
  String get saveToTempSuccess => '已保存至临时工作区';

  @override
  String get overwriteSuccess => '原图已更新';

  @override
  String get custom => '自定义';

  @override
  String get resize => '缩放';

  @override
  String get maintainAspectRatio => '保持纵横比';

  @override
  String get width => '宽度';

  @override
  String get height => '高度';

  @override
  String get sampling => '采样方式';

  @override
  String get drawMask => '绘制蒙版';

  @override
  String get maskEditor => '蒙版编辑器';

  @override
  String get brushSize => '画笔大小';

  @override
  String get maskColor => '蒙版颜色';

  @override
  String get maskOpacity => '蒙版透明度';

  @override
  String get undo => '撤销';

  @override
  String get saveToTemp => '保存至工作区';

  @override
  String get saveMaskToTemp => '保存遮罩至工作区';

  @override
  String get binaryMode => '二值化模式';

  @override
  String get maskSaved => '蒙版已保存至工作区';

  @override
  String maskSaveError(String error) {
    return '保存蒙版失败: $error';
  }

  @override
  String get promptOptimizer => '提示词优化器';

  @override
  String get refinerModel => '优化模型';

  @override
  String get systemPrompt => '系统提示词';

  @override
  String get refinerIntro => '使用 AI 分析图像并优化您的提示词。';

  @override
  String get roughPrompt => '初步想法 / 提示词';

  @override
  String get optimizedPrompt => '优化后的提示词';

  @override
  String get applyToWorkbench => '应用到工作台';

  @override
  String get promptApplied => '提示词已应用到工作台';

  @override
  String refineFailed(String error) {
    return '优化失败: $error';
  }

  @override
  String get executionLogs => '执行日志';

  @override
  String get saveToPhotos => '保存到系统相册';

  @override
  String get saveToGallery => '保存到相册';

  @override
  String get savedToPhotos => '已保存到系统相册';

  @override
  String saveFailed(String error) {
    return '保存失败: $error';
  }

  @override
  String get iosSandboxActive => 'iOS 沙盒模式生效';

  @override
  String get iosSandboxDesc => '在 iOS 上，请使用上方工具栏的“从系统图库导入”按钮将图片添加到临时工作区。';

  @override
  String get mobileSandboxActive => '移动端存储限制生效';

  @override
  String get mobileSandboxDesc =>
      '在移动设备上，直接访问文件夹可能受限。建议使用上方工具栏的“从系统图库导入”按钮将图片添加到临时工作区。';

  @override
  String get filesAppSuffix => ' (文件 App)';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get fileBrowser => '檔案瀏覽器';

  @override
  String get rename => '重新命名';

  @override
  String get renameFile => '重新命名檔案';

  @override
  String get newFilename => '新檔案名稱';

  @override
  String get renameSuccess => '重新命名成功';

  @override
  String renameFailed(String error) {
    return '重新命名失敗: $error';
  }

  @override
  String get fileAlreadyExists => '已存在同名檔案';

  @override
  String get noFilesFound => '未找到任何檔案';

  @override
  String get switchViewMode => '切換視圖模式';

  @override
  String get sortBy => '排序方式';

  @override
  String get sortName => '名稱';

  @override
  String get sortDate => '修改日期';

  @override
  String get sortType => '檔案類型';

  @override
  String get sortAsc => '升序';

  @override
  String get sortDesc => '降序';

  @override
  String get catAll => '全部';

  @override
  String get catImages => '圖片';

  @override
  String get catVideos => '影片';

  @override
  String get catAudio => '音訊';

  @override
  String get catText => '文字';

  @override
  String get catOthers => '其他';

  @override
  String get openWithSystemDefault => '使用系統預設值開啟';

  @override
  String get aiBatchRename => 'AI 批量重新命名';

  @override
  String get rulesInstructions => '重新命名規則/說明';

  @override
  String get generateSuggestions => '產生建議';

  @override
  String get noSuggestions => '尚未產生建議';

  @override
  String get applyRenames => '套用重新命名';

  @override
  String get addToSelection => '新增至選取項目';

  @override
  String get removeFromSelection => '從選取項目中移除';

  @override
  String imagesSelected(int count) {
    return '已選取 $count 個';
  }

  @override
  String get appTitle => 'Joycai Image AI Toolkits';

  @override
  String get save => '儲存';

  @override
  String get update => '更新';

  @override
  String get cancel => '取消';

  @override
  String get close => '關閉';

  @override
  String get back => '返回';

  @override
  String get next => '下一步';

  @override
  String get finish => '完成';

  @override
  String get exit => '結束';

  @override
  String get add => '新增';

  @override
  String get edit => '編輯';

  @override
  String get delete => '刪除';

  @override
  String get remove => '移除';

  @override
  String get clear => '清除';

  @override
  String get refresh => '重新整理';

  @override
  String get preview => '預覽';

  @override
  String get share => '分享';

  @override
  String get status => '狀態';

  @override
  String get started => '已開始';

  @override
  String get finished => '已完成';

  @override
  String get config => '設定';

  @override
  String get logs => '日誌';

  @override
  String get copyFilename => '複製檔案名稱';

  @override
  String get openInFolder => '在資料夾中開啟';

  @override
  String get openInPreview => '在預覽中開啟';

  @override
  String copiedToClipboard(String text) {
    return '已複製: $text';
  }

  @override
  String selectedCount(int count) {
    return '已選取 $count 個';
  }

  @override
  String shareFiles(int count) {
    return '分享選取的 $count 個項目';
  }

  @override
  String get comingSoon => '即將推出';

  @override
  String get viewAll => '檢視全部';

  @override
  String get sidebar => '側邊欄';

  @override
  String get white => '白色';

  @override
  String get black => '黑色';

  @override
  String get red => '紅色';

  @override
  String get green => '綠色';

  @override
  String get refine => '優化';

  @override
  String get apply => '套用';

  @override
  String get metadata => '元資料';

  @override
  String get filterPrompts => '篩選提示...';

  @override
  String shareFailed(String error) {
    return '分享失敗: $error';
  }

  @override
  String get downloader => '下載器';

  @override
  String get imageDownloader => '圖片下載器';

  @override
  String get url => '網址';

  @override
  String get prefix => '前綴';

  @override
  String get websiteUrl => '網站網址';

  @override
  String get websiteUrlHint => 'https://example.com';

  @override
  String get whatToFind => '要尋找什麼？';

  @override
  String get whatToFindHint => '例如：所有產品圖庫圖片';

  @override
  String get analysisModel => '分析模型';

  @override
  String get advancedOptions => '進階選項';

  @override
  String get analyzing => '分析中...';

  @override
  String get urlRequired => '請輸入有效的網站 URL。';

  @override
  String get requirementRequired => '請輸入您想要查找的圖片描述（需求）。';

  @override
  String get manualHtmlRequired => '手動模式下請先貼上 HTML 内容。';

  @override
  String get findImages => '尋找圖片';

  @override
  String get noImagesDiscovered => '尚未發現任何圖片。';

  @override
  String get enterUrlToStart => '請輸入網址和需求以開始。';

  @override
  String get addToQueue => '新增至佇列';

  @override
  String addedToQueue(int count) {
    return '已將 $count 張圖片新增至下載佇列。';
  }

  @override
  String get setOutputDirFirst => '請先在設定中設定輸出目錄。';

  @override
  String get cookiesHint => 'Cookie（Raw 或 Netscape 格式）';

  @override
  String get selectImagesToDownload => '選取要下載的圖片';

  @override
  String get importCookieFile => '匯入 Cookie 檔案';

  @override
  String get cookieFileInvalid => '不支援的 Cookie 檔案格式。請使用 Netscape 格式或純文字。';

  @override
  String cookieImportSuccess(int count) {
    return '成功匯入 $count 個 Cookie。';
  }

  @override
  String get saveOriginHtml => '儲存原始 HTML';

  @override
  String htmlSavedTo(String path) {
    return 'HTML 已儲存至: $path';
  }

  @override
  String get manualHtmlMode => '手動 HTML 模式';

  @override
  String get manualHtmlHint => '在此貼上呈現的 HTML（F12 -> 複製外部 HTML）';

  @override
  String get cookieHistory => 'Cookie 歷史記錄';

  @override
  String get noCookieHistory => '未儲存任何 Cookie 歷史記錄';

  @override
  String get pasteFromClipboard => '從剪貼簿貼上';

  @override
  String get openRawImage => '開啟原始圖片';

  @override
  String get usage => '用量';

  @override
  String get tokenUsageMetrics => 'Token 用量指標';

  @override
  String get clearAllUsage => '要清除所有用量資料嗎？';

  @override
  String get clearUsageWarning => '這將永久刪除資料庫中的所有 Token 用量記錄。';

  @override
  String get modelsLabel => '模型：';

  @override
  String get rangeLabel => '範圍：';

  @override
  String get today => '今天';

  @override
  String get lastWeek => '上週';

  @override
  String get lastMonth => '上個月';

  @override
  String get thisYear => '今年';

  @override
  String get inputTokens => '輸入 Token';

  @override
  String get outputTokens => '輸出 Token';

  @override
  String get estimatedCost => '預估成本';

  @override
  String clearDataForModel(String modelId) {
    return '要清除 $modelId 的資料嗎？';
  }

  @override
  String clearModelDataWarning(String modelId) {
    return '這將刪除與模型「$modelId」相關的所有用量記錄。';
  }

  @override
  String get clearModelData => '清除模型資料';

  @override
  String get usageByGroup => '按群組分類的用量';

  @override
  String get clearAll => '清除全部';

  @override
  String get models => '模型';

  @override
  String get modelManagement => '模型管理';

  @override
  String get feeManagement => '費用管理';

  @override
  String get modelsTab => '模型';

  @override
  String get channelsTab => '通道';

  @override
  String get addChannel => '新增通道';

  @override
  String get editChannel => '編輯通道';

  @override
  String get basicInfo => '基本資訊';

  @override
  String get configuration => '設定';

  @override
  String get tagAndAppearance => '標籤與外觀';

  @override
  String get billing => '計費';

  @override
  String get channelType => '通道類型';

  @override
  String get enableDiscovery => '啟用模型探索';

  @override
  String get filterModels => '篩選模型...';

  @override
  String get tagColor => '標籤顏色';

  @override
  String deleteChannelConfirm(String name) {
    return '您確定要刪除通道「$name」嗎？這將會取消所有關聯模型的連結。';
  }

  @override
  String get modelManager => '模型管理員';

  @override
  String get name => '名稱';

  @override
  String get addModel => '新增模型';

  @override
  String get editModel => '編輯模型';

  @override
  String get noModelsConfigured => '未設定模型';

  @override
  String countModels(int count) {
    return '$count 個模型';
  }

  @override
  String get addFirstModel => '新增您的第一個 LLM 模型以開始';

  @override
  String get addNewModel => '新增模型';

  @override
  String get deleteModel => '刪除模型';

  @override
  String get deleteModelConfirmTitle => '刪除模型？';

  @override
  String deleteModelConfirmMessage(String name) {
    return '您確定要刪除「$name」嗎？';
  }

  @override
  String get addLlmModel => '新增 LLM 模型';

  @override
  String get editLlmModel => '編輯 LLM 模型';

  @override
  String get modelIdLabel => '模型 ID（例如 gemini-pro）';

  @override
  String get displayName => '顯示名稱';

  @override
  String get type => '類型';

  @override
  String get tag => '標籤';

  @override
  String get inputFeeLabel => '輸入費用（美元/百萬 Token）';

  @override
  String get outputFeeLabel => '輸出費用（美元/百萬 Token）';

  @override
  String get paidModel => '付費模型';

  @override
  String get freeModel => '免費模型';

  @override
  String get billingMode => '計費模式';

  @override
  String get perToken => '每百萬 Token';

  @override
  String get perRequest => '每次請求';

  @override
  String get requestFeeLabel => '請求費用（美元/次）';

  @override
  String get requestCount => '請求次數';

  @override
  String get requests => '請求';

  @override
  String get feeGroups => '費用群組';

  @override
  String get feeGroup => '費用群組';

  @override
  String get channels => '通道';

  @override
  String get channel => '通道';

  @override
  String get noFeeGroup => '無費用群組';

  @override
  String get inputPrice => '輸入價格（美元/百萬 Token）';

  @override
  String get outputPrice => '輸出價格（美元/百萬 Token）';

  @override
  String get requestPrice => '請求價格（美元/次）';

  @override
  String get priceConfig => '價格設定';

  @override
  String get addFeeGroup => '新增費用群組';

  @override
  String get editFeeGroup => '編輯費用群組';

  @override
  String deleteFeeGroupConfirm(String name) {
    return '刪除費用群組「$name」？';
  }

  @override
  String get groupName => '群組名稱';

  @override
  String get fetchModels => '擷取模型';

  @override
  String get discoveringModels => '正在探索模型...';

  @override
  String get selectModelsToAdd => '選取要新增的模型';

  @override
  String get searchModels => '搜尋模型名稱或 ID...';

  @override
  String get selectAll => '全選';

  @override
  String get deselectAll => '取消全選';

  @override
  String modelsDiscovered(int count) {
    return '已探索 $count 個模型';
  }

  @override
  String addSelected(int count) {
    return '新增選取的 ($count)';
  }

  @override
  String get alreadyAdded => '已新增';

  @override
  String get noNewModelsFound => '未找到新模型。';

  @override
  String fetchFailed(String error) {
    return '擷取模型失敗：$error';
  }

  @override
  String get stepProtocol => '選擇協議';

  @override
  String get stepProvider => '選擇供應商';

  @override
  String get stepApiKey => 'API 金鑰';

  @override
  String get stepConfig => '額外設定';

  @override
  String get stepPreview => '預覽';

  @override
  String get protocolOpenAI => 'OpenAI 相容 (REST)';

  @override
  String get protocolOpenAIDesc => '標準 OpenAI REST API 相容性';

  @override
  String get protocolGoogle => 'Google GenAI (REST)';

  @override
  String get protocolGoogleDesc => '官方 Google Gemini REST API';

  @override
  String get providerOpenAIOfficial => 'OpenAI 官方';

  @override
  String get providerGoogleOfficial => 'Google GenAI 官方';

  @override
  String get providerGoogleCompatible => 'Google GenAI (OpenAI 相容)';

  @override
  String get providerGoogleCompatibleDesc => '透過 OpenAI 端點的 Google Gemini';

  @override
  String get providerCustom => '自訂供應商';

  @override
  String get providerCustomDesc => '自行託管或第三方供應商';

  @override
  String get customEndpointHint => '輸入您的自訂端點 URL';

  @override
  String get openaiV1Hint => '提示：OpenAI 相容端點通常以「/v1」結尾';

  @override
  String get googleV1BetaHint => '提示：Google GenAI 端點通常以「/v1beta」結尾';

  @override
  String get enterApiKey => '輸入您的 API 金鑰';

  @override
  String get apiKeyStorageNotice => '您的金鑰會儲存在本機，絕不會傳送至我們的伺服器。';

  @override
  String get nameHint => '例如：我的正式版 API';

  @override
  String get enableDiscoveryDesc => '從此端點自動列出可用的模型';

  @override
  String get tagHint => '例如：GPT4、Local 等。';

  @override
  String get bindTag => '綁定標籤';

  @override
  String get previewReady => '準備好新增此通道了嗎？';

  @override
  String get feeGroupDesc => '定義模型的計費標準，以準確計算使用成本。';

  @override
  String get noFeeGroups => '尚未建立費用群組';

  @override
  String get pricePerMillion => '每百萬 Token 價格';

  @override
  String get pricePerRequest => '每次請求價格';

  @override
  String get tokenBilling => 'Token 計費';

  @override
  String get requestBilling => '請求計費';

  @override
  String get model => '模型';

  @override
  String get prompts => '提示';

  @override
  String get promptLibrary => '提示庫';

  @override
  String get newPrompt => '新提示';

  @override
  String get editPrompt => '編輯提示';

  @override
  String get noPromptsSaved => '未儲存任何提示';

  @override
  String get saveFavoritePrompts => '在此儲存您最愛的提示或 Refiner 系統提示';

  @override
  String get createFirstPrompt => '建立第一個提示';

  @override
  String get deletePromptConfirmTitle => '刪除提示？';

  @override
  String deletePromptConfirmMessage(String title) {
    return '您確定要刪除「$title」嗎？';
  }

  @override
  String get title => '標題';

  @override
  String get tagCategory => '標籤（類別）';

  @override
  String get setAsRefiner => '設為 Refiner';

  @override
  String get promptContent => '提示內容';

  @override
  String get userPrompts => '使用者提示';

  @override
  String get refinerPrompts => 'Refiner 提示';

  @override
  String get systemTemplates => '系統範本';

  @override
  String get templateType => '範本類型';

  @override
  String get typeRename => '批次重新命名';

  @override
  String get typeRefiner => '提示 Refiner';

  @override
  String get selectRenameTemplate => '選取重新命名範本';

  @override
  String get selectCategory => '選取類別';

  @override
  String get categoriesTab => '類別';

  @override
  String get addCategory => '新增類別';

  @override
  String get editCategory => '編輯類別';

  @override
  String get library => '媒體庫';

  @override
  String get refiner => 'Refiner';

  @override
  String get settings => '設定';

  @override
  String get appearance => '外觀';

  @override
  String get connectivity => '連線';

  @override
  String get application => '應用程式';

  @override
  String get proxySettings => '代理伺服器設定';

  @override
  String get enableProxy => '啟用全域代理伺服器';

  @override
  String get proxyUrl => '代理伺服器 URL (主機:連接埠)';

  @override
  String get proxyUsername => '代理伺服器使用者名稱 (選用)';

  @override
  String get proxyPassword => '代理伺服器密碼 (選用)';

  @override
  String get language => '語言';

  @override
  String get themeAuto => '自動';

  @override
  String get themeLight => '淺色';

  @override
  String get themeDark => '深色';

  @override
  String get googleGenAiSettings => 'Google GenAI REST 設定';

  @override
  String get openAiApiSettings => 'OpenAI API REST 設定';

  @override
  String get standardConfig => '標準設定';

  @override
  String get endpointUrl => '端點 URL';

  @override
  String get apiKey => 'API 金鑰';

  @override
  String get outputDirectory => '輸出目錄';

  @override
  String get notSet => '未設定';

  @override
  String get dataManagement => '資料管理';

  @override
  String get exportSettings => '匯出設定';

  @override
  String get importSettings => '匯入設定';

  @override
  String get openAppDataDirectory => '開啟應用程式資料目錄';

  @override
  String get mcpServerSettings => 'MCP 伺服器設定';

  @override
  String get enableMcpServer => '啟用 MCP 伺服器';

  @override
  String get port => '連接埠';

  @override
  String get resetAllSettings => '重設所有設定';

  @override
  String get confirmReset => '要重設所有設定嗎？';

  @override
  String get resetWarning => '這將會刪除所有設定、模型和新增的資料夾。此動作無法復原。';

  @override
  String get resetEverything => '全部重設';

  @override
  String get settingsExported => '設定已成功匯出';

  @override
  String get settingsImported => '設定已成功匯入';

  @override
  String get exportOptions => '匯出選項';

  @override
  String get includeDirectories => '包含目錄設定';

  @override
  String get includeDirectoriesDesc => '工作台/瀏覽器目錄和輸出路徑';

  @override
  String get includePrompts => '包含提示';

  @override
  String get includePromptsDesc => '使用者和系統提示庫';

  @override
  String get includeUsage => '包含用量指標';

  @override
  String get includeUsageDesc => 'API Token 消耗歷史記錄';

  @override
  String get exportNow => '立即匯出';

  @override
  String get importNow => '立即匯入';

  @override
  String get importOptions => '匯入選項';

  @override
  String get notInBackup => '備份檔案中不可用';

  @override
  String get importSettingsTitle => '匯入設定？';

  @override
  String get importSettingsConfirm =>
      '這將會取代您目前所有的模型、通道和類別。\n\n注意：獨立的提示庫不受此匯入影響。請使用「提示」畫面進行提示資料管理。';

  @override
  String get importAndReplace => '匯入並取代';

  @override
  String get importMode => '匯入模式';

  @override
  String get importModeDesc =>
      '選擇您要如何匯入提示：\n\n合併：將新項目新增至您的媒體庫。\n取代：刪除目前的媒體庫並使用匯入的資料。';

  @override
  String get merge => '合併';

  @override
  String get replaceAll => '全部取代';

  @override
  String get applyOverwrite => '套用 (覆寫)';

  @override
  String get applyAppend => '套用 (附加)';

  @override
  String get portableMode => '可攜式模式';

  @override
  String get portableModeDesc => '將資料庫和快取儲存在應用程式資料夾中 (需要重新啟動)';

  @override
  String get restartRequired => '需要重新啟動';

  @override
  String get restartMessage => '必須重新啟動應用程式才能套用資料儲存位置的變更。';

  @override
  String get enableNotifications => '啟用系統通知';

  @override
  String get runSetupWizard => '執行設定精靈';

  @override
  String get clearDownloaderCache => '清除下載器快取';

  @override
  String get enableApiDebug => '啟用 API 偵錯記錄';

  @override
  String get apiDebugDesc =>
      '將原始 API 要求和回應記錄到檔案中以進行疑難排解。警告：如果未遮罩，API 金鑰等敏感資料可能會被記錄。';

  @override
  String get openLogFolder => '開啟記錄資料夾';

  @override
  String get iosOutputRecommend => '建議：在 iOS 上保留預設值。應用程式的資料夾可在「檔案」應用程式中看到。';

  @override
  String get downloaderCacheCleared => '下載器快取已清除。';

  @override
  String get tasks => '任務';

  @override
  String get taskQueueManager => '任務佇列管理員';

  @override
  String get noTasksInQueue => '佇列中沒有任務';

  @override
  String get submitTaskFromWorkbench => '從工作台提交任務以在此處查看。';

  @override
  String taskId(String id) {
    return '任務 ID: $id';
  }

  @override
  String get taskSummary => '任務摘要';

  @override
  String get pendingTasks => '待處理';

  @override
  String get processingTasks => '處理中';

  @override
  String get completedTasks => '已完成';

  @override
  String get failedTasks => '已失敗';

  @override
  String get clearCompleted => '清除已完成';

  @override
  String get cancelAllPending => '全部取消待辦';

  @override
  String get cancelTask => '取消任務';

  @override
  String get removeFromList => '從清單中移除';

  @override
  String get images => '圖片';

  @override
  String filesCount(int count) {
    return '$count 個檔案';
  }

  @override
  String runningCount(int count) {
    return '$count 個執行中';
  }

  @override
  String plannedCount(int count) {
    return '$count 個計畫中';
  }

  @override
  String get latestLog => '最新日誌：';

  @override
  String get taskCompletedNotification => '任務完成';

  @override
  String get taskFailedNotification => '任務失敗';

  @override
  String taskCompletedBody(String id) {
    return '任務 $id 已成功完成。';
  }

  @override
  String taskFailedBody(String id) {
    return '處理任務 $id 失敗。';
  }

  @override
  String get queueSettings => '佇列設定';

  @override
  String concurrencyLimit(int limit) {
    return '並行限制：$limit';
  }

  @override
  String retryCount(int count) {
    return '重試次數：$count';
  }

  @override
  String get setupWizardTitle => '歡迎設定';

  @override
  String get welcomeMessage => '歡迎使用 Joycai Image AI Toolkits！讓我們為您完成設定。';

  @override
  String get getStarted => '開始使用';

  @override
  String get stepAppearance => '外觀';

  @override
  String get stepStorage => '儲存';

  @override
  String get stepApi => '智慧 (API)';

  @override
  String get setupCompleteMessage => '您已全部設定完成！盡情享受創作吧。';

  @override
  String get skip => '略過';

  @override
  String get storageLocationDesc => '選取產生的圖片將儲存的位置。';

  @override
  String get addChannelOptional => '新增您的第一個 AI 供應商通道 (選用)。';

  @override
  String get configureModelOptional => '為您的新通道設定模型 (選用)。';

  @override
  String get googleGenAiFree => 'Google GenAI (免費)';

  @override
  String get googleGenAiPaid => 'Google GenAI (付費)';

  @override
  String get openaiApi => 'OpenAI API';

  @override
  String get filenamePrefix => '檔案名稱前綴詞';

  @override
  String get openaiEndpointHint => '提示：OpenAI 相容端點通常以「/v1」結尾';

  @override
  String get googleEndpointHint => '提示：Google GenAI 端點通常以「/v1beta」結尾 (內部處理)';

  @override
  String get workbench => '工作台';

  @override
  String get imageProcessing => '圖片處理';

  @override
  String get sourceGallery => '來源圖庫';

  @override
  String get sourceExplorer => '來源瀏覽器';

  @override
  String get tempWorkspace => '臨時工作區';

  @override
  String get processResults => '處理結果';

  @override
  String get resultCache => '結果快取';

  @override
  String get directories => '目錄';

  @override
  String get addFolder => '新增資料夾';

  @override
  String get noFolders => '未新增資料夾';

  @override
  String get clickAddFolder => '點擊「新增資料夾」開始掃描圖片。';

  @override
  String get noImagesFound => '未找到圖片';

  @override
  String get noResultsYet => '尚無結果';

  @override
  String get importFromGallery => '從圖庫匯入';

  @override
  String get takePhoto => '拍照';

  @override
  String get clearTempWorkspace => '清除工作區';

  @override
  String get dropFilesHere => '將圖片拖放到此處以新增到臨時工作區';

  @override
  String get noImagesSelected => '未選取圖片';

  @override
  String get selectSourceDirectory => '選取來源目錄';

  @override
  String get removeFolderTooltip => '移除資料夾';

  @override
  String get removeFolderConfirmTitle => '移除資料夾？';

  @override
  String removeFolderConfirmMessage(String folderName) {
    return '您確定要從列表中移除「$folderName」嗎？';
  }

  @override
  String get thumbnailSize => '縮圖大小';

  @override
  String get deleteFile => '刪除檔案';

  @override
  String get deleteFileConfirmTitle => '刪除檔案？';

  @override
  String deleteFileConfirmMessage(String filename) {
    return '您確定要刪除「$filename」嗎？';
  }

  @override
  String get moveToTrash => '移至資源回收筒';

  @override
  String get permanentlyDelete => '永久刪除';

  @override
  String get deleteSuccess => '刪除成功';

  @override
  String deleteFailed(String error) {
    return '刪除失敗：$error';
  }

  @override
  String get modelSelection => '模型選取';

  @override
  String get selectAModel => '選取模型';

  @override
  String get aspectRatio => '長寬比';

  @override
  String get resolution => '解析度';

  @override
  String get prompt => '提示詞';

  @override
  String get promptHint => '在此輸入提示詞...';

  @override
  String get prefixHint => '例如：result';

  @override
  String get processPrompt => '處理提示詞';

  @override
  String processImages(int count) {
    return '處理 $count 張圖片';
  }

  @override
  String get taskSubmitted => '任務已提交至佇列';

  @override
  String get comparator => '比較器';

  @override
  String get compareModeSync => '同步模式';

  @override
  String get compareModeSwap => '交換模式';

  @override
  String get sendToComparator => '發送到比較器';

  @override
  String get sendToComparatorRaw => '設為原始圖 (RAW)';

  @override
  String get sendToComparatorAfter => '設為處理後 (Result)';

  @override
  String get sendToSelection => '新增至選取項目';

  @override
  String get sendToOptimizer => '發送到提示詞優化器';

  @override
  String get optimizePromptWithImage => '使用圖片優化提示詞';

  @override
  String get selectFromLibrary => '從庫中選取';

  @override
  String get metadataSelectedNone => '未選取圖片中繼資料';

  @override
  String get labelRaw => '原始';

  @override
  String get labelAfter => '處理後';

  @override
  String get cropAndResize => '裁切與調整大小';

  @override
  String get overwriteSource => '覆蓋原始檔案';

  @override
  String get overwriteConfirmTitle => '覆蓋原始檔案？';

  @override
  String get overwriteConfirmMessage => '此操作將永久替換原始檔案。您確定嗎？';

  @override
  String get saveToTempSuccess => '圖片已儲存至臨時工作區';

  @override
  String get overwriteSuccess => '原始檔案已更新';

  @override
  String get custom => '自訂';

  @override
  String get resize => '調整大小';

  @override
  String get maintainAspectRatio => '保持長寬比';

  @override
  String get width => '寬度';

  @override
  String get height => '高度';

  @override
  String get sampling => '採樣';

  @override
  String get drawMask => '繪製遮罩';

  @override
  String get maskEditor => '遮罩編輯器';

  @override
  String get brushSize => '畫筆大小';

  @override
  String get maskColor => '遮罩顏色';

  @override
  String get maskOpacity => '遮罩透明度';

  @override
  String get undo => '復原';

  @override
  String get saveToTemp => '儲存到工作區';

  @override
  String get saveMaskToTemp => '儲存遮罩到工作區';

  @override
  String get binaryMode => '二進制模式';

  @override
  String get maskSaved => '遮罩已儲存到工作區';

  @override
  String maskSaveError(String error) {
    return '儲存遮罩出錯：$error';
  }

  @override
  String get promptOptimizer => '提示詞優化器';

  @override
  String get refinerModel => '優化模型';

  @override
  String get systemPrompt => '系統提示詞';

  @override
  String get refinerIntro => '使用 AI 分析圖片並優化您的提示詞。';

  @override
  String get roughPrompt => '初步想法 / 草稿';

  @override
  String get optimizedPrompt => '優化後的提示詞';

  @override
  String get applyToWorkbench => '套用到工作台';

  @override
  String get promptApplied => '提示詞已套用到工作台';

  @override
  String refineFailed(String error) {
    return '優化失敗：$error';
  }

  @override
  String get executionLogs => '執行日誌';

  @override
  String get saveToPhotos => '儲存到照片';

  @override
  String get saveToGallery => '儲存到相簿';

  @override
  String get savedToPhotos => '已儲存到照片';

  @override
  String saveFailed(String error) {
    return '儲存失敗：$error';
  }

  @override
  String get iosSandboxActive => 'iOS 沙盒已啟用';

  @override
  String get iosSandboxDesc => '在 iOS 上，請使用頂部工具列中的「從圖庫匯入」按鈕將圖片新增到您的臨時工作區。';

  @override
  String get mobileSandboxActive => '行動裝置儲存限制';

  @override
  String get mobileSandboxDesc =>
      '在行動裝置上，操作系統可能會限制直接存取資料夾。建議使用頂部工具列中的「從圖庫匯入」按鈕。';

  @override
  String get filesAppSuffix => ' (檔案 App)';
}
