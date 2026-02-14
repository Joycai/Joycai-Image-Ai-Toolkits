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
  String get fileBrowser => '文件浏览器';

  @override
  String get downloader => '下载器';

  @override
  String get url => '地址';

  @override
  String get prefix => '前缀';

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
  String get sourceExplorer => '源目录浏览器';

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
  String retryCount(int count) {
    return '重试次数: $count';
  }

  @override
  String get back => '返回';

  @override
  String get next => '下一步';

  @override
  String get storageLocationDesc => '选择生成图像的保存位置。';

  @override
  String get addChannelOptional => '添加您的第一个 AI 渠道（可选）。';

  @override
  String get configureModelOptional => '为新渠道配置一个模型（可选）。';

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
  String get exit => '退出';

  @override
  String get applyOverwrite => '应用 (覆盖)';

  @override
  String get applyAppend => '应用 (追加)';

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
  String get clearAll => '全部清除';

  @override
  String get cancelAllPending => '取消所有等待中';

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
  String get modelManagement => '模型管理';

  @override
  String get feeManagement => '费用管理';

  @override
  String get modelsTab => '模型管理';

  @override
  String get channelsTab => '渠道管理';

  @override
  String get categoriesTab => '分类管理';

  @override
  String get addCategory => '添加分类';

  @override
  String get editCategory => '编辑分类';

  @override
  String get addChannel => '添加渠道';

  @override
  String get editChannel => '编辑渠道';

  @override
  String get channelType => '渠道类型';

  @override
  String get enableDiscovery => '启用模型检索';

  @override
  String get filterModels => '过滤模型...';

  @override
  String get filterPrompts => '过滤提示词...';

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
  String get add => '添加';

  @override
  String get executionLogs => '执行日志';

  @override
  String get clickToExpand => '点击展开';

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
  String get aiBatchRename => 'AI 批量重命名';

  @override
  String get switchViewMode => '切换视图模式';

  @override
  String get noFilesFound => '未找到文件';

  @override
  String get rulesInstructions => '重命名规则 / 指令';

  @override
  String get generateSuggestions => '生成建议';

  @override
  String get noSuggestions => '尚未生成建议';

  @override
  String get applyRenames => '应用重命名';

  @override
  String get originalName => '原始名称';

  @override
  String get newName => '新名称';

  @override
  String get status => '状态';

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
  String get deleteSuccess => '删除成功';

  @override
  String deleteFailed(String error) {
    return '删除失败: $error';
  }

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
  String get portableMode => '便携模式';

  @override
  String get portableModeDesc => '在应用程序文件夹中存储数据库和缓存 (需要重启)';

  @override
  String get restartRequired => '需要重启';

  @override
  String get restartMessage => '必须重启应用程序以应用对数据存储位置的更改。';

  @override
  String get usageByGroup => '按费率组统计';

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
  String get googleGenAiFree => 'Google GenAI (免费)';

  @override
  String get googleGenAiPaid => 'Google GenAI (付费)';

  @override
  String get openaiApi => 'OpenAI API';

  @override
  String get filenamePrefix => '文件名前缀';

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
  String get finish => '完成';

  @override
  String get setupCompleteMessage => '设置完成！尽情创作吧。';

  @override
  String get runSetupWizard => '运行设置向导';

  @override
  String get clearDownloaderCache => '清除下载器缓存';

  @override
  String get skip => '跳过';

  @override
  String get fetchModels => '获取模型';

  @override
  String get discoveringModels => '正在发现模型...';

  @override
  String get selectModelsToAdd => '选择要添加的模型';

  @override
  String addSelected(Object count) {
    return '添加所选 ($count)';
  }

  @override
  String get alreadyAdded => '已添加';

  @override
  String get noNewModelsFound => '未发现新模型。';

  @override
  String fetchFailed(Object error) {
    return '获取模型失败: $error';
  }

  @override
  String get edit => '编辑';

  @override
  String get preview => '预览';

  @override
  String get openRawImage => '打开原始图像';

  @override
  String get pasteFromClipboard => '从剪贴板粘贴';

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
  String get openInPreview => '在预览窗口打开';

  @override
  String get comparator => '对比器';

  @override
  String get openWithSystemDefault => '使用系统默认程序打开';

  @override
  String get drawMask => '绘制蒙版';

  @override
  String get maskEditor => '蒙版编辑器';

  @override
  String get brushSize => '画笔大小';

  @override
  String get maskColor => '蒙版颜色';

  @override
  String get undo => '撤销';

  @override
  String get saveAndSelect => '保存并选中';

  @override
  String get black => '黑色';

  @override
  String get white => '白色';

  @override
  String get red => '红色';

  @override
  String get green => '绿色';

  @override
  String get sendToSelection => '发送到选中列表';

  @override
  String get sendToComparator => '发送至对比器';

  @override
  String get sendToComparatorRaw => '发送至对比器 (原图)';

  @override
  String get sendToComparatorAfter => '发送至对比器 (后图)';

  @override
  String get compareModeSync => '同步模式';

  @override
  String get compareModeSwap => '切换模式';

  @override
  String get tempWorkspace => '临时工作区';

  @override
  String get clearTempWorkspace => '清空工作区';

  @override
  String get dropFilesHere => '将图片拖放到此处以添加到临时工作区';

  @override
  String get enableNotifications => '启用系统通知';

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
  String get imageDownloader => '图像下载器';

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
  String get findImages => '寻找图像';

  @override
  String get noImagesDiscovered => '尚未发现图像。';

  @override
  String get enterUrlToStart => '输入网址和需求以开始。';

  @override
  String get addToQueue => '添加到下载队列';

  @override
  String imagesSelected(int count) {
    return '已选 $count 张';
  }

  @override
  String addedToQueue(int count) {
    return '已将 $count 张图像添加到下载队列。';
  }

  @override
  String get setOutputDirFirst => '请先在设置中设置输出目录。';

  @override
  String get cookiesHint => 'Cookie (原始或 Netscape 格式)';

  @override
  String get logs => '日志';

  @override
  String get selectImagesToDownload => '选择要下载的图像';

  @override
  String get openaiEndpointHint => '提示：OpenAI 兼容接口通常以 \'/v1\' 结尾';

  @override
  String get googleEndpointHint =>
      '提示：Google GenAI 接口通常以 \'/v1beta\' 结尾（内部已处理）';

  @override
  String get importCookieFile => '导入 Cookie 文件';

  @override
  String get cookieFileInvalid => '不支持的 Cookie 文件格式。请使用 Netscape 格式或原始文本。';

  @override
  String cookieImportSuccess(Object count) {
    return '成功导入 $count 条 Cookie。';
  }

  @override
  String get share => '分享';

  @override
  String shareFiles(int count) {
    return '分享选中的项 ($count)';
  }

  @override
  String get importFromGallery => '从系统图库导入';

  @override
  String get enableApiDebug => '开启 API 调试日志';

  @override
  String get apiDebugDesc => '将原始 API 请求和响应记录到文件中以便排查问题。警告：API 密钥等敏感数据可能会被记录。';

  @override
  String get openLogFolder => '打开日志目录';

  @override
  String get promptOptimizer => '提示词优化器';

  @override
  String get refinerIntro => '使用 AI 分析图像并优化您的提示词。';

  @override
  String get roughPrompt => '初步想法 / 提示词';

  @override
  String get optimizedPrompt => '优化后的提示词';

  @override
  String get applyToWorkbench => '应用到工作台';

  @override
  String get sidebar => '侧边栏';
}
