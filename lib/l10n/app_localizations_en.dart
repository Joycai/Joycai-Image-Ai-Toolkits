// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Joycai Image AI Toolkits';

  @override
  String get workbench => 'Workbench';

  @override
  String get tasks => 'Tasks';

  @override
  String get prompts => 'Prompts';

  @override
  String get usage => 'Usage';

  @override
  String get fileBrowser => 'File Browser';

  @override
  String get downloader => 'Downloader';

  @override
  String get url => 'URL';

  @override
  String get prefix => 'Prefix';

  @override
  String get models => 'Models';

  @override
  String get settings => 'Settings';

  @override
  String get addFolder => 'Add Folder';

  @override
  String get directories => 'DIRECTORIES';

  @override
  String get noFolders => 'No folders added';

  @override
  String get clickAddFolder =>
      'Click \"Add Folder\" to start scanning for images.';

  @override
  String get sourceGallery => 'Source Gallery';

  @override
  String get sourceExplorer => 'Source Explorer';

  @override
  String get processResults => 'Process Results';

  @override
  String get noImagesFound => 'No images found';

  @override
  String get noResultsYet => 'No results yet';

  @override
  String get selectAll => 'Select All';

  @override
  String get clear => 'Clear';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get copyFilename => 'Copy Filename';

  @override
  String get openInFolder => 'Open in Folder';

  @override
  String copiedToClipboard(String text) {
    return 'Copied: $text';
  }

  @override
  String get modelSelection => 'Model Selection';

  @override
  String get selectAModel => 'Select a model';

  @override
  String get aspectRatio => 'Aspect Ratio';

  @override
  String get resolution => 'Resolution';

  @override
  String get prompt => 'Prompt';

  @override
  String get library => 'Library';

  @override
  String get refiner => 'Refiner';

  @override
  String get processPrompt => 'Process Prompt';

  @override
  String processImages(int count) {
    return 'Process $count Images';
  }

  @override
  String get promptHint => 'Enter prompt here...';

  @override
  String get taskSubmitted => 'Task submitted to queue';

  @override
  String runningCount(int count) {
    return '$count running';
  }

  @override
  String plannedCount(int count) {
    return '$count planned';
  }

  @override
  String get selectFromLibrary => 'Select from Library';

  @override
  String get close => 'Close';

  @override
  String get queueSettings => 'Queue Settings';

  @override
  String concurrencyLimit(int limit) {
    return 'Concurrency Limit: $limit';
  }

  @override
  String retryCount(int count) {
    return 'Retry Count: $count';
  }

  @override
  String get back => 'Back';

  @override
  String get next => 'Next';

  @override
  String get storageLocationDesc =>
      'Select where generated images will be saved.';

  @override
  String get addChannelOptional =>
      'Add your first AI provider channel (Optional).';

  @override
  String get configureModelOptional =>
      'Configure a model for your new channel (Optional).';

  @override
  String get importSettingsTitle => 'Import Settings?';

  @override
  String get importSettingsConfirm =>
      'This will replace all your current models, channels, and categories. \n\nNote: Standalone prompt library is NOT affected by this import. Use the Prompts screen for prompt data management.';

  @override
  String get importAndReplace => 'Import & Replace';

  @override
  String get importMode => 'Import Mode';

  @override
  String get importModeDesc =>
      'Choose how you want to import prompts:\n\nMerge: Add new items to your library.\nReplace: Delete current library and use imported data.';

  @override
  String get merge => 'Merge';

  @override
  String get replaceAll => 'Replace All';

  @override
  String get exit => 'Exit';

  @override
  String get applyOverwrite => 'Apply (Overwrite)';

  @override
  String get applyAppend => 'Apply (Append)';

  @override
  String get aiPromptRefiner => 'AI Prompt Refiner';

  @override
  String get refinerModel => 'Refiner Model';

  @override
  String get systemPrompt => 'System Prompt';

  @override
  String get currentPrompt => 'Current Prompt';

  @override
  String get refinedPrompt => 'Refined Prompt';

  @override
  String get refine => 'Refine';

  @override
  String get apply => 'Apply';

  @override
  String refineFailed(String error) {
    return 'Refine failed: $error';
  }

  @override
  String get noImagesSelected => 'No images selected';

  @override
  String get selectSourceDirectory => 'Select Source Directory';

  @override
  String get removeFolderTooltip => 'Remove folder';

  @override
  String get removeFolderConfirmTitle => 'Remove Folder?';

  @override
  String removeFolderConfirmMessage(String folderName) {
    return 'Are you sure you want to remove \"$folderName\" from the list?';
  }

  @override
  String get remove => 'Remove';

  @override
  String get appearance => 'Appearance';

  @override
  String get connectivity => 'Connectivity';

  @override
  String get application => 'Application';

  @override
  String get proxySettings => 'Proxy Settings';

  @override
  String get enableProxy => 'Enable Global Proxy';

  @override
  String get proxyUrl => 'Proxy URL (host:port)';

  @override
  String get proxyUsername => 'Proxy Username (Optional)';

  @override
  String get proxyPassword => 'Proxy Password (Optional)';

  @override
  String get language => 'Language';

  @override
  String get themeAuto => 'Auto';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get googleGenAiSettings => 'Google GenAI REST Settings';

  @override
  String get openAiApiSettings => 'OpenAI API REST Settings';

  @override
  String get freeModel => 'Free Model';

  @override
  String get paidModel => 'Paid Model';

  @override
  String get standardConfig => 'Standard Config';

  @override
  String get endpointUrl => 'Endpoint URL';

  @override
  String get apiKey => 'API Key';

  @override
  String get outputDirectory => 'Output Directory';

  @override
  String get notSet => 'Not set';

  @override
  String get dataManagement => 'Data Management';

  @override
  String get exportSettings => 'Export Settings';

  @override
  String get importSettings => 'Import Settings';

  @override
  String get openAppDataDirectory => 'Open App Data Directory';

  @override
  String get mcpServerSettings => 'MCP Server Settings';

  @override
  String get enableMcpServer => 'Enable MCP Server';

  @override
  String get port => 'Port';

  @override
  String get resetAllSettings => 'Reset All Settings';

  @override
  String get confirmReset => 'Reset All Settings?';

  @override
  String get resetWarning =>
      'This will delete all configurations, models, and added folders. This action cannot be undone.';

  @override
  String get cancel => 'Cancel';

  @override
  String get resetEverything => 'Reset Everything';

  @override
  String get settingsExported => 'Settings exported successfully';

  @override
  String get settingsImported => 'Settings imported successfully';

  @override
  String get taskQueueManager => 'Task Queue Manager';

  @override
  String get refresh => 'Refresh';

  @override
  String get noTasksInQueue => 'No tasks in queue';

  @override
  String get submitTaskFromWorkbench =>
      'Submit a task from the Workbench to see it here.';

  @override
  String taskId(String id) {
    return 'Task ID: $id';
  }

  @override
  String get taskSummary => 'Task Summary';

  @override
  String get pendingTasks => 'Pending';

  @override
  String get processingTasks => 'Processing';

  @override
  String get completedTasks => 'Completed';

  @override
  String get failedTasks => 'Failed';

  @override
  String get clearCompleted => 'Clear Completed';

  @override
  String get clearAll => 'Clear All';

  @override
  String get cancelAllPending => 'Cancel All Pending';

  @override
  String get cancelTask => 'Cancel Task';

  @override
  String get removeFromList => 'Remove from list';

  @override
  String get model => 'Model';

  @override
  String get images => 'Images';

  @override
  String filesCount(int count) {
    return '$count files';
  }

  @override
  String get started => 'Started';

  @override
  String get finished => 'Finished';

  @override
  String get config => 'Config';

  @override
  String get latestLog => 'Latest Log:';

  @override
  String get promptLibrary => 'Prompt Library';

  @override
  String get newPrompt => 'New Prompt';

  @override
  String get editPrompt => 'Edit Prompt';

  @override
  String get noPromptsSaved => 'No prompts saved';

  @override
  String get saveFavoritePrompts =>
      'Save your favorite prompts or Refiner system prompts here';

  @override
  String get createFirstPrompt => 'Create First Prompt';

  @override
  String get deletePromptConfirmTitle => 'Delete Prompt?';

  @override
  String deletePromptConfirmMessage(String title) {
    return 'Are you sure you want to delete \"$title\"?';
  }

  @override
  String get delete => 'Delete';

  @override
  String get deleteModel => 'Delete Model';

  @override
  String get title => 'Title';

  @override
  String get tagCategory => 'Tag (Category)';

  @override
  String get setAsRefiner => 'Set as Refiner';

  @override
  String get promptContent => 'Prompt Content';

  @override
  String get save => 'Save';

  @override
  String get update => 'Update';

  @override
  String get tokenUsageMetrics => 'Token Usage Metrics';

  @override
  String get clearAllUsage => 'Clear All Usage Data?';

  @override
  String get clearUsageWarning =>
      'This will permanently delete all token usage records from the database.';

  @override
  String get modelsLabel => 'Models: ';

  @override
  String get rangeLabel => 'Range: ';

  @override
  String get today => 'Today';

  @override
  String get lastWeek => 'Last Week';

  @override
  String get lastMonth => 'Last Month';

  @override
  String get thisYear => 'This Year';

  @override
  String get inputTokens => 'Input Tokens';

  @override
  String get outputTokens => 'Output Tokens';

  @override
  String get estimatedCost => 'Estimated Cost';

  @override
  String clearDataForModel(String modelId) {
    return 'Clear Data for $modelId?';
  }

  @override
  String clearModelDataWarning(String modelId) {
    return 'This will delete all usage records associated with the model \"$modelId\".';
  }

  @override
  String get clearModelData => 'Clear Model Data';

  @override
  String get modelManagement => 'Model Management';

  @override
  String get feeManagement => 'Fee Management';

  @override
  String get modelsTab => 'Models';

  @override
  String get channelsTab => 'Channels';

  @override
  String get categoriesTab => 'Categories';

  @override
  String get addCategory => 'Add Category';

  @override
  String get editCategory => 'Edit Category';

  @override
  String get addChannel => 'Add Channel';

  @override
  String get editChannel => 'Edit Channel';

  @override
  String get channelType => 'Channel Type';

  @override
  String get enableDiscovery => 'Enable Model Discovery';

  @override
  String get filterModels => 'Filter models...';

  @override
  String get filterPrompts => 'Filter prompts...';

  @override
  String get tagColor => 'Tag Color';

  @override
  String deleteChannelConfirm(String name) {
    return 'Are you sure you want to delete channel \"$name\"? This will unlink all associated models.';
  }

  @override
  String get modelManager => 'Model Manager';

  @override
  String get name => 'Name';

  @override
  String get addModel => 'Add Model';

  @override
  String get editModel => 'Edit Model';

  @override
  String get noModelsConfigured => 'No models configured';

  @override
  String get addFirstModel => 'Add your first LLM model to get started';

  @override
  String get addNewModel => 'Add New Model';

  @override
  String get deleteModelConfirmTitle => 'Delete Model?';

  @override
  String deleteModelConfirmMessage(String name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get addLlmModel => 'Add LLM Model';

  @override
  String get editLlmModel => 'Edit LLM Model';

  @override
  String get modelIdLabel => 'Model ID (e.g. gemini-pro)';

  @override
  String get displayName => 'Display Name';

  @override
  String get type => 'Type';

  @override
  String get tag => 'Tag';

  @override
  String get inputFeeLabel => 'Input Fee (\$/M Tokens)';

  @override
  String get outputFeeLabel => 'Output Fee (\$/M Tokens)';

  @override
  String get billingMode => 'Billing Mode';

  @override
  String get perToken => 'Per Million Tokens';

  @override
  String get perRequest => 'Per Request';

  @override
  String get requestFeeLabel => 'Request Fee (\$/Request)';

  @override
  String get requestCount => 'Request Count';

  @override
  String get requests => 'Requests';

  @override
  String get add => 'Add';

  @override
  String get executionLogs => 'EXECUTION LOGS';

  @override
  String get clickToExpand => 'Click to expand';

  @override
  String get rename => 'Rename';

  @override
  String get renameFile => 'Rename File';

  @override
  String get newFilename => 'New Filename';

  @override
  String get renameSuccess => 'Renamed successfully';

  @override
  String renameFailed(String error) {
    return 'Failed to rename: $error';
  }

  @override
  String get fileAlreadyExists => 'A file with this name already exists';

  @override
  String get thumbnailSize => 'Thumbnail Size';

  @override
  String get deleteFile => 'Delete File';

  @override
  String get deleteFileConfirmTitle => 'Delete File?';

  @override
  String deleteFileConfirmMessage(String filename) {
    return 'Are you sure you want to delete \"$filename\"?';
  }

  @override
  String get moveToTrash => 'Move to Trash';

  @override
  String get permanentlyDelete => 'Permanently Delete';

  @override
  String get aiBatchRename => 'AI Batch Rename';

  @override
  String get switchViewMode => 'Switch View Mode';

  @override
  String get noFilesFound => 'No files found';

  @override
  String get rulesInstructions => 'Renaming Rules / Instructions';

  @override
  String get generateSuggestions => 'Generate Suggestions';

  @override
  String get noSuggestions => 'No suggestions generated yet';

  @override
  String get applyRenames => 'Apply Renames';

  @override
  String get originalName => 'Original Name';

  @override
  String get newName => 'New Name';

  @override
  String get status => 'Status';

  @override
  String get sortBy => 'Sort by';

  @override
  String get sortName => 'Name';

  @override
  String get sortDate => 'Modify Date';

  @override
  String get sortType => 'File Type';

  @override
  String get sortAsc => 'ASC';

  @override
  String get sortDesc => 'DESC';

  @override
  String get catAll => 'All';

  @override
  String get catImages => 'Images';

  @override
  String get catVideos => 'Videos';

  @override
  String get catAudio => 'Audio';

  @override
  String get catText => 'Text';

  @override
  String get catOthers => 'Others';

  @override
  String get deleteSuccess => 'Deleted successfully';

  @override
  String deleteFailed(String error) {
    return 'Failed to delete: $error';
  }

  @override
  String get userPrompts => 'User Prompts';

  @override
  String get refinerPrompts => 'Refiner Prompts';

  @override
  String get systemTemplates => 'System Templates';

  @override
  String get templateType => 'Template Type';

  @override
  String get typeRename => 'Batch Rename';

  @override
  String get typeRefiner => 'Prompt Refiner';

  @override
  String get selectRenameTemplate => 'Select Rename Template';

  @override
  String get selectCategory => 'Select Category';

  @override
  String get feeGroups => 'Fee Groups';

  @override
  String get feeGroup => 'Fee Group';

  @override
  String get channels => 'Channels';

  @override
  String get channel => 'Channel';

  @override
  String get noFeeGroup => 'No Fee Group';

  @override
  String get inputPrice => 'Input Price (\$/M Tokens)';

  @override
  String get outputPrice => 'Output Price (\$/M Tokens)';

  @override
  String get requestPrice => 'Request Price (\$/Req)';

  @override
  String get priceConfig => 'Price Config';

  @override
  String get portableMode => 'Portable Mode';

  @override
  String get portableModeDesc =>
      'Store database and cache in the application folder (requires restart)';

  @override
  String get restartRequired => 'Restart Required';

  @override
  String get restartMessage =>
      'The application must be restarted to apply changes to the data storage location.';

  @override
  String get usageByGroup => 'Usage by Group';

  @override
  String get addFeeGroup => 'Add Fee Group';

  @override
  String get editFeeGroup => 'Edit Fee Group';

  @override
  String deleteFeeGroupConfirm(String name) {
    return 'Delete Fee Group \"$name\"?';
  }

  @override
  String get groupName => 'Group Name';

  @override
  String get googleGenAiFree => 'Google GenAI (Free)';

  @override
  String get googleGenAiPaid => 'Google GenAI (Paid)';

  @override
  String get openaiApi => 'OpenAI API';

  @override
  String get filenamePrefix => 'Filename Prefix';

  @override
  String get setupWizardTitle => 'Welcome Setup';

  @override
  String get welcomeMessage =>
      'Welcome to Joycai Image AI Toolkits! Let\'s get you set up.';

  @override
  String get getStarted => 'Get Started';

  @override
  String get stepAppearance => 'Appearance';

  @override
  String get stepStorage => 'Storage';

  @override
  String get stepApi => 'Intelligence (API)';

  @override
  String get finish => 'Finish';

  @override
  String get setupCompleteMessage => 'You are all set! Enjoy creating.';

  @override
  String get runSetupWizard => 'Run Setup Wizard';

  @override
  String get clearDownloaderCache => 'Clear Downloader Cache';

  @override
  String get skip => 'Skip';

  @override
  String get fetchModels => 'Fetch Models';

  @override
  String get discoveringModels => 'Discovering Models...';

  @override
  String get selectModelsToAdd => 'Select models to add';

  @override
  String addSelected(Object count) {
    return 'Add Selected ($count)';
  }

  @override
  String get alreadyAdded => 'Already Added';

  @override
  String get noNewModelsFound => 'No new models found.';

  @override
  String fetchFailed(Object error) {
    return 'Failed to fetch models: $error';
  }

  @override
  String get edit => 'Edit';

  @override
  String get preview => 'Preview';

  @override
  String get openRawImage => 'Open Raw Image';

  @override
  String get pasteFromClipboard => 'Paste from Clipboard';

  @override
  String get saveOriginHtml => 'Save Origin HTML';

  @override
  String htmlSavedTo(String path) {
    return 'HTML saved to: $path';
  }

  @override
  String get manualHtmlMode => 'Manual HTML Mode';

  @override
  String get manualHtmlHint =>
      'Paste rendered HTML here (F12 -> Copy Outer HTML)';

  @override
  String get cookieHistory => 'Cookie History';

  @override
  String get noCookieHistory => 'No cookie history saved';

  @override
  String get openInPreview => 'Open in Preview';

  @override
  String get comparator => 'Comparator';

  @override
  String get openWithSystemDefault => 'Open with System Default';

  @override
  String get drawMask => 'Draw Mask';

  @override
  String get maskEditor => 'Mask Editor';

  @override
  String get brushSize => 'Brush Size';

  @override
  String get maskColor => 'Mask Color';

  @override
  String get undo => 'Undo';

  @override
  String get saveAndSelect => 'Save & Select';

  @override
  String get black => 'Black';

  @override
  String get white => 'White';

  @override
  String get red => 'Red';

  @override
  String get green => 'Green';

  @override
  String get sendToSelection => 'Send to Selection';

  @override
  String get sendToComparator => 'Send to Comparator';

  @override
  String get sendToComparatorRaw => 'Send to Comparator (Raw)';

  @override
  String get sendToComparatorAfter => 'Send to Comparator (After)';

  @override
  String get compareModeSync => 'Sync Mode';

  @override
  String get compareModeSwap => 'Swap Mode';

  @override
  String get tempWorkspace => 'Temp Workspace';

  @override
  String get clearTempWorkspace => 'Clear Workspace';

  @override
  String get dropFilesHere =>
      'Drop images here to add them to temporary workspace';

  @override
  String get enableNotifications => 'Enable System Notifications';

  @override
  String get taskCompletedNotification => 'Task Completed';

  @override
  String get taskFailedNotification => 'Task Failed';

  @override
  String taskCompletedBody(String id) {
    return 'Task $id has finished successfully.';
  }

  @override
  String taskFailedBody(String id) {
    return 'Task $id has failed.';
  }

  @override
  String get imageDownloader => 'Image Downloader';

  @override
  String get websiteUrl => 'Website URL';

  @override
  String get websiteUrlHint => 'https://example.com';

  @override
  String get whatToFind => 'What to find?';

  @override
  String get whatToFindHint => 'e.g. all product gallery images';

  @override
  String get analysisModel => 'Analysis Model';

  @override
  String get advancedOptions => 'Advanced Options';

  @override
  String get analyzing => 'Analyzing...';

  @override
  String get findImages => 'Find Images';

  @override
  String get noImagesDiscovered => 'No images discovered yet.';

  @override
  String get enterUrlToStart => 'Enter a URL and requirement to start.';

  @override
  String get addToQueue => 'Add to Queue';

  @override
  String imagesSelected(int count) {
    return '$count selected';
  }

  @override
  String addedToQueue(int count) {
    return 'Added $count images to download queue.';
  }

  @override
  String get setOutputDirFirst =>
      'Please set output directory in settings first.';

  @override
  String get cookiesHint => 'Cookies (Raw or Netscape format)';

  @override
  String get logs => 'Logs';

  @override
  String get selectImagesToDownload => 'Select images to download';

  @override
  String get openaiEndpointHint =>
      'Hint: OpenAI compatible endpoints usually end with \'/v1\'';

  @override
  String get googleEndpointHint =>
      'Hint: Google GenAI endpoints usually end with \'/v1beta\' (internal handling)';

  @override
  String get importCookieFile => 'Import Cookie File';

  @override
  String get cookieFileInvalid =>
      'Unsupported cookie file format. Please use Netscape format or raw text.';

  @override
  String cookieImportSuccess(Object count) {
    return 'Successfully imported $count cookies.';
  }

  @override
  String get share => 'Share';

  @override
  String shareFiles(int count) {
    return 'Share selected items ($count)';
  }

  @override
  String get importFromGallery => 'Import from Gallery';

  @override
  String get enableApiDebug => 'Enable API Debug Logging';

  @override
  String get apiDebugDesc =>
      'Logs raw API requests and responses to files for troubleshooting. Warning: Sensitive data like API Keys might be logged if not masked.';

  @override
  String get openLogFolder => 'Open Log Folder';
}
