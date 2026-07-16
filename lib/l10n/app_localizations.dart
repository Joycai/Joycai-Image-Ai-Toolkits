import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
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
    Locale('ja'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @fileBrowser.
  ///
  /// In en, this message translates to:
  /// **'File Browser'**
  String get fileBrowser;

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

  /// No description provided for @noFilesFound.
  ///
  /// In en, this message translates to:
  /// **'No files found'**
  String get noFilesFound;

  /// No description provided for @switchViewMode.
  ///
  /// In en, this message translates to:
  /// **'Switch View Mode'**
  String get switchViewMode;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortBy;

  /// No description provided for @sortName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sortName;

  /// No description provided for @sortDate.
  ///
  /// In en, this message translates to:
  /// **'Modify Date'**
  String get sortDate;

  /// No description provided for @sortType.
  ///
  /// In en, this message translates to:
  /// **'File Type'**
  String get sortType;

  /// No description provided for @sortAsc.
  ///
  /// In en, this message translates to:
  /// **'ASC'**
  String get sortAsc;

  /// No description provided for @sortDesc.
  ///
  /// In en, this message translates to:
  /// **'DESC'**
  String get sortDesc;

  /// No description provided for @catAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get catAll;

  /// No description provided for @catImages.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get catImages;

  /// No description provided for @catVideos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get catVideos;

  /// No description provided for @catAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get catAudio;

  /// No description provided for @catText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get catText;

  /// No description provided for @catOthers.
  ///
  /// In en, this message translates to:
  /// **'Others'**
  String get catOthers;

  /// No description provided for @openWithSystemDefault.
  ///
  /// In en, this message translates to:
  /// **'Open with System Default'**
  String get openWithSystemDefault;

  /// No description provided for @aiBatchRename.
  ///
  /// In en, this message translates to:
  /// **'AI Batch Rename'**
  String get aiBatchRename;

  /// No description provided for @rulesInstructions.
  ///
  /// In en, this message translates to:
  /// **'Renaming Rules / Instructions'**
  String get rulesInstructions;

  /// No description provided for @generateSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Generate Suggestions'**
  String get generateSuggestions;

  /// No description provided for @noSuggestions.
  ///
  /// In en, this message translates to:
  /// **'No suggestions generated yet'**
  String get noSuggestions;

  /// No description provided for @searchFilesHint.
  ///
  /// In en, this message translates to:
  /// **'Search files…'**
  String get searchFilesHint;

  /// No description provided for @deselectAllDirectories.
  ///
  /// In en, this message translates to:
  /// **'Deselect all directories'**
  String get deselectAllDirectories;

  /// No description provided for @applyRenames.
  ///
  /// In en, this message translates to:
  /// **'Apply Renames'**
  String get applyRenames;

  /// No description provided for @additionalInstructions.
  ///
  /// In en, this message translates to:
  /// **'Additional Instructions (Optional)'**
  String get additionalInstructions;

  /// No description provided for @aiRenameInstructionsHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Keep original extensions, convert to Pinyin...'**
  String get aiRenameInstructionsHint;

  /// No description provided for @noTemplateSelected.
  ///
  /// In en, this message translates to:
  /// **'No template selected'**
  String get noTemplateSelected;

  /// No description provided for @selectTemplateFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select a rename template first.'**
  String get selectTemplateFirst;

  /// No description provided for @generatingSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Generating suggestions…'**
  String get generatingSuggestions;

  /// No description provided for @renamePreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename Preview'**
  String get renamePreviewTitle;

  /// No description provided for @conflictsFound.
  ///
  /// In en, this message translates to:
  /// **'{count} conflict(s)'**
  String conflictsFound(int count);

  /// No description provided for @conflictDuplicateTarget.
  ///
  /// In en, this message translates to:
  /// **'Duplicate target name'**
  String get conflictDuplicateTarget;

  /// No description provided for @addToSelection.
  ///
  /// In en, this message translates to:
  /// **'Add to Selection'**
  String get addToSelection;

  /// No description provided for @removeFromSelection.
  ///
  /// In en, this message translates to:
  /// **'Remove from Selection'**
  String get removeFromSelection;

  /// No description provided for @imagesSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String imagesSelected(int count);

  /// No description provided for @featureLimitedOnMobile.
  ///
  /// In en, this message translates to:
  /// **'Feature Limited on Mobile'**
  String get featureLimitedOnMobile;

  /// No description provided for @fileBrowserDesktopOnlyDesc.
  ///
  /// In en, this message translates to:
  /// **'Due to OS sandboxing restrictions, the advanced file browser and mass renaming features are only available on Desktop versions.'**
  String get fileBrowserDesktopOnlyDesc;

  /// No description provided for @fileBrowseriOSHint.
  ///
  /// In en, this message translates to:
  /// **'Please use the system \'Files\' app to manage your generated images.'**
  String get fileBrowseriOSHint;

  /// No description provided for @fileBrowserAndroidHint.
  ///
  /// In en, this message translates to:
  /// **'Please use your device\'s file manager to organize files.'**
  String get fileBrowserAndroidHint;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Joycai Image AI Toolkits'**
  String get appTitle;

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

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @expandEditor.
  ///
  /// In en, this message translates to:
  /// **'Expand editor'**
  String get expandEditor;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @finish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get finish;

  /// No description provided for @exit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get exit;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

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

  /// No description provided for @logs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logs;

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

  /// No description provided for @openInPreview.
  ///
  /// In en, this message translates to:
  /// **'Open in Preview'**
  String get openInPreview;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied: {text}'**
  String copiedToClipboard(String text);

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @shareFiles.
  ///
  /// In en, this message translates to:
  /// **'Share selected items ({count})'**
  String shareFiles(int count);

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming Soon'**
  String get comingSoon;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get viewAll;

  /// No description provided for @noTasks.
  ///
  /// In en, this message translates to:
  /// **'No active tasks'**
  String get noTasks;

  /// No description provided for @sidebar.
  ///
  /// In en, this message translates to:
  /// **'Sidebar'**
  String get sidebar;

  /// No description provided for @white.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get white;

  /// No description provided for @black.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get black;

  /// No description provided for @red.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get red;

  /// No description provided for @green.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get green;

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

  /// No description provided for @metadata.
  ///
  /// In en, this message translates to:
  /// **'Metadata'**
  String get metadata;

  /// No description provided for @filterPrompts.
  ///
  /// In en, this message translates to:
  /// **'Filter prompts...'**
  String get filterPrompts;

  /// No description provided for @shareFailed.
  ///
  /// In en, this message translates to:
  /// **'Share failed: {error}'**
  String shareFailed(String error);

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @downloader.
  ///
  /// In en, this message translates to:
  /// **'Downloader'**
  String get downloader;

  /// No description provided for @imageDownloader.
  ///
  /// In en, this message translates to:
  /// **'Image Downloader'**
  String get imageDownloader;

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

  /// No description provided for @websiteUrl.
  ///
  /// In en, this message translates to:
  /// **'Website URL'**
  String get websiteUrl;

  /// No description provided for @websiteUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://example.com'**
  String get websiteUrlHint;

  /// No description provided for @whatToFind.
  ///
  /// In en, this message translates to:
  /// **'What to find?'**
  String get whatToFind;

  /// No description provided for @whatToFindHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. all product gallery images'**
  String get whatToFindHint;

  /// No description provided for @analysisModel.
  ///
  /// In en, this message translates to:
  /// **'Analysis Model'**
  String get analysisModel;

  /// No description provided for @advancedOptions.
  ///
  /// In en, this message translates to:
  /// **'Advanced Options'**
  String get advancedOptions;

  /// No description provided for @analyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing...'**
  String get analyzing;

  /// No description provided for @urlRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid Website URL.'**
  String get urlRequired;

  /// No description provided for @requirementRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter what images you want to find (Requirements).'**
  String get requirementRequired;

  /// No description provided for @manualHtmlRequired.
  ///
  /// In en, this message translates to:
  /// **'Please paste the HTML content in Manual Mode.'**
  String get manualHtmlRequired;

  /// No description provided for @findImages.
  ///
  /// In en, this message translates to:
  /// **'Find Images'**
  String get findImages;

  /// No description provided for @noImagesDiscovered.
  ///
  /// In en, this message translates to:
  /// **'No images discovered yet.'**
  String get noImagesDiscovered;

  /// No description provided for @enterUrlToStart.
  ///
  /// In en, this message translates to:
  /// **'Enter a URL and requirement to start.'**
  String get enterUrlToStart;

  /// No description provided for @addToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to Queue'**
  String get addToQueue;

  /// No description provided for @addedToQueue.
  ///
  /// In en, this message translates to:
  /// **'Added {count} images to download queue.'**
  String addedToQueue(int count);

  /// No description provided for @setOutputDirFirst.
  ///
  /// In en, this message translates to:
  /// **'Please set output directory in settings first.'**
  String get setOutputDirFirst;

  /// No description provided for @cookiesHint.
  ///
  /// In en, this message translates to:
  /// **'Cookies (Raw or Netscape format)'**
  String get cookiesHint;

  /// No description provided for @selectImagesToDownload.
  ///
  /// In en, this message translates to:
  /// **'Select images to download'**
  String get selectImagesToDownload;

  /// No description provided for @importCookieFile.
  ///
  /// In en, this message translates to:
  /// **'Import Cookie File'**
  String get importCookieFile;

  /// No description provided for @cookieFileInvalid.
  ///
  /// In en, this message translates to:
  /// **'Unsupported cookie file format. Please use Netscape format or raw text.'**
  String get cookieFileInvalid;

  /// No description provided for @cookieImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Successfully imported {count} cookies.'**
  String cookieImportSuccess(int count);

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

  /// No description provided for @pasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from Clipboard'**
  String get pasteFromClipboard;

  /// No description provided for @openRawImage.
  ///
  /// In en, this message translates to:
  /// **'Open Raw Image'**
  String get openRawImage;

  /// No description provided for @downloaderFoundSelected.
  ///
  /// In en, this message translates to:
  /// **'{found} found · {selected} selected'**
  String downloaderFoundSelected(int found, int selected);

  /// No description provided for @guideStep1Title.
  ///
  /// In en, this message translates to:
  /// **'1 · Enter a URL'**
  String get guideStep1Title;

  /// No description provided for @guideStep1Desc.
  ///
  /// In en, this message translates to:
  /// **'Paste a gallery or article page'**
  String get guideStep1Desc;

  /// No description provided for @guideStep2Title.
  ///
  /// In en, this message translates to:
  /// **'2 · Describe what to find'**
  String get guideStep2Title;

  /// No description provided for @guideStep2Desc.
  ///
  /// In en, this message translates to:
  /// **'Tell the AI which images you need'**
  String get guideStep2Desc;

  /// No description provided for @guideStep3Title.
  ///
  /// In en, this message translates to:
  /// **'3 · Pick & download'**
  String get guideStep3Title;

  /// No description provided for @guideStep3Desc.
  ///
  /// In en, this message translates to:
  /// **'Select results and queue the downloads'**
  String get guideStep3Desc;

  /// No description provided for @copyLogs.
  ///
  /// In en, this message translates to:
  /// **'Copy logs'**
  String get copyLogs;

  /// No description provided for @usage.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get usage;

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

  /// No description provided for @cachedInputTokens.
  ///
  /// In en, this message translates to:
  /// **'Cached Input'**
  String get cachedInputTokens;

  /// No description provided for @outputTokens.
  ///
  /// In en, this message translates to:
  /// **'Output Tokens'**
  String get outputTokens;

  /// No description provided for @cacheHitRate.
  ///
  /// In en, this message translates to:
  /// **'Cache Hit Rate'**
  String get cacheHitRate;

  /// No description provided for @cacheHitRateHint.
  ///
  /// In en, this message translates to:
  /// **'Share of input tokens served from the prompt cache'**
  String get cacheHitRateHint;

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

  /// No description provided for @usageByGroup.
  ///
  /// In en, this message translates to:
  /// **'Usage by Group'**
  String get usageByGroup;

  /// No description provided for @usageColumnDetail.
  ///
  /// In en, this message translates to:
  /// **'Detail'**
  String get usageColumnDetail;

  /// No description provided for @usageColumnTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get usageColumnTime;

  /// No description provided for @usageColumnCost.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get usageColumnCost;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @usageRecordCount.
  ///
  /// In en, this message translates to:
  /// **'{count} records'**
  String usageRecordCount(int count);

  /// No description provided for @usageItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String usageItemCount(int count);

  /// No description provided for @noUsageInRange.
  ///
  /// In en, this message translates to:
  /// **'No usage data in the selected range.'**
  String get noUsageInRange;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load More'**
  String get loadMore;

  /// No description provided for @models.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get models;

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

  /// No description provided for @basicInfo.
  ///
  /// In en, this message translates to:
  /// **'Basic Info'**
  String get basicInfo;

  /// No description provided for @configuration.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get configuration;

  /// No description provided for @tagAndAppearance.
  ///
  /// In en, this message translates to:
  /// **'Tag & Appearance'**
  String get tagAndAppearance;

  /// No description provided for @billing.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get billing;

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

  /// No description provided for @tagColor.
  ///
  /// In en, this message translates to:
  /// **'Tag Color'**
  String get tagColor;

  /// No description provided for @deleteChannelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete channel \"{name}\"? Its models will be deleted too.'**
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

  /// No description provided for @countModels.
  ///
  /// In en, this message translates to:
  /// **'{count} Models'**
  String countModels(int count);

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

  /// No description provided for @deleteModel.
  ///
  /// In en, this message translates to:
  /// **'Delete Model'**
  String get deleteModel;

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

  /// No description provided for @paidModel.
  ///
  /// In en, this message translates to:
  /// **'Paid Model'**
  String get paidModel;

  /// No description provided for @freeModel.
  ///
  /// In en, this message translates to:
  /// **'Free Model'**
  String get freeModel;

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

  /// No description provided for @cacheInputPrice.
  ///
  /// In en, this message translates to:
  /// **'Cached Input Price (\$/M Tokens)'**
  String get cacheInputPrice;

  /// No description provided for @cacheInputPriceHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to bill cache hits at the input price'**
  String get cacheInputPriceHint;

  /// No description provided for @cachePriceFollowsInput.
  ///
  /// In en, this message translates to:
  /// **'Cache hits are billed at the input price'**
  String get cachePriceFollowsInput;

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

  /// No description provided for @priceLabelInput.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get priceLabelInput;

  /// No description provided for @priceLabelCache.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get priceLabelCache;

  /// No description provided for @priceLabelOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get priceLabelOutput;

  /// No description provided for @priceLabelRequest.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get priceLabelRequest;

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

  /// No description provided for @searchModels.
  ///
  /// In en, this message translates to:
  /// **'Search model name or ID...'**
  String get searchModels;

  /// No description provided for @modelsDiscovered.
  ///
  /// In en, this message translates to:
  /// **'{count} models discovered'**
  String modelsDiscovered(int count);

  /// No description provided for @addSelected.
  ///
  /// In en, this message translates to:
  /// **'Add Selected ({count})'**
  String addSelected(int count);

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
  String fetchFailed(String error);

  /// No description provided for @stepProtocol.
  ///
  /// In en, this message translates to:
  /// **'Choose Protocol'**
  String get stepProtocol;

  /// No description provided for @stepProvider.
  ///
  /// In en, this message translates to:
  /// **'Choose Provider'**
  String get stepProvider;

  /// No description provided for @stepApiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get stepApiKey;

  /// No description provided for @stepConfig.
  ///
  /// In en, this message translates to:
  /// **'Extra Config'**
  String get stepConfig;

  /// No description provided for @stepPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get stepPreview;

  /// No description provided for @protocolOpenAI.
  ///
  /// In en, this message translates to:
  /// **'OpenAI Compatible (REST)'**
  String get protocolOpenAI;

  /// No description provided for @protocolOpenAIDesc.
  ///
  /// In en, this message translates to:
  /// **'Standard OpenAI REST API compatibility'**
  String get protocolOpenAIDesc;

  /// No description provided for @protocolGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google GenAI (REST)'**
  String get protocolGoogle;

  /// No description provided for @protocolGoogleDesc.
  ///
  /// In en, this message translates to:
  /// **'Official Google Gemini REST API'**
  String get protocolGoogleDesc;

  /// No description provided for @protocolMidjourney.
  ///
  /// In en, this message translates to:
  /// **'Midjourney Proxy'**
  String get protocolMidjourney;

  /// No description provided for @protocolMidjourneyDesc.
  ///
  /// In en, this message translates to:
  /// **'midjourney-proxy / NewAPI /mj/* surface'**
  String get protocolMidjourneyDesc;

  /// No description provided for @midjourneyEndpointHint.
  ///
  /// In en, this message translates to:
  /// **'Host root (e.g. https://your-newapi.com). /mj/* paths are added automatically.'**
  String get midjourneyEndpointHint;

  /// No description provided for @providerOpenAIOfficial.
  ///
  /// In en, this message translates to:
  /// **'OpenAI Official'**
  String get providerOpenAIOfficial;

  /// No description provided for @providerGoogleOfficial.
  ///
  /// In en, this message translates to:
  /// **'Google GenAI Official'**
  String get providerGoogleOfficial;

  /// No description provided for @providerGoogleCompatible.
  ///
  /// In en, this message translates to:
  /// **'Google GenAI (OpenAI Compatible)'**
  String get providerGoogleCompatible;

  /// No description provided for @providerGoogleCompatibleDesc.
  ///
  /// In en, this message translates to:
  /// **'Google Gemini via OpenAI endpoint'**
  String get providerGoogleCompatibleDesc;

  /// No description provided for @providerCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom Provider'**
  String get providerCustom;

  /// No description provided for @providerCustomDesc.
  ///
  /// In en, this message translates to:
  /// **'Self-hosted or 3rd party provider'**
  String get providerCustomDesc;

  /// No description provided for @providerGroupOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get providerGroupOther;

  /// No description provided for @stepConnection.
  ///
  /// In en, this message translates to:
  /// **'Endpoint & key'**
  String get stepConnection;

  /// No description provided for @sectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get sectionAppearance;

  /// No description provided for @moreColors.
  ///
  /// In en, this message translates to:
  /// **'More colors'**
  String get moreColors;

  /// No description provided for @protocolXai.
  ///
  /// In en, this message translates to:
  /// **'xAI (Grok) API'**
  String get protocolXai;

  /// No description provided for @providerXaiOfficial.
  ///
  /// In en, this message translates to:
  /// **'xAI Official'**
  String get providerXaiOfficial;

  /// No description provided for @providerXaiOfficialDesc.
  ///
  /// In en, this message translates to:
  /// **'api.x.ai · Grok chat + native Imagine video'**
  String get providerXaiOfficialDesc;

  /// No description provided for @providerNewApiOpenAI.
  ///
  /// In en, this message translates to:
  /// **'New API (OpenAI format)'**
  String get providerNewApiOpenAI;

  /// No description provided for @providerNewApiGemini.
  ///
  /// In en, this message translates to:
  /// **'New API (Gemini format)'**
  String get providerNewApiGemini;

  /// No description provided for @providerNewApiDesc.
  ///
  /// In en, this message translates to:
  /// **'New API relay · bearer-token auth'**
  String get providerNewApiDesc;

  /// No description provided for @newApiBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'New API Base URL'**
  String get newApiBaseUrl;

  /// No description provided for @newApiBaseHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your New API host; the version path is added automatically'**
  String get newApiBaseHint;

  /// No description provided for @customEndpointHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your custom endpoint URL'**
  String get customEndpointHint;

  /// No description provided for @openaiV1Hint.
  ///
  /// In en, this message translates to:
  /// **'Hint: OpenAI compatible endpoints usually end with \'/v1\''**
  String get openaiV1Hint;

  /// No description provided for @googleV1BetaHint.
  ///
  /// In en, this message translates to:
  /// **'Hint: Google GenAI endpoints usually end with \'/v1beta\''**
  String get googleV1BetaHint;

  /// No description provided for @enterApiKey.
  ///
  /// In en, this message translates to:
  /// **'Enter your API Key'**
  String get enterApiKey;

  /// No description provided for @apiKeyStorageNotice.
  ///
  /// In en, this message translates to:
  /// **'Your key is stored locally and never sent to our servers.'**
  String get apiKeyStorageNotice;

  /// No description provided for @nameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. My Production API'**
  String get nameHint;

  /// No description provided for @enableDiscoveryDesc.
  ///
  /// In en, this message translates to:
  /// **'Automatically list available models from this endpoint'**
  String get enableDiscoveryDesc;

  /// No description provided for @tagHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. GPT4, Local, etc.'**
  String get tagHint;

  /// No description provided for @bindTag.
  ///
  /// In en, this message translates to:
  /// **'Bind Tag'**
  String get bindTag;

  /// No description provided for @previewReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to add this channel?'**
  String get previewReady;

  /// No description provided for @feeGroupDesc.
  ///
  /// In en, this message translates to:
  /// **'Define billing standards for models to accurately calculate usage costs.'**
  String get feeGroupDesc;

  /// No description provided for @feeGroupEditorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure how a model is billed'**
  String get feeGroupEditorSubtitle;

  /// No description provided for @noFeeGroups.
  ///
  /// In en, this message translates to:
  /// **'No fee groups created yet'**
  String get noFeeGroups;

  /// No description provided for @pricePerMillion.
  ///
  /// In en, this message translates to:
  /// **'Price per Million Tokens'**
  String get pricePerMillion;

  /// No description provided for @pricePerRequest.
  ///
  /// In en, this message translates to:
  /// **'Price per Request'**
  String get pricePerRequest;

  /// No description provided for @tokenBilling.
  ///
  /// In en, this message translates to:
  /// **'Token Billing'**
  String get tokenBilling;

  /// No description provided for @requestBilling.
  ///
  /// In en, this message translates to:
  /// **'Request Billing'**
  String get requestBilling;

  /// No description provided for @feeGroupModelCount.
  ///
  /// In en, this message translates to:
  /// **'{count} models'**
  String feeGroupModelCount(int count);

  /// No description provided for @feeGroupUnused.
  ///
  /// In en, this message translates to:
  /// **'Not used by any model'**
  String get feeGroupUnused;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @modelsAndChannelsCount.
  ///
  /// In en, this message translates to:
  /// **'{models} models · {channels} channels'**
  String modelsAndChannelsCount(int models, int channels);

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get deselectAll;

  /// No description provided for @capabilities.
  ///
  /// In en, this message translates to:
  /// **'Capabilities'**
  String get capabilities;

  /// No description provided for @supportsStreaming.
  ///
  /// In en, this message translates to:
  /// **'Supports Streaming'**
  String get supportsStreaming;

  /// No description provided for @supportsStreamingDesc.
  ///
  /// In en, this message translates to:
  /// **'Enable if the model supports server-sent events'**
  String get supportsStreamingDesc;

  /// No description provided for @supportsStandardRequest.
  ///
  /// In en, this message translates to:
  /// **'Supports Standard Request'**
  String get supportsStandardRequest;

  /// No description provided for @supportsStandardRequestDesc.
  ///
  /// In en, this message translates to:
  /// **'Enable for standard JSON/REST requests'**
  String get supportsStandardRequestDesc;

  /// No description provided for @contextWindow.
  ///
  /// In en, this message translates to:
  /// **'Context Window'**
  String get contextWindow;

  /// No description provided for @contextUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get contextUnlimited;

  /// No description provided for @contextUnlimitedDesc.
  ///
  /// In en, this message translates to:
  /// **'Send all candidates in one request (no batching)'**
  String get contextUnlimitedDesc;

  /// No description provided for @contextMax.
  ///
  /// In en, this message translates to:
  /// **'Max context'**
  String get contextMax;

  /// No description provided for @contextTokens.
  ///
  /// In en, this message translates to:
  /// **'{size} tokens'**
  String contextTokens(String size);

  /// No description provided for @contextWindowHint.
  ///
  /// In en, this message translates to:
  /// **'Larger context lets more images be analyzed per request.'**
  String get contextWindowHint;

  /// No description provided for @agentBehavior.
  ///
  /// In en, this message translates to:
  /// **'Agent Behavior'**
  String get agentBehavior;

  /// No description provided for @forceViewAllImages.
  ///
  /// In en, this message translates to:
  /// **'View all reference images'**
  String get forceViewAllImages;

  /// No description provided for @forceViewAllImagesDesc.
  ///
  /// In en, this message translates to:
  /// **'Agents must view every reference image before delivering a result. Recommended for small local models.'**
  String get forceViewAllImagesDesc;

  /// No description provided for @prompts.
  ///
  /// In en, this message translates to:
  /// **'Prompts'**
  String get prompts;

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

  /// No description provided for @systemTemplates.
  ///
  /// In en, this message translates to:
  /// **'System Templates'**
  String get systemTemplates;

  /// No description provided for @templateType.
  ///
  /// In en, this message translates to:
  /// **'Template Type'**
  String get templateType;

  /// No description provided for @typeRename.
  ///
  /// In en, this message translates to:
  /// **'Batch Rename'**
  String get typeRename;

  /// No description provided for @typeRefiner.
  ///
  /// In en, this message translates to:
  /// **'Prompt Refiner'**
  String get typeRefiner;

  /// No description provided for @selectRenameTemplate.
  ///
  /// In en, this message translates to:
  /// **'Select Rename Template'**
  String get selectRenameTemplate;

  /// No description provided for @selectCategory.
  ///
  /// In en, this message translates to:
  /// **'Select Category'**
  String get selectCategory;

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

  /// No description provided for @selectionMode.
  ///
  /// In en, this message translates to:
  /// **'Selection Mode'**
  String get selectionMode;

  /// No description provided for @selectionModeCount.
  ///
  /// In en, this message translates to:
  /// **'Selection Mode ({count})'**
  String selectionModeCount(int count);

  /// No description provided for @nSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} Selected'**
  String nSelected(int count);

  /// No description provided for @categorize.
  ///
  /// In en, this message translates to:
  /// **'Categorize'**
  String get categorize;

  /// No description provided for @bulkCategorize.
  ///
  /// In en, this message translates to:
  /// **'Bulk Categorize'**
  String get bulkCategorize;

  /// No description provided for @selectCategoriesToApply.
  ///
  /// In en, this message translates to:
  /// **'Select categories to apply to the selected prompts:'**
  String get selectCategoriesToApply;

  /// No description provided for @deleteNPromptsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} prompts?'**
  String deleteNPromptsConfirm(int count);

  /// No description provided for @actionCannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone.'**
  String get actionCannotBeUndone;

  /// No description provided for @deleteCategoryConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete category \"{name}\"? Prompts will be moved to General.'**
  String deleteCategoryConfirmMessage(String name);

  /// No description provided for @moveToTop.
  ///
  /// In en, this message translates to:
  /// **'Move to Top'**
  String get moveToTop;

  /// No description provided for @moveToBottom.
  ///
  /// In en, this message translates to:
  /// **'Move to Bottom'**
  String get moveToBottom;

  /// No description provided for @addSystemTemplateHint.
  ///
  /// In en, this message translates to:
  /// **'Add system templates for the Refiner or Batch Rename here.'**
  String get addSystemTemplateHint;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailed(String error);

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @newTemplate.
  ///
  /// In en, this message translates to:
  /// **'New Template'**
  String get newTemplate;

  /// No description provided for @reorderDisabledWhileFiltered.
  ///
  /// In en, this message translates to:
  /// **'Reordering is unavailable while a filter or search is active'**
  String get reorderDisabledWhileFiltered;

  /// No description provided for @matchModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get matchModeLabel;

  /// No description provided for @matchAny.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get matchAny;

  /// No description provided for @matchAllTags.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get matchAllTags;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @connectivity.
  ///
  /// In en, this message translates to:
  /// **'Connectivity'**
  String get connectivity;

  /// No description provided for @application.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get application;

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

  /// No description provided for @font.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get font;

  /// No description provided for @fontSystem.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get fontSystem;

  /// No description provided for @fontDownloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Download Font'**
  String get fontDownloadTitle;

  /// No description provided for @fontDownloadPrompt.
  ///
  /// In en, this message translates to:
  /// **'This font isn\'t bundled with the app and needs to be downloaded once before it can be used.'**
  String get fontDownloadPrompt;

  /// No description provided for @fontDownloadAction.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get fontDownloadAction;

  /// No description provided for @fontDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading font…'**
  String get fontDownloading;

  /// No description provided for @fontDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Font download failed. Check your connection and try again.'**
  String get fontDownloadFailed;

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

  /// No description provided for @exportOptions.
  ///
  /// In en, this message translates to:
  /// **'Export Options'**
  String get exportOptions;

  /// No description provided for @includeDirectories.
  ///
  /// In en, this message translates to:
  /// **'Include Directory Config'**
  String get includeDirectories;

  /// No description provided for @includeDirectoriesDesc.
  ///
  /// In en, this message translates to:
  /// **'Workbench/Browser directories and output path'**
  String get includeDirectoriesDesc;

  /// No description provided for @includePrompts.
  ///
  /// In en, this message translates to:
  /// **'Include Prompts'**
  String get includePrompts;

  /// No description provided for @includePromptsDesc.
  ///
  /// In en, this message translates to:
  /// **'User and system prompt library'**
  String get includePromptsDesc;

  /// No description provided for @includeUsage.
  ///
  /// In en, this message translates to:
  /// **'Include Usage Metrics'**
  String get includeUsage;

  /// No description provided for @includeUsageDesc.
  ///
  /// In en, this message translates to:
  /// **'API token consumption history'**
  String get includeUsageDesc;

  /// No description provided for @exportNow.
  ///
  /// In en, this message translates to:
  /// **'Export Now'**
  String get exportNow;

  /// No description provided for @importNow.
  ///
  /// In en, this message translates to:
  /// **'Import Now'**
  String get importNow;

  /// No description provided for @importOptions.
  ///
  /// In en, this message translates to:
  /// **'Import Options'**
  String get importOptions;

  /// No description provided for @notInBackup.
  ///
  /// In en, this message translates to:
  /// **'Not available in backup file'**
  String get notInBackup;

  /// No description provided for @importSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Settings?'**
  String get importSettingsTitle;

  /// No description provided for @importSettingsConfirm.
  ///
  /// In en, this message translates to:
  /// **'This will replace all your current models, channels, and categories. \n\nNote: Standalone prompt library is NOT affected by this import. Use the Prompts screen for prompt data management.'**
  String get importSettingsConfirm;

  /// No description provided for @importAndReplace.
  ///
  /// In en, this message translates to:
  /// **'Import & Replace'**
  String get importAndReplace;

  /// No description provided for @importErrorPromptsOnly.
  ///
  /// In en, this message translates to:
  /// **'This is a prompt library export, not a full backup. Import it from the Prompts screen instead.'**
  String get importErrorPromptsOnly;

  /// No description provided for @importErrorNotABackup.
  ///
  /// In en, this message translates to:
  /// **'This file is not a valid backup. Choose a file exported with Export Settings.'**
  String get importErrorNotABackup;

  /// No description provided for @importErrorNewerSchema.
  ///
  /// In en, this message translates to:
  /// **'This backup was created by a newer version of the app. Please update before importing it.'**
  String get importErrorNewerSchema;

  /// No description provided for @importMode.
  ///
  /// In en, this message translates to:
  /// **'Import Mode'**
  String get importMode;

  /// No description provided for @importModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose how you want to import prompts:\n\nMerge: Add new items to your library.\nReplace: Delete current library and use imported data.'**
  String get importModeDesc;

  /// No description provided for @merge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get merge;

  /// No description provided for @replaceAll.
  ///
  /// In en, this message translates to:
  /// **'Replace All'**
  String get replaceAll;

  /// No description provided for @applyOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Apply (Overwrite)'**
  String get applyOverwrite;

  /// No description provided for @applyAppend.
  ///
  /// In en, this message translates to:
  /// **'Apply (Append)'**
  String get applyAppend;

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

  /// No description provided for @enableNotifications.
  ///
  /// In en, this message translates to:
  /// **'Enable System Notifications'**
  String get enableNotifications;

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

  /// No description provided for @enableApiDebug.
  ///
  /// In en, this message translates to:
  /// **'Enable API Debug Logging'**
  String get enableApiDebug;

  /// No description provided for @apiDebugDesc.
  ///
  /// In en, this message translates to:
  /// **'Logs raw API requests and responses to files for troubleshooting. Warning: Sensitive data like API Keys might be logged if not masked.'**
  String get apiDebugDesc;

  /// No description provided for @openLogFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Log Folder'**
  String get openLogFolder;

  /// No description provided for @iosOutputRecommend.
  ///
  /// In en, this message translates to:
  /// **'Recommended: Leave as default on iOS. The app\'s folder is visible in the \'Files\' app.'**
  String get iosOutputRecommend;

  /// No description provided for @downloaderCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Downloader cache cleared.'**
  String get downloaderCacheCleared;

  /// No description provided for @knowledgeBaseFolder.
  ///
  /// In en, this message translates to:
  /// **'Knowledge Base Folder'**
  String get knowledgeBaseFolder;

  /// No description provided for @kbOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder'**
  String get kbOpenFolder;

  /// No description provided for @kbInvalidDir.
  ///
  /// In en, this message translates to:
  /// **'Folder not found'**
  String get kbInvalidDir;

  /// No description provided for @kbMissingEntry.
  ///
  /// In en, this message translates to:
  /// **'README.md entry file not found in the folder'**
  String get kbMissingEntry;

  /// No description provided for @assistantRetention.
  ///
  /// In en, this message translates to:
  /// **'Assistant Conversations to Keep'**
  String get assistantRetention;

  /// No description provided for @assistantRetentionDesc.
  ///
  /// In en, this message translates to:
  /// **'Older prompt assistant conversations beyond this count are deleted automatically'**
  String get assistantRetentionDesc;

  /// No description provided for @tasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasks;

  /// No description provided for @taskQueueManager.
  ///
  /// In en, this message translates to:
  /// **'Task Queue Manager'**
  String get taskQueueManager;

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

  /// No description provided for @taskSummary.
  ///
  /// In en, this message translates to:
  /// **'Task Summary'**
  String get taskSummary;

  /// No description provided for @pendingTasks.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pendingTasks;

  /// No description provided for @processingTasks.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get processingTasks;

  /// No description provided for @completedTasks.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completedTasks;

  /// No description provided for @failedTasks.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failedTasks;

  /// No description provided for @clearCompleted.
  ///
  /// In en, this message translates to:
  /// **'Clear Completed'**
  String get clearCompleted;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get clearAll;

  /// No description provided for @clearAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'This will remove all non-running tasks. This action cannot be undone.'**
  String get clearAllConfirm;

  /// No description provided for @cancelAllPending.
  ///
  /// In en, this message translates to:
  /// **'Cancel All Pending'**
  String get cancelAllPending;

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

  /// No description provided for @latestLog.
  ///
  /// In en, this message translates to:
  /// **'Latest Log:'**
  String get latestLog;

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

  /// No description provided for @taskTotalCount.
  ///
  /// In en, this message translates to:
  /// **'{count} total'**
  String taskTotalCount(int count);

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @retryTask.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryTask;

  /// No description provided for @queuedPosition.
  ///
  /// In en, this message translates to:
  /// **'#{position} in queue'**
  String queuedPosition(int position);

  /// No description provided for @tookDuration.
  ///
  /// In en, this message translates to:
  /// **'took {duration}'**
  String tookDuration(String duration);

  /// No description provided for @retryCount.
  ///
  /// In en, this message translates to:
  /// **'Retry Count: {count}'**
  String retryCount(int count);

  /// No description provided for @viewTaskLog.
  ///
  /// In en, this message translates to:
  /// **'View Log'**
  String get viewTaskLog;

  /// No description provided for @taskLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Task Log'**
  String get taskLogTitle;

  /// No description provided for @taskLogLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get taskLogLive;

  /// No description provided for @noTaskLog.
  ///
  /// In en, this message translates to:
  /// **'No log recorded for this task.'**
  String get noTaskLog;

  /// No description provided for @noTaskLogHint.
  ///
  /// In en, this message translates to:
  /// **'Tasks that ran before this update did not keep their logs.'**
  String get noTaskLogHint;

  /// No description provided for @taskLogCopied.
  ///
  /// In en, this message translates to:
  /// **'Log copied to clipboard'**
  String get taskLogCopied;

  /// No description provided for @copyPrompt.
  ///
  /// In en, this message translates to:
  /// **'Copy prompt'**
  String get copyPrompt;

  /// No description provided for @taskLogLineCount.
  ///
  /// In en, this message translates to:
  /// **'{count} lines'**
  String taskLogLineCount(int count);

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

  /// No description provided for @setupCompleteMessage.
  ///
  /// In en, this message translates to:
  /// **'You are all set! Enjoy creating.'**
  String get setupCompleteMessage;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @storageLocationDesc.
  ///
  /// In en, this message translates to:
  /// **'Select where generated images will be saved.'**
  String get storageLocationDesc;

  /// No description provided for @addChannelOptional.
  ///
  /// In en, this message translates to:
  /// **'Add your first AI provider channel (Optional).'**
  String get addChannelOptional;

  /// No description provided for @configureModelOptional.
  ///
  /// In en, this message translates to:
  /// **'Configure a model for your new channel (Optional).'**
  String get configureModelOptional;

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

  /// No description provided for @openaiEndpointHint.
  ///
  /// In en, this message translates to:
  /// **'Hint: OpenAI compatible endpoints usually end with \'/v1\''**
  String get openaiEndpointHint;

  /// No description provided for @googleEndpointHint.
  ///
  /// In en, this message translates to:
  /// **'Hint: Google GenAI endpoints usually end with \'/v1beta\' (internal handling)'**
  String get googleEndpointHint;

  /// No description provided for @workbench.
  ///
  /// In en, this message translates to:
  /// **'Workbench'**
  String get workbench;

  /// No description provided for @imageProcessing.
  ///
  /// In en, this message translates to:
  /// **'Image Processing'**
  String get imageProcessing;

  /// No description provided for @wbModeImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get wbModeImage;

  /// No description provided for @wbModeVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get wbModeVideo;

  /// No description provided for @wbTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get wbTools;

  /// No description provided for @sourceGallery.
  ///
  /// In en, this message translates to:
  /// **'Source Gallery'**
  String get sourceGallery;

  /// No description provided for @sourceExplorer.
  ///
  /// In en, this message translates to:
  /// **'Source Explorer'**
  String get sourceExplorer;

  /// No description provided for @tempWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Temp Workspace'**
  String get tempWorkspace;

  /// No description provided for @processResults.
  ///
  /// In en, this message translates to:
  /// **'Process Results'**
  String get processResults;

  /// No description provided for @resultCache.
  ///
  /// In en, this message translates to:
  /// **'Result Cache'**
  String get resultCache;

  /// No description provided for @sectionSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get sectionSources;

  /// No description provided for @sectionResults.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get sectionResults;

  /// No description provided for @sectionWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get sectionWorkspace;

  /// No description provided for @allSources.
  ///
  /// In en, this message translates to:
  /// **'All Sources'**
  String get allSources;

  /// No description provided for @allResults.
  ///
  /// In en, this message translates to:
  /// **'All Results'**
  String get allResults;

  /// No description provided for @backToAll.
  ///
  /// In en, this message translates to:
  /// **'Back to all'**
  String get backToAll;

  /// No description provided for @directories.
  ///
  /// In en, this message translates to:
  /// **'DIRECTORIES'**
  String get directories;

  /// No description provided for @addFolder.
  ///
  /// In en, this message translates to:
  /// **'Add Folder'**
  String get addFolder;

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

  /// No description provided for @importFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Import from Gallery'**
  String get importFromGallery;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take Photo'**
  String get takePhoto;

  /// No description provided for @clearTempWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Clear Workspace'**
  String get clearTempWorkspace;

  /// No description provided for @dropFilesHere.
  ///
  /// In en, this message translates to:
  /// **'Drop images here to add them to temporary workspace'**
  String get dropFilesHere;

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

  /// No description provided for @quality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get quality;

  /// No description provided for @optionAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get optionAuto;

  /// No description provided for @qualityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get qualityLow;

  /// No description provided for @qualityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get qualityMedium;

  /// No description provided for @qualityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get qualityHigh;

  /// No description provided for @mjVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get mjVersion;

  /// No description provided for @mjMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get mjMode;

  /// No description provided for @mjStylize.
  ///
  /// In en, this message translates to:
  /// **'Stylize'**
  String get mjStylize;

  /// No description provided for @mjChaos.
  ///
  /// In en, this message translates to:
  /// **'Chaos'**
  String get mjChaos;

  /// No description provided for @referenceImagesNotSupported.
  ///
  /// In en, this message translates to:
  /// **'This model does not support reference images. Selected images will be ignored.'**
  String get referenceImagesNotSupported;

  /// No description provided for @referenceImagesLimited.
  ///
  /// In en, this message translates to:
  /// **'This model accepts at most {count} reference image(s); the rest will be ignored.'**
  String referenceImagesLimited(int count);

  /// No description provided for @prompt.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get prompt;

  /// No description provided for @promptHint.
  ///
  /// In en, this message translates to:
  /// **'Enter prompt here...'**
  String get promptHint;

  /// No description provided for @promptHistory.
  ///
  /// In en, this message translates to:
  /// **'Prompt History'**
  String get promptHistory;

  /// No description provided for @noPromptHistory.
  ///
  /// In en, this message translates to:
  /// **'No recent prompts'**
  String get noPromptHistory;

  /// No description provided for @noPromptHistoryDesc.
  ///
  /// In en, this message translates to:
  /// **'Prompts you submit will appear here.'**
  String get noPromptHistoryDesc;

  /// No description provided for @usePrompt.
  ///
  /// In en, this message translates to:
  /// **'Use This Prompt'**
  String get usePrompt;

  /// No description provided for @applyPromptWarning.
  ///
  /// In en, this message translates to:
  /// **'This will replace the prompt currently in the editor.'**
  String get applyPromptWarning;

  /// No description provided for @clearPromptHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get clearPromptHistory;

  /// No description provided for @clearPromptHistoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove all recent prompts? This cannot be undone.'**
  String get clearPromptHistoryConfirm;

  /// No description provided for @timeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String timeMinutesAgo(int count);

  /// No description provided for @timeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} h ago'**
  String timeHoursAgo(int count);

  /// No description provided for @timeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} d ago'**
  String timeDaysAgo(int count);

  /// No description provided for @prefixHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. result'**
  String get prefixHint;

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

  /// No description provided for @useStreaming.
  ///
  /// In en, this message translates to:
  /// **'Use Streaming'**
  String get useStreaming;

  /// No description provided for @useStreamingDesc.
  ///
  /// In en, this message translates to:
  /// **'Real-time AI response (if supported)'**
  String get useStreamingDesc;

  /// No description provided for @taskSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Task submitted to queue'**
  String get taskSubmitted;

  /// No description provided for @comparator.
  ///
  /// In en, this message translates to:
  /// **'Comparator'**
  String get comparator;

  /// No description provided for @compareModeSync.
  ///
  /// In en, this message translates to:
  /// **'Sync Mode'**
  String get compareModeSync;

  /// No description provided for @compareModeSwap.
  ///
  /// In en, this message translates to:
  /// **'Swap Mode'**
  String get compareModeSwap;

  /// No description provided for @sendToComparator.
  ///
  /// In en, this message translates to:
  /// **'Send to Comparator'**
  String get sendToComparator;

  /// No description provided for @sendToComparatorRaw.
  ///
  /// In en, this message translates to:
  /// **'Set as Before (RAW)'**
  String get sendToComparatorRaw;

  /// No description provided for @sendToComparatorAfter.
  ///
  /// In en, this message translates to:
  /// **'Set as After (Result)'**
  String get sendToComparatorAfter;

  /// No description provided for @sendToFirstFrame.
  ///
  /// In en, this message translates to:
  /// **'Set as First Frame (Video)'**
  String get sendToFirstFrame;

  /// No description provided for @sendToLastFrame.
  ///
  /// In en, this message translates to:
  /// **'Set as Last Frame (Video)'**
  String get sendToLastFrame;

  /// No description provided for @sendToVideoReferences.
  ///
  /// In en, this message translates to:
  /// **'Add to Video References'**
  String get sendToVideoReferences;

  /// No description provided for @sendToSelection.
  ///
  /// In en, this message translates to:
  /// **'Add to Selection'**
  String get sendToSelection;

  /// No description provided for @sendToOptimizer.
  ///
  /// In en, this message translates to:
  /// **'Send to Prompt Assistant'**
  String get sendToOptimizer;

  /// No description provided for @optimizePromptWithImage.
  ///
  /// In en, this message translates to:
  /// **'Optimize Prompt with Image'**
  String get optimizePromptWithImage;

  /// No description provided for @selectFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Select from Library'**
  String get selectFromLibrary;

  /// No description provided for @metadataSelectedNone.
  ///
  /// In en, this message translates to:
  /// **'No image metadata selected'**
  String get metadataSelectedNone;

  /// No description provided for @labelRaw.
  ///
  /// In en, this message translates to:
  /// **'RAW'**
  String get labelRaw;

  /// No description provided for @labelAfter.
  ///
  /// In en, this message translates to:
  /// **'AFTER'**
  String get labelAfter;

  /// No description provided for @cropAndResize.
  ///
  /// In en, this message translates to:
  /// **'Crop & Resize'**
  String get cropAndResize;

  /// No description provided for @overwriteSource.
  ///
  /// In en, this message translates to:
  /// **'Overwrite Original'**
  String get overwriteSource;

  /// No description provided for @overwriteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Overwrite Original File?'**
  String get overwriteConfirmTitle;

  /// No description provided for @overwriteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This action will permanently replace the original file. Are you sure?'**
  String get overwriteConfirmMessage;

  /// No description provided for @saveToTempSuccess.
  ///
  /// In en, this message translates to:
  /// **'Image saved to temporary workspace'**
  String get saveToTempSuccess;

  /// No description provided for @overwriteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Original file updated'**
  String get overwriteSuccess;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @resize.
  ///
  /// In en, this message translates to:
  /// **'Resize'**
  String get resize;

  /// No description provided for @maintainAspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Maintain Aspect Ratio'**
  String get maintainAspectRatio;

  /// No description provided for @width.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get width;

  /// No description provided for @height.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get height;

  /// No description provided for @sampling.
  ///
  /// In en, this message translates to:
  /// **'Sampling'**
  String get sampling;

  /// No description provided for @drawMask.
  ///
  /// In en, this message translates to:
  /// **'Draw Mask'**
  String get drawMask;

  /// No description provided for @maskEditor.
  ///
  /// In en, this message translates to:
  /// **'Mask Editor'**
  String get maskEditor;

  /// No description provided for @brushSize.
  ///
  /// In en, this message translates to:
  /// **'Brush Size'**
  String get brushSize;

  /// No description provided for @maskColor.
  ///
  /// In en, this message translates to:
  /// **'Mask Color'**
  String get maskColor;

  /// No description provided for @maskOpacity.
  ///
  /// In en, this message translates to:
  /// **'Mask Opacity'**
  String get maskOpacity;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @saveToTemp.
  ///
  /// In en, this message translates to:
  /// **'Save to Workspace'**
  String get saveToTemp;

  /// No description provided for @saveMaskToTemp.
  ///
  /// In en, this message translates to:
  /// **'Save Mask to Workspace'**
  String get saveMaskToTemp;

  /// No description provided for @binaryMode.
  ///
  /// In en, this message translates to:
  /// **'Binary Mode'**
  String get binaryMode;

  /// No description provided for @maskSaved.
  ///
  /// In en, this message translates to:
  /// **'Mask saved to workspace'**
  String get maskSaved;

  /// No description provided for @maskSaveError.
  ///
  /// In en, this message translates to:
  /// **'Error saving mask: {error}'**
  String maskSaveError(String error);

  /// No description provided for @promptOptimizer.
  ///
  /// In en, this message translates to:
  /// **'Prompt Assistant'**
  String get promptOptimizer;

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

  /// No description provided for @preset.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get preset;

  /// No description provided for @customSysPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a custom system prompt for this session...'**
  String get customSysPromptHint;

  /// No description provided for @refinerIntro.
  ///
  /// In en, this message translates to:
  /// **'Use AI to analyze images and refine your prompt.'**
  String get refinerIntro;

  /// No description provided for @roughPrompt.
  ///
  /// In en, this message translates to:
  /// **'Rough Prompt / Ideas'**
  String get roughPrompt;

  /// No description provided for @optimizedPrompt.
  ///
  /// In en, this message translates to:
  /// **'Optimized Prompt'**
  String get optimizedPrompt;

  /// No description provided for @applyToWorkbench.
  ///
  /// In en, this message translates to:
  /// **'Apply to Workbench'**
  String get applyToWorkbench;

  /// No description provided for @promptApplied.
  ///
  /// In en, this message translates to:
  /// **'Prompt applied to workbench'**
  String get promptApplied;

  /// No description provided for @refineFailed.
  ///
  /// In en, this message translates to:
  /// **'Refine failed: {error}'**
  String refineFailed(String error);

  /// No description provided for @optChatHint.
  ///
  /// In en, this message translates to:
  /// **'Describe your idea or paste a rough prompt...'**
  String get optChatHint;

  /// No description provided for @optSend.
  ///
  /// In en, this message translates to:
  /// **'Send (Ctrl+Enter)'**
  String get optSend;

  /// No description provided for @optNewSession.
  ///
  /// In en, this message translates to:
  /// **'New Conversation'**
  String get optNewSession;

  /// No description provided for @optAgentWorking.
  ///
  /// In en, this message translates to:
  /// **'Optimizing...'**
  String get optAgentWorking;

  /// No description provided for @optToolListImages.
  ///
  /// In en, this message translates to:
  /// **'Checked the reference image list'**
  String get optToolListImages;

  /// No description provided for @optToolViewImage.
  ///
  /// In en, this message translates to:
  /// **'Viewed reference image: {name}'**
  String optToolViewImage(String name);

  /// No description provided for @optPromptVersion.
  ///
  /// In en, this message translates to:
  /// **'Optimized Prompt v{version}'**
  String optPromptVersion(int version);

  /// No description provided for @optCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get optCopy;

  /// No description provided for @optPromptCopied.
  ///
  /// In en, this message translates to:
  /// **'Prompt copied to clipboard'**
  String get optPromptCopied;

  /// No description provided for @optEmptyChat.
  ///
  /// In en, this message translates to:
  /// **'Send a rough prompt or idea to start. The AI inspects reference images on demand, and you can refine the result over multiple turns.'**
  String get optEmptyChat;

  /// No description provided for @optViewed.
  ///
  /// In en, this message translates to:
  /// **'Viewed by AI'**
  String get optViewed;

  /// No description provided for @optRemoveImage.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get optRemoveImage;

  /// No description provided for @optEmptyImagesHint.
  ///
  /// In en, this message translates to:
  /// **'Right-click an image in the gallery and choose \"Send to Prompt Assistant\" to add it here.'**
  String get optEmptyImagesHint;

  /// No description provided for @videoGeneration.
  ///
  /// In en, this message translates to:
  /// **'Video Generation'**
  String get videoGeneration;

  /// No description provided for @referenceImages.
  ///
  /// In en, this message translates to:
  /// **'Reference Images'**
  String get referenceImages;

  /// No description provided for @firstFrame.
  ///
  /// In en, this message translates to:
  /// **'First Frame'**
  String get firstFrame;

  /// No description provided for @lastFrame.
  ///
  /// In en, this message translates to:
  /// **'Last Frame'**
  String get lastFrame;

  /// No description provided for @generateVideo.
  ///
  /// In en, this message translates to:
  /// **'Generate Video'**
  String get generateVideo;

  /// No description provided for @frames.
  ///
  /// In en, this message translates to:
  /// **'Frames'**
  String get frames;

  /// No description provided for @videoResolution.
  ///
  /// In en, this message translates to:
  /// **'Video Resolution'**
  String get videoResolution;

  /// No description provided for @videoAspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Video Aspect Ratio'**
  String get videoAspectRatio;

  /// No description provided for @videoSeconds.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get videoSeconds;

  /// No description provided for @videoQualityStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get videoQualityStandard;

  /// No description provided for @videoQualityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get videoQualityHigh;

  /// No description provided for @openInSystemPlayer.
  ///
  /// In en, this message translates to:
  /// **'Open in System Player'**
  String get openInSystemPlayer;

  /// No description provided for @dropVideoReferenceHere.
  ///
  /// In en, this message translates to:
  /// **'Drop images here for style/content reference'**
  String get dropVideoReferenceHere;

  /// No description provided for @dropFirstFrameHere.
  ///
  /// In en, this message translates to:
  /// **'Drop image here for start frame'**
  String get dropFirstFrameHere;

  /// No description provided for @dropLastFrameHere.
  ///
  /// In en, this message translates to:
  /// **'Drop image here for end frame'**
  String get dropLastFrameHere;

  /// No description provided for @executionLogs.
  ///
  /// In en, this message translates to:
  /// **'EXECUTION LOGS'**
  String get executionLogs;

  /// No description provided for @saveToPhotos.
  ///
  /// In en, this message translates to:
  /// **'Save to Photos'**
  String get saveToPhotos;

  /// No description provided for @saveToGallery.
  ///
  /// In en, this message translates to:
  /// **'Save to Gallery'**
  String get saveToGallery;

  /// No description provided for @savedToPhotos.
  ///
  /// In en, this message translates to:
  /// **'Saved to Photos'**
  String get savedToPhotos;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailed(String error);

  /// No description provided for @iosSandboxActive.
  ///
  /// In en, this message translates to:
  /// **'iOS Sandbox Active'**
  String get iosSandboxActive;

  /// No description provided for @iosSandboxDesc.
  ///
  /// In en, this message translates to:
  /// **'On iOS, please use the \'Import from Gallery\' button in the top toolbar to add images to your Temporary Workspace.'**
  String get iosSandboxDesc;

  /// No description provided for @mobileSandboxActive.
  ///
  /// In en, this message translates to:
  /// **'Mobile Storage Restriction'**
  String get mobileSandboxActive;

  /// No description provided for @mobileSandboxDesc.
  ///
  /// In en, this message translates to:
  /// **'On mobile devices, direct folder access may be limited by the OS. It is recommended to use the \'Import from Gallery\' button in the top toolbar.'**
  String get mobileSandboxDesc;

  /// No description provided for @filesAppSuffix.
  ///
  /// In en, this message translates to:
  /// **' (Files App)'**
  String get filesAppSuffix;

  /// No description provided for @tapToPick.
  ///
  /// In en, this message translates to:
  /// **'Tap to Pick'**
  String get tapToPick;

  /// No description provided for @goToGallery.
  ///
  /// In en, this message translates to:
  /// **'Go to Gallery'**
  String get goToGallery;

  /// No description provided for @binaryModeActive.
  ///
  /// In en, this message translates to:
  /// **'Binary mode active — background hidden for clean mask export'**
  String get binaryModeActive;

  /// No description provided for @imageSizePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Image Size'**
  String get imageSizePickerTitle;

  /// No description provided for @imageSizeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get imageSizeAuto;

  /// No description provided for @imageSizeAutoDesc.
  ///
  /// In en, this message translates to:
  /// **'Let the model choose the size'**
  String get imageSizeAutoDesc;

  /// No description provided for @imageSizePresets.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get imageSizePresets;

  /// No description provided for @imageSizeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get imageSizeCustom;

  /// No description provided for @imageSizeWidth.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get imageSizeWidth;

  /// No description provided for @imageSizeHeight.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get imageSizeHeight;

  /// No description provided for @imageSizeSnapHint.
  ///
  /// In en, this message translates to:
  /// **'Both edges snap to multiples of 16 px on commit.'**
  String get imageSizeSnapHint;

  /// No description provided for @sizeRuleMultiple16.
  ///
  /// In en, this message translates to:
  /// **'Both edges are multiples of 16'**
  String get sizeRuleMultiple16;

  /// No description provided for @sizeRuleMaxEdge.
  ///
  /// In en, this message translates to:
  /// **'Longest edge {long} px ≤ 3840'**
  String sizeRuleMaxEdge(int long);

  /// No description provided for @sizeRuleAspect.
  ///
  /// In en, this message translates to:
  /// **'Aspect ratio {ratio} ≤ 3:1'**
  String sizeRuleAspect(String ratio);

  /// No description provided for @sizeRulePixels.
  ///
  /// In en, this message translates to:
  /// **'Total {mp} within 0.66–8.29 MP'**
  String sizeRulePixels(String mp);

  /// No description provided for @safetySettings.
  ///
  /// In en, this message translates to:
  /// **'Safety Settings'**
  String get safetySettings;

  /// No description provided for @safetySettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Gemini content-filter thresholds, applied to every request (strict → permissive). Not supported by Veo/Imagen.'**
  String get safetySettingsDesc;

  /// No description provided for @safetyCategoryHarassment.
  ///
  /// In en, this message translates to:
  /// **'Harassment'**
  String get safetyCategoryHarassment;

  /// No description provided for @safetyCategoryHateSpeech.
  ///
  /// In en, this message translates to:
  /// **'Hate speech'**
  String get safetyCategoryHateSpeech;

  /// No description provided for @safetyCategorySexuallyExplicit.
  ///
  /// In en, this message translates to:
  /// **'Sexually explicit'**
  String get safetyCategorySexuallyExplicit;

  /// No description provided for @safetyCategoryDangerousContent.
  ///
  /// In en, this message translates to:
  /// **'Dangerous content'**
  String get safetyCategoryDangerousContent;

  /// No description provided for @safetyThresholdBlockLowAndAbove.
  ///
  /// In en, this message translates to:
  /// **'Block most'**
  String get safetyThresholdBlockLowAndAbove;

  /// No description provided for @safetyThresholdBlockMediumAndAbove.
  ///
  /// In en, this message translates to:
  /// **'Block some'**
  String get safetyThresholdBlockMediumAndAbove;

  /// No description provided for @safetyThresholdBlockOnlyHigh.
  ///
  /// In en, this message translates to:
  /// **'Block few'**
  String get safetyThresholdBlockOnlyHigh;

  /// No description provided for @safetyThresholdBlockNone.
  ///
  /// In en, this message translates to:
  /// **'Block none'**
  String get safetyThresholdBlockNone;

  /// No description provided for @safetyThresholdOff.
  ///
  /// In en, this message translates to:
  /// **'Filter off'**
  String get safetyThresholdOff;

  /// No description provided for @optModeSystemPrompt.
  ///
  /// In en, this message translates to:
  /// **'System Prompt'**
  String get optModeSystemPrompt;

  /// No description provided for @optModeKnowledge.
  ///
  /// In en, this message translates to:
  /// **'Knowledge Base'**
  String get optModeKnowledge;

  /// No description provided for @knowledgeBase.
  ///
  /// In en, this message translates to:
  /// **'Knowledge Base'**
  String get knowledgeBase;

  /// No description provided for @optKbNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Knowledge base is not configured or invalid — choose its folder in Settings first.'**
  String get optKbNotConfigured;

  /// No description provided for @optModeSwitchConfirm.
  ///
  /// In en, this message translates to:
  /// **'Switching the mode starts a new conversation. Continue?'**
  String get optModeSwitchConfirm;

  /// No description provided for @optToolListKnowledge.
  ///
  /// In en, this message translates to:
  /// **'Browsed knowledge base files'**
  String get optToolListKnowledge;

  /// No description provided for @optToolReadKnowledge.
  ///
  /// In en, this message translates to:
  /// **'Read knowledge: {name}'**
  String optToolReadKnowledge(String name);

  /// No description provided for @optHistory.
  ///
  /// In en, this message translates to:
  /// **'Conversation History'**
  String get optHistory;

  /// No description provided for @optNoHistory.
  ///
  /// In en, this message translates to:
  /// **'No saved conversations yet'**
  String get optNoHistory;

  /// No description provided for @optDeleteSessionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this conversation permanently?'**
  String get optDeleteSessionConfirm;

  /// No description provided for @optCompactedNotice.
  ///
  /// In en, this message translates to:
  /// **'Earlier messages were compacted into a summary to save context.'**
  String get optCompactedNotice;

  /// No description provided for @optImageMissing.
  ///
  /// In en, this message translates to:
  /// **'Some reference images of this conversation no longer exist — re-add them to continue using them.'**
  String get optImageMissing;

  /// No description provided for @optRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get optRetry;

  /// No description provided for @optModeKnowledgeEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit KB'**
  String get optModeKnowledgeEdit;

  /// No description provided for @optToolWriteKnowledge.
  ///
  /// In en, this message translates to:
  /// **'Proposed knowledge update: {name}'**
  String optToolWriteKnowledge(String name);

  /// No description provided for @kbEditProposedCreate.
  ///
  /// In en, this message translates to:
  /// **'New file'**
  String get kbEditProposedCreate;

  /// No description provided for @kbEditProposedUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update file'**
  String get kbEditProposedUpdate;

  /// No description provided for @kbEditApply.
  ///
  /// In en, this message translates to:
  /// **'Write file'**
  String get kbEditApply;

  /// No description provided for @kbEditReject.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get kbEditReject;

  /// No description provided for @kbEditApplied.
  ///
  /// In en, this message translates to:
  /// **'Written to disk'**
  String get kbEditApplied;

  /// No description provided for @kbEditRejected.
  ///
  /// In en, this message translates to:
  /// **'Discarded'**
  String get kbEditRejected;

  /// No description provided for @kbEditFailedShort.
  ///
  /// In en, this message translates to:
  /// **'Write failed'**
  String get kbEditFailedShort;

  /// No description provided for @kbEditShow.
  ///
  /// In en, this message translates to:
  /// **'Show content ({chars} chars)'**
  String kbEditShow(int chars);

  /// No description provided for @kbEditHide.
  ///
  /// In en, this message translates to:
  /// **'Hide content'**
  String get kbEditHide;

  /// No description provided for @kbEditShrinkWarning.
  ///
  /// In en, this message translates to:
  /// **'The new content is much shorter than the current file ({oldChars} → {newChars} chars). Check it is complete before writing.'**
  String kbEditShrinkWarning(int oldChars, int newChars);

  /// No description provided for @kbEditFailed.
  ///
  /// In en, this message translates to:
  /// **'Write failed: {error}'**
  String kbEditFailed(String error);

  /// No description provided for @kbScaffoldAlreadyInit.
  ///
  /// In en, this message translates to:
  /// **'Already initialized — this folder has a {name} and will not be touched.'**
  String kbScaffoldAlreadyInit(String name);

  /// No description provided for @kbScaffoldCreate.
  ///
  /// In en, this message translates to:
  /// **'Initialize knowledge base'**
  String get kbScaffoldCreate;

  /// No description provided for @kbScaffoldConfirm.
  ///
  /// In en, this message translates to:
  /// **'Initialize {path} as a knowledge base? Sample rule files will be created there.'**
  String kbScaffoldConfirm(String path);

  /// No description provided for @kbScaffoldDone.
  ///
  /// In en, this message translates to:
  /// **'Knowledge base initialized: {created} file(s) created.'**
  String kbScaffoldDone(int created);

  /// No description provided for @kbScaffoldFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create the knowledge base: {error}'**
  String kbScaffoldFailed(String error);
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
      <String>['en', 'ja', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
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
