import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Joycai Image AI Toolkits'**
  String get appTitle;

  /// No description provided for @workbench.
  ///
  /// In en, this message translates to:
  /// **'Workbench'**
  String get workbench;

  /// No description provided for @tasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasks;

  /// No description provided for @prompts.
  ///
  /// In en, this message translates to:
  /// **'Prompts'**
  String get prompts;

  /// No description provided for @usage.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get usage;

  /// No description provided for @downloader.
  ///
  /// In en, this message translates to:
  /// **'Downloader'**
  String get downloader;

  /// No description provided for @url.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get url;

  /// No description provided for @prefix.
  ///
  /// In en, this message translates to:
  /// **'Prefix'**
  String get prefix;

  /// No description provided for @models.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get models;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @addFolder.
  ///
  /// In en, this message translates to:
  /// **'Add Folder'**
  String get addFolder;

  /// No description provided for @directories.
  ///
  /// In en, this message translates to:
  /// **'DIRECTORIES'**
  String get directories;

  /// No description provided for @noFolders.
  ///
  /// In en, this message translates to:
  /// **'No folders added'**
  String get noFolders;

  /// No description provided for @clickAddFolder.
  ///
  /// In en, this message translates to:
  /// **'Click \"Add Folder\" to start scanning for images.'**
  String get clickAddFolder;

  /// No description provided for @sourceGallery.
  ///
  /// In en, this message translates to:
  /// **'Source Gallery'**
  String get sourceGallery;

  /// No description provided for @processResults.
  ///
  /// In en, this message translates to:
  /// **'Process Results'**
  String get processResults;

  /// No description provided for @noImagesFound.
  ///
  /// In en, this message translates to:
  /// **'No images found'**
  String get noImagesFound;

  /// No description provided for @noResultsYet.
  ///
  /// In en, this message translates to:
  /// **'No results yet'**
  String get noResultsYet;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @copyFilename.
  ///
  /// In en, this message translates to:
  /// **'Copy Filename'**
  String get copyFilename;

  /// No description provided for @openInFolder.
  ///
  /// In en, this message translates to:
  /// **'Open in Folder'**
  String get openInFolder;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied: {text}'**
  String copiedToClipboard(String text);

  /// No description provided for @modelSelection.
  ///
  /// In en, this message translates to:
  /// **'Model Selection'**
  String get modelSelection;

  /// No description provided for @selectAModel.
  ///
  /// In en, this message translates to:
  /// **'Select a model'**
  String get selectAModel;

  /// No description provided for @aspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Aspect Ratio'**
  String get aspectRatio;

  /// No description provided for @resolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get resolution;

  /// No description provided for @prompt.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get prompt;

  /// No description provided for @library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// No description provided for @refiner.
  ///
  /// In en, this message translates to:
  /// **'Refiner'**
  String get refiner;

  /// No description provided for @processPrompt.
  ///
  /// In en, this message translates to:
  /// **'Process Prompt'**
  String get processPrompt;

  /// No description provided for @processImages.
  ///
  /// In en, this message translates to:
  /// **'Process {count} Images'**
  String processImages(int count);

  /// No description provided for @promptHint.
  ///
  /// In en, this message translates to:
  /// **'Enter prompt here...'**
  String get promptHint;

  /// No description provided for @taskSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Task submitted to queue'**
  String get taskSubmitted;

  /// No description provided for @runningCount.
  ///
  /// In en, this message translates to:
  /// **'{count} running'**
  String runningCount(int count);

  /// No description provided for @plannedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} planned'**
  String plannedCount(int count);

  /// No description provided for @selectFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Select from Library'**
  String get selectFromLibrary;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @queueSettings.
  ///
  /// In en, this message translates to:
  /// **'Queue Settings'**
  String get queueSettings;

  /// No description provided for @concurrencyLimit.
  ///
  /// In en, this message translates to:
  /// **'Concurrency Limit: {limit}'**
  String concurrencyLimit(int limit);

  /// No description provided for @aiPromptRefiner.
  ///
  /// In en, this message translates to:
  /// **'AI Prompt Refiner'**
  String get aiPromptRefiner;

  /// No description provided for @refinerModel.
  ///
  /// In en, this message translates to:
  /// **'Refiner Model'**
  String get refinerModel;

  /// No description provided for @systemPrompt.
  ///
  /// In en, this message translates to:
  /// **'System Prompt'**
  String get systemPrompt;

  /// No description provided for @currentPrompt.
  ///
  /// In en, this message translates to:
  /// **'Current Prompt'**
  String get currentPrompt;

  /// No description provided for @refinedPrompt.
  ///
  /// In en, this message translates to:
  /// **'Refined Prompt'**
  String get refinedPrompt;

  /// No description provided for @refine.
  ///
  /// In en, this message translates to:
  /// **'Refine'**
  String get refine;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @refineFailed.
  ///
  /// In en, this message translates to:
  /// **'Refine failed: {error}'**
  String refineFailed(String error);

  /// No description provided for @noImagesSelected.
  ///
  /// In en, this message translates to:
  /// **'No images selected'**
  String get noImagesSelected;

  /// No description provided for @selectSourceDirectory.
  ///
  /// In en, this message translates to:
  /// **'Select Source Directory'**
  String get selectSourceDirectory;

  /// No description provided for @removeFolderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove folder'**
  String get removeFolderTooltip;

  /// No description provided for @removeFolderConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove Folder?'**
  String get removeFolderConfirmTitle;

  /// No description provided for @removeFolderConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove \"{folderName}\" from the list?'**
  String removeFolderConfirmMessage(String folderName);

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @proxySettings.
  ///
  /// In en, this message translates to:
  /// **'Proxy Settings'**
  String get proxySettings;

  /// No description provided for @enableProxy.
  ///
  /// In en, this message translates to:
  /// **'Enable Global Proxy'**
  String get enableProxy;

  /// No description provided for @proxyUrl.
  ///
  /// In en, this message translates to:
  /// **'Proxy URL (host:port)'**
  String get proxyUrl;

  /// No description provided for @proxyUsername.
  ///
  /// In en, this message translates to:
  /// **'Proxy Username (Optional)'**
  String get proxyUsername;

  /// No description provided for @proxyPassword.
  ///
  /// In en, this message translates to:
  /// **'Proxy Password (Optional)'**
  String get proxyPassword;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @themeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get themeAuto;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @googleGenAiSettings.
  ///
  /// In en, this message translates to:
  /// **'Google GenAI REST Settings'**
  String get googleGenAiSettings;

  /// No description provided for @openAiApiSettings.
  ///
  /// In en, this message translates to:
  /// **'OpenAI API REST Settings'**
  String get openAiApiSettings;

  /// No description provided for @freeModel.
  ///
  /// In en, this message translates to:
  /// **'Free Model'**
  String get freeModel;

  /// No description provided for @paidModel.
  ///
  /// In en, this message translates to:
  /// **'Paid Model'**
  String get paidModel;

  /// No description provided for @standardConfig.
  ///
  /// In en, this message translates to:
  /// **'Standard Config'**
  String get standardConfig;

  /// No description provided for @endpointUrl.
  ///
  /// In en, this message translates to:
  /// **'Endpoint URL'**
  String get endpointUrl;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiKey;

  /// No description provided for @outputDirectory.
  ///
  /// In en, this message translates to:
  /// **'Output Directory'**
  String get outputDirectory;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @dataManagement.
  ///
  /// In en, this message translates to:
  /// **'Data Management'**
  String get dataManagement;

  /// No description provided for @exportSettings.
  ///
  /// In en, this message translates to:
  /// **'Export Settings'**
  String get exportSettings;

  /// No description provided for @importSettings.
  ///
  /// In en, this message translates to:
  /// **'Import Settings'**
  String get importSettings;

  /// No description provided for @openAppDataDirectory.
  ///
  /// In en, this message translates to:
  /// **'Open App Data Directory'**
  String get openAppDataDirectory;

  /// No description provided for @mcpServerSettings.
  ///
  /// In en, this message translates to:
  /// **'MCP Server Settings'**
  String get mcpServerSettings;

  /// No description provided for @enableMcpServer.
  ///
  /// In en, this message translates to:
  /// **'Enable MCP Server'**
  String get enableMcpServer;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @resetAllSettings.
  ///
  /// In en, this message translates to:
  /// **'Reset All Settings'**
  String get resetAllSettings;

  /// No description provided for @confirmReset.
  ///
  /// In en, this message translates to:
  /// **'Reset All Settings?'**
  String get confirmReset;

  /// No description provided for @resetWarning.
  ///
  /// In en, this message translates to:
  /// **'This will delete all configurations, models, and added folders. This action cannot be undone.'**
  String get resetWarning;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @resetEverything.
  ///
  /// In en, this message translates to:
  /// **'Reset Everything'**
  String get resetEverything;

  /// No description provided for @settingsExported.
  ///
  /// In en, this message translates to:
  /// **'Settings exported successfully'**
  String get settingsExported;

  /// No description provided for @settingsImported.
  ///
  /// In en, this message translates to:
  /// **'Settings imported successfully'**
  String get settingsImported;

  /// No description provided for @taskQueueManager.
  ///
  /// In en, this message translates to:
  /// **'Task Queue Manager'**
  String get taskQueueManager;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @noTasksInQueue.
  ///
  /// In en, this message translates to:
  /// **'No tasks in queue'**
  String get noTasksInQueue;

  /// No description provided for @submitTaskFromWorkbench.
  ///
  /// In en, this message translates to:
  /// **'Submit a task from the Workbench to see it here.'**
  String get submitTaskFromWorkbench;

  /// No description provided for @taskId.
  ///
  /// In en, this message translates to:
  /// **'Task ID: {id}'**
  String taskId(String id);

  /// No description provided for @cancelTask.
  ///
  /// In en, this message translates to:
  /// **'Cancel Task'**
  String get cancelTask;

  /// No description provided for @removeFromList.
  ///
  /// In en, this message translates to:
  /// **'Remove from list'**
  String get removeFromList;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @images.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get images;

  /// No description provided for @filesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} files'**
  String filesCount(int count);

  /// No description provided for @started.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get started;

  /// No description provided for @finished.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get finished;

  /// No description provided for @config.
  ///
  /// In en, this message translates to:
  /// **'Config'**
  String get config;

  /// No description provided for @latestLog.
  ///
  /// In en, this message translates to:
  /// **'Latest Log:'**
  String get latestLog;

  /// No description provided for @promptLibrary.
  ///
  /// In en, this message translates to:
  /// **'Prompt Library'**
  String get promptLibrary;

  /// No description provided for @newPrompt.
  ///
  /// In en, this message translates to:
  /// **'New Prompt'**
  String get newPrompt;

  /// No description provided for @editPrompt.
  ///
  /// In en, this message translates to:
  /// **'Edit Prompt'**
  String get editPrompt;

  /// No description provided for @noPromptsSaved.
  ///
  /// In en, this message translates to:
  /// **'No prompts saved'**
  String get noPromptsSaved;

  /// No description provided for @saveFavoritePrompts.
  ///
  /// In en, this message translates to:
  /// **'Save your favorite prompts or Refiner system prompts here'**
  String get saveFavoritePrompts;

  /// No description provided for @createFirstPrompt.
  ///
  /// In en, this message translates to:
  /// **'Create First Prompt'**
  String get createFirstPrompt;

  /// No description provided for @deletePromptConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Prompt?'**
  String get deletePromptConfirmTitle;

  /// No description provided for @deletePromptConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{title}\"?'**
  String deletePromptConfirmMessage(String title);

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteModel.
  ///
  /// In en, this message translates to:
  /// **'Delete Model'**
  String get deleteModel;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @tagCategory.
  ///
  /// In en, this message translates to:
  /// **'Tag (Category)'**
  String get tagCategory;

  /// No description provided for @setAsRefiner.
  ///
  /// In en, this message translates to:
  /// **'Set as Refiner'**
  String get setAsRefiner;

  /// No description provided for @promptContent.
  ///
  /// In en, this message translates to:
  /// **'Prompt Content'**
  String get promptContent;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @tokenUsageMetrics.
  ///
  /// In en, this message translates to:
  /// **'Token Usage Metrics'**
  String get tokenUsageMetrics;

  /// No description provided for @clearAllUsage.
  ///
  /// In en, this message translates to:
  /// **'Clear All Usage Data?'**
  String get clearAllUsage;

  /// No description provided for @clearUsageWarning.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete all token usage records from the database.'**
  String get clearUsageWarning;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get clearAll;

  /// No description provided for @modelsLabel.
  ///
  /// In en, this message translates to:
  /// **'Models: '**
  String get modelsLabel;

  /// No description provided for @rangeLabel.
  ///
  /// In en, this message translates to:
  /// **'Range: '**
  String get rangeLabel;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @lastWeek.
  ///
  /// In en, this message translates to:
  /// **'Last Week'**
  String get lastWeek;

  /// No description provided for @lastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last Month'**
  String get lastMonth;

  /// No description provided for @thisYear.
  ///
  /// In en, this message translates to:
  /// **'This Year'**
  String get thisYear;

  /// No description provided for @inputTokens.
  ///
  /// In en, this message translates to:
  /// **'Input Tokens'**
  String get inputTokens;

  /// No description provided for @outputTokens.
  ///
  /// In en, this message translates to:
  /// **'Output Tokens'**
  String get outputTokens;

  /// No description provided for @estimatedCost.
  ///
  /// In en, this message translates to:
  /// **'Estimated Cost'**
  String get estimatedCost;

  /// No description provided for @clearDataForModel.
  ///
  /// In en, this message translates to:
  /// **'Clear Data for {modelId}?'**
  String clearDataForModel(String modelId);

  /// No description provided for @clearModelDataWarning.
  ///
  /// In en, this message translates to:
  /// **'This will delete all usage records associated with the model \"{modelId}\".'**
  String clearModelDataWarning(String modelId);

  /// No description provided for @clearModelData.
  ///
  /// In en, this message translates to:
  /// **'Clear Model Data'**
  String get clearModelData;

  /// No description provided for @modelManagement.
  ///
  /// In en, this message translates to:
  /// **'Model Management'**
  String get modelManagement;

  /// No description provided for @feeManagement.
  ///
  /// In en, this message translates to:
  /// **'Fee Management'**
  String get feeManagement;

  /// No description provided for @modelsTab.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get modelsTab;

  /// No description provided for @channelsTab.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get channelsTab;

  /// No description provided for @categoriesTab.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categoriesTab;

  /// No description provided for @addCategory.
  ///
  /// In en, this message translates to:
  /// **'Add Category'**
  String get addCategory;

  /// No description provided for @editCategory.
  ///
  /// In en, this message translates to:
  /// **'Edit Category'**
  String get editCategory;

  /// No description provided for @addChannel.
  ///
  /// In en, this message translates to:
  /// **'Add Channel'**
  String get addChannel;

  /// No description provided for @editChannel.
  ///
  /// In en, this message translates to:
  /// **'Edit Channel'**
  String get editChannel;

  /// No description provided for @channelType.
  ///
  /// In en, this message translates to:
  /// **'Channel Type'**
  String get channelType;

  /// No description provided for @enableDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Enable Model Discovery'**
  String get enableDiscovery;

  /// No description provided for @filterModels.
  ///
  /// In en, this message translates to:
  /// **'Filter models...'**
  String get filterModels;

  /// No description provided for @filterPrompts.
  ///
  /// In en, this message translates to:
  /// **'Filter prompts...'**
  String get filterPrompts;

  /// No description provided for @tagColor.
  ///
  /// In en, this message translates to:
  /// **'Tag Color'**
  String get tagColor;

  /// No description provided for @deleteChannelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete channel \"{name}\"? This will unlink all associated models.'**
  String deleteChannelConfirm(String name);

  /// No description provided for @modelManager.
  ///
  /// In en, this message translates to:
  /// **'Model Manager'**
  String get modelManager;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @addModel.
  ///
  /// In en, this message translates to:
  /// **'Add Model'**
  String get addModel;

  /// No description provided for @editModel.
  ///
  /// In en, this message translates to:
  /// **'Edit Model'**
  String get editModel;

  /// No description provided for @noModelsConfigured.
  ///
  /// In en, this message translates to:
  /// **'No models configured'**
  String get noModelsConfigured;

  /// No description provided for @addFirstModel.
  ///
  /// In en, this message translates to:
  /// **'Add your first LLM model to get started'**
  String get addFirstModel;

  /// No description provided for @addNewModel.
  ///
  /// In en, this message translates to:
  /// **'Add New Model'**
  String get addNewModel;

  /// No description provided for @deleteModelConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Model?'**
  String get deleteModelConfirmTitle;

  /// No description provided for @deleteModelConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String deleteModelConfirmMessage(String name);

  /// No description provided for @addLlmModel.
  ///
  /// In en, this message translates to:
  /// **'Add LLM Model'**
  String get addLlmModel;

  /// No description provided for @editLlmModel.
  ///
  /// In en, this message translates to:
  /// **'Edit LLM Model'**
  String get editLlmModel;

  /// No description provided for @modelIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Model ID (e.g. gemini-pro)'**
  String get modelIdLabel;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get displayName;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @tag.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get tag;

  /// No description provided for @inputFeeLabel.
  ///
  /// In en, this message translates to:
  /// **'Input Fee (\$/M Tokens)'**
  String get inputFeeLabel;

  /// No description provided for @outputFeeLabel.
  ///
  /// In en, this message translates to:
  /// **'Output Fee (\$/M Tokens)'**
  String get outputFeeLabel;

  /// No description provided for @billingMode.
  ///
  /// In en, this message translates to:
  /// **'Billing Mode'**
  String get billingMode;

  /// No description provided for @perToken.
  ///
  /// In en, this message translates to:
  /// **'Per Million Tokens'**
  String get perToken;

  /// No description provided for @perRequest.
  ///
  /// In en, this message translates to:
  /// **'Per Request'**
  String get perRequest;

  /// No description provided for @requestFeeLabel.
  ///
  /// In en, this message translates to:
  /// **'Request Fee (\$/Request)'**
  String get requestFeeLabel;

  /// No description provided for @requestCount.
  ///
  /// In en, this message translates to:
  /// **'Request Count'**
  String get requestCount;

  /// No description provided for @requests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get requests;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @executionLogs.
  ///
  /// In en, this message translates to:
  /// **'EXECUTION LOGS'**
  String get executionLogs;

  /// No description provided for @clickToExpand.
  ///
  /// In en, this message translates to:
  /// **'Click to expand'**
  String get clickToExpand;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @renameFile.
  ///
  /// In en, this message translates to:
  /// **'Rename File'**
  String get renameFile;

  /// No description provided for @newFilename.
  ///
  /// In en, this message translates to:
  /// **'New Filename'**
  String get newFilename;

  /// No description provided for @renameSuccess.
  ///
  /// In en, this message translates to:
  /// **'Renamed successfully'**
  String get renameSuccess;

  /// No description provided for @renameFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to rename: {error}'**
  String renameFailed(String error);

  /// No description provided for @fileAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'A file with this name already exists'**
  String get fileAlreadyExists;

  /// No description provided for @thumbnailSize.
  ///
  /// In en, this message translates to:
  /// **'Thumbnail Size'**
  String get thumbnailSize;

  /// No description provided for @deleteFile.
  ///
  /// In en, this message translates to:
  /// **'Delete File'**
  String get deleteFile;

  /// No description provided for @deleteFileConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete File?'**
  String get deleteFileConfirmTitle;

  /// No description provided for @deleteFileConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{filename}\"?'**
  String deleteFileConfirmMessage(String filename);

  /// No description provided for @moveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get moveToTrash;

  /// No description provided for @permanentlyDelete.
  ///
  /// In en, this message translates to:
  /// **'Permanently Delete'**
  String get permanentlyDelete;

  /// No description provided for @deleteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Deleted successfully'**
  String get deleteSuccess;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete: {error}'**
  String deleteFailed(String error);

  /// No description provided for @userPrompts.
  ///
  /// In en, this message translates to:
  /// **'User Prompts'**
  String get userPrompts;

  /// No description provided for @refinerPrompts.
  ///
  /// In en, this message translates to:
  /// **'Refiner Prompts'**
  String get refinerPrompts;

  /// No description provided for @selectCategory.
  ///
  /// In en, this message translates to:
  /// **'Select Category'**
  String get selectCategory;

  /// No description provided for @feeGroups.
  ///
  /// In en, this message translates to:
  /// **'Fee Groups'**
  String get feeGroups;

  /// No description provided for @feeGroup.
  ///
  /// In en, this message translates to:
  /// **'Fee Group'**
  String get feeGroup;

  /// No description provided for @channels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get channels;

  /// No description provided for @channel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get channel;

  /// No description provided for @noFeeGroup.
  ///
  /// In en, this message translates to:
  /// **'No Fee Group'**
  String get noFeeGroup;

  /// No description provided for @inputPrice.
  ///
  /// In en, this message translates to:
  /// **'Input Price (\$/M Tokens)'**
  String get inputPrice;

  /// No description provided for @outputPrice.
  ///
  /// In en, this message translates to:
  /// **'Output Price (\$/M Tokens)'**
  String get outputPrice;

  /// No description provided for @requestPrice.
  ///
  /// In en, this message translates to:
  /// **'Request Price (\$/Req)'**
  String get requestPrice;

  /// No description provided for @priceConfig.
  ///
  /// In en, this message translates to:
  /// **'Price Config'**
  String get priceConfig;

  /// No description provided for @portableMode.
  ///
  /// In en, this message translates to:
  /// **'Portable Mode'**
  String get portableMode;

  /// No description provided for @portableModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Store database and cache in the application folder (requires restart)'**
  String get portableModeDesc;

  /// No description provided for @restartRequired.
  ///
  /// In en, this message translates to:
  /// **'Restart Required'**
  String get restartRequired;

  /// No description provided for @restartMessage.
  ///
  /// In en, this message translates to:
  /// **'The application must be restarted to apply changes to the data storage location.'**
  String get restartMessage;

  /// No description provided for @usageByGroup.
  ///
  /// In en, this message translates to:
  /// **'Usage by Group'**
  String get usageByGroup;

  /// No description provided for @addFeeGroup.
  ///
  /// In en, this message translates to:
  /// **'Add Fee Group'**
  String get addFeeGroup;

  /// No description provided for @editFeeGroup.
  ///
  /// In en, this message translates to:
  /// **'Edit Fee Group'**
  String get editFeeGroup;

  /// No description provided for @deleteFeeGroupConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete Fee Group \"{name}\"?'**
  String deleteFeeGroupConfirm(String name);

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group Name'**
  String get groupName;

  /// No description provided for @googleGenAiFree.
  ///
  /// In en, this message translates to:
  /// **'Google GenAI (Free)'**
  String get googleGenAiFree;

  /// No description provided for @googleGenAiPaid.
  ///
  /// In en, this message translates to:
  /// **'Google GenAI (Paid)'**
  String get googleGenAiPaid;

  /// No description provided for @openaiApi.
  ///
  /// In en, this message translates to:
  /// **'OpenAI API'**
  String get openaiApi;

  /// No description provided for @filenamePrefix.
  ///
  /// In en, this message translates to:
  /// **'Filename Prefix'**
  String get filenamePrefix;

  /// No description provided for @setupWizardTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome Setup'**
  String get setupWizardTitle;

  /// No description provided for @welcomeMessage.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Joycai Image AI Toolkits! Let\'s get you set up.'**
  String get welcomeMessage;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// No description provided for @stepAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get stepAppearance;

  /// No description provided for @stepStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get stepStorage;

  /// No description provided for @stepApi.
  ///
  /// In en, this message translates to:
  /// **'Intelligence (API)'**
  String get stepApi;

  /// No description provided for @finish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get finish;

  /// No description provided for @setupCompleteMessage.
  ///
  /// In en, this message translates to:
  /// **'You are all set! Enjoy creating.'**
  String get setupCompleteMessage;

  /// No description provided for @runSetupWizard.
  ///
  /// In en, this message translates to:
  /// **'Run Setup Wizard'**
  String get runSetupWizard;

  /// No description provided for @clearDownloaderCache.
  ///
  /// In en, this message translates to:
  /// **'Clear Downloader Cache'**
  String get clearDownloaderCache;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @fetchModels.
  ///
  /// In en, this message translates to:
  /// **'Fetch Models'**
  String get fetchModels;

  /// No description provided for @discoveringModels.
  ///
  /// In en, this message translates to:
  /// **'Discovering Models...'**
  String get discoveringModels;

  /// No description provided for @selectModelsToAdd.
  ///
  /// In en, this message translates to:
  /// **'Select models to add'**
  String get selectModelsToAdd;

  /// No description provided for @addSelected.
  ///
  /// In en, this message translates to:
  /// **'Add Selected ({count})'**
  String addSelected(Object count);

  /// No description provided for @alreadyAdded.
  ///
  /// In en, this message translates to:
  /// **'Already Added'**
  String get alreadyAdded;

  /// No description provided for @noNewModelsFound.
  ///
  /// In en, this message translates to:
  /// **'No new models found.'**
  String get noNewModelsFound;

  /// No description provided for @fetchFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch models: {error}'**
  String fetchFailed(Object error);

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @openRawImage.
  ///
  /// In en, this message translates to:
  /// **'Open Raw Image'**
  String get openRawImage;

  /// No description provided for @pasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from Clipboard'**
  String get pasteFromClipboard;

  /// No description provided for @saveOriginHtml.
  ///
  /// In en, this message translates to:
  /// **'Save Origin HTML'**
  String get saveOriginHtml;

  /// No description provided for @htmlSavedTo.
  ///
  /// In en, this message translates to:
  /// **'HTML saved to: {path}'**
  String htmlSavedTo(String path);

  /// No description provided for @manualHtmlMode.
  ///
  /// In en, this message translates to:
  /// **'Manual HTML Mode'**
  String get manualHtmlMode;

  /// No description provided for @manualHtmlHint.
  ///
  /// In en, this message translates to:
  /// **'Paste rendered HTML here (F12 -> Copy Outer HTML)'**
  String get manualHtmlHint;

  /// No description provided for @cookieHistory.
  ///
  /// In en, this message translates to:
  /// **'Cookie History'**
  String get cookieHistory;

  /// No description provided for @noCookieHistory.
  ///
  /// In en, this message translates to:
  /// **'No cookie history saved'**
  String get noCookieHistory;

  /// No description provided for @openInPreview.
  ///
  /// In en, this message translates to:
  /// **'Open in Preview'**
  String get openInPreview;

  /// No description provided for @enableNotifications.
  ///
  /// In en, this message translates to:
  /// **'Enable System Notifications'**
  String get enableNotifications;

  /// No description provided for @taskCompletedNotification.
  ///
  /// In en, this message translates to:
  /// **'Task Completed'**
  String get taskCompletedNotification;

  /// No description provided for @taskFailedNotification.
  ///
  /// In en, this message translates to:
  /// **'Task Failed'**
  String get taskFailedNotification;

  /// No description provided for @taskCompletedBody.
  ///
  /// In en, this message translates to:
  /// **'Task {id} has finished successfully.'**
  String taskCompletedBody(String id);

  /// No description provided for @taskFailedBody.
  ///
  /// In en, this message translates to:
  /// **'Task {id} has failed.'**
  String taskFailedBody(String id);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
