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
  String get searchFilesHint => '搜索文件名…';

  @override
  String get deselectAllDirectories => '取消全部目录选择';

  @override
  String get applyRenames => '应用重命名';

  @override
  String get additionalInstructions => '补充指令（可选）';

  @override
  String get aiRenameInstructionsHint => '例如：保留原扩展名、转换为拼音…';

  @override
  String get noTemplateSelected => '未选择模板';

  @override
  String get selectTemplateFirst => '请先选择一个重命名模板。';

  @override
  String get generatingSuggestions => '正在生成建议…';

  @override
  String get renamePreviewTitle => '重命名预览';

  @override
  String conflictsFound(int count) {
    return '$count 个冲突';
  }

  @override
  String get conflictDuplicateTarget => '目标文件名重复';

  @override
  String get addToSelection => '添加到选中列表';

  @override
  String get removeFromSelection => '从选中列表移除';

  @override
  String imagesSelected(int count) {
    return '已选 $count 项';
  }

  @override
  String get featureLimitedOnMobile => '功能受限于移动端';

  @override
  String get fileBrowserDesktopOnlyDesc =>
      '由于操作系统沙盒限制，高级文件浏览器和批量重命名功能仅在桌面版本上可用。';

  @override
  String get fileBrowseriOSHint => '请使用系统文件 App 来管理您的生成图像。';

  @override
  String get fileBrowserAndroidHint => '请使用设备的文件管理器来整理文件。';

  @override
  String get stagingArea => '暂存区';

  @override
  String get addToStaging => '加入暂存区';

  @override
  String addToStagingCount(int count) {
    return '加入暂存区 · $count 项';
  }

  @override
  String get removeFromStaging => '从暂存区移除';

  @override
  String get stagedBadge => '已暂存';

  @override
  String get clearStaging => '清空';

  @override
  String get stagingEmptyTitle => '暂存区是空的';

  @override
  String get stagingEmptyDesc =>
      '选中文件后点「加入暂存区」，把要搬运的文件先记在这里 —— 只做标记，不移动任何文件。切换目录、筛选或重启应用都不会丢。';

  @override
  String get stagingTarget => '目标目录';

  @override
  String get stagingNoTarget => '未选择目标目录';

  @override
  String get stagingTargetHint => '在左栏文件夹上右键「移动 / 复制到此」，或把文件直接拖到文件夹上。';

  @override
  String stagingRestored(int count) {
    return '已从上次会话恢复 $count 项';
  }

  @override
  String get stagingSameAsTarget => '与目标相同 · 执行时跳过';

  @override
  String get stagingMissing => '已失效';

  @override
  String stagingClearMissing(int count) {
    return '清理失效项 ($count)';
  }

  @override
  String get moveHere => '移动到此';

  @override
  String get copyHere => '复制到此';

  @override
  String moveCountHere(int count) {
    return '移动 $count 项到此';
  }

  @override
  String copyCountHere(int count) {
    return '复制 $count 项到此';
  }

  @override
  String stagingItemsCount(int count) {
    return '$count 项';
  }

  @override
  String stagingMissingCount(int count) {
    return '$count 项失效';
  }

  @override
  String stagingAtTargetCount(int count) {
    return '$count 项已在目标目录（将跳过）';
  }

  @override
  String get onlyThisDirectory => '仅看此目录';

  @override
  String pasteMoveTitle(String folder) {
    return '移动到 $folder';
  }

  @override
  String pasteCopyTitle(String folder) {
    return '复制到 $folder';
  }

  @override
  String get pasteNoDestination => '请先指定目标目录';

  @override
  String get pasteDestinationGone => '目标目录已不存在';

  @override
  String get pasteNothingToDo => '没有可搬运的文件';

  @override
  String get conflictsTitle => '处理同名冲突';

  @override
  String get conflictSkip => '跳过';

  @override
  String get conflictOverwrite => '覆盖';

  @override
  String get conflictRename => '自动改名';

  @override
  String get conflictApplyToRest => '对全部剩余项应用';

  @override
  String get conflictReasonExists => '目标目录中已存在';

  @override
  String get conflictReasonDuplicate => '另一个暂存文件同名';

  @override
  String get conflictReasonSameLocation => '已在此目录中';

  @override
  String get conflictReasonMissing => '源文件已不存在';

  @override
  String get pasteCrossVolumeWarning => '跨盘搬运：先复制再删除，耗时更久，且可能中途停下。';

  @override
  String get pasteRunningMove => '正在移动…';

  @override
  String get pasteRunningCopy => '正在复制…';

  @override
  String pasteProgressCount(int done, int total) {
    return '$done / $total';
  }

  @override
  String get pasteDoneTitle => '搬运完成';

  @override
  String get pasteCancelledTitle => '搬运已取消';

  @override
  String pasteSucceededCount(int count) {
    return '成功 $count 项';
  }

  @override
  String pasteSkippedCount(int count) {
    return '跳过 $count 项';
  }

  @override
  String pasteFailedCount(int count) {
    return '失败 $count 项';
  }

  @override
  String renameSubtitleFiles(int files, int dirs) {
    return '$files 个文件 · 来自 $dirs 个目录';
  }

  @override
  String get renameSectionModel => '模型';

  @override
  String get renameSectionTemplate => '命名模板';

  @override
  String get renameSectionInstructions => '补充指令';

  @override
  String renameBatchEstimate(int files, int size, int batches) {
    return '$files 个文件 · 每批 $size · 预计 $batches 批';
  }

  @override
  String get renameStopGenerating => '中断生成';

  @override
  String get renameRegenerate => '重新生成';

  @override
  String get renameFilterAll => '全部';

  @override
  String get renameFilterConflicts => '冲突';

  @override
  String get renameFilterSkipped => '已跳过';

  @override
  String get renameNextConflict => '下一个冲突';

  @override
  String get renameEmptyTitle => '还没有建议';

  @override
  String renameEmptyDesc(int files, int batches, int size) {
    return '在左侧选好模型与命名模板后点「生成建议」。$files 个文件将按每批 $size 个分 $batches 批提交，生成过程中即可开始逐项审阅。';
  }

  @override
  String get renameGenerating => '正在生成建议';

  @override
  String renameBatchProgress(int batch, int total, int done, int files) {
    return '第 $batch / $total 批 · 已产出 $done / $files 条';
  }

  @override
  String get renameStop => '中断';

  @override
  String renameProducedHint(int count) {
    return '已产出 $count 条 · 生成完成前可先审阅，不能应用';
  }

  @override
  String renameSuggestionsCount(int count) {
    return '$count 条建议';
  }

  @override
  String renameSkippedCount(int count) {
    return '已跳过 $count';
  }

  @override
  String renameEditingHint(int row) {
    return '第 $row 行正在就地改名';
  }

  @override
  String renameConflictsPending(int count) {
    return '$count 个冲突待处理 · 未决冲突不会被应用';
  }

  @override
  String renameApplyCount(int count) {
    return '应用 $count 项重命名';
  }

  @override
  String renameApplyShort(int count) {
    return '应用 $count 项';
  }

  @override
  String get renameDuplicateBadge => '重名';

  @override
  String get renameSkippedBadge => '已跳过';

  @override
  String get renameRenamedBadge => '已改名';

  @override
  String get renameActionAccept => '接受';

  @override
  String get renameActionSkip => '跳过';

  @override
  String get renameActionEdit => '就地改名';

  @override
  String get renameActionUndo => '撤销跳过';

  @override
  String get renameConflictAutoRename => '改名';

  @override
  String get renameNoModelsTitle => '没有可用的语言模型';

  @override
  String get renameNoModelsDesc =>
      '批量重命名需要一个对话模型来阅读图片并生成名字。请先在「模型与渠道」里配置至少一个可用渠道。';

  @override
  String get renameGoToSettings => '前往设置';

  @override
  String renameBatchFailed(int batch, String reason) {
    return '第 $batch 批请求失败 · $reason';
  }

  @override
  String renameBatchFailedDesc(int kept, int missing) {
    return '已产出的 $kept 条建议已保留，未生成的 $missing 个文件可单独重试';
  }

  @override
  String get renameRetryBatch => '重试此批';

  @override
  String get renameEditConfig => '编辑配置';

  @override
  String get renameTemplateLabel => '模板';

  @override
  String pasteMovingCount(int count) {
    return '正在移动 $count 项';
  }

  @override
  String pasteCopyingCount(int count) {
    return '正在复制 $count 项';
  }

  @override
  String pasteRoute(String from_, String to) {
    return '$from_ → $to';
  }

  @override
  String get pasteCrossVolumeTag => '跨磁盘';

  @override
  String pasteProgressItems(
    int done,
    int total,
    String doneSize,
    String totalSize,
  ) {
    return '$done / $total 项 · $doneSize / $totalSize';
  }

  @override
  String pasteCurrentFile(String name) {
    return '正在复制 $name';
  }

  @override
  String get pasteRollbackNote => '跨磁盘移动按「复制 + 删除」执行；取消时已复制的文件将被回滚删除，源文件保持不动。';

  @override
  String get pasteRunInBackground => '后台运行';

  @override
  String get pasteMoveDone => '移动完成';

  @override
  String get pasteCopyDone => '复制完成';

  @override
  String pasteElapsed(int count, String time) {
    return '$count 项 · 用时 $time';
  }

  @override
  String get pasteStatSucceeded => '成功';

  @override
  String get pasteStatSkipped => '跳过（与目标相同）';

  @override
  String get pasteStatFailed => '失败';

  @override
  String get pasteRetry => '重试';

  @override
  String pasteKeptInStaging(int kept, int moved) {
    return '失败与跳过的 $kept 项仍保留在暂存区，成功的 $moved 项已自动移出。';
  }

  @override
  String get pasteExportLog => '导出日志';

  @override
  String pasteLogSaved(String path) {
    return '日志已保存到 $path';
  }

  @override
  String conflictsSubtitle(int count, int total, String folder) {
    return '$count / $total 项与目标 $folder 重名';
  }

  @override
  String get conflictsIntro => '逐项选择处理方式；也可以勾选下方「对剩余项应用」。';

  @override
  String get conflictPending => '待定';

  @override
  String conflictWriteInfo(String size, String date) {
    return '写入 · $size · $date';
  }

  @override
  String conflictExistingInfo(String size, String date) {
    return '已有 · $size · $date';
  }

  @override
  String get conflictOverwriteWarning => '目标文件将被替换，不可撤销';

  @override
  String conflictApplyRestCount(int count) {
    return '对剩余 $count 项应用同一选择';
  }

  @override
  String get conflictApplyAndContinue => '应用并继续';

  @override
  String dragMoveHint(int count) {
    return '移动 $count 项 · 按住 Ctrl 复制';
  }

  @override
  String get showInSystem => '在系统中显示';

  @override
  String get newSubfolder => '新建子文件夹';

  @override
  String get newFolderDefaultName => '新建文件夹';

  @override
  String get moveFolderTo => '移动到…';

  @override
  String get removeFromList => '从列表中移除';

  @override
  String get rootCannotMove => '根目录不能移动';

  @override
  String get deleteFolderTitle => '删除文件夹？';

  @override
  String get trashFolderTitle => '移到回收站？';

  @override
  String get deleteFolderEmptyDesc => '这个文件夹是空的，删除后无法撤销。';

  @override
  String get trashFolderEmptyDesc => '这个文件夹是空的，删除后可从系统回收站找回。';

  @override
  String get deleteFolderIrreversible => '此操作无法撤销';

  @override
  String get trashFolderRestorable => '可从系统回收站找回';

  @override
  String get inventorySubfolders => '子文件夹';

  @override
  String get inventoryFiles => '文件';

  @override
  String get inventorySize => '大小';

  @override
  String get inventoryCounting => '正在盘点…';

  @override
  String deleteFolderCount(int count) {
    return '删除 $count 项';
  }

  @override
  String trashFolderCount(int count) {
    return '移到回收站 · $count 项';
  }

  @override
  String get moveToTrash => '移至回收站';

  @override
  String get folderNameEmpty => '名称不能为空';

  @override
  String folderNameIllegalChars(String chars) {
    return '名称不能包含 $chars';
  }

  @override
  String get folderNameReserved => '这是系统保留名';

  @override
  String get folderNameExists => '已有同名文件夹';

  @override
  String get folderPathRegistered => '该路径已在列表中';

  @override
  String get moveFolderIntoSelf => '文件夹不能移动到自身内部';

  @override
  String get moveFolderSameParent => '文件夹已在该位置';

  @override
  String get moveFolderTargetExists => '目标位置已有同名项';

  @override
  String dragMoveFolderHint(String name) {
    return '移动「$name」';
  }

  @override
  String dragCopyFolderHint(String name) {
    return '复制「$name」';
  }

  @override
  String folderMovingTitle(String name) {
    return '正在移动文件夹 $name';
  }

  @override
  String folderCopyingTitle(String name) {
    return '正在复制文件夹 $name';
  }

  @override
  String folderTransferItems(int count) {
    return '$count 项';
  }

  @override
  String get folderMoveCrossVolumeNote =>
      '不同磁盘 · 先复制再删除，源目录会在全部到达后才移除，取消不会丢失任何内容。';

  @override
  String get folderMoveCancelledTitle => '已取消移动';

  @override
  String get folderCopyCancelledTitle => '已取消复制';

  @override
  String folderTransferStoppedAt(int done, int total) {
    return '在 $done / $total 项处停止';
  }

  @override
  String get folderMoveStatCopied => '已复制到目标';

  @override
  String get folderMoveStatPending => '未开始';

  @override
  String get folderMoveStatSourceKept => '源目录保留';

  @override
  String get folderMoveCancelledDesc =>
      '源目录完整保留，未删除任何文件。已复制到目标的项保留在目标位置，可稍后重新拖动，同名项会逐项处理。';

  @override
  String get showDestinationInSystem => '在系统中显示目标';

  @override
  String get gotIt => '知道了';

  @override
  String folderCreated(String name) {
    return '已创建 $name';
  }

  @override
  String folderRenamed(String name) {
    return '已重命名为 $name';
  }

  @override
  String folderDeleted(String name) {
    return '已删除 $name';
  }

  @override
  String folderTrashed(String name) {
    return '已将 $name 移到回收站';
  }

  @override
  String folderMoved(String name, String target) {
    return '已移动 $name 到 $target';
  }

  @override
  String folderCopied(String name, String target) {
    return '已复制 $name 到 $target';
  }

  @override
  String folderOpFailed(String error) {
    return '操作失败：$error';
  }

  @override
  String get appTitle => 'Joycai Image AI 工具集';

  @override
  String get save => '保存';

  @override
  String get update => '更新';

  @override
  String get cancel => '取消';

  @override
  String get close => '关闭';

  @override
  String get minimizeWindow => '最小化';

  @override
  String get maximizeWindow => '最大化';

  @override
  String get restoreWindow => '向下还原';

  @override
  String get closeWindow => '关闭';

  @override
  String get expandEditor => '放大编辑';

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
  String get clear => '清空';

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
  String get finished => '结束时间';

  @override
  String get config => '配置';

  @override
  String get logs => '日志';

  @override
  String get copyFilename => '复制文件名';

  @override
  String get openInFolder => '在文件夹中打开';

  @override
  String get openInPreview => '在预览中打开';

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
  String get noTasks => '暂无任务';

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
  String get more => '更多';

  @override
  String get confirm => '确认';

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
  String downloaderFoundSelected(int found, int selected) {
    return '发现 $found 张 · 已选 $selected 张';
  }

  @override
  String get guideStep1Title => '1 · 输入网址';

  @override
  String get guideStep1Desc => '粘贴图库或文章页面链接';

  @override
  String get guideStep2Title => '2 · 描述需求';

  @override
  String get guideStep2Desc => '告诉 AI 要寻找的图像';

  @override
  String get guideStep3Title => '3 · 挑选下载';

  @override
  String get guideStep3Desc => '批量选择并加入任务队列';

  @override
  String get copyLogs => '复制日志';

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
  String get cachedInputTokens => '缓存输入';

  @override
  String get outputTokens => '输出 Token';

  @override
  String get cacheHitRate => '缓存命中率';

  @override
  String get cacheHitRateHint => '命中缓存的输入 Token 占全部输入 Token 的比例';

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
  String get usageColumnDetail => '明细';

  @override
  String get usageColumnTime => '时间';

  @override
  String get usageColumnCost => '成本';

  @override
  String get yesterday => '昨天';

  @override
  String usageRecordCount(int count) {
    return '$count 条';
  }

  @override
  String usageItemCount(int count) {
    return '$count 项';
  }

  @override
  String get noUsageInRange => '所选时间范围内没有用量数据。';

  @override
  String get loadMore => '加载更多';

  @override
  String get invalidPriceValue => '请输入有效的非负数字';

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
  String get probeChannel => '测试连接';

  @override
  String get probeOk => '连接成功且鉴权通过';

  @override
  String get probeModels => '个模型';

  @override
  String get probeConnectedNoModels => '已连通——该端点没有模型列表，部分中转属正常情况。';

  @override
  String get probeAuthFailed => '端点有响应，但拒绝了 API 密钥。';

  @override
  String get probeNotAnApi => '该地址返回的不是本 API（可能是网页）——请检查 Base URL。';

  @override
  String get probeUnreachable => '端点无响应';

  @override
  String get probeNotSupported => '该渠道类型不支持连接测试。';

  @override
  String get enableDiscovery => '启用模型检索';

  @override
  String get filterModels => '过滤模型...';

  @override
  String get tagColor => '标签颜色';

  @override
  String deleteChannelConfirm(String name) {
    return '确定要删除渠道“$name”吗？其下的关联模型也会一并删除。';
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
  String get modelIdLabel => '模型 ID';

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
  String get cacheInputPrice => '输入价格·命中缓存 (\$/M Tokens)';

  @override
  String get cacheInputPriceHint => '留空则缓存命中按“输入价格”计费';

  @override
  String get requestPriceHint => '按每次成功请求计费，与 Token 用量无关。';

  @override
  String get cachePriceFollowsInput => '缓存命中按“输入价格”计费';

  @override
  String get outputPrice => '输出价格 (\$/M Tokens)';

  @override
  String get requestPrice => '请求价格 (\$/次)';

  @override
  String get priceConfig => '价格配置';

  @override
  String get priceLabelInput => '输入';

  @override
  String get priceLabelCache => '缓存';

  @override
  String get priceLabelOutput => '输出';

  @override
  String get priceLabelRequest => '请求';

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
  String get protocolMidjourney => 'Midjourney 代理';

  @override
  String get protocolMidjourneyDesc => 'midjourney-proxy / NewAPI 的 /mj/* 协议';

  @override
  String get protocolAnthropic => 'Anthropic Messages 协议';

  @override
  String get protocolAnthropicDesc => 'Claude 原生 /v1/messages 接口';

  @override
  String get midjourneyEndpointHint =>
      '填写主机根地址（如 https://your-newapi.com），/mj/* 路径将自动补全。';

  @override
  String get providerOpenAIOfficial => 'OpenAI 官方';

  @override
  String get providerGoogleOfficial => 'Google GenAI 官方';

  @override
  String get providerGoogleCompatible => 'Google GenAI (OpenAI 兼容)';

  @override
  String get providerGoogleCompatibleDesc => '通过 OpenAI 适配端点访问 Gemini';

  @override
  String get providerDashScopeDesc =>
      'dashscope.aliyuncs.com/compatible-mode · OpenAI 形状请求 · 千问对话 + qwen-image / 万相原生出图 + 万相视频';

  @override
  String get providerDashScopeCompat => '阿里云百炼（OpenAI 兼容）';

  @override
  String get providerDashScopeNative => '阿里云百炼（DashScope 原生）';

  @override
  String get providerDashScopeNativeDesc =>
      'dashscope.aliyuncs.com/api/v1 · 阿里云自有请求格式 · qwen-audio 只能走这条';

  @override
  String get endpointOverrideHint => '已按所选提供商预填，可改为中转、网关或国际站地址。';

  @override
  String get providerQianwen => '千问平台';

  @override
  String get providerQianwenDesc =>
      'platform.qianwenai.com · API 同 DashScope — 千问对话 + qwen-image / wan2.7 出图';

  @override
  String get providerCustom => '自定义提供商';

  @override
  String get providerCustomDesc => '自建或第三方 API 服务商';

  @override
  String get providerGroupOther => '其他';

  @override
  String get stepConnection => '连接与密钥';

  @override
  String get sectionAppearance => '外观';

  @override
  String get moreColors => '更多颜色';

  @override
  String get protocolXai => 'xAI (Grok) API';

  @override
  String get providerXaiOfficial => 'xAI 官方';

  @override
  String get providerXaiOfficialDesc => 'api.x.ai · Grok 聊天 + 原生 Imagine 视频';

  @override
  String get providerNewApiOpenAI => 'New API（OpenAI 格式）';

  @override
  String get providerNewApiGemini => 'New API（Gemini 格式）';

  @override
  String get providerNewApiDesc => 'New API 中转 · Bearer 令牌鉴权';

  @override
  String get providerAnthropicOfficial => 'Anthropic 官方';

  @override
  String get providerAnthropicOfficialDesc => 'api.anthropic.com · Claude';

  @override
  String get providerNewApiAnthropic => 'New API（Anthropic 格式）';

  @override
  String get providerMiniMaxAnthropic => 'MiniMax（Anthropic 格式）';

  @override
  String get providerMiniMaxDesc => 'OpenAI 兼容 /v1 端点';

  @override
  String get newApiBaseUrl => 'New API 基础地址';

  @override
  String get newApiBaseHint => '填写 New API 主机地址，版本路径将自动补全';

  @override
  String get customEndpointHint => '请输入自定义端点 URL';

  @override
  String get openaiV1Hint => '提示：OpenAI 兼容接口通常以 \'/v1\' 结尾';

  @override
  String get googleV1BetaHint => '提示：Google GenAI 接口通常以 \'/v1beta\' 结尾';

  @override
  String get anthropicV1Hint => '提示：Anthropic 接口通常以 \'/v1\' 结尾';

  @override
  String get dashscopeApiV1Hint => '提示：DashScope 原生接口以 \'/api/v1\' 结尾';

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
  String get feeGroupEditorSubtitle => '配置模型的计费标准';

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
  String feeGroupModelCount(int count) {
    return '$count 个模型';
  }

  @override
  String get feeGroupUnused => '没有模型在使用';

  @override
  String get model => '模型';

  @override
  String modelsAndChannelsCount(int models, int channels) {
    return '$models 个模型 · $channels 个频道';
  }

  @override
  String get deselectAll => '取消全选';

  @override
  String get capabilities => '能力';

  @override
  String get modelSaveRequirementHint => '渠道、名称、ID 三项齐备后方可保存。';

  @override
  String get cardPreview => '卡片预览';

  @override
  String get capabilityStreamingShort => '流式';

  @override
  String get capabilityStandardShort => '标准请求';

  @override
  String get supportsStreaming => '支持流式传输';

  @override
  String get supportsStreamingDesc => '如果模型支持服务器推送事件（SSE）请启用';

  @override
  String get supportsStandardRequest => '支持标准请求';

  @override
  String get supportsStandardRequestDesc => '启用标准 JSON/REST 请求';

  @override
  String get contextWindow => '上下文大小';

  @override
  String get contextUnset => '未设置';

  @override
  String get contextUnsetDesc => '使用保守默认值——不确定模型真实上限时选这个。';

  @override
  String get contextSpecify => '指定大小';

  @override
  String get contextUnlimited => '不限制';

  @override
  String get contextUnlimitedDesc => '一次性发送所有候选图片，且不按窗口大小限制提示词助手。';

  @override
  String get contextMax => '最大上下文';

  @override
  String contextTokens(String size) {
    return '$size tokens';
  }

  @override
  String get contextWindowHint => '用于每次请求的图片分批，以及提示词助手读取知识库与摘要的预算。';

  @override
  String get agentBehavior => '代理行为';

  @override
  String get forceViewAllImages => '查看全部参考图';

  @override
  String get forceViewAllImagesDesc => '代理必须查看所有参考图后才能提交结果，推荐为本地小模型开启。';

  @override
  String get reasoningEffort => '推理强度';

  @override
  String get reasoningEffortDesc =>
      '模型作答前的思考强度。默认＝不发送任何字段（由端点自行决定）；其他档位会消耗输出 token。适用于 OpenAI 与 Anthropic 格式渠道。Anthropic 格式渠道上，Claude 4.6 及更新的模型以 output_config.effort 下发档位；「最高」只有最新一代模型接受，若 400 报文点名该档位，请降一档。';

  @override
  String get reasoningEffortDefault => '默认（不发送）';

  @override
  String get reasoningEffortOff => '关闭';

  @override
  String get reasoningEffortLow => '低';

  @override
  String get reasoningEffortMedium => '中';

  @override
  String get reasoningEffortHigh => '高';

  @override
  String get reasoningEffortMax => '最高';

  @override
  String get enableThinking => '深度思考';

  @override
  String get enableThinkingDesc => '让模型先推理再作答。会消耗输出 token，仅 Anthropic 格式渠道支持。';

  @override
  String get enableWebSearch => '服务端联网搜索';

  @override
  String get enableWebSearchDesc => '允许服务商在作答过程中自行搜索网页。按额外 token 计费，并会代你抓取网页。';

  @override
  String get addChannelSubtitle => '先选这是谁，再填连接方式';

  @override
  String get searchProviders => '搜索提供商…';

  @override
  String get noProviderMatch => '没有匹配的提供商';

  @override
  String get resetToDefault => '重置为默认';

  @override
  String get apiKeyRequired => '该提供商需要密钥才能添加渠道';

  @override
  String get endpointRequired => '请填写接口地址';

  @override
  String get probeRetry => '重试';

  @override
  String get customColor => '自定义颜色';

  @override
  String get stepConnectionAppearance => '连接与外观';

  @override
  String get channelListPreview => '列表预览';

  @override
  String get pickerNoMatches => '没有匹配项';

  @override
  String pickerMatchCount(int count) {
    return '显示 $count 项';
  }

  @override
  String get selectAChannel => '选择渠道';

  @override
  String get searchChannels => '搜索渠道名称或标签...';

  @override
  String get kindChat => '对话';

  @override
  String get kindImage => '图像';

  @override
  String get kindVideo => '视频';

  @override
  String get kindMultimodal => '多模态';

  @override
  String reasoningChip(String level) {
    return '推理·$level';
  }

  @override
  String get webSearchChip => '联网';

  @override
  String get viewAllImagesChip => '看全部参考图';

  @override
  String countGroups(int count) {
    return '$count 组';
  }

  @override
  String get previewInList => '列表中的样子';

  @override
  String get providerGroupVendor => '厂商';

  @override
  String get providerGroupVendorHint => '官方直连 · 地址已预填';

  @override
  String get providerGroupRelay => '中转站';

  @override
  String get providerGroupRelayHint => '协议已知 · 地址自填';

  @override
  String get providerGroupCustom => '自定义';

  @override
  String get providerGroupCustomHint => '地址自填 + 显式选协议';

  @override
  String get providerGroupLocal => '本地';

  @override
  String get providerGroupLocalHint => '默认 localhost';

  @override
  String get providerNeedKeyOnly => '仅填密钥';

  @override
  String get providerNeedEndpoint => '需填地址';

  @override
  String get providerNeedKeyless => '免密钥';

  @override
  String get providerCustomOpenAIDesc => '任何提供 OpenAI 对话接口的服务';

  @override
  String get providerCustomGoogleDesc => '任何提供 Google GenAI 接口的服务';

  @override
  String get providerCustomAnthropicDesc => '任何提供 Anthropic Messages 接口的服务';

  @override
  String get variantTitleGoogle => '接入方式';

  @override
  String get variantTitleMiniMax => '接入面';

  @override
  String get variantTitleNewApi => '接口格式';

  @override
  String get variantTitleGeneric => '接入方式';

  @override
  String get variantHintGoogle => 'Google 同一批模型提供两种接入方式，切换会改写下面的接口地址。';

  @override
  String get variantHintMiniMax => 'MiniMax 同时提供两套接口，选一套即可，之后仍可改。';

  @override
  String get variantHintNewApi => 'host 由你填，尾段跟着你选的格式走。';

  @override
  String get variantHintGeneric => '切换会改写下面的接口地址。';

  @override
  String get variantGoogleNative => 'GenAI 原生协议';

  @override
  String get variantGoogleOpenAI => 'OpenAI 兼容面';

  @override
  String get variantMiniMaxOpenAI => 'OpenAI 面';

  @override
  String get variantMiniMaxAnthropic => 'Anthropic 面';

  @override
  String get variantNewApiOpenAI => 'OpenAI 格式';

  @override
  String get variantNewApiGemini => 'Gemini 格式';

  @override
  String get variantNewApiAnthropic => 'Anthropic 格式';

  @override
  String get channelPresetLabel => '供应商预设';

  @override
  String get channelPresetHint => '预设只负责一键填好下面的字段。填完仍可逐项修改，改过也不会被覆盖。';

  @override
  String get changePreset => '更换预设';

  @override
  String get presetUnmatched => '未匹配预设';

  @override
  String get presetUnmatchedHint =>
      '这条渠道用的是旧版本创建的类型，已不在预设列表里。保持不动即可继续使用；点「更换预设」会覆盖下面的字段。';

  @override
  String get presetEndpointModified => '地址已改过';

  @override
  String get restorePresetEndpoint => '恢复预设值';

  @override
  String get changePresetOverlayHint => '选中会用预设值覆盖接口协议与地址（密钥、名称、标签不动）。';

  @override
  String get protocolField => '接口协议';

  @override
  String get protocolFieldHint => '共 5 个协议族，任何已存储的类型都能在这里表示。';

  @override
  String get deprecatedLabel => '已废弃';

  @override
  String get apiKeyOptional => '可选';

  @override
  String get apiKeyLocalPlaceholder => '本地服务通常不需要';

  @override
  String get apiKeyLocalNote => '留空即可。如果你给本地服务加了反向代理鉴权，在这里填对应的密钥。';

  @override
  String get searchProvidersAlias => '搜索供应商，或试试「千问」';

  @override
  String providerCountSummary(int count, int groups) {
    return '$count 个供应商 · $groups 组';
  }

  @override
  String providerVariantCount(int count) {
    return '$count 种接入';
  }

  @override
  String get requestMethod => '请求方式';

  @override
  String get interfaceProtocol => '接口协议';

  @override
  String get protocolAuto => '自动';

  @override
  String protocolAutoResolved(String name) {
    return '自动 · 当前解析为「$name」';
  }

  @override
  String get protocolAutoHelper => '跟随渠道供应商，换供应商后自动重解析。';

  @override
  String protocolStaleHelper(String name) {
    return '原选择「$name」在当前供应商下不可用，已回到自动。';
  }

  @override
  String get protocolOpenAICompat => 'OpenAI 兼容';

  @override
  String get protocolAnthropicCompat => 'Anthropic 兼容';

  @override
  String get protocolDashScopeNative => 'DashScope 原生';

  @override
  String get protocolDashScopeNativeDesc => '阿里云自有请求格式，qwen-audio 只能走这条';

  @override
  String get protocolImageSync => '同步生成';

  @override
  String get protocolImageSyncDesc => '一次请求直接返回图片';

  @override
  String get protocolImageAsync => '异步任务';

  @override
  String get protocolImageAsyncDesc => '提交后轮询结果，生成中可取消';

  @override
  String get protocolVideoTask => '异步视频任务';

  @override
  String get protocolStreamIgnoredAsync => '异步任务不使用流式传输，此项已忽略';

  @override
  String get protocolAsyncQueueNote => '提交后进入任务队列轮询，生成中可取消。';

  @override
  String get protocolPinStale => '点单已失效';

  @override
  String protocolStaleTooltip(String name) {
    return '原选择「$name」不可用，正在按自动运行。';
  }

  @override
  String get channelReorderHandleTooltip => '拖动调整顺序';

  @override
  String get channelOrderSaveFailed => '顺序未能保存，已恢复原顺序';

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
  String get selectionMode => '选择模式';

  @override
  String selectionModeCount(int count) {
    return '选择模式（$count）';
  }

  @override
  String nSelected(int count) {
    return '已选择 $count 项';
  }

  @override
  String get categorize => '归类';

  @override
  String get bulkCategorize => '批量归类';

  @override
  String get selectCategoriesToApply => '选择要应用到所选提示词的分类：';

  @override
  String deleteNPromptsConfirm(int count) {
    return '删除 $count 个提示词？';
  }

  @override
  String get actionCannotBeUndone => '此操作无法撤销。';

  @override
  String deleteCategoryConfirmMessage(String name) {
    return '删除分类“$name”？其中的提示词将移至 General。';
  }

  @override
  String get moveToTop => '移到顶部';

  @override
  String get moveToBottom => '移到底部';

  @override
  String get addSystemTemplateHint => '在此添加用于优化器或批量重命名的系统模板。';

  @override
  String importFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String get filterAll => '全部';

  @override
  String get newTemplate => '新建模板';

  @override
  String get reorderDisabledWhileFiltered => '筛选或搜索时无法拖动排序';

  @override
  String get matchModeLabel => '匹配';

  @override
  String get matchAny => '任一';

  @override
  String get matchAllTags => '全部';

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
  String get font => '字体';

  @override
  String get fontSystem => '系统默认';

  @override
  String get fontDownloadTitle => '下载字体';

  @override
  String get fontDownloadPrompt => '该字体未随应用打包，首次使用前需要下载一次。';

  @override
  String get fontDownloadAction => '下载';

  @override
  String get fontDownloading => '正在下载字体…';

  @override
  String get fontDownloadFailed => '字体下载失败，请检查网络后重试。';

  @override
  String get preferHighPerformanceGpu => '优先使用高性能 GPU';

  @override
  String get preferHighPerformanceGpuDesc => '让 Windows 使用独立显卡运行本应用，下次启动时生效。';

  @override
  String get reduceVisualEffects => '减少视觉效果';

  @override
  String get reduceVisualEffectsDesc => '关闭模糊效果，在核显或低性能 GPU 上获得更流畅的体验。';

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
  String get importErrorPromptsOnly => '这是提示词库导出文件，不是完整备份。请在提示词页面导入。';

  @override
  String get importErrorNotABackup => '该文件不是有效的备份文件。请选择通过“导出设置”生成的文件。';

  @override
  String get importErrorNewerSchema => '该备份由更高版本的应用创建。请先升级应用后再导入。';

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
  String get knowledgeBaseFolder => '知识库文件夹';

  @override
  String get kbOpenFolder => '打开文件夹';

  @override
  String get kbInvalidDir => '文件夹不存在';

  @override
  String get kbMissingEntry => '文件夹中缺少入口文件 README.md';

  @override
  String get assistantContextRatio => '助手摘要阈值';

  @override
  String get assistantContextRatioDesc =>
      '提示词助手在上下文占用达到模型窗口的该比例时自动摘要对话，腾出空间继续工作。仅对已设置上下文大小的模型生效。';

  @override
  String get kbSubAgent => '知识库子代理';

  @override
  String get kbSubAgentDesc => '允许助手把知识库检索交给子代理，在独立上下文中通读文件，保持主对话轻量。实验性功能。';

  @override
  String get kbSubAgentModel => '子代理模型';

  @override
  String get kbSubAgentModelFollow => '跟随会话模型';

  @override
  String get kbSubAgentModelMissing => '绑定的模型已不存在——在重新选择之前，委托功能将被停用。';

  @override
  String get assistantRetention => '助手会话保留数量';

  @override
  String get assistantRetentionDesc => '超出数量的较旧提示词助手会话将被自动删除';

  @override
  String get about => '关于';

  @override
  String aboutVersion(Object version) {
    return '版本 $version';
  }

  @override
  String get aboutGithubRepo => 'GitHub 仓库';

  @override
  String get aboutViewSource => '查看源代码与发布版本';

  @override
  String get aboutLicense => '许可协议';

  @override
  String aboutCopyright(Object year, Object holder) {
    return '版权所有 © $year $holder，基于 MIT 许可协议发布。';
  }

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
  String get clearAll => '清除全部';

  @override
  String get clearAllConfirm => '此操作将删除所有未运行的任务，且无法撤销。';

  @override
  String get cancelAllPending => '取消所有等待中';

  @override
  String get cancelTask => '取消任务';

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
  String taskTotalCount(int count) {
    return '共 $count 个任务';
  }

  @override
  String get statusCancelled => '已取消';

  @override
  String get retryTask => '重试';

  @override
  String queuedPosition(int position) {
    return '排队第 $position 位';
  }

  @override
  String tookDuration(String duration) {
    return '用时 $duration';
  }

  @override
  String retryCount(int count) {
    return '重试次数: $count';
  }

  @override
  String get viewTaskLog => '查看日志';

  @override
  String get taskLogTitle => '任务日志';

  @override
  String get taskLogLive => '实时';

  @override
  String get noTaskLog => '该任务没有日志记录。';

  @override
  String get noTaskLogHint => '本次更新之前运行的任务不会保存日志。';

  @override
  String get taskLogCopied => '日志已复制到剪贴板';

  @override
  String get copyPrompt => '复制提示词';

  @override
  String taskLogLineCount(int count) {
    return '$count 行';
  }

  @override
  String get goToWorkbench => '前往工作台';

  @override
  String get copyAll => '复制全部';

  @override
  String get copiedAll => '已复制到剪贴板';

  @override
  String get noLogsYet => '这个任务还没有日志';

  @override
  String get sourceFiles => '源文件';

  @override
  String get requestParameters => '请求参数';

  @override
  String get outputPaths => '产物路径';

  @override
  String get copyError => '复制报错';

  @override
  String taskTotalShort(int count) {
    return '共 $count';
  }

  @override
  String get statusShortRunning => '执行';

  @override
  String get statusShortPending => '待';

  @override
  String get statusShortDone => '完成';

  @override
  String get statusShortFailed => '失败';

  @override
  String get sortNewestFirst => '最新在前';

  @override
  String get sortOldestFirst => '最早在前';

  @override
  String get sortSection => '排序';

  @override
  String get pinActiveTasks => '执行中与待处理置顶';

  @override
  String get restByCreatedTime => '其余按创建时间';

  @override
  String get createdAt => '创建';

  @override
  String get cancelledByUser => '已取消 · 手动';

  @override
  String get noRunningTasks => '没有执行中的任务';

  @override
  String get noPendingTasks => '没有待处理的任务';

  @override
  String get noCompletedTasks => '没有已完成的任务';

  @override
  String get noFailedTasks => '没有失败的任务';

  @override
  String filteredEmptyHint(int count) {
    return '当前筛选下没有任务，其余 $count 个任务未受影响。';
  }

  @override
  String get viewAllTasks => '查看全部';

  @override
  String get durationLabel => '用时';

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
  String get wbModeImage => '图像';

  @override
  String get wbModeVideo => '视频';

  @override
  String get wbTools => '工具';

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
  String get sectionSources => '来源';

  @override
  String get sectionResults => '结果';

  @override
  String get sectionWorkspace => '工作区';

  @override
  String get allSources => '全部来源';

  @override
  String get allResults => '全部结果';

  @override
  String get backToAll => '返回全部';

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
  String get selectAll => '全选';

  @override
  String get importFromGallery => '从系统图库导入';

  @override
  String get takePhoto => '拍摄照片';

  @override
  String get clearTempWorkspace => '清空工作区';

  @override
  String get clearTempWorkspaceConfirmTitle => '清空临时工作区？';

  @override
  String clearTempWorkspaceConfirmMessage(int count) {
    return '将从临时工作区移除全部 $count 项。文件本身不会被删除。';
  }

  @override
  String get dropFilesHere => '将图片拖放到此处以添加到临时工作区';

  @override
  String get noImagesSelected => '未选择图像';

  @override
  String get imageLoadFailed => '图像加载失败';

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
  String get thumbnailDisplay => '缩略图展示';

  @override
  String get thumbnailFitContain => '适应（完整显示）';

  @override
  String get thumbnailFitCover => '填充（裁切铺满）';

  @override
  String get deleteFile => '删除文件';

  @override
  String get deleteFileConfirmTitle => '删除文件？';

  @override
  String deleteFileConfirmMessage(String filename) {
    return '确定要删除“$filename”吗？';
  }

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
  String get imageSizeLabel => '尺寸';

  @override
  String get quality => '质量';

  @override
  String get promptExtend => '提示词扩写';

  @override
  String get promptExtendOn => '开启';

  @override
  String get promptExtendOff => '关闭';

  @override
  String get optionAuto => '自动';

  @override
  String get qualityLow => '低';

  @override
  String get qualityMedium => '中';

  @override
  String get qualityHigh => '高';

  @override
  String get mjVersion => '版本';

  @override
  String get mjMode => '模式';

  @override
  String get mjStylize => '风格化';

  @override
  String get mjChaos => '混乱度';

  @override
  String get referenceImagesNotSupported => '该模型不支持参考图，所选图片将被忽略。';

  @override
  String referenceImagesLimited(int count) {
    return '该模型最多支持 $count 张参考图，其余将被忽略。';
  }

  @override
  String get prompt => '提示词';

  @override
  String get promptHint => '在此输入提示词...';

  @override
  String get promptHistory => '历史记录';

  @override
  String get noPromptHistory => '暂无历史记录';

  @override
  String get noPromptHistoryDesc => '提交过的提示词会显示在这里。';

  @override
  String get usePrompt => '使用该提示词';

  @override
  String get applyPromptWarning => '将替换编辑器中当前的提示词。';

  @override
  String get clearPromptHistory => '清空历史记录';

  @override
  String get clearPromptHistoryConfirm => '确定清空全部历史记录吗？此操作无法撤销。';

  @override
  String get timeJustNow => '刚刚';

  @override
  String timeMinutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String timeHoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String timeDaysAgo(int count) {
    return '$count 天前';
  }

  @override
  String get prefixHint => '例如：result';

  @override
  String get processPrompt => '处理提示词';

  @override
  String processImages(int count) {
    return '处理 $count 张图像';
  }

  @override
  String get useStreaming => '使用流式传输';

  @override
  String get useStreamingDesc => '实时 AI 响应（如果支持）';

  @override
  String get compressReferenceImages => '压缩参考图';

  @override
  String get compressReferenceImagesDesc => '超过 3MB 的图片重编码为 JPEG';

  @override
  String get taskSubmitted => '任务已提交至队列';

  @override
  String get comparator => '对比器';

  @override
  String get compareLayoutSideBySide => '左右并排';

  @override
  String get compareLayoutStacked => '上下并排';

  @override
  String get compareLayoutSlider => '滑动对比';

  @override
  String get compareSyncTransform => '同步缩放平移';

  @override
  String get comparatorEmptyHint => '从文件浏览器或任务结果发送，也可以直接从库中选择两张图';

  @override
  String get comparatorPickRaw => '选择原图';

  @override
  String get comparatorPickAfter => '选择效果图';

  @override
  String comparatorZoomSynced(int percent) {
    return '缩放 $percent% · 已同步';
  }

  @override
  String comparatorZoomIndependent(int percent) {
    return '缩放 $percent% · 独立';
  }

  @override
  String comparatorSizeReduction(String percent) {
    return '体积减少 $percent';
  }

  @override
  String comparatorSizeIncrease(String percent) {
    return '体积增加 $percent';
  }

  @override
  String get fileSize => '文件大小';

  @override
  String get sendToComparator => '发送至对比器';

  @override
  String get sendToComparatorRaw => '设置为对比原图';

  @override
  String get sendToComparatorAfter => '设置为对比效果图';

  @override
  String get sendToFirstFrame => '设置为视频首帧';

  @override
  String get sendToLastFrame => '设置为视频尾帧';

  @override
  String get sendToVideoReferences => '添加到视频参考图';

  @override
  String get sendToSelection => '添加到选中列表';

  @override
  String get sendToOptimizer => '发送到提示词助手';

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
  String get overwriteConfirmSaveCopyInstead => '改为保存副本';

  @override
  String get overwriteConfirmSubtitle => '此操作无法撤销';

  @override
  String get overwriteConfirmKeepOriginalHint => '如需保留原图，可改用「保存副本」。';

  @override
  String overwriteUnsupportedFormat(String format) {
    return '无法覆盖 $format 文件——该格式只能读取、不能写入。请改用「保存副本」。';
  }

  @override
  String get saveToTempSuccess => '已保存至临时工作区';

  @override
  String get overwriteSuccess => '原图已更新';

  @override
  String get custom => '自定义';

  @override
  String get cropResizeFreeRatio => '自由';

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
  String get reset => '重置';

  @override
  String cropResizeOriginalInfo(int width, int height, String size) {
    return '原图 $width×$height · $size';
  }

  @override
  String cropResizeCanvasLabel(String name) {
    return '$name（原图预览）';
  }

  @override
  String get cropResizeCropOnly => '裁剪';

  @override
  String cropResizeCropAndScale(int percent) {
    return '裁剪 + 缩放 $percent%';
  }

  @override
  String get cropResizeOutputPreview => '输出预览';

  @override
  String cropResizeOutputSummary(
    String originalSize,
    String outputSize,
    String operation,
    String sampling,
  ) {
    return '$originalSize → $outputSize · $operation · $sampling';
  }

  @override
  String cropResizeWillSaveTo(String path) {
    return '副本将存入 $path';
  }

  @override
  String get cropResizeTempWorkspaceLabel => '临时工作区';

  @override
  String get saveCopy => '保存副本';

  @override
  String get cropResizeSaveDestinationHint => '到工作区';

  @override
  String get cropResizeResample => '重采样';

  @override
  String get fitToWindow => '适应窗口';

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
  String maskSourceCaption(int width, int height) {
    return '蒙版 $width×$height';
  }

  @override
  String maskBrushBadge(String color, int size) {
    return '$color笔刷 · $size px';
  }

  @override
  String get maskOutputLabel => '输出';

  @override
  String maskOutputSummary(int width, int height) {
    return '遮罩 $width×$height · PNG（黑白）';
  }

  @override
  String maskCompositeOutputSummary(int width, int height) {
    return '合成图 $width×$height · PNG';
  }

  @override
  String maskWillSaveTo(String path) {
    return '遮罩将存入 $path';
  }

  @override
  String get maskSaveComposite => '保存合成图';

  @override
  String get maskSaveMask => '保存遮罩';

  @override
  String get maskSaved => '蒙版已保存至工作区';

  @override
  String maskSaveError(String error) {
    return '保存蒙版失败: $error';
  }

  @override
  String get promptOptimizer => '提示词助手';

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
  String get optChatHint => '描述你的想法或粘贴粗略提示词...';

  @override
  String get optSend => '发送 (Ctrl+Enter)';

  @override
  String get optNewSession => '新会话';

  @override
  String get optToolListImages => '查看了参考图列表';

  @override
  String optToolViewImage(String name) {
    return '查看了参考图：$name';
  }

  @override
  String get optPromptTitle => '优化提示词';

  @override
  String get optCopy => '复制';

  @override
  String get optPromptCopied => '提示词已复制到剪贴板';

  @override
  String get optEmptyChat => '发送粗略提示词或想法开始优化。AI 会按需查看参考图，你可以多轮追问持续调整结果。';

  @override
  String get optViewed => 'AI 已查看';

  @override
  String get optRemoveImage => '移除图片';

  @override
  String get optEmptyImagesHint => '在图库中右键图片，选择“发送到提示词助手”即可添加到这里。';

  @override
  String get videoGeneration => '视频生成';

  @override
  String get referenceImages => '参考图片';

  @override
  String get firstFrame => '首帧';

  @override
  String get lastFrame => '尾帧';

  @override
  String get generateVideo => '生成视频';

  @override
  String get frames => '帧控制';

  @override
  String get videoResolution => '视频分辨率';

  @override
  String get videoAspectRatio => '视频比例';

  @override
  String get videoSeconds => '时长';

  @override
  String get videoQualityStandard => '标准';

  @override
  String get videoQualityHigh => '高清';

  @override
  String get openInSystemPlayer => '在系统播放器中打开';

  @override
  String get dropVideoReferenceHere => '在此处拖入用于风格/内容参考的图片';

  @override
  String get dropFirstFrameHere => '在此处拖入起始帧图片';

  @override
  String get dropLastFrameHere => '在此处拖入结束帧图片';

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

  @override
  String get tapToPick => '点击选取';

  @override
  String get goToGallery => '前往图库';

  @override
  String get binaryModeActive => '二值化模式已启用 — 背景已隐藏以导出纯净蒙版';

  @override
  String get imageSizePickerTitle => '图像尺寸';

  @override
  String get imageSizeAuto => '自动';

  @override
  String get imageSizeAutoDesc => '由模型自行决定尺寸';

  @override
  String get imageSizePresets => '预设';

  @override
  String get imageSizeCustom => '自定义';

  @override
  String get imageSizeRatio => '比例';

  @override
  String get imageSizeLongEdge => '长边';

  @override
  String get imageSizeCompute => '计算';

  @override
  String get imageSizeWidth => '宽度';

  @override
  String get imageSizeHeight => '高度';

  @override
  String get imageSizeSnapHint => '两边在提交时会自动对齐到 16 像素的整数倍。';

  @override
  String get sizeRuleMultiple16 => '两边均为 16 的整数倍';

  @override
  String sizeRuleMaxEdge(int long) {
    return '长边 ${long}px ≤ 3840';
  }

  @override
  String sizeRuleAspect(String ratio) {
    return '长宽比 $ratio ≤ 3:1';
  }

  @override
  String sizeRulePixels(String mp) {
    return '总像素 $mp 在 0.66–8.29 MP 之间';
  }

  @override
  String get safetySettings => '安全设置';

  @override
  String get safetySettingsDesc =>
      'Gemini 内容过滤阈值，随每个请求发送（从严格到宽松）。Veo/Imagen 不支持。';

  @override
  String get safetyCategoryHarassment => '骚扰内容';

  @override
  String get safetyCategoryHateSpeech => '仇恨言论';

  @override
  String get safetyCategorySexuallyExplicit => '露骨色情';

  @override
  String get safetyCategoryDangerousContent => '危险内容';

  @override
  String get safetyThresholdBlockLowAndAbove => '屏蔽大部分';

  @override
  String get safetyThresholdBlockMediumAndAbove => '屏蔽一部分';

  @override
  String get safetyThresholdBlockOnlyHigh => '屏蔽少部分';

  @override
  String get safetyThresholdBlockNone => '全部不屏蔽';

  @override
  String get safetyThresholdOff => '关闭过滤';

  @override
  String get optModeSystemPrompt => '系统提示词';

  @override
  String get optModeKnowledge => '知识库';

  @override
  String get knowledgeBase => '知识库';

  @override
  String get optKbNotConfigured => '知识库未配置或无效，请先在设置中选择知识库文件夹。';

  @override
  String get optModeSwitchConfirm => '切换模式将开始新会话，是否继续？';

  @override
  String get optToolListKnowledge => '浏览了知识库文件列表';

  @override
  String optToolReadKnowledge(String name) {
    return '阅读知识库：$name';
  }

  @override
  String get optHistory => '历史会话';

  @override
  String get optNoHistory => '暂无已保存的会话';

  @override
  String get optDeleteSessionConfirm => '确定永久删除该会话？';

  @override
  String get optKbEntryTooLarge =>
      '知识库的 README.md 占用了该模型上下文窗口的很大一部分。它每次请求都会重发，且摘要无法压缩它——请精简它，或改用窗口更大的模型。';

  @override
  String get optCompactedNotice => '较早的对话已压缩为摘要，以节省上下文。';

  @override
  String get optKbDistillRequested => '已请求：将本次调优经验总结进知识库。';

  @override
  String get optResultFeedbackAction => '反馈给助手';

  @override
  String get optResultFeedbackChatLabel => '结果图反馈';

  @override
  String get optResultFeedbackHint => '这张图哪里不符合预期？';

  @override
  String optResultFeedbackHelper(int version) {
    return '这张结果图会连同反馈一起进入会话，助手在 v$version 基础上继续调整。';
  }

  @override
  String get optDistillAction => '总结本次经验';

  @override
  String get optDistillDisabledTooltip => '本次会话还没有 prompt 版本，先让助手优化一次';

  @override
  String optDistillCounts(int versions, int feedbacks) {
    return '$versions 个版本 · $feedbacks 条反馈';
  }

  @override
  String get optDistillAlreadyPending => '总结请求已在等待执行。';

  @override
  String get optResultImages => '结果图';

  @override
  String get optResultNoFeedback => '未反馈';

  @override
  String get optDistillDoneTitle => '本次经验已写入知识库';

  @override
  String get optSaveFinalPrompt => '将最终 prompt 存入提示词库';

  @override
  String get optTimelineTitle => '迭代时间线';

  @override
  String optTimelineCount(int count) {
    return '$count 版';
  }

  @override
  String get optFeedbackShort => '反馈';

  @override
  String get optPromptVersionLabel => '提示词';

  @override
  String get optImageMissing => '该会话的部分参考图已不存在，可重新添加后继续使用。';

  @override
  String get optRetry => '重试';

  @override
  String get optModeKnowledgeEdit => '知识库编辑';

  @override
  String optToolWriteKnowledge(String name) {
    return '建议更新知识库：$name';
  }

  @override
  String get kbEditProposedCreate => '新建文件';

  @override
  String get kbEditProposedUpdate => '更新文件';

  @override
  String get kbEditApply => '写入文件';

  @override
  String get kbEditReject => '放弃';

  @override
  String get kbEditApplied => '已写入磁盘';

  @override
  String get kbEditRejected => '已放弃';

  @override
  String get kbEditFailedShort => '写入失败';

  @override
  String kbEditShow(int chars) {
    return '展开内容（$chars 字符）';
  }

  @override
  String get kbEditHide => '收起内容';

  @override
  String kbEditShrinkWarning(int oldChars, int newChars) {
    return '新内容比当前文件短很多（$oldChars → $newChars 字符），请先确认内容完整再写入。';
  }

  @override
  String kbEditFailed(String error) {
    return '写入失败：$error';
  }

  @override
  String kbScaffoldAlreadyInit(String name) {
    return '已初始化——该文件夹已有 $name，不会被改动。';
  }

  @override
  String get kbScaffoldCreate => '初始化';

  @override
  String kbScaffoldConfirm(String path) {
    return '将把 $path 初始化为知识库，并在其中创建示例规则文件。是否继续？';
  }

  @override
  String kbScaffoldDone(int created) {
    return '知识库已初始化：新建 $created 个文件。';
  }

  @override
  String kbScaffoldFailed(String error) {
    return '创建知识库失败：$error';
  }

  @override
  String get optAskUserTitle => '助手需要确认几个问题';

  @override
  String get optAskUserMultiHint => '可多选';

  @override
  String get optAskUserOtherHint => '其他 / 补充说明...';

  @override
  String get optAskUserConfirm => '发送回答';

  @override
  String get optAskUserAnswered => '已回答';

  @override
  String get optAskUserDismissed => '已在对话中继续';

  @override
  String optAgentSteps(int count) {
    return 'Agent 过程 · $count 步';
  }

  @override
  String optAgentStepsImages(int count) {
    return '查看 $count 张参考图';
  }

  @override
  String optAgentStepsDocs(int count) {
    return '阅读 $count 篇文档';
  }

  @override
  String optAgentStepsExpand(int count) {
    return '展开全部 $count 步';
  }

  @override
  String get optAgentStepsCollapse => '收起步骤';

  @override
  String get optPromptExpand => '展开全文';

  @override
  String get optPromptCollapse => '收起';

  @override
  String get optKbReady => '已初始化';

  @override
  String optKbTreeStats(int files, int dirs) {
    return '$files 篇文档 · $dirs 个目录';
  }

  @override
  String optKbContentUpdated(String time) {
    return '内容更新于 $time';
  }

  @override
  String get optKbRescan => '重新扫描';

  @override
  String get optKbCitedThisRound => '本轮引用';

  @override
  String optKbCitedAll(int count) {
    return '全部 $count 篇';
  }

  @override
  String get optKbCitedNone => '尚无引用';

  @override
  String get optCtxTitle => '上下文占用';

  @override
  String get optCtxSystemPrompt => '系统提示词';

  @override
  String get optCtxTools => '工具定义';

  @override
  String get optCtxHistory => '会话历史';

  @override
  String get optCtxRemaining => '剩余窗口';

  @override
  String get optCtxWindowUnknown => '窗口未设置';

  @override
  String get optCtxWindowUnlimited => '不限';

  @override
  String get optCtxWindowAssumed => '该模型未设置上下文窗口，此处按默认值估算。';

  @override
  String optAttachedImages(int count) {
    return '$count 张参考图随消息发送';
  }

  @override
  String get optSendHint => 'Enter 发送 · Shift+Enter 换行';

  @override
  String optModeBadgeAgent(String mode) {
    return '$mode · Agent';
  }

  @override
  String get optRefNumberingHint => '序号与提示词中引用的文件名对应，agent 可查看这些图片。';

  @override
  String get optModeKnowledgeEditShort => '库编辑';

  @override
  String get optRunning => '执行中';

  @override
  String optRunningStep(int count) {
    return '执行中 · 步骤 $count';
  }

  @override
  String get optAgentStepsRunning => 'Agent 过程 · 进行中';

  @override
  String get optAgentStepWorking => '正在执行下一步…';

  @override
  String optElapsedSeconds(int seconds) {
    return '已用 ${seconds}s';
  }

  @override
  String optElapsedMinutes(int minutes, int seconds) {
    return '已用 ${minutes}m ${seconds}s';
  }

  @override
  String get optChatBusyHint => 'Agent 正在执行，完成后可继续输入…';

  @override
  String get optAbort => '中断';

  @override
  String get optAbortHint => 'Esc 中断';

  @override
  String get optKbSearching => '检索中';

  @override
  String get optKbCitedRunning => '进行中';

  @override
  String get optSysPromptTemplate => '模板';

  @override
  String get optSysPromptPick => '选择模板';

  @override
  String get optSysPromptSearch => '搜索模板…';

  @override
  String get optSysPromptNone => '未选择模板';

  @override
  String get optSysPromptUnsaved => '未保存';

  @override
  String get optSysPromptSave => '保存';

  @override
  String get optSysPromptReset => '重置';

  @override
  String get optSysPromptSaved => '模板已保存';

  @override
  String get optSysPromptHint => '写下希望助手遵循的指令…';

  @override
  String optSysPromptChars(int count) {
    return '$count 字';
  }

  @override
  String optSysPromptTokens(String tokens) {
    return '约 $tokens tokens';
  }

  @override
  String get optSysPromptNoTools => '此模式不挂载知识库工具，agent 不产生工具调用。';

  @override
  String get kbEditNoChange => '此提议未改动文件内容。';

  @override
  String get kbEditPendingTitle => '待确认改动';

  @override
  String get kbEditWriteAll => '全部写入';

  @override
  String get kbEditDiscardAll => '全部丢弃';

  @override
  String kbEditConfirmAll(int count) {
    return '确认写入 $count 处';
  }

  @override
  String optKbDocCount(int count) {
    return '$count 篇';
  }

  @override
  String get optKbSearchDocs => '搜索文档…';

  @override
  String get optKbTreeEmpty => '这个知识库里还没有文档';

  @override
  String get optKbTreeScanFailed => '无法读取知识库文件夹';

  @override
  String get optKbTreeNoMatch => '没有匹配的文档';

  @override
  String get optKbTreeChanged => '已改';

  @override
  String get optKbTreeAdded => '新增';

  @override
  String optKbTreePending(int count) {
    return '$count 处改动待确认';
  }

  @override
  String get kbWritePolicyTitle => '写入权限';

  @override
  String get kbWriteAllow => '允许 agent 写入知识库';

  @override
  String get kbWriteConfirmEach => '写入前逐条确认';

  @override
  String get kbWriteBackup => '覆盖前保留 .bak 副本';

  @override
  String get kbWriteNoConfirmWarning => '关闭逐条确认后，agent 起草的内容会不经你过目直接写进文件。';
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
  String get searchFilesHint => '搜尋檔案名稱…';

  @override
  String get deselectAllDirectories => '取消全部目錄選擇';

  @override
  String get applyRenames => '套用重新命名';

  @override
  String get additionalInstructions => '補充指令（可選）';

  @override
  String get aiRenameInstructionsHint => '例如：保留原始副檔名、轉換為拼音…';

  @override
  String get noTemplateSelected => '未選擇模板';

  @override
  String get selectTemplateFirst => '請先選擇一個重新命名模板。';

  @override
  String get generatingSuggestions => '正在產生建議…';

  @override
  String get renamePreviewTitle => '重新命名預覽';

  @override
  String conflictsFound(int count) {
    return '$count 個衝突';
  }

  @override
  String get conflictDuplicateTarget => '目標檔名重複';

  @override
  String get addToSelection => '新增至選取項目';

  @override
  String get removeFromSelection => '從選取項目中移除';

  @override
  String imagesSelected(int count) {
    return '已選取 $count 個';
  }

  @override
  String get featureLimitedOnMobile => '功能受限於行動裝置';

  @override
  String get fileBrowserDesktopOnlyDesc =>
      '由於作業系統沙盒限制，進階檔案瀏覽器和批次重新命名功能僅適用於桌面版本。';

  @override
  String get fileBrowseriOSHint => '請使用系統「檔案」App 來管理您產生的圖像。';

  @override
  String get fileBrowserAndroidHint => '請使用裝置的檔案管理員來整理檔案。';

  @override
  String get stagingArea => '暫存區';

  @override
  String get addToStaging => '加入暫存區';

  @override
  String addToStagingCount(int count) {
    return '加入暫存區 · $count 項';
  }

  @override
  String get removeFromStaging => '從暫存區移除';

  @override
  String get stagedBadge => '已暫存';

  @override
  String get clearStaging => '清空';

  @override
  String get stagingEmptyTitle => '暫存區是空的';

  @override
  String get stagingEmptyDesc =>
      '選取檔案後點「加入暫存區」，把要搬運的檔案先記在這裡 —— 只做標記，不移動任何檔案。切換目錄、篩選或重新啟動應用都不會丟。';

  @override
  String get stagingTarget => '目標目錄';

  @override
  String get stagingNoTarget => '未選擇目標目錄';

  @override
  String get stagingTargetHint => '在左欄資料夾上按右鍵「移動 / 複製到此」，或把檔案直接拖到資料夾上。';

  @override
  String stagingRestored(int count) {
    return '已從上次工作階段恢復 $count 項';
  }

  @override
  String get stagingSameAsTarget => '與目標相同 · 執行時跳過';

  @override
  String get stagingMissing => '已失效';

  @override
  String stagingClearMissing(int count) {
    return '清理失效項 ($count)';
  }

  @override
  String get moveHere => '移動到此';

  @override
  String get copyHere => '複製到此';

  @override
  String moveCountHere(int count) {
    return '移動 $count 項到此';
  }

  @override
  String copyCountHere(int count) {
    return '複製 $count 項到此';
  }

  @override
  String stagingItemsCount(int count) {
    return '$count 項';
  }

  @override
  String stagingMissingCount(int count) {
    return '$count 項失效';
  }

  @override
  String stagingAtTargetCount(int count) {
    return '$count 項已在目標目錄（將跳過）';
  }

  @override
  String get onlyThisDirectory => '僅看此目錄';

  @override
  String pasteMoveTitle(String folder) {
    return '移動到 $folder';
  }

  @override
  String pasteCopyTitle(String folder) {
    return '複製到 $folder';
  }

  @override
  String get pasteNoDestination => '請先指定目標目錄';

  @override
  String get pasteDestinationGone => '目標目錄已不存在';

  @override
  String get pasteNothingToDo => '沒有可搬運的檔案';

  @override
  String get conflictsTitle => '處理同名衝突';

  @override
  String get conflictSkip => '跳過';

  @override
  String get conflictOverwrite => '覆蓋';

  @override
  String get conflictRename => '自動改名';

  @override
  String get conflictApplyToRest => '對全部剩餘項套用';

  @override
  String get conflictReasonExists => '目標目錄中已存在';

  @override
  String get conflictReasonDuplicate => '另一個暫存檔案同名';

  @override
  String get conflictReasonSameLocation => '已在此目錄中';

  @override
  String get conflictReasonMissing => '來源檔案已不存在';

  @override
  String get pasteCrossVolumeWarning => '跨磁碟搬運：先複製再刪除，耗時更久，且可能中途停下。';

  @override
  String get pasteRunningMove => '正在移動…';

  @override
  String get pasteRunningCopy => '正在複製…';

  @override
  String pasteProgressCount(int done, int total) {
    return '$done / $total';
  }

  @override
  String get pasteDoneTitle => '搬運完成';

  @override
  String get pasteCancelledTitle => '搬運已取消';

  @override
  String pasteSucceededCount(int count) {
    return '成功 $count 項';
  }

  @override
  String pasteSkippedCount(int count) {
    return '跳過 $count 項';
  }

  @override
  String pasteFailedCount(int count) {
    return '失敗 $count 項';
  }

  @override
  String renameSubtitleFiles(int files, int dirs) {
    return '$files 個檔案 · 來自 $dirs 個目錄';
  }

  @override
  String get renameSectionModel => '模型';

  @override
  String get renameSectionTemplate => '命名範本';

  @override
  String get renameSectionInstructions => '補充指令';

  @override
  String renameBatchEstimate(int files, int size, int batches) {
    return '$files 個檔案 · 每批 $size · 預計 $batches 批';
  }

  @override
  String get renameStopGenerating => '中斷生成';

  @override
  String get renameRegenerate => '重新生成';

  @override
  String get renameFilterAll => '全部';

  @override
  String get renameFilterConflicts => '衝突';

  @override
  String get renameFilterSkipped => '已跳過';

  @override
  String get renameNextConflict => '下一個衝突';

  @override
  String get renameEmptyTitle => '還沒有建議';

  @override
  String renameEmptyDesc(int files, int batches, int size) {
    return '在左側選好模型與命名範本後點「生成建議」。$files 個檔案將按每批 $size 個分 $batches 批提交，生成過程中即可開始逐項審閱。';
  }

  @override
  String get renameGenerating => '正在生成建議';

  @override
  String renameBatchProgress(int batch, int total, int done, int files) {
    return '第 $batch / $total 批 · 已產出 $done / $files 條';
  }

  @override
  String get renameStop => '中斷';

  @override
  String renameProducedHint(int count) {
    return '已產出 $count 條 · 生成完成前可先審閱，不能套用';
  }

  @override
  String renameSuggestionsCount(int count) {
    return '$count 條建議';
  }

  @override
  String renameSkippedCount(int count) {
    return '已跳過 $count';
  }

  @override
  String renameEditingHint(int row) {
    return '第 $row 行正在就地改名';
  }

  @override
  String renameConflictsPending(int count) {
    return '$count 個衝突待處理 · 未決衝突不會被套用';
  }

  @override
  String renameApplyCount(int count) {
    return '套用 $count 項重新命名';
  }

  @override
  String renameApplyShort(int count) {
    return '套用 $count 項';
  }

  @override
  String get renameDuplicateBadge => '重名';

  @override
  String get renameSkippedBadge => '已跳過';

  @override
  String get renameRenamedBadge => '已改名';

  @override
  String get renameActionAccept => '接受';

  @override
  String get renameActionSkip => '跳過';

  @override
  String get renameActionEdit => '就地改名';

  @override
  String get renameActionUndo => '撤銷跳過';

  @override
  String get renameConflictAutoRename => '改名';

  @override
  String get renameNoModelsTitle => '沒有可用的語言模型';

  @override
  String get renameNoModelsDesc =>
      '批次重新命名需要一個對話模型來閱讀圖片並產生名字。請先在「模型與通道」裡設定至少一個可用通道。';

  @override
  String get renameGoToSettings => '前往設定';

  @override
  String renameBatchFailed(int batch, String reason) {
    return '第 $batch 批請求失敗 · $reason';
  }

  @override
  String renameBatchFailedDesc(int kept, int missing) {
    return '已產出的 $kept 條建議已保留，未生成的 $missing 個檔案可單獨重試';
  }

  @override
  String get renameRetryBatch => '重試此批';

  @override
  String get renameEditConfig => '編輯設定';

  @override
  String get renameTemplateLabel => '範本';

  @override
  String pasteMovingCount(int count) {
    return '正在移動 $count 項';
  }

  @override
  String pasteCopyingCount(int count) {
    return '正在複製 $count 項';
  }

  @override
  String pasteRoute(String from_, String to) {
    return '$from_ → $to';
  }

  @override
  String get pasteCrossVolumeTag => '跨磁碟';

  @override
  String pasteProgressItems(
    int done,
    int total,
    String doneSize,
    String totalSize,
  ) {
    return '$done / $total 項 · $doneSize / $totalSize';
  }

  @override
  String pasteCurrentFile(String name) {
    return '正在複製 $name';
  }

  @override
  String get pasteRollbackNote => '跨磁碟移動按「複製 + 刪除」執行；取消時已複製的檔案將被回滾刪除，來源檔案保持不動。';

  @override
  String get pasteRunInBackground => '背景執行';

  @override
  String get pasteMoveDone => '移動完成';

  @override
  String get pasteCopyDone => '複製完成';

  @override
  String pasteElapsed(int count, String time) {
    return '$count 項 · 用時 $time';
  }

  @override
  String get pasteStatSucceeded => '成功';

  @override
  String get pasteStatSkipped => '跳過（與目標相同）';

  @override
  String get pasteStatFailed => '失敗';

  @override
  String get pasteRetry => '重試';

  @override
  String pasteKeptInStaging(int kept, int moved) {
    return '失敗與跳過的 $kept 項仍保留在暫存區，成功的 $moved 項已自動移出。';
  }

  @override
  String get pasteExportLog => '匯出日誌';

  @override
  String pasteLogSaved(String path) {
    return '日誌已儲存到 $path';
  }

  @override
  String conflictsSubtitle(int count, int total, String folder) {
    return '$count / $total 項與目標 $folder 重名';
  }

  @override
  String get conflictsIntro => '逐項選擇處理方式；也可以勾選下方「對剩餘項套用」。';

  @override
  String get conflictPending => '待定';

  @override
  String conflictWriteInfo(String size, String date) {
    return '寫入 · $size · $date';
  }

  @override
  String conflictExistingInfo(String size, String date) {
    return '已有 · $size · $date';
  }

  @override
  String get conflictOverwriteWarning => '目標檔案將被替換，不可撤銷';

  @override
  String conflictApplyRestCount(int count) {
    return '對剩餘 $count 項套用同一選擇';
  }

  @override
  String get conflictApplyAndContinue => '套用並繼續';

  @override
  String dragMoveHint(int count) {
    return '移動 $count 項 · 按住 Ctrl 複製';
  }

  @override
  String get showInSystem => '在系統中顯示';

  @override
  String get newSubfolder => '新增子資料夾';

  @override
  String get newFolderDefaultName => '新增資料夾';

  @override
  String get moveFolderTo => '移動到…';

  @override
  String get removeFromList => '從清單中移除';

  @override
  String get rootCannotMove => '根目錄無法移動';

  @override
  String get deleteFolderTitle => '刪除資料夾？';

  @override
  String get trashFolderTitle => '移到垃圾桶？';

  @override
  String get deleteFolderEmptyDesc => '這個資料夾是空的，刪除後無法復原。';

  @override
  String get trashFolderEmptyDesc => '這個資料夾是空的，刪除後可從系統垃圾桶找回。';

  @override
  String get deleteFolderIrreversible => '此操作無法復原';

  @override
  String get trashFolderRestorable => '可從系統垃圾桶找回';

  @override
  String get inventorySubfolders => '子資料夾';

  @override
  String get inventoryFiles => '檔案';

  @override
  String get inventorySize => '大小';

  @override
  String get inventoryCounting => '正在盤點…';

  @override
  String deleteFolderCount(int count) {
    return '刪除 $count 項';
  }

  @override
  String trashFolderCount(int count) {
    return '移到垃圾桶 · $count 項';
  }

  @override
  String get moveToTrash => '移至資源回收筒';

  @override
  String get folderNameEmpty => '名稱不能為空';

  @override
  String folderNameIllegalChars(String chars) {
    return '名稱不能包含 $chars';
  }

  @override
  String get folderNameReserved => '這是系統保留名稱';

  @override
  String get folderNameExists => '已有同名資料夾';

  @override
  String get folderPathRegistered => '該路徑已在清單中';

  @override
  String get moveFolderIntoSelf => '資料夾不能移動到自身內部';

  @override
  String get moveFolderSameParent => '資料夾已在該位置';

  @override
  String get moveFolderTargetExists => '目標位置已有同名項目';

  @override
  String dragMoveFolderHint(String name) {
    return '移動「$name」';
  }

  @override
  String dragCopyFolderHint(String name) {
    return '複製「$name」';
  }

  @override
  String folderMovingTitle(String name) {
    return '正在移動資料夾 $name';
  }

  @override
  String folderCopyingTitle(String name) {
    return '正在複製資料夾 $name';
  }

  @override
  String folderTransferItems(int count) {
    return '$count 項';
  }

  @override
  String get folderMoveCrossVolumeNote =>
      '不同磁碟 · 先複製再刪除，來源目錄會在全部到達後才移除，取消不會遺失任何內容。';

  @override
  String get folderMoveCancelledTitle => '已取消移動';

  @override
  String get folderCopyCancelledTitle => '已取消複製';

  @override
  String folderTransferStoppedAt(int done, int total) {
    return '在 $done / $total 項處停止';
  }

  @override
  String get folderMoveStatCopied => '已複製到目標';

  @override
  String get folderMoveStatPending => '未開始';

  @override
  String get folderMoveStatSourceKept => '來源目錄保留';

  @override
  String get folderMoveCancelledDesc =>
      '來源目錄完整保留，未刪除任何檔案。已複製到目標的項目保留在目標位置，可稍後重新拖曳，同名項目會逐項處理。';

  @override
  String get showDestinationInSystem => '在系統中顯示目標';

  @override
  String get gotIt => '知道了';

  @override
  String folderCreated(String name) {
    return '已建立 $name';
  }

  @override
  String folderRenamed(String name) {
    return '已重新命名為 $name';
  }

  @override
  String folderDeleted(String name) {
    return '已刪除 $name';
  }

  @override
  String folderTrashed(String name) {
    return '已將 $name 移到垃圾桶';
  }

  @override
  String folderMoved(String name, String target) {
    return '已移動 $name 到 $target';
  }

  @override
  String folderCopied(String name, String target) {
    return '已複製 $name 到 $target';
  }

  @override
  String folderOpFailed(String error) {
    return '操作失敗：$error';
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
  String get minimizeWindow => '最小化';

  @override
  String get maximizeWindow => '最大化';

  @override
  String get restoreWindow => '向下還原';

  @override
  String get closeWindow => '關閉';

  @override
  String get expandEditor => '放大編輯';

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
  String get more => '更多';

  @override
  String get confirm => '確認';

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
  String downloaderFoundSelected(int found, int selected) {
    return '發現 $found 張 · 已選 $selected 張';
  }

  @override
  String get guideStep1Title => '1 · 輸入網址';

  @override
  String get guideStep1Desc => '貼上圖庫或文章頁面連結';

  @override
  String get guideStep2Title => '2 · 描述需求';

  @override
  String get guideStep2Desc => '告訴 AI 要尋找的圖像';

  @override
  String get guideStep3Title => '3 · 挑選下載';

  @override
  String get guideStep3Desc => '批次選擇並加入任務佇列';

  @override
  String get copyLogs => '複製日誌';

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
  String get cachedInputTokens => '快取輸入';

  @override
  String get outputTokens => '輸出 Token';

  @override
  String get cacheHitRate => '快取命中率';

  @override
  String get cacheHitRateHint => '命中快取的輸入 Token 佔全部輸入 Token 的比例';

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
  String get usageColumnDetail => '明細';

  @override
  String get usageColumnTime => '時間';

  @override
  String get usageColumnCost => '成本';

  @override
  String get yesterday => '昨天';

  @override
  String usageRecordCount(int count) {
    return '$count 筆';
  }

  @override
  String usageItemCount(int count) {
    return '$count 項';
  }

  @override
  String get noUsageInRange => '所選時間範圍內沒有用量資料。';

  @override
  String get loadMore => '載入更多';

  @override
  String get invalidPriceValue => '請輸入有效的非負數字';

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
  String get probeChannel => '測試連線';

  @override
  String get probeOk => '連線成功且鑑權通過';

  @override
  String get probeModels => '個模型';

  @override
  String get probeConnectedNoModels => '已連通——該端點沒有模型列表，部分中轉屬正常情況。';

  @override
  String get probeAuthFailed => '端點有回應，但拒絕了 API 金鑰。';

  @override
  String get probeNotAnApi => '該地址回傳的不是本 API（可能是網頁）——請檢查 Base URL。';

  @override
  String get probeUnreachable => '端點無回應';

  @override
  String get probeNotSupported => '該渠道類型不支援連線測試。';

  @override
  String get enableDiscovery => '啟用模型探索';

  @override
  String get filterModels => '篩選模型...';

  @override
  String get tagColor => '標籤顏色';

  @override
  String deleteChannelConfirm(String name) {
    return '您確定要刪除通道「$name」嗎？其下的關聯模型也會一併刪除。';
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
  String get modelIdLabel => '模型 ID';

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
  String get cacheInputPrice => '輸入價格·命中快取（美元/百萬 Token）';

  @override
  String get cacheInputPriceHint => '留空則快取命中依「輸入價格」計費';

  @override
  String get requestPriceHint => '依每次成功請求計費，與 Token 用量無關。';

  @override
  String get cachePriceFollowsInput => '快取命中依「輸入價格」計費';

  @override
  String get outputPrice => '輸出價格（美元/百萬 Token）';

  @override
  String get requestPrice => '請求價格（美元/次）';

  @override
  String get priceConfig => '價格設定';

  @override
  String get priceLabelInput => '輸入';

  @override
  String get priceLabelCache => '快取';

  @override
  String get priceLabelOutput => '輸出';

  @override
  String get priceLabelRequest => '請求';

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
  String get protocolMidjourney => 'Midjourney 代理';

  @override
  String get protocolMidjourneyDesc => 'midjourney-proxy / NewAPI 的 /mj/* 介面';

  @override
  String get protocolAnthropic => 'Anthropic Messages 協定';

  @override
  String get protocolAnthropicDesc => 'Claude 原生 /v1/messages 介面';

  @override
  String get midjourneyEndpointHint =>
      '填寫主機根位址（如 https://your-newapi.com），/mj/* 路徑將自動補全。';

  @override
  String get providerOpenAIOfficial => 'OpenAI 官方';

  @override
  String get providerGoogleOfficial => 'Google GenAI 官方';

  @override
  String get providerGoogleCompatible => 'Google GenAI (OpenAI 相容)';

  @override
  String get providerGoogleCompatibleDesc => '透過 OpenAI 端點的 Google Gemini';

  @override
  String get providerDashScopeDesc =>
      'dashscope.aliyuncs.com/compatible-mode · OpenAI 形狀請求 · 千問對話 + qwen-image / 萬相原生出圖 + 萬相影片';

  @override
  String get providerDashScopeCompat => '阿里雲百煉（OpenAI 相容）';

  @override
  String get providerDashScopeNative => '阿里雲百煉（DashScope 原生）';

  @override
  String get providerDashScopeNativeDesc =>
      'dashscope.aliyuncs.com/api/v1 · 阿里雲自有請求格式 · qwen-audio 只能走這條';

  @override
  String get endpointOverrideHint => '已依所選提供商預填，可改為中轉、閘道或國際站位址。';

  @override
  String get providerQianwen => '千問平台';

  @override
  String get providerQianwenDesc =>
      'platform.qianwenai.com · API 同 DashScope — 千問對話 + qwen-image / wan2.7 出圖';

  @override
  String get providerCustom => '自訂供應商';

  @override
  String get providerCustomDesc => '自行託管或第三方供應商';

  @override
  String get providerGroupOther => '其他';

  @override
  String get stepConnection => '連線與金鑰';

  @override
  String get sectionAppearance => '外觀';

  @override
  String get moreColors => '更多顏色';

  @override
  String get protocolXai => 'xAI (Grok) API';

  @override
  String get providerXaiOfficial => 'xAI 官方';

  @override
  String get providerXaiOfficialDesc => 'api.x.ai · Grok 聊天 + 原生 Imagine 影片';

  @override
  String get providerNewApiOpenAI => 'New API（OpenAI 格式）';

  @override
  String get providerNewApiGemini => 'New API（Gemini 格式）';

  @override
  String get providerNewApiDesc => 'New API 中轉 · Bearer 權杖驗證';

  @override
  String get providerAnthropicOfficial => 'Anthropic 官方';

  @override
  String get providerAnthropicOfficialDesc => 'api.anthropic.com · Claude';

  @override
  String get providerNewApiAnthropic => 'New API（Anthropic 格式）';

  @override
  String get providerMiniMaxAnthropic => 'MiniMax（Anthropic 格式）';

  @override
  String get providerMiniMaxDesc => 'OpenAI 相容 /v1 端點';

  @override
  String get newApiBaseUrl => 'New API 基礎位址';

  @override
  String get newApiBaseHint => '填寫 New API 主機位址，版本路徑將自動補全';

  @override
  String get customEndpointHint => '輸入您的自訂端點 URL';

  @override
  String get openaiV1Hint => '提示：OpenAI 相容端點通常以「/v1」結尾';

  @override
  String get googleV1BetaHint => '提示：Google GenAI 端點通常以「/v1beta」結尾';

  @override
  String get anthropicV1Hint => '提示：Anthropic 端點通常以「/v1」結尾';

  @override
  String get dashscopeApiV1Hint => '提示：DashScope 原生端點以「/api/v1」結尾';

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
  String get feeGroupEditorSubtitle => '設定模型的計費標準';

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
  String feeGroupModelCount(int count) {
    return '$count 個模型';
  }

  @override
  String get feeGroupUnused => '沒有模型在使用';

  @override
  String get model => '模型';

  @override
  String modelsAndChannelsCount(int models, int channels) {
    return '$models 個模型 · $channels 個頻道';
  }

  @override
  String get deselectAll => '取消全部選取';

  @override
  String get capabilities => '能力';

  @override
  String get modelSaveRequirementHint => '通道、名稱、ID 三項齊備後方可儲存。';

  @override
  String get cardPreview => '卡片預覽';

  @override
  String get capabilityStreamingShort => '串流';

  @override
  String get capabilityStandardShort => '標準請求';

  @override
  String get supportsStreaming => '支援串流傳輸';

  @override
  String get supportsStreamingDesc => '若模型支援伺服器推送事件（SSE）請啟用';

  @override
  String get supportsStandardRequest => '支援標準請求';

  @override
  String get supportsStandardRequestDesc => '啟用標準 JSON/REST 請求';

  @override
  String get contextWindow => '上下文大小';

  @override
  String get contextUnset => '未設定';

  @override
  String get contextUnsetDesc => '使用保守預設值——不確定模型真實上限時選這個。';

  @override
  String get contextSpecify => '指定大小';

  @override
  String get contextUnlimited => '不限制';

  @override
  String get contextUnlimitedDesc => '一次性傳送所有候選圖片，且不依視窗大小限制提示詞助手。';

  @override
  String get contextMax => '最大上下文';

  @override
  String contextTokens(String size) {
    return '$size tokens';
  }

  @override
  String get contextWindowHint => '用於每次請求的圖片分批，以及提示詞助手讀取知識庫與摘要的預算。';

  @override
  String get agentBehavior => '代理行為';

  @override
  String get forceViewAllImages => '檢視全部參考圖';

  @override
  String get forceViewAllImagesDesc => '代理必須檢視所有參考圖後才能提交結果，建議為本地小模型開啟。';

  @override
  String get reasoningEffort => '推理強度';

  @override
  String get reasoningEffortDesc =>
      '模型作答前的思考強度。預設＝不傳送任何欄位（由端點自行決定）；其他檔位會消耗輸出 token。適用於 OpenAI 與 Anthropic 格式渠道。Anthropic 格式渠道上，Claude 4.6 及更新的模型以 output_config.effort 下發檔位；「最高」只有最新一代模型接受，若 400 回報點名該檔位，請降一檔。';

  @override
  String get reasoningEffortDefault => '預設（不傳送）';

  @override
  String get reasoningEffortOff => '關閉';

  @override
  String get reasoningEffortLow => '低';

  @override
  String get reasoningEffortMedium => '中';

  @override
  String get reasoningEffortHigh => '高';

  @override
  String get reasoningEffortMax => '最高';

  @override
  String get enableThinking => '深度思考';

  @override
  String get enableThinkingDesc => '讓模型先推理再作答。會消耗輸出 token，僅 Anthropic 格式通道支援。';

  @override
  String get enableWebSearch => '伺服器端聯網搜尋';

  @override
  String get enableWebSearchDesc => '允許服務商在作答過程中自行搜尋網頁。按額外 token 計費，並會代你抓取網頁。';

  @override
  String get addChannelSubtitle => '先選這是誰，再填連線方式';

  @override
  String get searchProviders => '搜尋提供商…';

  @override
  String get noProviderMatch => '沒有符合的提供商';

  @override
  String get resetToDefault => '重設為預設值';

  @override
  String get apiKeyRequired => '此提供商需要金鑰才能新增通道';

  @override
  String get endpointRequired => '請填寫介面位址';

  @override
  String get probeRetry => '重試';

  @override
  String get customColor => '自訂顏色';

  @override
  String get stepConnectionAppearance => '連線與外觀';

  @override
  String get channelListPreview => '清單預覽';

  @override
  String get pickerNoMatches => '沒有符合項目';

  @override
  String pickerMatchCount(int count) {
    return '顯示 $count 項';
  }

  @override
  String get selectAChannel => '選擇通道';

  @override
  String get searchChannels => '搜尋通道名稱或標籤...';

  @override
  String get kindChat => '對話';

  @override
  String get kindImage => '圖像';

  @override
  String get kindVideo => '影片';

  @override
  String get kindMultimodal => '多模態';

  @override
  String reasoningChip(String level) {
    return '推理·$level';
  }

  @override
  String get webSearchChip => '聯網';

  @override
  String get viewAllImagesChip => '看全部參考圖';

  @override
  String countGroups(int count) {
    return '$count 組';
  }

  @override
  String get previewInList => '列表中的樣子';

  @override
  String get providerGroupVendor => '廠商';

  @override
  String get providerGroupVendorHint => '官方直連 · 位址已預填';

  @override
  String get providerGroupRelay => '中轉站';

  @override
  String get providerGroupRelayHint => '協定已知 · 位址自填';

  @override
  String get providerGroupCustom => '自訂';

  @override
  String get providerGroupCustomHint => '位址自填 + 明確選協定';

  @override
  String get providerGroupLocal => '本機';

  @override
  String get providerGroupLocalHint => '預設 localhost';

  @override
  String get providerNeedKeyOnly => '僅填密鑰';

  @override
  String get providerNeedEndpoint => '需填位址';

  @override
  String get providerNeedKeyless => '免密鑰';

  @override
  String get providerCustomOpenAIDesc => '任何提供 OpenAI 對話介面的服務';

  @override
  String get providerCustomGoogleDesc => '任何提供 Google GenAI 介面的服務';

  @override
  String get providerCustomAnthropicDesc => '任何提供 Anthropic Messages 介面的服務';

  @override
  String get variantTitleGoogle => '接入方式';

  @override
  String get variantTitleMiniMax => '接入面';

  @override
  String get variantTitleNewApi => '介面格式';

  @override
  String get variantTitleGeneric => '接入方式';

  @override
  String get variantHintGoogle => 'Google 同一批模型提供兩種接入方式，切換會改寫下面的介面位址。';

  @override
  String get variantHintMiniMax => 'MiniMax 同時提供兩套介面，選一套即可，之後仍可改。';

  @override
  String get variantHintNewApi => 'host 由你填，尾段跟著你選的格式走。';

  @override
  String get variantHintGeneric => '切換會改寫下面的介面位址。';

  @override
  String get variantGoogleNative => 'GenAI 原生協定';

  @override
  String get variantGoogleOpenAI => 'OpenAI 相容面';

  @override
  String get variantMiniMaxOpenAI => 'OpenAI 面';

  @override
  String get variantMiniMaxAnthropic => 'Anthropic 面';

  @override
  String get variantNewApiOpenAI => 'OpenAI 格式';

  @override
  String get variantNewApiGemini => 'Gemini 格式';

  @override
  String get variantNewApiAnthropic => 'Anthropic 格式';

  @override
  String get channelPresetLabel => '供應商預設';

  @override
  String get channelPresetHint => '預設只負責一鍵填好下面的欄位。填完仍可逐項修改，改過也不會被覆蓋。';

  @override
  String get changePreset => '更換預設';

  @override
  String get presetUnmatched => '未匹配預設';

  @override
  String get presetUnmatchedHint =>
      '這條頻道用的是舊版本建立的類型，已不在預設清單裡。保持不動即可繼續使用；點「更換預設」會覆蓋下面的欄位。';

  @override
  String get presetEndpointModified => '位址已改過';

  @override
  String get restorePresetEndpoint => '恢復預設值';

  @override
  String get changePresetOverlayHint => '選中會用預設值覆蓋介面協定與位址（密鑰、名稱、標籤不動）。';

  @override
  String get protocolField => '介面協定';

  @override
  String get protocolFieldHint => '共 5 個協定族，任何已儲存的類型都能在這裡表示。';

  @override
  String get deprecatedLabel => '已廢棄';

  @override
  String get apiKeyOptional => '可選';

  @override
  String get apiKeyLocalPlaceholder => '本機服務通常不需要';

  @override
  String get apiKeyLocalNote => '留空即可。如果你給本機服務加了反向代理鑑權，在這裡填對應的密鑰。';

  @override
  String get searchProvidersAlias => '搜尋供應商，或試試「千問」';

  @override
  String providerCountSummary(int count, int groups) {
    return '$count 個供應商 · $groups 組';
  }

  @override
  String providerVariantCount(int count) {
    return '$count 種接入';
  }

  @override
  String get requestMethod => '請求方式';

  @override
  String get interfaceProtocol => '介面協定';

  @override
  String get protocolAuto => '自動';

  @override
  String protocolAutoResolved(String name) {
    return '自動 · 目前解析為「$name」';
  }

  @override
  String get protocolAutoHelper => '跟隨渠道供應商，更換供應商後自動重新解析。';

  @override
  String protocolStaleHelper(String name) {
    return '原選擇「$name」在目前供應商下不可用，已回到自動。';
  }

  @override
  String get protocolOpenAICompat => 'OpenAI 相容';

  @override
  String get protocolAnthropicCompat => 'Anthropic 相容';

  @override
  String get protocolDashScopeNative => 'DashScope 原生';

  @override
  String get protocolDashScopeNativeDesc => '阿里雲自有請求格式，qwen-audio 只能走這條';

  @override
  String get protocolImageSync => '同步生成';

  @override
  String get protocolImageSyncDesc => '一次請求直接返回圖片';

  @override
  String get protocolImageAsync => '非同步任務';

  @override
  String get protocolImageAsyncDesc => '提交後輪詢結果，生成中可取消';

  @override
  String get protocolVideoTask => '非同步影片任務';

  @override
  String get protocolStreamIgnoredAsync => '非同步任務不使用串流傳輸，此項已忽略';

  @override
  String get protocolAsyncQueueNote => '提交後進入任務佇列輪詢，生成中可取消。';

  @override
  String get protocolPinStale => '點單已失效';

  @override
  String protocolStaleTooltip(String name) {
    return '原選擇「$name」不可用，正在按自動運行。';
  }

  @override
  String get channelReorderHandleTooltip => '拖動調整順序';

  @override
  String get channelOrderSaveFailed => '順序未能儲存，已恢復原順序';

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
  String get selectionMode => '選擇模式';

  @override
  String selectionModeCount(int count) {
    return '選擇模式（$count）';
  }

  @override
  String nSelected(int count) {
    return '已選擇 $count 項';
  }

  @override
  String get categorize => '歸類';

  @override
  String get bulkCategorize => '批次歸類';

  @override
  String get selectCategoriesToApply => '選擇要套用到所選提示的類別：';

  @override
  String deleteNPromptsConfirm(int count) {
    return '刪除 $count 個提示？';
  }

  @override
  String get actionCannotBeUndone => '此操作無法復原。';

  @override
  String deleteCategoryConfirmMessage(String name) {
    return '刪除類別「$name」？其中的提示將移至 General。';
  }

  @override
  String get moveToTop => '移到頂部';

  @override
  String get moveToBottom => '移到底部';

  @override
  String get addSystemTemplateHint => '在此新增用於 Refiner 或批次重新命名的系統範本。';

  @override
  String importFailed(String error) {
    return '匯入失敗：$error';
  }

  @override
  String get filterAll => '全部';

  @override
  String get newTemplate => '新增範本';

  @override
  String get reorderDisabledWhileFiltered => '篩選或搜尋時無法拖曳排序';

  @override
  String get matchModeLabel => '符合';

  @override
  String get matchAny => '任一';

  @override
  String get matchAllTags => '全部';

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
  String get font => '字型';

  @override
  String get fontSystem => '系統預設';

  @override
  String get fontDownloadTitle => '下載字型';

  @override
  String get fontDownloadPrompt => '此字型未隨應用程式打包，首次使用前需要下載一次。';

  @override
  String get fontDownloadAction => '下載';

  @override
  String get fontDownloading => '正在下載字型…';

  @override
  String get fontDownloadFailed => '字型下載失敗，請檢查網路後重試。';

  @override
  String get preferHighPerformanceGpu => '優先使用高效能 GPU';

  @override
  String get preferHighPerformanceGpuDesc =>
      '讓 Windows 使用獨立顯示卡執行本應用程式，下次啟動時生效。';

  @override
  String get reduceVisualEffects => '減少視覺效果';

  @override
  String get reduceVisualEffectsDesc => '關閉模糊效果，在內顯或低效能 GPU 上獲得更流暢的體驗。';

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
  String get importErrorPromptsOnly => '這是提示詞庫匯出檔案，不是完整備份。請在提示詞頁面匯入。';

  @override
  String get importErrorNotABackup => '該檔案不是有效的備份檔案。請選擇透過「匯出設定」產生的檔案。';

  @override
  String get importErrorNewerSchema => '該備份由更新版本的應用程式建立。請先升級應用程式後再匯入。';

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
  String get knowledgeBaseFolder => '知識庫資料夾';

  @override
  String get kbOpenFolder => '開啟資料夾';

  @override
  String get kbInvalidDir => '資料夾不存在';

  @override
  String get kbMissingEntry => '資料夾中缺少入口檔案 README.md';

  @override
  String get assistantContextRatio => '助手摘要閾值';

  @override
  String get assistantContextRatioDesc =>
      '提示詞助手在上下文佔用達到模型視窗的該比例時自動摘要對話，騰出空間繼續工作。僅對已設定上下文大小的模型生效。';

  @override
  String get kbSubAgent => '知識庫子代理';

  @override
  String get kbSubAgentDesc => '允許助手把知識庫檢索交給子代理，在獨立上下文中通讀檔案，保持主對話輕量。實驗性功能。';

  @override
  String get kbSubAgentModel => '子代理模型';

  @override
  String get kbSubAgentModelFollow => '跟隨會話模型';

  @override
  String get kbSubAgentModelMissing => '綁定的模型已不存在——在重新選擇之前，委託功能將被停用。';

  @override
  String get assistantRetention => '助手對話保留數量';

  @override
  String get assistantRetentionDesc => '超出數量的較舊提示詞助手對話將被自動刪除';

  @override
  String get about => '關於';

  @override
  String aboutVersion(Object version) {
    return '版本 $version';
  }

  @override
  String get aboutGithubRepo => 'GitHub 儲存庫';

  @override
  String get aboutViewSource => '查看原始碼與發行版本';

  @override
  String get aboutLicense => '授權條款';

  @override
  String aboutCopyright(Object year, Object holder) {
    return '版權所有 © $year $holder，依 MIT 授權條款發布。';
  }

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
  String get clearAll => '清除全部';

  @override
  String get clearAllConfirm => '此操作將刪除所有未運行的任務，且無法復原。';

  @override
  String get cancelAllPending => '取消所有待處理';

  @override
  String get cancelTask => '取消任務';

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
    return '$count 個已計劃';
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
    return '並行限制: $limit';
  }

  @override
  String taskTotalCount(int count) {
    return '共 $count 個任務';
  }

  @override
  String get statusCancelled => '已取消';

  @override
  String get retryTask => '重試';

  @override
  String queuedPosition(int position) {
    return '排隊第 $position 位';
  }

  @override
  String tookDuration(String duration) {
    return '耗時 $duration';
  }

  @override
  String retryCount(int count) {
    return '重試次數: $count';
  }

  @override
  String get viewTaskLog => '檢視日誌';

  @override
  String get taskLogTitle => '任務日誌';

  @override
  String get taskLogLive => '即時';

  @override
  String get noTaskLog => '此任務沒有日誌記錄。';

  @override
  String get noTaskLogHint => '本次更新之前執行的任務不會保存日誌。';

  @override
  String get taskLogCopied => '日誌已複製到剪貼簿';

  @override
  String get copyPrompt => '複製提示詞';

  @override
  String taskLogLineCount(int count) {
    return '$count 行';
  }

  @override
  String get goToWorkbench => '前往工作台';

  @override
  String get copyAll => '複製全部';

  @override
  String get copiedAll => '已複製到剪貼簿';

  @override
  String get noLogsYet => '這個任務還沒有日誌';

  @override
  String get sourceFiles => '來源檔案';

  @override
  String get requestParameters => '請求參數';

  @override
  String get outputPaths => '產物路徑';

  @override
  String get copyError => '複製錯誤';

  @override
  String taskTotalShort(int count) {
    return '共 $count';
  }

  @override
  String get statusShortRunning => '執行';

  @override
  String get statusShortPending => '待';

  @override
  String get statusShortDone => '完成';

  @override
  String get statusShortFailed => '失敗';

  @override
  String get sortNewestFirst => '最新在前';

  @override
  String get sortOldestFirst => '最早在前';

  @override
  String get sortSection => '排序';

  @override
  String get pinActiveTasks => '執行中與待處理置頂';

  @override
  String get restByCreatedTime => '其餘按建立時間';

  @override
  String get createdAt => '建立';

  @override
  String get cancelledByUser => '已取消 · 手動';

  @override
  String get noRunningTasks => '沒有執行中的任務';

  @override
  String get noPendingTasks => '沒有待處理的任務';

  @override
  String get noCompletedTasks => '沒有已完成的任務';

  @override
  String get noFailedTasks => '沒有失敗的任務';

  @override
  String filteredEmptyHint(int count) {
    return '目前篩選下沒有任務，其餘 $count 個任務未受影響。';
  }

  @override
  String get viewAllTasks => '查看全部';

  @override
  String get durationLabel => '用時';

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
  String get wbModeImage => '圖像';

  @override
  String get wbModeVideo => '影片';

  @override
  String get wbTools => '工具';

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
  String get sectionSources => '來源';

  @override
  String get sectionResults => '結果';

  @override
  String get sectionWorkspace => '工作區';

  @override
  String get allSources => '全部來源';

  @override
  String get allResults => '全部結果';

  @override
  String get backToAll => '返回全部';

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
  String get selectAll => '全選';

  @override
  String get importFromGallery => '從圖庫匯入';

  @override
  String get takePhoto => '拍照';

  @override
  String get clearTempWorkspace => '清除工作區';

  @override
  String get clearTempWorkspaceConfirmTitle => '清除暫存工作區？';

  @override
  String clearTempWorkspaceConfirmMessage(int count) {
    return '將從暫存工作區移除全部 $count 項。檔案本身不會被刪除。';
  }

  @override
  String get dropFilesHere => '將圖片拖放到此處以新增到臨時工作區';

  @override
  String get noImagesSelected => '未選取圖片';

  @override
  String get imageLoadFailed => '圖片載入失敗';

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
  String get thumbnailDisplay => '縮圖顯示';

  @override
  String get thumbnailFitContain => '適應（完整顯示）';

  @override
  String get thumbnailFitCover => '填滿（裁切鋪滿）';

  @override
  String get deleteFile => '刪除檔案';

  @override
  String get deleteFileConfirmTitle => '刪除檔案？';

  @override
  String deleteFileConfirmMessage(String filename) {
    return '您確定要刪除「$filename」嗎？';
  }

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
  String get imageSizeLabel => '尺寸';

  @override
  String get quality => '品質';

  @override
  String get promptExtend => '提示詞擴寫';

  @override
  String get promptExtendOn => '開啟';

  @override
  String get promptExtendOff => '關閉';

  @override
  String get optionAuto => '自動';

  @override
  String get qualityLow => '低';

  @override
  String get qualityMedium => '中';

  @override
  String get qualityHigh => '高';

  @override
  String get mjVersion => '版本';

  @override
  String get mjMode => '模式';

  @override
  String get mjStylize => '風格化';

  @override
  String get mjChaos => '混亂度';

  @override
  String get referenceImagesNotSupported => '此模型不支援參考圖，所選圖片將被忽略。';

  @override
  String referenceImagesLimited(int count) {
    return '此模型最多支援 $count 張參考圖，其餘將被忽略。';
  }

  @override
  String get prompt => '提示詞';

  @override
  String get promptHint => '在此輸入提示詞...';

  @override
  String get promptHistory => '歷史紀錄';

  @override
  String get noPromptHistory => '尚無歷史紀錄';

  @override
  String get noPromptHistoryDesc => '送出過的提示詞會顯示在這裡。';

  @override
  String get usePrompt => '使用此提示詞';

  @override
  String get applyPromptWarning => '將取代編輯器中目前的提示詞。';

  @override
  String get clearPromptHistory => '清除歷史紀錄';

  @override
  String get clearPromptHistoryConfirm => '確定清除全部歷史紀錄嗎？此操作無法復原。';

  @override
  String get timeJustNow => '剛剛';

  @override
  String timeMinutesAgo(int count) {
    return '$count 分鐘前';
  }

  @override
  String timeHoursAgo(int count) {
    return '$count 小時前';
  }

  @override
  String timeDaysAgo(int count) {
    return '$count 天前';
  }

  @override
  String get prefixHint => '例如：result';

  @override
  String get processPrompt => '處理提示詞';

  @override
  String processImages(int count) {
    return '處理 $count 張圖片';
  }

  @override
  String get useStreaming => '使用串流';

  @override
  String get useStreamingDesc => '即時 AI 回應（若支援）';

  @override
  String get compressReferenceImages => '壓縮參考圖';

  @override
  String get compressReferenceImagesDesc => '超過 3MB 的圖片重新編碼為 JPEG';

  @override
  String get taskSubmitted => '任務已提交至佇列';

  @override
  String get comparator => '比較器';

  @override
  String get compareLayoutSideBySide => '左右並排';

  @override
  String get compareLayoutStacked => '上下並排';

  @override
  String get compareLayoutSlider => '滑動對比';

  @override
  String get compareSyncTransform => '同步縮放平移';

  @override
  String get comparatorEmptyHint => '從檔案瀏覽器或任務結果傳送，也可以直接從庫中選取兩張圖';

  @override
  String get comparatorPickRaw => '選取原圖';

  @override
  String get comparatorPickAfter => '選取效果圖';

  @override
  String comparatorZoomSynced(int percent) {
    return '縮放 $percent% · 已同步';
  }

  @override
  String comparatorZoomIndependent(int percent) {
    return '縮放 $percent% · 獨立';
  }

  @override
  String comparatorSizeReduction(String percent) {
    return '體積減少 $percent';
  }

  @override
  String comparatorSizeIncrease(String percent) {
    return '體積增加 $percent';
  }

  @override
  String get fileSize => '檔案大小';

  @override
  String get sendToComparator => '發送到比較器';

  @override
  String get sendToComparatorRaw => '設為原始圖 (RAW)';

  @override
  String get sendToComparatorAfter => '設為處理後 (Result)';

  @override
  String get sendToFirstFrame => '設為影片首格';

  @override
  String get sendToLastFrame => '設為影片末格';

  @override
  String get sendToVideoReferences => '加入影片參考圖';

  @override
  String get sendToSelection => '新增至選取項目';

  @override
  String get sendToOptimizer => '發送到提示詞助手';

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
  String get overwriteConfirmSaveCopyInstead => '改為儲存副本';

  @override
  String get overwriteConfirmSubtitle => '此操作無法復原';

  @override
  String get overwriteConfirmKeepOriginalHint => '如需保留原圖，可改用「儲存副本」。';

  @override
  String overwriteUnsupportedFormat(String format) {
    return '無法覆蓋 $format 檔案——此格式只能讀取、不能寫入。請改用「儲存副本」。';
  }

  @override
  String get saveToTempSuccess => '圖片已儲存至臨時工作區';

  @override
  String get overwriteSuccess => '原始檔案已更新';

  @override
  String get custom => '自訂';

  @override
  String get cropResizeFreeRatio => '自由';

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
  String get reset => '重設';

  @override
  String cropResizeOriginalInfo(int width, int height, String size) {
    return '原圖 $width×$height · $size';
  }

  @override
  String cropResizeCanvasLabel(String name) {
    return '$name（原圖預覽）';
  }

  @override
  String get cropResizeCropOnly => '裁切';

  @override
  String cropResizeCropAndScale(int percent) {
    return '裁切 + 縮放 $percent%';
  }

  @override
  String get cropResizeOutputPreview => '輸出預覽';

  @override
  String cropResizeOutputSummary(
    String originalSize,
    String outputSize,
    String operation,
    String sampling,
  ) {
    return '$originalSize → $outputSize · $operation · $sampling';
  }

  @override
  String cropResizeWillSaveTo(String path) {
    return '副本將存入 $path';
  }

  @override
  String get cropResizeTempWorkspaceLabel => '臨時工作區';

  @override
  String get saveCopy => '儲存副本';

  @override
  String get cropResizeSaveDestinationHint => '到工作區';

  @override
  String get cropResizeResample => '重新取樣';

  @override
  String get fitToWindow => '適應視窗';

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
  String maskSourceCaption(int width, int height) {
    return '遮罩 $width×$height';
  }

  @override
  String maskBrushBadge(String color, int size) {
    return '$color筆刷 · $size px';
  }

  @override
  String get maskOutputLabel => '輸出';

  @override
  String maskOutputSummary(int width, int height) {
    return '遮罩 $width×$height · PNG（黑白）';
  }

  @override
  String maskCompositeOutputSummary(int width, int height) {
    return '合成圖 $width×$height · PNG';
  }

  @override
  String maskWillSaveTo(String path) {
    return '遮罩將存入 $path';
  }

  @override
  String get maskSaveComposite => '儲存合成圖';

  @override
  String get maskSaveMask => '儲存遮罩';

  @override
  String get maskSaved => '遮罩已儲存到工作區';

  @override
  String maskSaveError(String error) {
    return '儲存遮罩出錯：$error';
  }

  @override
  String get promptOptimizer => '提示詞助手';

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
    return '優化失敗: $error';
  }

  @override
  String get optChatHint => '描述你的想法或貼上粗略提示詞...';

  @override
  String get optSend => '傳送 (Ctrl+Enter)';

  @override
  String get optNewSession => '新對話';

  @override
  String get optToolListImages => '查看了參考圖清單';

  @override
  String optToolViewImage(String name) {
    return '查看了參考圖：$name';
  }

  @override
  String get optPromptTitle => '優化提示詞';

  @override
  String get optCopy => '複製';

  @override
  String get optPromptCopied => '提示詞已複製到剪貼簿';

  @override
  String get optEmptyChat => '傳送粗略提示詞或想法開始優化。AI 會按需查看參考圖，你可以多輪追問持續調整結果。';

  @override
  String get optViewed => 'AI 已查看';

  @override
  String get optRemoveImage => '移除圖片';

  @override
  String get optEmptyImagesHint => '在圖庫中右鍵圖片，選擇「發送到提示詞助手」即可加入此處。';

  @override
  String get videoGeneration => '影片生成';

  @override
  String get referenceImages => '參考圖片';

  @override
  String get firstFrame => '首幀';

  @override
  String get lastFrame => '尾幀';

  @override
  String get generateVideo => '生成影片';

  @override
  String get frames => '幀控制';

  @override
  String get videoResolution => '影片解析度';

  @override
  String get videoAspectRatio => '影片比例';

  @override
  String get videoSeconds => '時長';

  @override
  String get videoQualityStandard => '標準';

  @override
  String get videoQualityHigh => '高畫質';

  @override
  String get openInSystemPlayer => '在系統播放器中打開';

  @override
  String get dropVideoReferenceHere => '在此處拖入用於風格/內容參考的圖片';

  @override
  String get dropFirstFrameHere => '在此處拖入起始幀圖片';

  @override
  String get dropLastFrameHere => '在此處拖入結束幀圖片';

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

  @override
  String get tapToPick => '點擊選取';

  @override
  String get goToGallery => '前往圖庫';

  @override
  String get binaryModeActive => '二值化模式已啟用 — 背景已隱藏以匯出純淨遮罩';

  @override
  String get imageSizePickerTitle => '影像尺寸';

  @override
  String get imageSizeAuto => '自動';

  @override
  String get imageSizeAutoDesc => '由模型自行決定尺寸';

  @override
  String get imageSizePresets => '預設';

  @override
  String get imageSizeCustom => '自訂';

  @override
  String get imageSizeRatio => '比例';

  @override
  String get imageSizeLongEdge => '長邊';

  @override
  String get imageSizeCompute => '計算';

  @override
  String get imageSizeWidth => '寬度';

  @override
  String get imageSizeHeight => '高度';

  @override
  String get imageSizeSnapHint => '兩邊在套用時會自動對齊到 16 像素的整數倍。';

  @override
  String get sizeRuleMultiple16 => '兩邊均為 16 的整數倍';

  @override
  String sizeRuleMaxEdge(int long) {
    return '長邊 ${long}px ≤ 3840';
  }

  @override
  String sizeRuleAspect(String ratio) {
    return '長寬比 $ratio ≤ 3:1';
  }

  @override
  String sizeRulePixels(String mp) {
    return '總像素 $mp 落在 0.66–8.29 MP 區間';
  }

  @override
  String get safetySettings => '安全設定';

  @override
  String get safetySettingsDesc =>
      'Gemini 內容過濾閾值，隨每個請求送出（由嚴格到寬鬆）。Veo/Imagen 不支援。';

  @override
  String get safetyCategoryHarassment => '騷擾內容';

  @override
  String get safetyCategoryHateSpeech => '仇恨言論';

  @override
  String get safetyCategorySexuallyExplicit => '露骨色情';

  @override
  String get safetyCategoryDangerousContent => '危險內容';

  @override
  String get safetyThresholdBlockLowAndAbove => '封鎖大部分';

  @override
  String get safetyThresholdBlockMediumAndAbove => '封鎖一部分';

  @override
  String get safetyThresholdBlockOnlyHigh => '封鎖少部分';

  @override
  String get safetyThresholdBlockNone => '全部不封鎖';

  @override
  String get safetyThresholdOff => '關閉過濾';

  @override
  String get optModeSystemPrompt => '系統提示詞';

  @override
  String get optModeKnowledge => '知識庫';

  @override
  String get knowledgeBase => '知識庫';

  @override
  String get optKbNotConfigured => '知識庫未設定或無效，請先在設定中選擇知識庫資料夾。';

  @override
  String get optModeSwitchConfirm => '切換模式將開始新的對話，是否繼續？';

  @override
  String get optToolListKnowledge => '瀏覽了知識庫檔案列表';

  @override
  String optToolReadKnowledge(String name) {
    return '閱讀知識庫：$name';
  }

  @override
  String get optHistory => '歷史對話';

  @override
  String get optNoHistory => '尚無已儲存的對話';

  @override
  String get optDeleteSessionConfirm => '確定永久刪除該對話？';

  @override
  String get optKbEntryTooLarge =>
      '知識庫的 README.md 佔用了該模型上下文視窗的很大一部分。它每次請求都會重送，且摘要無法壓縮它——請精簡它，或改用視窗更大的模型。';

  @override
  String get optCompactedNotice => '較早的對話已壓縮為摘要，以節省上下文。';

  @override
  String get optKbDistillRequested => '已請求：將本次調優經驗總結進知識庫。';

  @override
  String get optResultFeedbackAction => '回饋給助手';

  @override
  String get optResultFeedbackChatLabel => '結果圖回饋';

  @override
  String get optResultFeedbackHint => '這張圖哪裡不符合預期？';

  @override
  String optResultFeedbackHelper(int version) {
    return '這張結果圖會連同回饋一起進入會話，助手在 v$version 基礎上繼續調整。';
  }

  @override
  String get optDistillAction => '總結本次經驗';

  @override
  String get optDistillDisabledTooltip => '本次會話還沒有 prompt 版本，先讓助手最佳化一次';

  @override
  String optDistillCounts(int versions, int feedbacks) {
    return '$versions 個版本 · $feedbacks 條回饋';
  }

  @override
  String get optDistillAlreadyPending => '總結請求已在等待執行。';

  @override
  String get optResultImages => '結果圖';

  @override
  String get optResultNoFeedback => '未回饋';

  @override
  String get optDistillDoneTitle => '本次經驗已寫入知識庫';

  @override
  String get optSaveFinalPrompt => '將最終 prompt 存入提示詞庫';

  @override
  String get optTimelineTitle => '迭代時間線';

  @override
  String optTimelineCount(int count) {
    return '$count 版';
  }

  @override
  String get optFeedbackShort => '回饋';

  @override
  String get optPromptVersionLabel => '提示詞';

  @override
  String get optImageMissing => '該對話的部分參考圖已不存在，可重新加入後繼續使用。';

  @override
  String get optRetry => '重試';

  @override
  String get optModeKnowledgeEdit => '知識庫編輯';

  @override
  String optToolWriteKnowledge(String name) {
    return '建議更新知識庫：$name';
  }

  @override
  String get kbEditProposedCreate => '新增檔案';

  @override
  String get kbEditProposedUpdate => '更新檔案';

  @override
  String get kbEditApply => '寫入檔案';

  @override
  String get kbEditReject => '捨棄';

  @override
  String get kbEditApplied => '已寫入磁碟';

  @override
  String get kbEditRejected => '已捨棄';

  @override
  String get kbEditFailedShort => '寫入失敗';

  @override
  String kbEditShow(int chars) {
    return '展開內容（$chars 字元）';
  }

  @override
  String get kbEditHide => '收合內容';

  @override
  String kbEditShrinkWarning(int oldChars, int newChars) {
    return '新內容比目前檔案短很多（$oldChars → $newChars 字元），請先確認內容完整再寫入。';
  }

  @override
  String kbEditFailed(String error) {
    return '寫入失敗：$error';
  }

  @override
  String kbScaffoldAlreadyInit(String name) {
    return '已初始化——該資料夾已有 $name，不會被更動。';
  }

  @override
  String get kbScaffoldCreate => '初始化';

  @override
  String kbScaffoldConfirm(String path) {
    return '將把 $path 初始化為知識庫，並在其中建立範例規則檔案。是否繼續？';
  }

  @override
  String kbScaffoldDone(int created) {
    return '知識庫已初始化：新增 $created 個檔案。';
  }

  @override
  String kbScaffoldFailed(String error) {
    return '建立知識庫失敗：$error';
  }

  @override
  String get optAskUserTitle => '助手需要確認幾個問題';

  @override
  String get optAskUserMultiHint => '可複選';

  @override
  String get optAskUserOtherHint => '其他 / 補充說明...';

  @override
  String get optAskUserConfirm => '送出回答';

  @override
  String get optAskUserAnswered => '已回答';

  @override
  String get optAskUserDismissed => '已在對話中繼續';

  @override
  String optAgentSteps(int count) {
    return 'Agent 過程 · $count 步';
  }

  @override
  String optAgentStepsImages(int count) {
    return '檢視 $count 張參考圖';
  }

  @override
  String optAgentStepsDocs(int count) {
    return '閱讀 $count 篇文件';
  }

  @override
  String optAgentStepsExpand(int count) {
    return '展開全部 $count 步';
  }

  @override
  String get optAgentStepsCollapse => '收合步驟';

  @override
  String get optPromptExpand => '展開全文';

  @override
  String get optPromptCollapse => '收合';

  @override
  String get optKbReady => '已初始化';

  @override
  String optKbTreeStats(int files, int dirs) {
    return '$files 篇文件 · $dirs 個目錄';
  }

  @override
  String optKbContentUpdated(String time) {
    return '內容更新於 $time';
  }

  @override
  String get optKbRescan => '重新掃描';

  @override
  String get optKbCitedThisRound => '本輪引用';

  @override
  String optKbCitedAll(int count) {
    return '全部 $count 篇';
  }

  @override
  String get optKbCitedNone => '尚無引用';

  @override
  String get optCtxTitle => '上下文佔用';

  @override
  String get optCtxSystemPrompt => '系統提示詞';

  @override
  String get optCtxTools => '工具定義';

  @override
  String get optCtxHistory => '對話歷史';

  @override
  String get optCtxRemaining => '剩餘視窗';

  @override
  String get optCtxWindowUnknown => '視窗未設定';

  @override
  String get optCtxWindowUnlimited => '不限';

  @override
  String get optCtxWindowAssumed => '此模型未設定上下文視窗，這裡以預設值估算。';

  @override
  String optAttachedImages(int count) {
    return '$count 張參考圖隨訊息傳送';
  }

  @override
  String get optSendHint => 'Enter 傳送 · Shift+Enter 換行';

  @override
  String optModeBadgeAgent(String mode) {
    return '$mode · Agent';
  }

  @override
  String get optRefNumberingHint => '序號與提示詞中引用的檔名對應，agent 可檢視這些圖片。';

  @override
  String get optModeKnowledgeEditShort => '庫編輯';

  @override
  String get optRunning => '執行中';

  @override
  String optRunningStep(int count) {
    return '執行中 · 步驟 $count';
  }

  @override
  String get optAgentStepsRunning => 'Agent 過程 · 進行中';

  @override
  String get optAgentStepWorking => '正在執行下一步…';

  @override
  String optElapsedSeconds(int seconds) {
    return '已用 ${seconds}s';
  }

  @override
  String optElapsedMinutes(int minutes, int seconds) {
    return '已用 ${minutes}m ${seconds}s';
  }

  @override
  String get optChatBusyHint => 'Agent 正在執行，完成後可繼續輸入…';

  @override
  String get optAbort => '中斷';

  @override
  String get optAbortHint => 'Esc 中斷';

  @override
  String get optKbSearching => '檢索中';

  @override
  String get optKbCitedRunning => '進行中';

  @override
  String get optSysPromptTemplate => '範本';

  @override
  String get optSysPromptPick => '選擇範本';

  @override
  String get optSysPromptSearch => '搜尋範本…';

  @override
  String get optSysPromptNone => '未選擇範本';

  @override
  String get optSysPromptUnsaved => '未儲存';

  @override
  String get optSysPromptSave => '儲存';

  @override
  String get optSysPromptReset => '重設';

  @override
  String get optSysPromptSaved => '範本已儲存';

  @override
  String get optSysPromptHint => '寫下希望助手遵循的指令…';

  @override
  String optSysPromptChars(int count) {
    return '$count 字';
  }

  @override
  String optSysPromptTokens(String tokens) {
    return '約 $tokens tokens';
  }

  @override
  String get optSysPromptNoTools => '此模式不掛載知識庫工具，agent 不產生工具呼叫。';

  @override
  String get kbEditNoChange => '此提議未變更檔案內容。';

  @override
  String get kbEditPendingTitle => '待確認變更';

  @override
  String get kbEditWriteAll => '全部寫入';

  @override
  String get kbEditDiscardAll => '全部捨棄';

  @override
  String kbEditConfirmAll(int count) {
    return '確認寫入 $count 處';
  }

  @override
  String optKbDocCount(int count) {
    return '$count 篇';
  }

  @override
  String get optKbSearchDocs => '搜尋文件…';

  @override
  String get optKbTreeEmpty => '這個知識庫裡還沒有文件';

  @override
  String get optKbTreeScanFailed => '無法讀取知識庫資料夾';

  @override
  String get optKbTreeNoMatch => '沒有符合的文件';

  @override
  String get optKbTreeChanged => '已改';

  @override
  String get optKbTreeAdded => '新增';

  @override
  String optKbTreePending(int count) {
    return '$count 處變更待確認';
  }

  @override
  String get kbWritePolicyTitle => '寫入權限';

  @override
  String get kbWriteAllow => '允許 agent 寫入知識庫';

  @override
  String get kbWriteConfirmEach => '寫入前逐條確認';

  @override
  String get kbWriteBackup => '覆蓋前保留 .bak 副本';

  @override
  String get kbWriteNoConfirmWarning => '關閉逐條確認後，agent 起草的內容會不經你過目直接寫進檔案。';
}
