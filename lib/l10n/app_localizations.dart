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

  /// No description provided for @generateSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Generate Suggestions'**
  String get generateSuggestions;

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

  /// No description provided for @stagingArea.
  ///
  /// In en, this message translates to:
  /// **'Staging'**
  String get stagingArea;

  /// No description provided for @addToStaging.
  ///
  /// In en, this message translates to:
  /// **'Add to Staging'**
  String get addToStaging;

  /// No description provided for @removeFromStaging.
  ///
  /// In en, this message translates to:
  /// **'Remove from Staging'**
  String get removeFromStaging;

  /// No description provided for @stagedBadge.
  ///
  /// In en, this message translates to:
  /// **'Staged'**
  String get stagedBadge;

  /// No description provided for @clearStaging.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearStaging;

  /// No description provided for @stagingEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Staging is empty'**
  String get stagingEmptyTitle;

  /// No description provided for @stagingEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'Pick files and hit Add to Staging to note down what you want to move. It only marks them - nothing is moved. Switching folders, filtering, or restarting the app will not lose it.'**
  String get stagingEmptyDesc;

  /// No description provided for @stagingTarget.
  ///
  /// In en, this message translates to:
  /// **'DESTINATION'**
  String get stagingTarget;

  /// No description provided for @stagingNoTarget.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get stagingNoTarget;

  /// No description provided for @stagingTargetHint.
  ///
  /// In en, this message translates to:
  /// **'Right-click a folder in the left column and choose Move / Copy here, or drag files onto a folder.'**
  String get stagingTargetHint;

  /// No description provided for @stagingRestored.
  ///
  /// In en, this message translates to:
  /// **'Restored {count} from the last session'**
  String stagingRestored(int count);

  /// No description provided for @stagingSameAsTarget.
  ///
  /// In en, this message translates to:
  /// **'Already here - will be skipped'**
  String get stagingSameAsTarget;

  /// No description provided for @stagingMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get stagingMissing;

  /// No description provided for @stagingClearMissing.
  ///
  /// In en, this message translates to:
  /// **'Remove missing ({count})'**
  String stagingClearMissing(int count);

  /// No description provided for @moveHere.
  ///
  /// In en, this message translates to:
  /// **'Move here'**
  String get moveHere;

  /// No description provided for @copyHere.
  ///
  /// In en, this message translates to:
  /// **'Copy here'**
  String get copyHere;

  /// No description provided for @moveCountHere.
  ///
  /// In en, this message translates to:
  /// **'Move {count} here'**
  String moveCountHere(int count);

  /// No description provided for @copyCountHere.
  ///
  /// In en, this message translates to:
  /// **'Copy {count} here'**
  String copyCountHere(int count);

  /// No description provided for @stagingItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String stagingItemsCount(int count);

  /// No description provided for @stagingMissingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} missing'**
  String stagingMissingCount(int count);

  /// No description provided for @stagingAtTargetCount.
  ///
  /// In en, this message translates to:
  /// **'{count} already there (skipped)'**
  String stagingAtTargetCount(int count);

  /// No description provided for @onlyThisDirectory.
  ///
  /// In en, this message translates to:
  /// **'Show only this folder'**
  String get onlyThisDirectory;

  /// No description provided for @pasteNoDestination.
  ///
  /// In en, this message translates to:
  /// **'Pick a destination folder first'**
  String get pasteNoDestination;

  /// No description provided for @pasteDestinationGone.
  ///
  /// In en, this message translates to:
  /// **'The destination folder no longer exists'**
  String get pasteDestinationGone;

  /// No description provided for @pasteNothingToDo.
  ///
  /// In en, this message translates to:
  /// **'Nothing to transfer'**
  String get pasteNothingToDo;

  /// No description provided for @conflictsTitle.
  ///
  /// In en, this message translates to:
  /// **'Name conflicts'**
  String get conflictsTitle;

  /// No description provided for @conflictSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get conflictSkip;

  /// No description provided for @conflictOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get conflictOverwrite;

  /// No description provided for @conflictRename.
  ///
  /// In en, this message translates to:
  /// **'Keep both'**
  String get conflictRename;

  /// No description provided for @conflictReasonExists.
  ///
  /// In en, this message translates to:
  /// **'Already in the destination'**
  String get conflictReasonExists;

  /// No description provided for @conflictReasonDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Another staged file has this name'**
  String get conflictReasonDuplicate;

  /// No description provided for @conflictReasonSameLocation.
  ///
  /// In en, this message translates to:
  /// **'Already in this folder'**
  String get conflictReasonSameLocation;

  /// No description provided for @conflictReasonMissing.
  ///
  /// In en, this message translates to:
  /// **'Source file is gone'**
  String get conflictReasonMissing;

  /// No description provided for @pasteProgressCount.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total}'**
  String pasteProgressCount(int done, int total);

  /// No description provided for @pasteCancelledTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfer cancelled'**
  String get pasteCancelledTitle;

  /// No description provided for @pasteSucceededCount.
  ///
  /// In en, this message translates to:
  /// **'{count} transferred'**
  String pasteSucceededCount(int count);

  /// No description provided for @pasteSkippedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} skipped'**
  String pasteSkippedCount(int count);

  /// No description provided for @pasteFailedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} failed'**
  String pasteFailedCount(int count);

  /// No description provided for @renameSubtitleFiles.
  ///
  /// In en, this message translates to:
  /// **'{files} files from {dirs} folders'**
  String renameSubtitleFiles(int files, int dirs);

  /// No description provided for @renameSectionModel.
  ///
  /// In en, this message translates to:
  /// **'MODEL'**
  String get renameSectionModel;

  /// No description provided for @renameSectionTemplate.
  ///
  /// In en, this message translates to:
  /// **'NAMING TEMPLATE'**
  String get renameSectionTemplate;

  /// No description provided for @renameSectionInstructions.
  ///
  /// In en, this message translates to:
  /// **'EXTRA INSTRUCTIONS'**
  String get renameSectionInstructions;

  /// No description provided for @renameBatchEstimate.
  ///
  /// In en, this message translates to:
  /// **'{files} files · {size} per batch · {batches} batches'**
  String renameBatchEstimate(int files, int size, int batches);

  /// No description provided for @renameStopGenerating.
  ///
  /// In en, this message translates to:
  /// **'Stop generating'**
  String get renameStopGenerating;

  /// No description provided for @renameRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get renameRegenerate;

  /// No description provided for @renameFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get renameFilterAll;

  /// No description provided for @renameFilterConflicts.
  ///
  /// In en, this message translates to:
  /// **'Conflicts'**
  String get renameFilterConflicts;

  /// No description provided for @renameFilterSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get renameFilterSkipped;

  /// No description provided for @renameNextConflict.
  ///
  /// In en, this message translates to:
  /// **'Next conflict'**
  String get renameNextConflict;

  /// No description provided for @renameEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No suggestions yet'**
  String get renameEmptyTitle;

  /// No description provided for @renameEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'Pick a model and a naming template on the left, then Generate. The {files} files go out in {batches} batches of {size}; you can start reviewing while the rest are still coming.'**
  String renameEmptyDesc(int files, int batches, int size);

  /// No description provided for @renameGenerating.
  ///
  /// In en, this message translates to:
  /// **'Generating suggestions'**
  String get renameGenerating;

  /// No description provided for @renameBatchProgress.
  ///
  /// In en, this message translates to:
  /// **'Batch {batch} / {total} · {done} / {files} produced'**
  String renameBatchProgress(int batch, int total, int done, int files);

  /// No description provided for @renameStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get renameStop;

  /// No description provided for @renameProducedHint.
  ///
  /// In en, this message translates to:
  /// **'{count} produced · reviewable now, applied once generation finishes'**
  String renameProducedHint(int count);

  /// No description provided for @renameSuggestionsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} suggestions'**
  String renameSuggestionsCount(int count);

  /// No description provided for @renameSkippedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} skipped'**
  String renameSkippedCount(int count);

  /// No description provided for @renameConflictsPending.
  ///
  /// In en, this message translates to:
  /// **'{count} conflicts unresolved · they will not be applied'**
  String renameConflictsPending(int count);

  /// No description provided for @renameApplyCount.
  ///
  /// In en, this message translates to:
  /// **'Apply {count} renames'**
  String renameApplyCount(int count);

  /// No description provided for @renameApplyShort.
  ///
  /// In en, this message translates to:
  /// **'Apply {count}'**
  String renameApplyShort(int count);

  /// No description provided for @renameDuplicateBadge.
  ///
  /// In en, this message translates to:
  /// **'Name taken'**
  String get renameDuplicateBadge;

  /// No description provided for @renameSkippedBadge.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get renameSkippedBadge;

  /// No description provided for @renameRenamedBadge.
  ///
  /// In en, this message translates to:
  /// **'Renamed'**
  String get renameRenamedBadge;

  /// No description provided for @renameActionSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get renameActionSkip;

  /// No description provided for @renameActionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit name'**
  String get renameActionEdit;

  /// No description provided for @renameActionUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo skip'**
  String get renameActionUndo;

  /// No description provided for @renameConflictAutoRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameConflictAutoRename;

  /// No description provided for @renameNoModelsTitle.
  ///
  /// In en, this message translates to:
  /// **'No chat model available'**
  String get renameNoModelsTitle;

  /// No description provided for @renameNoModelsDesc.
  ///
  /// In en, this message translates to:
  /// **'Batch renaming needs a chat model to read the pictures and write the names. Configure at least one working channel under Models and Channels first.'**
  String get renameNoModelsDesc;

  /// No description provided for @renameGoToSettings.
  ///
  /// In en, this message translates to:
  /// **'Go to settings'**
  String get renameGoToSettings;

  /// No description provided for @renameBatchFailedDesc.
  ///
  /// In en, this message translates to:
  /// **'The {kept} suggestions produced so far are kept; the {missing} files with no name can be retried on their own.'**
  String renameBatchFailedDesc(int kept, int missing);

  /// No description provided for @renameRetryBatch.
  ///
  /// In en, this message translates to:
  /// **'Retry these'**
  String get renameRetryBatch;

  /// No description provided for @renameEditConfig.
  ///
  /// In en, this message translates to:
  /// **'Edit config'**
  String get renameEditConfig;

  /// No description provided for @renameTemplateLabel.
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get renameTemplateLabel;

  /// No description provided for @pasteMovingCount.
  ///
  /// In en, this message translates to:
  /// **'Moving {count} items'**
  String pasteMovingCount(int count);

  /// No description provided for @pasteCopyingCount.
  ///
  /// In en, this message translates to:
  /// **'Copying {count} items'**
  String pasteCopyingCount(int count);

  /// No description provided for @pasteRoute.
  ///
  /// In en, this message translates to:
  /// **'{from_} to {to}'**
  String pasteRoute(String from_, String to);

  /// No description provided for @pasteCrossVolumeTag.
  ///
  /// In en, this message translates to:
  /// **'across drives'**
  String get pasteCrossVolumeTag;

  /// No description provided for @pasteCurrentFile.
  ///
  /// In en, this message translates to:
  /// **'Copying {name}'**
  String pasteCurrentFile(String name);

  /// No description provided for @pasteRollbackNote.
  ///
  /// In en, this message translates to:
  /// **'A cross-drive move runs as copy then delete. Cancelling deletes the copy that was in flight and leaves the source where it is.'**
  String get pasteRollbackNote;

  /// No description provided for @pasteRunInBackground.
  ///
  /// In en, this message translates to:
  /// **'Run in background'**
  String get pasteRunInBackground;

  /// No description provided for @pasteMoveDone.
  ///
  /// In en, this message translates to:
  /// **'Move finished'**
  String get pasteMoveDone;

  /// No description provided for @pasteCopyDone.
  ///
  /// In en, this message translates to:
  /// **'Copy finished'**
  String get pasteCopyDone;

  /// No description provided for @pasteElapsed.
  ///
  /// In en, this message translates to:
  /// **'{count} items · {time}'**
  String pasteElapsed(int count, String time);

  /// No description provided for @pasteStatSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Transferred'**
  String get pasteStatSucceeded;

  /// No description provided for @pasteStatSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped (already there)'**
  String get pasteStatSkipped;

  /// No description provided for @pasteStatFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get pasteStatFailed;

  /// No description provided for @pasteRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get pasteRetry;

  /// No description provided for @pasteKeptInStaging.
  ///
  /// In en, this message translates to:
  /// **'The {kept} failed or skipped items stay in Staging; the {moved} that went through were taken out.'**
  String pasteKeptInStaging(int kept, int moved);

  /// No description provided for @pasteExportLog.
  ///
  /// In en, this message translates to:
  /// **'Export log'**
  String get pasteExportLog;

  /// No description provided for @pasteLogSaved.
  ///
  /// In en, this message translates to:
  /// **'Log saved to {path}'**
  String pasteLogSaved(String path);

  /// No description provided for @conflictsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} clash with names in {folder}'**
  String conflictsSubtitle(int count, int total, String folder);

  /// No description provided for @conflictsIntro.
  ///
  /// In en, this message translates to:
  /// **'Choose what to do with each, or tick the box below to apply one answer to the rest.'**
  String get conflictsIntro;

  /// No description provided for @conflictPending.
  ///
  /// In en, this message translates to:
  /// **'Undecided'**
  String get conflictPending;

  /// No description provided for @conflictOverwriteWarning.
  ///
  /// In en, this message translates to:
  /// **'The file there will be replaced. This cannot be undone.'**
  String get conflictOverwriteWarning;

  /// No description provided for @conflictApplyRestCount.
  ///
  /// In en, this message translates to:
  /// **'Apply the same answer to the remaining {count}'**
  String conflictApplyRestCount(int count);

  /// No description provided for @conflictApplyAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Apply and continue'**
  String get conflictApplyAndContinue;

  /// No description provided for @showInSystem.
  ///
  /// In en, this message translates to:
  /// **'Show in system'**
  String get showInSystem;

  /// No description provided for @newSubfolder.
  ///
  /// In en, this message translates to:
  /// **'New subfolder'**
  String get newSubfolder;

  /// No description provided for @newFolderDefaultName.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get newFolderDefaultName;

  /// No description provided for @moveFolderTo.
  ///
  /// In en, this message translates to:
  /// **'Move to…'**
  String get moveFolderTo;

  /// No description provided for @removeFromList.
  ///
  /// In en, this message translates to:
  /// **'Remove from list'**
  String get removeFromList;

  /// No description provided for @rootCannotMove.
  ///
  /// In en, this message translates to:
  /// **'Root folders cannot be moved'**
  String get rootCannotMove;

  /// No description provided for @deleteFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete folder?'**
  String get deleteFolderTitle;

  /// No description provided for @trashFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to trash?'**
  String get trashFolderTitle;

  /// No description provided for @deleteFolderEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty. Deleting it cannot be undone.'**
  String get deleteFolderEmptyDesc;

  /// No description provided for @trashFolderEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty. It can be restored from the system trash.'**
  String get trashFolderEmptyDesc;

  /// No description provided for @deleteFolderIrreversible.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone'**
  String get deleteFolderIrreversible;

  /// No description provided for @trashFolderRestorable.
  ///
  /// In en, this message translates to:
  /// **'Can be restored from the system trash'**
  String get trashFolderRestorable;

  /// No description provided for @inventorySubfolders.
  ///
  /// In en, this message translates to:
  /// **'Subfolders'**
  String get inventorySubfolders;

  /// No description provided for @inventoryFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get inventoryFiles;

  /// No description provided for @inventorySize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get inventorySize;

  /// No description provided for @inventoryCounting.
  ///
  /// In en, this message translates to:
  /// **'Counting…'**
  String get inventoryCounting;

  /// No description provided for @deleteFolderCount.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} items'**
  String deleteFolderCount(int count);

  /// No description provided for @trashFolderCount.
  ///
  /// In en, this message translates to:
  /// **'Move {count} items to trash'**
  String trashFolderCount(int count);

  /// No description provided for @moveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get moveToTrash;

  /// No description provided for @folderNameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Name cannot be empty'**
  String get folderNameEmpty;

  /// No description provided for @folderNameIllegalChars.
  ///
  /// In en, this message translates to:
  /// **'Name cannot contain {chars}'**
  String folderNameIllegalChars(String chars);

  /// No description provided for @folderNameReserved.
  ///
  /// In en, this message translates to:
  /// **'This name is reserved by the system'**
  String get folderNameReserved;

  /// No description provided for @folderNameExists.
  ///
  /// In en, this message translates to:
  /// **'A folder with this name already exists'**
  String get folderNameExists;

  /// No description provided for @folderPathRegistered.
  ///
  /// In en, this message translates to:
  /// **'This path is already in the list'**
  String get folderPathRegistered;

  /// No description provided for @moveFolderIntoSelf.
  ///
  /// In en, this message translates to:
  /// **'A folder cannot be moved into itself'**
  String get moveFolderIntoSelf;

  /// No description provided for @moveFolderSameParent.
  ///
  /// In en, this message translates to:
  /// **'The folder is already there'**
  String get moveFolderSameParent;

  /// No description provided for @moveFolderTargetExists.
  ///
  /// In en, this message translates to:
  /// **'The destination already has an entry with this name'**
  String get moveFolderTargetExists;

  /// No description provided for @dragMoveFolderHint.
  ///
  /// In en, this message translates to:
  /// **'Move “{name}”'**
  String dragMoveFolderHint(String name);

  /// No description provided for @dragCopyFolderHint.
  ///
  /// In en, this message translates to:
  /// **'Copy “{name}”'**
  String dragCopyFolderHint(String name);

  /// No description provided for @folderMovingTitle.
  ///
  /// In en, this message translates to:
  /// **'Moving folder {name}'**
  String folderMovingTitle(String name);

  /// No description provided for @folderCopyingTitle.
  ///
  /// In en, this message translates to:
  /// **'Copying folder {name}'**
  String folderCopyingTitle(String name);

  /// No description provided for @folderTransferItems.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String folderTransferItems(int count);

  /// No description provided for @folderMoveCrossVolumeNote.
  ///
  /// In en, this message translates to:
  /// **'A different drive. The folder is copied first and the source is removed only after everything has arrived, so cancelling never loses anything.'**
  String get folderMoveCrossVolumeNote;

  /// No description provided for @folderMoveCancelledTitle.
  ///
  /// In en, this message translates to:
  /// **'Move cancelled'**
  String get folderMoveCancelledTitle;

  /// No description provided for @folderCopyCancelledTitle.
  ///
  /// In en, this message translates to:
  /// **'Copy cancelled'**
  String get folderCopyCancelledTitle;

  /// No description provided for @folderTransferStoppedAt.
  ///
  /// In en, this message translates to:
  /// **'stopped at {done} / {total} items'**
  String folderTransferStoppedAt(int done, int total);

  /// No description provided for @folderMoveStatCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to destination'**
  String get folderMoveStatCopied;

  /// No description provided for @folderMoveStatPending.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get folderMoveStatPending;

  /// No description provided for @folderMoveStatSourceKept.
  ///
  /// In en, this message translates to:
  /// **'Kept in source'**
  String get folderMoveStatSourceKept;

  /// No description provided for @folderMoveCancelledDesc.
  ///
  /// In en, this message translates to:
  /// **'The source folder is untouched. The files already copied stay in the destination; drop the folder again later and same-name files will be handled one by one.'**
  String get folderMoveCancelledDesc;

  /// No description provided for @showDestinationInSystem.
  ///
  /// In en, this message translates to:
  /// **'Show destination in system'**
  String get showDestinationInSystem;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @folderCreated.
  ///
  /// In en, this message translates to:
  /// **'Created {name}'**
  String folderCreated(String name);

  /// No description provided for @folderRenamed.
  ///
  /// In en, this message translates to:
  /// **'Renamed to {name}'**
  String folderRenamed(String name);

  /// No description provided for @folderDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted {name}'**
  String folderDeleted(String name);

  /// No description provided for @folderTrashed.
  ///
  /// In en, this message translates to:
  /// **'Moved {name} to trash'**
  String folderTrashed(String name);

  /// No description provided for @folderMoved.
  ///
  /// In en, this message translates to:
  /// **'Moved {name} to {target}'**
  String folderMoved(String name, String target);

  /// No description provided for @folderCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied {name} to {target}'**
  String folderCopied(String name, String target);

  /// No description provided for @folderOpFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed: {error}'**
  String folderOpFailed(String error);

  /// No description provided for @browserViewGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get browserViewGrid;

  /// No description provided for @browserViewList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get browserViewList;

  /// No description provided for @browserSearchEscHint.
  ///
  /// In en, this message translates to:
  /// **'Esc to clear'**
  String get browserSearchEscHint;

  /// No description provided for @browserNoFilesHint.
  ///
  /// In en, this message translates to:
  /// **'Try another filter, or clear the search'**
  String get browserNoFilesHint;

  /// No description provided for @browserFoldersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} folders'**
  String browserFoldersCount(int count);

  /// No description provided for @browserScanningCount.
  ///
  /// In en, this message translates to:
  /// **'Scanning {count} files…'**
  String browserScanningCount(int count);

  /// No description provided for @browserDragFootnote.
  ///
  /// In en, this message translates to:
  /// **'Drag onto a folder to move · hold Ctrl to copy'**
  String get browserDragFootnote;

  /// No description provided for @stagingDropHint.
  ///
  /// In en, this message translates to:
  /// **'Drop files on a folder in the left column to stage them'**
  String get stagingDropHint;

  /// No description provided for @renameBatchFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch {batch} failed'**
  String renameBatchFailedTitle(int batch);

  /// No description provided for @conflictIncoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get conflictIncoming;

  /// No description provided for @conflictAlreadyThere.
  ///
  /// In en, this message translates to:
  /// **'Already there'**
  String get conflictAlreadyThere;

  /// No description provided for @conflictUndecidedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} undecided'**
  String conflictUndecidedCount(int count);

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

  /// No description provided for @minimizeWindow.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get minimizeWindow;

  /// No description provided for @maximizeWindow.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get maximizeWindow;

  /// No description provided for @restoreWindow.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreWindow;

  /// No description provided for @closeWindow.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeWindow;

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

  /// No description provided for @moreSheetDesktopOnlyNote.
  ///
  /// In en, this message translates to:
  /// **'File Browser and Image Downloader are available on desktop and tablet only.'**
  String get moreSheetDesktopOnlyNote;

  /// No description provided for @consoleIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get consoleIdle;

  /// No description provided for @consoleFailedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} failed'**
  String consoleFailedCount(int count);

  /// No description provided for @logSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Filter logs…'**
  String get logSearchHint;

  /// No description provided for @logLevelError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get logLevelError;

  /// No description provided for @logLevelRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get logLevelRunning;

  /// No description provided for @logLevelSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get logLevelSuccess;

  /// No description provided for @goToSettings.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings'**
  String get goToSettings;

  /// No description provided for @actionImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get actionImport;

  /// No description provided for @actionExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get actionExport;

  /// No description provided for @actionOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get actionOpen;

  /// No description provided for @actionClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get actionClear;

  /// No description provided for @actionRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get actionRun;

  /// No description provided for @actionChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get actionChange;

  /// No description provided for @experimental.
  ///
  /// In en, this message translates to:
  /// **'Experimental'**
  String get experimental;

  /// No description provided for @dropAtPosition.
  ///
  /// In en, this message translates to:
  /// **'Drop at {position}'**
  String dropAtPosition(int position);

  /// No description provided for @dropAtEnd.
  ///
  /// In en, this message translates to:
  /// **'Drop at end'**
  String get dropAtEnd;

  /// No description provided for @reorderPositionOf.
  ///
  /// In en, this message translates to:
  /// **'Position {position} of {count}'**
  String reorderPositionOf(int position, int count);

  /// No description provided for @reorderOffFiltered.
  ///
  /// In en, this message translates to:
  /// **'Reordering is off while the list is filtered. Use Move up / Move down in the row menu.'**
  String get reorderOffFiltered;

  /// No description provided for @dragKeepToScroll.
  ///
  /// In en, this message translates to:
  /// **'Keep dragging to scroll'**
  String get dragKeepToScroll;

  /// No description provided for @dropRelease.
  ///
  /// In en, this message translates to:
  /// **'Release to drop'**
  String get dropRelease;

  /// No description provided for @dropFirstFrame.
  ///
  /// In en, this message translates to:
  /// **'Drop first frame'**
  String get dropFirstFrame;

  /// No description provided for @dropLastFrame.
  ///
  /// In en, this message translates to:
  /// **'Drop last frame'**
  String get dropLastFrame;

  /// No description provided for @dropSetAsFirstFrame.
  ///
  /// In en, this message translates to:
  /// **'Set as first frame'**
  String get dropSetAsFirstFrame;

  /// No description provided for @dropSetAsLastFrame.
  ///
  /// In en, this message translates to:
  /// **'Set as last frame'**
  String get dropSetAsLastFrame;

  /// No description provided for @dropAddedToReferences.
  ///
  /// In en, this message translates to:
  /// **'Added to reference images · {count} / {max}'**
  String dropAddedToReferences(int count, int max);

  /// No description provided for @dropImagesOnly.
  ///
  /// In en, this message translates to:
  /// **'Images only'**
  String get dropImagesOnly;

  /// No description provided for @dropReferenceLimit.
  ///
  /// In en, this message translates to:
  /// **'Up to {count} reference images'**
  String dropReferenceLimit(int count);

  /// No description provided for @galleryDropSystemHint.
  ///
  /// In en, this message translates to:
  /// **'Or drag files in from your file manager'**
  String get galleryDropSystemHint;

  /// No description provided for @dropMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to {name}'**
  String dropMoveTo(String name);

  /// No description provided for @dropCopyTo.
  ///
  /// In en, this message translates to:
  /// **'Copy to {name}'**
  String dropCopyTo(String name);

  /// No description provided for @dropCopyItemsTo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Copy 1 item to {name}} other{Copy {count} items to {name}}}'**
  String dropCopyItemsTo(int count, String name);

  /// No description provided for @dragMoveItems.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Move 1 item} other{Move {count} items}}'**
  String dragMoveItems(int count);

  /// No description provided for @dragCopyItems.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Copy 1 item} other{Copy {count} items}}'**
  String dragCopyItems(int count);

  /// No description provided for @dropRejectIntoItself.
  ///
  /// In en, this message translates to:
  /// **'Can\'t move a folder into itself'**
  String get dropRejectIntoItself;

  /// No description provided for @dropRejectSameFolder.
  ///
  /// In en, this message translates to:
  /// **'Already in this folder'**
  String get dropRejectSameFolder;

  /// No description provided for @dropRejectRoot.
  ///
  /// In en, this message translates to:
  /// **'The root folder can\'t hold files'**
  String get dropRejectRoot;

  /// No description provided for @dropRejectReadOnly.
  ///
  /// In en, this message translates to:
  /// **'This folder is read-only'**
  String get dropRejectReadOnly;

  /// No description provided for @dropAddedToReferencesUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Added to reference images · {count}'**
  String dropAddedToReferencesUnlimited(int count);

  /// No description provided for @dropReplacesFrame.
  ///
  /// In en, this message translates to:
  /// **'Replaces the current frame'**
  String get dropReplacesFrame;

  /// No description provided for @dropRejectNameTaken.
  ///
  /// In en, this message translates to:
  /// **'A folder with this name is already here'**
  String get dropRejectNameTaken;

  /// No description provided for @browserDragFootnoteMac.
  ///
  /// In en, this message translates to:
  /// **'Drag onto a folder to move · hold ⌥ to copy'**
  String get browserDragFootnoteMac;

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

  /// No description provided for @downloaderFoundCount.
  ///
  /// In en, this message translates to:
  /// **'{count} found'**
  String downloaderFoundCount(int count);

  /// No description provided for @downloaderAdvancedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only applies to downloads from this screen'**
  String get downloaderAdvancedSubtitle;

  /// No description provided for @copyImageUrl.
  ///
  /// In en, this message translates to:
  /// **'Copy Image URL'**
  String get copyImageUrl;

  /// No description provided for @manualHtmlEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No HTML pasted yet'**
  String get manualHtmlEmptyTitle;

  /// No description provided for @manualHtmlEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'View the page source in your browser, select all and copy, then click Paste above.'**
  String get manualHtmlEmptyDesc;

  /// No description provided for @cookieHistoryUse.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get cookieHistoryUse;

  /// No description provided for @cookieHistoryPairs.
  ///
  /// In en, this message translates to:
  /// **'{count} pairs'**
  String cookieHistoryPairs(int count);

  /// No description provided for @cookieHistoryEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'Cookies you paste are remembered here for the same site next time.'**
  String get cookieHistoryEmptyDesc;

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

  /// No description provided for @invalidPriceValue.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid non-negative number'**
  String get invalidPriceValue;

  /// No description provided for @usageLoadingRecords.
  ///
  /// In en, this message translates to:
  /// **'Totalling usage records…'**
  String get usageLoadingRecords;

  /// No description provided for @noUsageInRangeHint.
  ///
  /// In en, this message translates to:
  /// **'Try another range, or run a task first.'**
  String get noUsageInRangeHint;

  /// No description provided for @usageLoadMoreStatus.
  ///
  /// In en, this message translates to:
  /// **'{pageSize} per page · {shown} / {total} shown'**
  String usageLoadMoreStatus(int pageSize, int shown, int total);

  /// No description provided for @models.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get models;

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

  /// No description provided for @probeChannel.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get probeChannel;

  /// No description provided for @probeOk.
  ///
  /// In en, this message translates to:
  /// **'Connected and authenticated'**
  String get probeOk;

  /// No description provided for @probeModels.
  ///
  /// In en, this message translates to:
  /// **'models found'**
  String get probeModels;

  /// No description provided for @probeConnectedNoModels.
  ///
  /// In en, this message translates to:
  /// **'Connected — this endpoint has no model list, which is normal for some relays.'**
  String get probeConnectedNoModels;

  /// No description provided for @probeAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'The endpoint answered, but rejected the API key.'**
  String get probeAuthFailed;

  /// No description provided for @probeNotAnApi.
  ///
  /// In en, this message translates to:
  /// **'The URL answered with something that is not this API (an HTML page?) — check the base URL.'**
  String get probeNotAnApi;

  /// No description provided for @probeUnreachable.
  ///
  /// In en, this message translates to:
  /// **'No answer from the endpoint'**
  String get probeUnreachable;

  /// No description provided for @probeNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Connection test is not available for this channel type.'**
  String get probeNotSupported;

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

  /// No description provided for @modelIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Model ID'**
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

  /// No description provided for @requestPriceHint.
  ///
  /// In en, this message translates to:
  /// **'Billed per successful request, independent of token usage.'**
  String get requestPriceHint;

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

  /// No description provided for @stepProvider.
  ///
  /// In en, this message translates to:
  /// **'Choose Provider'**
  String get stepProvider;

  /// No description provided for @protocolOpenAIDesc.
  ///
  /// In en, this message translates to:
  /// **'Standard OpenAI REST API compatibility'**
  String get protocolOpenAIDesc;

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

  /// No description provided for @protocolAnthropicDesc.
  ///
  /// In en, this message translates to:
  /// **'Native /v1/messages surface (Claude)'**
  String get protocolAnthropicDesc;

  /// No description provided for @midjourneyEndpointHint.
  ///
  /// In en, this message translates to:
  /// **'Host root (e.g. https://your-newapi.com). /mj/* paths are added automatically.'**
  String get midjourneyEndpointHint;

  /// No description provided for @providerDashScopeDesc.
  ///
  /// In en, this message translates to:
  /// **'dashscope.aliyuncs.com/compatible-mode · OpenAI-shaped requests · Qwen chat + native qwen-image / wan images + wan video'**
  String get providerDashScopeDesc;

  /// No description provided for @providerDashScopeCompat.
  ///
  /// In en, this message translates to:
  /// **'Alibaba DashScope (OpenAI compatible)'**
  String get providerDashScopeCompat;

  /// No description provided for @providerDashScopeNative.
  ///
  /// In en, this message translates to:
  /// **'Alibaba DashScope (native)'**
  String get providerDashScopeNative;

  /// No description provided for @providerDashScopeNativeDesc.
  ///
  /// In en, this message translates to:
  /// **'dashscope.aliyuncs.com/api/v1 · Alibaba\'s own request format · the only route for qwen-audio'**
  String get providerDashScopeNativeDesc;

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

  /// No description provided for @stepConnection.
  ///
  /// In en, this message translates to:
  /// **'Endpoint & key'**
  String get stepConnection;

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

  /// No description provided for @providerNewApiAnthropic.
  ///
  /// In en, this message translates to:
  /// **'New API (Anthropic format)'**
  String get providerNewApiAnthropic;

  /// No description provided for @providerMiniMaxAnthropic.
  ///
  /// In en, this message translates to:
  /// **'MiniMax (Anthropic format)'**
  String get providerMiniMaxAnthropic;

  /// No description provided for @providerMiniMaxDesc.
  ///
  /// In en, this message translates to:
  /// **'OpenAI-compatible /v1 endpoint'**
  String get providerMiniMaxDesc;

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

  /// No description provided for @anthropicV1Hint.
  ///
  /// In en, this message translates to:
  /// **'Hint: Anthropic endpoints usually end with \'/v1\''**
  String get anthropicV1Hint;

  /// No description provided for @dashscopeApiV1Hint.
  ///
  /// In en, this message translates to:
  /// **'Hint: DashScope native endpoints end with \'/api/v1\''**
  String get dashscopeApiV1Hint;

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

  /// No description provided for @noFeeGroups.
  ///
  /// In en, this message translates to:
  /// **'No fee groups created yet'**
  String get noFeeGroups;

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

  /// No description provided for @cardPreview.
  ///
  /// In en, this message translates to:
  /// **'Card preview'**
  String get cardPreview;

  /// No description provided for @capabilityStreamingShort.
  ///
  /// In en, this message translates to:
  /// **'Streaming'**
  String get capabilityStreamingShort;

  /// No description provided for @capabilityStandardShort.
  ///
  /// In en, this message translates to:
  /// **'Standard requests'**
  String get capabilityStandardShort;

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

  /// No description provided for @contextUnset.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get contextUnset;

  /// No description provided for @contextUnsetDesc.
  ///
  /// In en, this message translates to:
  /// **'Use conservative defaults — pick this when you do not know the model\'s real limit.'**
  String get contextUnsetDesc;

  /// No description provided for @contextSpecify.
  ///
  /// In en, this message translates to:
  /// **'Specify'**
  String get contextSpecify;

  /// No description provided for @contextUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get contextUnlimited;

  /// No description provided for @contextUnlimitedDesc.
  ///
  /// In en, this message translates to:
  /// **'Send all candidates in one request, and never cap the Prompt Assistant by window size.'**
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
  /// **'Used to batch images per request, and to budget the Prompt Assistant\'s knowledge-base reads and summarization.'**
  String get contextWindowHint;

  /// No description provided for @contextSliderHint.
  ///
  /// In en, this message translates to:
  /// **'The slider moves in 1,024-token steps from 8k to 1M. A typed value wins: the slider follows it, and rests between two presets in proportion.'**
  String get contextSliderHint;

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

  /// No description provided for @reasoningEffort.
  ///
  /// In en, this message translates to:
  /// **'Reasoning Effort'**
  String get reasoningEffort;

  /// No description provided for @reasoningEffortDesc.
  ///
  /// In en, this message translates to:
  /// **'How hard the model should think before answering. Default sends nothing (the endpoint decides); other levels cost output tokens. OpenAI- and Anthropic-format channels. On Anthropic-format channels the level goes out as output_config.effort for Claude 4.6 and later; Max is accepted only by the newest models, and a 400 naming the level means pick a lower one.'**
  String get reasoningEffortDesc;

  /// No description provided for @reasoningEffortDefault.
  ///
  /// In en, this message translates to:
  /// **'Default (send nothing)'**
  String get reasoningEffortDefault;

  /// No description provided for @reasoningEffortOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get reasoningEffortOff;

  /// No description provided for @reasoningEffortLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get reasoningEffortLow;

  /// No description provided for @reasoningEffortMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get reasoningEffortMedium;

  /// No description provided for @reasoningEffortHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get reasoningEffortHigh;

  /// No description provided for @reasoningEffortMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get reasoningEffortMax;

  /// No description provided for @reasoningEffortDefaultShort.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get reasoningEffortDefaultShort;

  /// No description provided for @reasoningEffortOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get reasoningEffortOn;

  /// No description provided for @reasoningEffortUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get reasoningEffortUnavailable;

  /// No description provided for @enableThinking.
  ///
  /// In en, this message translates to:
  /// **'Extended thinking'**
  String get enableThinking;

  /// No description provided for @enableThinkingDesc.
  ///
  /// In en, this message translates to:
  /// **'Let the model reason before answering. Costs output tokens; Anthropic-format channels only.'**
  String get enableThinkingDesc;

  /// No description provided for @enableWebSearch.
  ///
  /// In en, this message translates to:
  /// **'Host web search'**
  String get enableWebSearch;

  /// No description provided for @enableWebSearchDesc.
  ///
  /// In en, this message translates to:
  /// **'Let the provider run its own web searches mid-answer. Billed as extra tokens and fetches pages on your behalf.'**
  String get enableWebSearchDesc;

  /// No description provided for @noProviderMatch.
  ///
  /// In en, this message translates to:
  /// **'No provider matches this search'**
  String get noProviderMatch;

  /// No description provided for @apiKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'This provider needs an API key before the channel can be added'**
  String get apiKeyRequired;

  /// No description provided for @endpointRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the endpoint URL for this channel'**
  String get endpointRequired;

  /// No description provided for @probeRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get probeRetry;

  /// No description provided for @customColor.
  ///
  /// In en, this message translates to:
  /// **'Custom color'**
  String get customColor;

  /// No description provided for @channelListPreview.
  ///
  /// In en, this message translates to:
  /// **'List preview'**
  String get channelListPreview;

  /// No description provided for @pickerNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get pickerNoMatches;

  /// No description provided for @pickerMatchCount.
  ///
  /// In en, this message translates to:
  /// **'{count} shown'**
  String pickerMatchCount(int count);

  /// No description provided for @selectAChannel.
  ///
  /// In en, this message translates to:
  /// **'Select a channel'**
  String get selectAChannel;

  /// No description provided for @searchChannels.
  ///
  /// In en, this message translates to:
  /// **'Search channel name or tag...'**
  String get searchChannels;

  /// No description provided for @kindChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get kindChat;

  /// No description provided for @kindImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get kindImage;

  /// No description provided for @kindVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get kindVideo;

  /// No description provided for @kindMultimodal.
  ///
  /// In en, this message translates to:
  /// **'Multimodal'**
  String get kindMultimodal;

  /// No description provided for @reasoningChip.
  ///
  /// In en, this message translates to:
  /// **'Reasoning · {level}'**
  String reasoningChip(String level);

  /// No description provided for @webSearchChip.
  ///
  /// In en, this message translates to:
  /// **'Web search'**
  String get webSearchChip;

  /// No description provided for @viewAllImagesChip.
  ///
  /// In en, this message translates to:
  /// **'All ref images'**
  String get viewAllImagesChip;

  /// No description provided for @countGroups.
  ///
  /// In en, this message translates to:
  /// **'{count} groups'**
  String countGroups(int count);

  /// No description provided for @providerGroupVendor.
  ///
  /// In en, this message translates to:
  /// **'Vendors'**
  String get providerGroupVendor;

  /// No description provided for @providerGroupVendorHint.
  ///
  /// In en, this message translates to:
  /// **'Official · endpoint prefilled'**
  String get providerGroupVendorHint;

  /// No description provided for @providerGroupRelay.
  ///
  /// In en, this message translates to:
  /// **'Relays'**
  String get providerGroupRelay;

  /// No description provided for @providerGroupRelayHint.
  ///
  /// In en, this message translates to:
  /// **'Known protocol · your own host'**
  String get providerGroupRelayHint;

  /// No description provided for @providerGroupCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get providerGroupCustom;

  /// No description provided for @providerGroupCustomHint.
  ///
  /// In en, this message translates to:
  /// **'Your host + an explicit protocol'**
  String get providerGroupCustomHint;

  /// No description provided for @providerGroupLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get providerGroupLocal;

  /// No description provided for @providerGroupLocalHint.
  ///
  /// In en, this message translates to:
  /// **'Defaults to localhost'**
  String get providerGroupLocalHint;

  /// No description provided for @providerNeedKeyOnly.
  ///
  /// In en, this message translates to:
  /// **'Key only'**
  String get providerNeedKeyOnly;

  /// No description provided for @providerNeedEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Needs address'**
  String get providerNeedEndpoint;

  /// No description provided for @providerNeedKeyless.
  ///
  /// In en, this message translates to:
  /// **'No key'**
  String get providerNeedKeyless;

  /// No description provided for @providerCustomOpenAIDesc.
  ///
  /// In en, this message translates to:
  /// **'Any host serving the OpenAI chat surface'**
  String get providerCustomOpenAIDesc;

  /// No description provided for @providerCustomGoogleDesc.
  ///
  /// In en, this message translates to:
  /// **'Any host serving the Google GenAI surface'**
  String get providerCustomGoogleDesc;

  /// No description provided for @providerCustomAnthropicDesc.
  ///
  /// In en, this message translates to:
  /// **'Any host serving the Anthropic Messages surface'**
  String get providerCustomAnthropicDesc;

  /// No description provided for @variantTitleGoogle.
  ///
  /// In en, this message translates to:
  /// **'Access method'**
  String get variantTitleGoogle;

  /// No description provided for @variantTitleMiniMax.
  ///
  /// In en, this message translates to:
  /// **'Interface'**
  String get variantTitleMiniMax;

  /// No description provided for @variantTitleNewApi.
  ///
  /// In en, this message translates to:
  /// **'Endpoint format'**
  String get variantTitleNewApi;

  /// No description provided for @variantTitleGeneric.
  ///
  /// In en, this message translates to:
  /// **'Access method'**
  String get variantTitleGeneric;

  /// No description provided for @variantHintGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google serves the same models two ways. Switching rewrites the address below.'**
  String get variantHintGoogle;

  /// No description provided for @variantHintMiniMax.
  ///
  /// In en, this message translates to:
  /// **'MiniMax offers two interfaces; pick one — you can still change it later.'**
  String get variantHintMiniMax;

  /// No description provided for @variantHintNewApi.
  ///
  /// In en, this message translates to:
  /// **'You supply the host; the version path follows the format you pick.'**
  String get variantHintNewApi;

  /// No description provided for @variantHintGeneric.
  ///
  /// In en, this message translates to:
  /// **'Switching rewrites the address below.'**
  String get variantHintGeneric;

  /// No description provided for @variantGoogleNative.
  ///
  /// In en, this message translates to:
  /// **'GenAI native'**
  String get variantGoogleNative;

  /// No description provided for @variantGoogleOpenAI.
  ///
  /// In en, this message translates to:
  /// **'OpenAI compatible'**
  String get variantGoogleOpenAI;

  /// No description provided for @variantMiniMaxOpenAI.
  ///
  /// In en, this message translates to:
  /// **'OpenAI interface'**
  String get variantMiniMaxOpenAI;

  /// No description provided for @variantMiniMaxAnthropic.
  ///
  /// In en, this message translates to:
  /// **'Anthropic interface'**
  String get variantMiniMaxAnthropic;

  /// No description provided for @variantNewApiOpenAI.
  ///
  /// In en, this message translates to:
  /// **'OpenAI format'**
  String get variantNewApiOpenAI;

  /// No description provided for @variantNewApiGemini.
  ///
  /// In en, this message translates to:
  /// **'Gemini format'**
  String get variantNewApiGemini;

  /// No description provided for @variantNewApiAnthropic.
  ///
  /// In en, this message translates to:
  /// **'Anthropic format'**
  String get variantNewApiAnthropic;

  /// No description provided for @channelPresetLabel.
  ///
  /// In en, this message translates to:
  /// **'Provider preset'**
  String get channelPresetLabel;

  /// No description provided for @changePreset.
  ///
  /// In en, this message translates to:
  /// **'Change preset'**
  String get changePreset;

  /// No description provided for @presetUnmatched.
  ///
  /// In en, this message translates to:
  /// **'No matching preset'**
  String get presetUnmatched;

  /// No description provided for @presetUnmatchedHint.
  ///
  /// In en, this message translates to:
  /// **'This channel uses a type from an older build that is no longer offered. Leaving it alone keeps it working; Change preset overwrites the fields below.'**
  String get presetUnmatchedHint;

  /// No description provided for @presetEndpointModified.
  ///
  /// In en, this message translates to:
  /// **'Address edited'**
  String get presetEndpointModified;

  /// No description provided for @restorePresetEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Restore preset value'**
  String get restorePresetEndpoint;

  /// No description provided for @changePresetOverlayHint.
  ///
  /// In en, this message translates to:
  /// **'Picking one overwrites the protocol and address with the preset\'s values. Key, name and tag are left alone.'**
  String get changePresetOverlayHint;

  /// No description provided for @protocolField.
  ///
  /// In en, this message translates to:
  /// **'API protocol'**
  String get protocolField;

  /// No description provided for @deprecatedLabel.
  ///
  /// In en, this message translates to:
  /// **'Deprecated'**
  String get deprecatedLabel;

  /// No description provided for @apiKeyOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get apiKeyOptional;

  /// No description provided for @apiKeyLocalPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Local services usually need none'**
  String get apiKeyLocalPlaceholder;

  /// No description provided for @apiKeyLocalNote.
  ///
  /// In en, this message translates to:
  /// **'Leave it empty. If you put reverse-proxy auth in front of your local service, enter its key here.'**
  String get apiKeyLocalNote;

  /// No description provided for @searchProvidersAlias.
  ///
  /// In en, this message translates to:
  /// **'Search providers, or try “Qwen”'**
  String get searchProvidersAlias;

  /// No description provided for @providerCountSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} providers · {groups} groups'**
  String providerCountSummary(int count, int groups);

  /// No description provided for @providerVariantCount.
  ///
  /// In en, this message translates to:
  /// **'{count} ways in'**
  String providerVariantCount(int count);

  /// No description provided for @requestMethod.
  ///
  /// In en, this message translates to:
  /// **'Request Method'**
  String get requestMethod;

  /// No description provided for @interfaceProtocol.
  ///
  /// In en, this message translates to:
  /// **'API Protocol'**
  String get interfaceProtocol;

  /// No description provided for @protocolAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get protocolAuto;

  /// No description provided for @protocolAutoResolved.
  ///
  /// In en, this message translates to:
  /// **'Auto · resolves to “{name}”'**
  String protocolAutoResolved(String name);

  /// No description provided for @protocolAutoHelper.
  ///
  /// In en, this message translates to:
  /// **'Follows the channel and the model type; re-resolved automatically when either changes.'**
  String get protocolAutoHelper;

  /// No description provided for @protocolStaleHelper.
  ///
  /// In en, this message translates to:
  /// **'The previous choice “{name}” is unavailable with this provider; back to Auto.'**
  String protocolStaleHelper(String name);

  /// No description provided for @protocolOpenAICompat.
  ///
  /// In en, this message translates to:
  /// **'OpenAI-compatible'**
  String get protocolOpenAICompat;

  /// No description provided for @protocolAnthropicCompat.
  ///
  /// In en, this message translates to:
  /// **'Anthropic-compatible'**
  String get protocolAnthropicCompat;

  /// No description provided for @protocolDashScopeNative.
  ///
  /// In en, this message translates to:
  /// **'DashScope native'**
  String get protocolDashScopeNative;

  /// No description provided for @protocolDashScopeNativeDesc.
  ///
  /// In en, this message translates to:
  /// **'Alibaba\'s own request format; the only route for qwen-audio'**
  String get protocolDashScopeNativeDesc;

  /// No description provided for @protocolImageSync.
  ///
  /// In en, this message translates to:
  /// **'Synchronous'**
  String get protocolImageSync;

  /// No description provided for @protocolImageSyncDesc.
  ///
  /// In en, this message translates to:
  /// **'One request returns the image directly'**
  String get protocolImageSyncDesc;

  /// No description provided for @protocolImageAsync.
  ///
  /// In en, this message translates to:
  /// **'Async task'**
  String get protocolImageAsync;

  /// No description provided for @protocolImageAsyncDesc.
  ///
  /// In en, this message translates to:
  /// **'Submit, then poll for the result; cancellable while queued'**
  String get protocolImageAsyncDesc;

  /// No description provided for @protocolChatImage.
  ///
  /// In en, this message translates to:
  /// **'Image via chat reply'**
  String get protocolChatImage;

  /// No description provided for @protocolChatImageDesc.
  ///
  /// In en, this message translates to:
  /// **'Images come back in the chat reply; how most relays serve image models'**
  String get protocolChatImageDesc;

  /// No description provided for @protocolImagesApiDesc.
  ///
  /// In en, this message translates to:
  /// **'OpenAI\'s image endpoint, the gpt-image family'**
  String get protocolImagesApiDesc;

  /// No description provided for @protocolImagenDesc.
  ///
  /// In en, this message translates to:
  /// **'Google\'s dedicated image endpoint'**
  String get protocolImagenDesc;

  /// No description provided for @protocolVideosApiDesc.
  ///
  /// In en, this message translates to:
  /// **'OpenAI\'s video task endpoint (Sora-style)'**
  String get protocolVideosApiDesc;

  /// No description provided for @protocolVeoDesc.
  ///
  /// In en, this message translates to:
  /// **'Google\'s video task endpoint'**
  String get protocolVeoDesc;

  /// No description provided for @protocolXaiImages.
  ///
  /// In en, this message translates to:
  /// **'xAI Images'**
  String get protocolXaiImages;

  /// No description provided for @protocolXaiVideos.
  ///
  /// In en, this message translates to:
  /// **'xAI Video'**
  String get protocolXaiVideos;

  /// No description provided for @protocolMinimaxImages.
  ///
  /// In en, this message translates to:
  /// **'MiniMax Images'**
  String get protocolMinimaxImages;

  /// No description provided for @protocolMinimaxVideo.
  ///
  /// In en, this message translates to:
  /// **'MiniMax Video'**
  String get protocolMinimaxVideo;

  /// No description provided for @protocolAutoMenuDesc.
  ///
  /// In en, this message translates to:
  /// **'Follows the channel and model type; resolves to “{name}”'**
  String protocolAutoMenuDesc(String name);

  /// No description provided for @protocolUnrecognizedAuto.
  ///
  /// In en, this message translates to:
  /// **'This model ID isn\'t recognized, so it is sent the channel\'s default way. If your relay uses “{name}”, choose it here.'**
  String protocolUnrecognizedAuto(String name);

  /// No description provided for @protocolUnrecognizedSingle.
  ///
  /// In en, this message translates to:
  /// **'This model ID isn\'t recognized; parameters follow the “{name}” defaults.'**
  String protocolUnrecognizedSingle(String name);

  /// No description provided for @protocolParamsLabel.
  ///
  /// In en, this message translates to:
  /// **'Parameters'**
  String get protocolParamsLabel;

  /// No description provided for @protocolParamsNone.
  ///
  /// In en, this message translates to:
  /// **'No model-specific parameters; just the prompt and reference images'**
  String get protocolParamsNone;

  /// No description provided for @protocolParamReferenceLimit.
  ///
  /// In en, this message translates to:
  /// **'reference image limit'**
  String get protocolParamReferenceLimit;

  /// No description provided for @protocolSendVia.
  ///
  /// In en, this message translates to:
  /// **'Sent via “{name}”'**
  String protocolSendVia(String name);

  /// No description provided for @protocolOnlyOneWay.
  ///
  /// In en, this message translates to:
  /// **'· the only way this channel offers'**
  String get protocolOnlyOneWay;

  /// No description provided for @protocolNoSurface.
  ///
  /// In en, this message translates to:
  /// **'This channel uses the {format} format, which has no {kind} endpoint. The model can be saved, but won\'t appear in the workbench.'**
  String protocolNoSurface(String format, String kind);

  /// No description provided for @protocolChatImageUnlikely.
  ///
  /// In en, this message translates to:
  /// **'The {format} format rarely returns images; whether this works depends on the relay.'**
  String protocolChatImageUnlikely(String format);

  /// No description provided for @protocolStaleKindHelper.
  ///
  /// In en, this message translates to:
  /// **'The type is now “{kind}”, so the previous choice “{name}” no longer applies; back to Auto.'**
  String protocolStaleKindHelper(String kind, String name);

  /// No description provided for @protocolStreamIgnored.
  ///
  /// In en, this message translates to:
  /// **'“{name}” does not use streaming; this setting is ignored'**
  String protocolStreamIgnored(String name);

  /// No description provided for @protocolAutoSuffix.
  ///
  /// In en, this message translates to:
  /// **'· Auto'**
  String get protocolAutoSuffix;

  /// No description provided for @protocolBackToAuto.
  ///
  /// In en, this message translates to:
  /// **'Back to Auto'**
  String get protocolBackToAuto;

  /// No description provided for @contextImageUnsetDesc.
  ///
  /// In en, this message translates to:
  /// **'Image models don\'t use the context budget; leave this unset.'**
  String get contextImageUnsetDesc;

  /// No description provided for @contextVideoUnsetDesc.
  ///
  /// In en, this message translates to:
  /// **'Video models don\'t use the context budget; leave this unset.'**
  String get contextVideoUnsetDesc;

  /// No description provided for @protocolVideoTask.
  ///
  /// In en, this message translates to:
  /// **'Async video task'**
  String get protocolVideoTask;

  /// No description provided for @protocolAsyncQueueNote.
  ///
  /// In en, this message translates to:
  /// **'Submitted to the task queue and polled; can be cancelled while generating.'**
  String get protocolAsyncQueueNote;

  /// No description provided for @protocolPinStale.
  ///
  /// In en, this message translates to:
  /// **'Selection inactive'**
  String get protocolPinStale;

  /// No description provided for @protocolStaleTooltip.
  ///
  /// In en, this message translates to:
  /// **'“{name}” is unavailable; running on Auto.'**
  String protocolStaleTooltip(String name);

  /// No description provided for @channelReorderHandleTooltip.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get channelReorderHandleTooltip;

  /// No description provided for @channelOrderSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the order; the previous one is back.'**
  String get channelOrderSaveFailed;

  /// No description provided for @wizardStepCounter.
  ///
  /// In en, this message translates to:
  /// **'Step {current} / {total}'**
  String wizardStepCounter(int current, int total);

  /// No description provided for @wizardStepsAdaptNote.
  ///
  /// In en, this message translates to:
  /// **'Steps adjust to the provider\'s access method'**
  String get wizardStepsAdaptNote;

  /// No description provided for @providerNoMatchHint.
  ///
  /// In en, this message translates to:
  /// **'\"{query}\" isn\'t in the list. Use the Custom group and choose OpenAI compatible.'**
  String providerNoMatchHint(String query);

  /// No description provided for @providerUseCustom.
  ///
  /// In en, this message translates to:
  /// **'Add as custom'**
  String get providerUseCustom;

  /// No description provided for @probeSkippableNote.
  ///
  /// In en, this message translates to:
  /// **'Optional; you can still set the name and tag next'**
  String get probeSkippableNote;

  /// No description provided for @endpointPresetValue.
  ///
  /// In en, this message translates to:
  /// **'Preset value: {endpoint}'**
  String endpointPresetValue(String endpoint);

  /// No description provided for @variantResultLabel.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get variantResultLabel;

  /// No description provided for @probeOkNext.
  ///
  /// In en, this message translates to:
  /// **'You can turn on model discovery right away'**
  String get probeOkNext;

  /// No description provided for @probeNoModelsNext.
  ///
  /// In en, this message translates to:
  /// **'Endpoint and key work, but the model list is empty. Add a Model ID by hand.'**
  String get probeNoModelsNext;

  /// No description provided for @probeAuthFailedNext.
  ///
  /// In en, this message translates to:
  /// **'Check the key was copied in full and hasn\'t expired.'**
  String get probeAuthFailedNext;

  /// No description provided for @probeNotAnApiNext.
  ///
  /// In en, this message translates to:
  /// **'An HTML page came back, probably a console URL. API endpoints usually end in /v1 or /v1beta.'**
  String get probeNotAnApiNext;

  /// No description provided for @probeUnreachableNext.
  ///
  /// In en, this message translates to:
  /// **'DNS failed or timed out. Check the URL, proxy and network.'**
  String get probeUnreachableNext;

  /// No description provided for @probeNotSupportedNext.
  ///
  /// In en, this message translates to:
  /// **'This protocol has no model list; it can only be verified by submitting a task.'**
  String get probeNotSupportedNext;

  /// No description provided for @previewEmptyKeyNote.
  ///
  /// In en, this message translates to:
  /// **'No key yet. You can add it later in Edit Channel.'**
  String get previewEmptyKeyNote;

  /// No description provided for @presetShortHint.
  ///
  /// In en, this message translates to:
  /// **'Fills endpoint and protocol in one tap'**
  String get presetShortHint;

  /// No description provided for @deleteChannel.
  ///
  /// In en, this message translates to:
  /// **'Delete channel'**
  String get deleteChannel;

  /// No description provided for @discoveryOffEffect.
  ///
  /// In en, this message translates to:
  /// **'When off, Fetch Models is disabled for this channel'**
  String get discoveryOffEffect;

  /// No description provided for @protocolUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get protocolUnavailable;

  /// No description provided for @reasoningEffortUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This model takes no reasoning parameters, so the slider stays at Off. It lights up when you switch to a model that does.'**
  String get reasoningEffortUnsupported;

  /// No description provided for @modelIdRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Model ID can\'t be empty'**
  String get modelIdRequiredTitle;

  /// No description provided for @modelIdRequiredDesc.
  ///
  /// In en, this message translates to:
  /// **'It\'s the only required field; a blank name uses the ID as the display name.'**
  String get modelIdRequiredDesc;

  /// No description provided for @contextSpecifyInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive whole number; blank or 0 can\'t be saved.'**
  String get contextSpecifyInvalid;

  /// No description provided for @addModelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When adding by hand, only the ID is required'**
  String get addModelSubtitle;

  /// No description provided for @addModelIdHelper.
  ///
  /// In en, this message translates to:
  /// **'Leaving this blank blocks saving; a blank name uses the ID.'**
  String get addModelIdHelper;

  /// No description provided for @addModelDefaultsNote.
  ///
  /// In en, this message translates to:
  /// **'Protocol, context window and capability switches stay on Auto or their defaults. Add it first, run it once, then pin what needs pinning.'**
  String get addModelDefaultsNote;

  /// No description provided for @modelNameOptionalHint.
  ///
  /// In en, this message translates to:
  /// **'Can be left blank'**
  String get modelNameOptionalHint;

  /// No description provided for @moveUp.
  ///
  /// In en, this message translates to:
  /// **'Move Up'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In en, this message translates to:
  /// **'Move Down'**
  String get moveDown;

  /// No description provided for @channelReorderFootnote.
  ///
  /// In en, this message translates to:
  /// **'Hover for the handle · drag to reorder · right-click or Alt+↑/↓ does the same'**
  String get channelReorderFootnote;

  /// No description provided for @noModelsConfiguredHint.
  ///
  /// In en, this message translates to:
  /// **'Use Fetch Models to discover them, or add one by hand.'**
  String get noModelsConfiguredHint;

  /// No description provided for @addModelManually.
  ///
  /// In en, this message translates to:
  /// **'Add manually'**
  String get addModelManually;

  /// No description provided for @selectAChannelHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a channel on the left to see its models here.'**
  String get selectAChannelHint;

  /// No description provided for @noModelsMatchQuery.
  ///
  /// In en, this message translates to:
  /// **'No models match \"{query}\"'**
  String noModelsMatchQuery(String query);

  /// No description provided for @noFeeGroupsHint.
  ///
  /// In en, this message translates to:
  /// **'Create a group, then point models at it.'**
  String get noFeeGroupsHint;

  /// No description provided for @noNewModelsFoundHint.
  ///
  /// In en, this message translates to:
  /// **'Every model this channel returned is already in the list.'**
  String get noNewModelsFoundHint;

  /// No description provided for @discoveryCapabilitiesNote.
  ///
  /// In en, this message translates to:
  /// **'Discovered models carry only an ID and a type; capabilities, context window and fee group are set per model.'**
  String get discoveryCapabilitiesNote;

  /// No description provided for @deleteChannelTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete channel \"{name}\"?'**
  String deleteChannelTitle(String name);

  /// No description provided for @deleteChannelModelsNote.
  ///
  /// In en, this message translates to:
  /// **'Includes {count} models'**
  String deleteChannelModelsNote(int count);

  /// No description provided for @deleteChannelBody.
  ///
  /// In en, this message translates to:
  /// **'Workbench settings using these models become \"No model selected\"; submitted tasks are unaffected. Usage records are kept by model name.'**
  String get deleteChannelBody;

  /// No description provided for @newFeeGroup.
  ///
  /// In en, this message translates to:
  /// **'New Group'**
  String get newFeeGroup;

  /// No description provided for @cachePriceBlankPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Blank = input price'**
  String get cachePriceBlankPlaceholder;

  /// No description provided for @fetchFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get fetchFailedTitle;

  /// No description provided for @channelDefaultFeeGroup.
  ///
  /// In en, this message translates to:
  /// **'Default fee group'**
  String get channelDefaultFeeGroup;

  /// No description provided for @channelDefaultFeeGroupHint.
  ///
  /// In en, this message translates to:
  /// **'Models added to this channel start in this group'**
  String get channelDefaultFeeGroupHint;

  /// No description provided for @modelIdTakenTitle.
  ///
  /// In en, this message translates to:
  /// **'This channel already has this Model ID'**
  String get modelIdTakenTitle;

  /// No description provided for @modelIdTakenDesc.
  ///
  /// In en, this message translates to:
  /// **'A Model ID must be unique within a channel. Change the ID, or edit the model that already has it.'**
  String get modelIdTakenDesc;

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

  /// No description provided for @promptFilterSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} categories · {matches} matching'**
  String promptFilterSummary(int count, int matches);

  /// No description provided for @promptEditorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Once saved, apply it from the workbench in one click'**
  String get promptEditorSubtitle;

  /// No description provided for @categoryColorHint.
  ///
  /// In en, this message translates to:
  /// **'Colour only tells categories apart'**
  String get categoryColorHint;

  /// No description provided for @promptCount.
  ///
  /// In en, this message translates to:
  /// **'{count} prompts'**
  String promptCount(int count);

  /// No description provided for @categoryDeleteNote.
  ///
  /// In en, this message translates to:
  /// **'Deleting a category moves its prompts to General; they are not deleted.'**
  String get categoryDeleteNote;

  /// No description provided for @importFileSummary.
  ///
  /// In en, this message translates to:
  /// **'{file} · {count} items'**
  String importFileSummary(String file, int count);

  /// No description provided for @importMergeDetail.
  ///
  /// In en, this message translates to:
  /// **'Keep the existing {current}, add the new ones'**
  String importMergeDetail(int current);

  /// No description provided for @importReplaceDetail.
  ///
  /// In en, this message translates to:
  /// **'Delete the existing {current}, keep only the {count} in the file'**
  String importReplaceDetail(int current, int count);

  /// No description provided for @promptLibraryEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Save the prompts you use most in the workbench and apply them in one click next time.'**
  String get promptLibraryEmptyHint;

  /// No description provided for @colorPresets.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get colorPresets;

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

  /// No description provided for @themeColor.
  ///
  /// In en, this message translates to:
  /// **'Theme Color'**
  String get themeColor;

  /// No description provided for @themeColorHintCards.
  ///
  /// In en, this message translates to:
  /// **'Each card shows light mode on the left and dark mode on the right, drawn in the shade that mode really uses. The two shades are calibrated separately: the light one is deeper so white labels stay legible; the dark one is lighter and more saturated, with a dark ink for anything written on it.'**
  String get themeColorHintCards;

  /// No description provided for @themeColorHintDots.
  ///
  /// In en, this message translates to:
  /// **'Each theme colour comes as two calibrated shades: light mode uses the deeper one, dark mode the lighter, more saturated one. Long-press a swatch to see the values.'**
  String get themeColorHintDots;

  /// No description provided for @themeColorPair.
  ///
  /// In en, this message translates to:
  /// **'Light {light} · Dark {dark}'**
  String themeColorPair(String light, String dark);

  /// No description provided for @themeColorCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom…'**
  String get themeColorCustom;

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

  /// No description provided for @renderingGpu.
  ///
  /// In en, this message translates to:
  /// **'Rendering GPU'**
  String get renderingGpu;

  /// No description provided for @renderingGpuUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not be determined'**
  String get renderingGpuUnavailable;

  /// No description provided for @openGraphicsSettings.
  ///
  /// In en, this message translates to:
  /// **'Windows graphics settings'**
  String get openGraphicsSettings;

  /// No description provided for @reduceVisualEffects.
  ///
  /// In en, this message translates to:
  /// **'Reduce visual effects'**
  String get reduceVisualEffects;

  /// No description provided for @reduceVisualEffectsDesc.
  ///
  /// In en, this message translates to:
  /// **'Turns off the blur effects for smoother performance on integrated or low-power GPUs.'**
  String get reduceVisualEffectsDesc;

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

  /// No description provided for @clearTempFiles.
  ///
  /// In en, this message translates to:
  /// **'Clear Temporary Files'**
  String get clearTempFiles;

  /// No description provided for @clearTempFilesConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Temporary Files?'**
  String get clearTempFilesConfirmTitle;

  /// No description provided for @clearTempFilesConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Deletes {size} of masks, crop copies, downloader cache and video thumbnails. Entries in the temporary workspace that point at these files are removed with them; files in your own folders are untouched.'**
  String clearTempFilesConfirmMessage(String size);

  /// No description provided for @tempFilesCleared.
  ///
  /// In en, this message translates to:
  /// **'Freed {size}.'**
  String tempFilesCleared(String size);

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

  /// No description provided for @assistantContextRatio.
  ///
  /// In en, this message translates to:
  /// **'Assistant Summary Limit'**
  String get assistantContextRatio;

  /// No description provided for @assistantContextRatioDesc.
  ///
  /// In en, this message translates to:
  /// **'The prompt assistant summarizes the conversation once it fills this share of the model\'s context window, freeing room to keep working. Only applies to models with a context window set.'**
  String get assistantContextRatioDesc;

  /// No description provided for @kbSubAgent.
  ///
  /// In en, this message translates to:
  /// **'Knowledge Sub-agent'**
  String get kbSubAgent;

  /// No description provided for @kbSubAgentDesc.
  ///
  /// In en, this message translates to:
  /// **'Let the assistant hand knowledge-base research to a sub-agent that reads files in its own separate context, keeping the main conversation small. Experimental.'**
  String get kbSubAgentDesc;

  /// No description provided for @kbSubAgentModel.
  ///
  /// In en, this message translates to:
  /// **'Sub-agent Model'**
  String get kbSubAgentModel;

  /// No description provided for @kbSubAgentModelFollow.
  ///
  /// In en, this message translates to:
  /// **'Follow session model'**
  String get kbSubAgentModelFollow;

  /// No description provided for @kbSubAgentModelMissing.
  ///
  /// In en, this message translates to:
  /// **'The bound model no longer exists — delegation is disabled until you pick another.'**
  String get kbSubAgentModelMissing;

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

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(Object version);

  /// No description provided for @aboutGithubRepo.
  ///
  /// In en, this message translates to:
  /// **'GitHub Repository'**
  String get aboutGithubRepo;

  /// No description provided for @aboutViewSource.
  ///
  /// In en, this message translates to:
  /// **'View source code and releases'**
  String get aboutViewSource;

  /// No description provided for @aboutLicense.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get aboutLicense;

  /// No description provided for @aboutCopyright.
  ///
  /// In en, this message translates to:
  /// **'Copyright © {year} {holder}. Released under the MIT License.'**
  String aboutCopyright(Object year, Object holder);

  /// No description provided for @themeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme mode'**
  String get themeMode;

  /// No description provided for @visualEffects.
  ///
  /// In en, this message translates to:
  /// **'Effects'**
  String get visualEffects;

  /// No description provided for @settingsGroupNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications & logging'**
  String get settingsGroupNotifications;

  /// No description provided for @settingsGroupDirectories.
  ///
  /// In en, this message translates to:
  /// **'Directories'**
  String get settingsGroupDirectories;

  /// No description provided for @settingsGroupAssistant.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get settingsGroupAssistant;

  /// No description provided for @customAccentTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom theme color'**
  String get customAccentTitle;

  /// No description provided for @customAccentHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the ring or paste a hex value'**
  String get customAccentHint;

  /// No description provided for @customAccentDerived.
  ///
  /// In en, this message translates to:
  /// **'Derived pair'**
  String get customAccentDerived;

  /// No description provided for @customAccentPassed.
  ///
  /// In en, this message translates to:
  /// **'White labels hold; the button keeps white text.'**
  String get customAccentPassed;

  /// No description provided for @customAccentInkFallback.
  ///
  /// In en, this message translates to:
  /// **'White can\'t hold on this shade, so the button uses a deep ink of the same hue.'**
  String get customAccentInkFallback;

  /// No description provided for @customAccentFailed.
  ///
  /// In en, this message translates to:
  /// **'This colour can\'t meet the contrast floor.'**
  String get customAccentFailed;

  /// No description provided for @fontFollowSystem.
  ///
  /// In en, this message translates to:
  /// **'Follows the operating system'**
  String get fontFollowSystem;

  /// No description provided for @fontNotDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded'**
  String get fontNotDownloaded;

  /// No description provided for @fontDownloadedOffline.
  ///
  /// In en, this message translates to:
  /// **'Downloaded · available offline'**
  String get fontDownloadedOffline;

  /// No description provided for @languageFollowSystem.
  ///
  /// In en, this message translates to:
  /// **'Follows the system language'**
  String get languageFollowSystem;

  /// No description provided for @exportSettingsNote.
  ///
  /// In en, this message translates to:
  /// **'Directories, prompts and usage are optional; API keys are never included'**
  String get exportSettingsNote;

  /// No description provided for @clearTempFilesNote.
  ///
  /// In en, this message translates to:
  /// **'Masks · crop copies · downloader cache · video thumbnails'**
  String get clearTempFilesNote;

  /// No description provided for @resetAllSettingsNote.
  ///
  /// In en, this message translates to:
  /// **'Back to the first-run state'**
  String get resetAllSettingsNote;

  /// No description provided for @resetIrreversible.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be undone'**
  String get resetIrreversible;

  /// No description provided for @proxyAppliesToAll.
  ///
  /// In en, this message translates to:
  /// **'Applies to all channel requests'**
  String get proxyAppliesToAll;

  /// No description provided for @notificationsDesc.
  ///
  /// In en, this message translates to:
  /// **'Notify when a task finishes or fails'**
  String get notificationsDesc;

  /// No description provided for @mcpServerDesc.
  ///
  /// In en, this message translates to:
  /// **'Lets external tools call this app over MCP'**
  String get mcpServerDesc;

  /// No description provided for @mcpComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon (not in this version)'**
  String get mcpComingSoon;

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

  /// No description provided for @goToWorkbench.
  ///
  /// In en, this message translates to:
  /// **'Go to the workbench'**
  String get goToWorkbench;

  /// No description provided for @copyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get copyAll;

  /// No description provided for @copiedAll.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedAll;

  /// No description provided for @noLogsYet.
  ///
  /// In en, this message translates to:
  /// **'This task has logged nothing yet'**
  String get noLogsYet;

  /// No description provided for @sourceFiles.
  ///
  /// In en, this message translates to:
  /// **'Source files'**
  String get sourceFiles;

  /// No description provided for @requestParameters.
  ///
  /// In en, this message translates to:
  /// **'Request parameters'**
  String get requestParameters;

  /// No description provided for @outputPaths.
  ///
  /// In en, this message translates to:
  /// **'Output files'**
  String get outputPaths;

  /// No description provided for @copyError.
  ///
  /// In en, this message translates to:
  /// **'Copy the error'**
  String get copyError;

  /// No description provided for @taskTotalShort.
  ///
  /// In en, this message translates to:
  /// **'{count} total'**
  String taskTotalShort(int count);

  /// No description provided for @statusShortRunning.
  ///
  /// In en, this message translates to:
  /// **'run'**
  String get statusShortRunning;

  /// No description provided for @statusShortPending.
  ///
  /// In en, this message translates to:
  /// **'wait'**
  String get statusShortPending;

  /// No description provided for @statusShortDone.
  ///
  /// In en, this message translates to:
  /// **'done'**
  String get statusShortDone;

  /// No description provided for @statusShortFailed.
  ///
  /// In en, this message translates to:
  /// **'fail'**
  String get statusShortFailed;

  /// No description provided for @sortNewestFirst.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get sortNewestFirst;

  /// No description provided for @sortOldestFirst.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get sortOldestFirst;

  /// No description provided for @sortSection.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sortSection;

  /// No description provided for @pinActiveTasks.
  ///
  /// In en, this message translates to:
  /// **'Pin running & pending'**
  String get pinActiveTasks;

  /// No description provided for @restByCreatedTime.
  ///
  /// In en, this message translates to:
  /// **'Rest by creation time'**
  String get restByCreatedTime;

  /// No description provided for @createdAt.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get createdAt;

  /// No description provided for @cancelledByUser.
  ///
  /// In en, this message translates to:
  /// **'Cancelled · manual'**
  String get cancelledByUser;

  /// No description provided for @noRunningTasks.
  ///
  /// In en, this message translates to:
  /// **'No running tasks'**
  String get noRunningTasks;

  /// No description provided for @noPendingTasks.
  ///
  /// In en, this message translates to:
  /// **'No pending tasks'**
  String get noPendingTasks;

  /// No description provided for @noCompletedTasks.
  ///
  /// In en, this message translates to:
  /// **'No completed tasks'**
  String get noCompletedTasks;

  /// No description provided for @noFailedTasks.
  ///
  /// In en, this message translates to:
  /// **'No failed tasks'**
  String get noFailedTasks;

  /// No description provided for @filteredEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches this filter. The other {count} tasks are unaffected.'**
  String filteredEmptyHint(int count);

  /// No description provided for @viewAllTasks.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get viewAllTasks;

  /// No description provided for @durationLabel.
  ///
  /// In en, this message translates to:
  /// **'Elapsed'**
  String get durationLabel;

  /// No description provided for @clearAllTasksTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear all tasks?'**
  String get clearAllTasksTitle;

  /// No description provided for @clearAllRunningNote.
  ///
  /// In en, this message translates to:
  /// **'Includes {count} running tasks'**
  String clearAllRunningNote(int count);

  /// No description provided for @clearAllKeepsFiles.
  ///
  /// In en, this message translates to:
  /// **'Running tasks are left alone. Generated files stay in the output folder; only the queue\'s records are cleared.'**
  String get clearAllKeepsFiles;

  /// No description provided for @taskNoOutputsFailed.
  ///
  /// In en, this message translates to:
  /// **'No outputs. The task failed before writing any.'**
  String get taskNoOutputsFailed;

  /// No description provided for @noTaskLogCancelledHint.
  ///
  /// In en, this message translates to:
  /// **'The task was cancelled before it started, so it left no log.'**
  String get noTaskLogCancelledHint;

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

  /// No description provided for @stepStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get stepStorage;

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

  /// No description provided for @filenamePrefix.
  ///
  /// In en, this message translates to:
  /// **'Filename Prefix'**
  String get filenamePrefix;

  /// No description provided for @workbench.
  ///
  /// In en, this message translates to:
  /// **'Workbench'**
  String get workbench;

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

  /// No description provided for @clearTempWorkspaceConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Workspace?'**
  String get clearTempWorkspaceConfirmTitle;

  /// No description provided for @clearTempWorkspaceConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove all {count} items from the temporary workspace? The files themselves are not deleted.'**
  String clearTempWorkspaceConfirmMessage(int count);

  /// No description provided for @removeFromWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Remove from Workspace'**
  String get removeFromWorkspace;

  /// No description provided for @noImagesSelected.
  ///
  /// In en, this message translates to:
  /// **'No images selected'**
  String get noImagesSelected;

  /// No description provided for @imageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load image'**
  String get imageLoadFailed;

  /// No description provided for @selectSourceDirectory.
  ///
  /// In en, this message translates to:
  /// **'Select Source Directory'**
  String get selectSourceDirectory;

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

  /// No description provided for @thumbnailDisplay.
  ///
  /// In en, this message translates to:
  /// **'Thumbnail Display'**
  String get thumbnailDisplay;

  /// No description provided for @thumbnailFitContain.
  ///
  /// In en, this message translates to:
  /// **'Fit (whole image)'**
  String get thumbnailFitContain;

  /// No description provided for @thumbnailFitCover.
  ///
  /// In en, this message translates to:
  /// **'Fill (cropped)'**
  String get thumbnailFitCover;

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

  /// No description provided for @imageSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get imageSizeLabel;

  /// No description provided for @quality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get quality;

  /// No description provided for @promptExtend.
  ///
  /// In en, this message translates to:
  /// **'Prompt rewrite'**
  String get promptExtend;

  /// No description provided for @promptExtendOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get promptExtendOn;

  /// No description provided for @promptExtendOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get promptExtendOff;

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

  /// No description provided for @compressReferenceImages.
  ///
  /// In en, this message translates to:
  /// **'Compress Reference Images'**
  String get compressReferenceImages;

  /// No description provided for @compressReferenceImagesDesc.
  ///
  /// In en, this message translates to:
  /// **'Re-encode images over 3MB to JPEG'**
  String get compressReferenceImagesDesc;

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

  /// No description provided for @compareLayoutSideBySide.
  ///
  /// In en, this message translates to:
  /// **'Side by Side'**
  String get compareLayoutSideBySide;

  /// No description provided for @compareLayoutStacked.
  ///
  /// In en, this message translates to:
  /// **'Stacked'**
  String get compareLayoutStacked;

  /// No description provided for @compareLayoutSlider.
  ///
  /// In en, this message translates to:
  /// **'Slider'**
  String get compareLayoutSlider;

  /// No description provided for @compareSyncTransform.
  ///
  /// In en, this message translates to:
  /// **'Sync Zoom & Pan'**
  String get compareSyncTransform;

  /// No description provided for @comparatorEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Send images from the file browser or a task result, or pick two from the library'**
  String get comparatorEmptyHint;

  /// No description provided for @comparatorPickRaw.
  ///
  /// In en, this message translates to:
  /// **'Choose Before'**
  String get comparatorPickRaw;

  /// No description provided for @comparatorPickAfter.
  ///
  /// In en, this message translates to:
  /// **'Choose Result'**
  String get comparatorPickAfter;

  /// No description provided for @comparatorZoomSynced.
  ///
  /// In en, this message translates to:
  /// **'Zoom {percent}% · Synced'**
  String comparatorZoomSynced(int percent);

  /// No description provided for @comparatorZoomIndependent.
  ///
  /// In en, this message translates to:
  /// **'Zoom {percent}% · Independent'**
  String comparatorZoomIndependent(int percent);

  /// No description provided for @comparatorSizeReduction.
  ///
  /// In en, this message translates to:
  /// **'Size reduced {percent}'**
  String comparatorSizeReduction(String percent);

  /// No description provided for @comparatorSizeIncrease.
  ///
  /// In en, this message translates to:
  /// **'Size increased {percent}'**
  String comparatorSizeIncrease(String percent);

  /// No description provided for @fileSize.
  ///
  /// In en, this message translates to:
  /// **'File Size'**
  String get fileSize;

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

  /// No description provided for @overwriteConfirmSaveCopyInstead.
  ///
  /// In en, this message translates to:
  /// **'Save Copy Instead'**
  String get overwriteConfirmSaveCopyInstead;

  /// No description provided for @overwriteConfirmSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone.'**
  String get overwriteConfirmSubtitle;

  /// No description provided for @overwriteConfirmKeepOriginalHint.
  ///
  /// In en, this message translates to:
  /// **'To keep the original, use Save Copy instead.'**
  String get overwriteConfirmKeepOriginalHint;

  /// No description provided for @overwriteUnsupportedFormat.
  ///
  /// In en, this message translates to:
  /// **'Cannot overwrite a {format} file — this format can be opened but not written. Use Save Copy instead.'**
  String overwriteUnsupportedFormat(String format);

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

  /// No description provided for @cropResizeFreeRatio.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get cropResizeFreeRatio;

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

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @cropResizeOriginalInfo.
  ///
  /// In en, this message translates to:
  /// **'Original {width}×{height} · {size}'**
  String cropResizeOriginalInfo(int width, int height, String size);

  /// No description provided for @cropResizeCanvasLabel.
  ///
  /// In en, this message translates to:
  /// **'{name} (Original Preview)'**
  String cropResizeCanvasLabel(String name);

  /// No description provided for @cropResizeCropOnly.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get cropResizeCropOnly;

  /// No description provided for @cropResizeCropAndScale.
  ///
  /// In en, this message translates to:
  /// **'Crop + Scale {percent}%'**
  String cropResizeCropAndScale(int percent);

  /// No description provided for @cropResizeOutputPreview.
  ///
  /// In en, this message translates to:
  /// **'Output Preview'**
  String get cropResizeOutputPreview;

  /// No description provided for @cropResizeOutputSummary.
  ///
  /// In en, this message translates to:
  /// **'{originalSize} → {outputSize} · {operation} · {sampling}'**
  String cropResizeOutputSummary(
    String originalSize,
    String outputSize,
    String operation,
    String sampling,
  );

  /// No description provided for @cropResizeWillSaveTo.
  ///
  /// In en, this message translates to:
  /// **'Copy will save to {path}'**
  String cropResizeWillSaveTo(String path);

  /// No description provided for @cropResizeTempWorkspaceLabel.
  ///
  /// In en, this message translates to:
  /// **'Temporary Workspace'**
  String get cropResizeTempWorkspaceLabel;

  /// No description provided for @saveCopy.
  ///
  /// In en, this message translates to:
  /// **'Save Copy'**
  String get saveCopy;

  /// No description provided for @cropResizeSaveDestinationHint.
  ///
  /// In en, this message translates to:
  /// **'to Workspace'**
  String get cropResizeSaveDestinationHint;

  /// No description provided for @cropResizeResample.
  ///
  /// In en, this message translates to:
  /// **'Resample'**
  String get cropResizeResample;

  /// No description provided for @fitToWindow.
  ///
  /// In en, this message translates to:
  /// **'Fit to Window'**
  String get fitToWindow;

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

  /// No description provided for @binaryMode.
  ///
  /// In en, this message translates to:
  /// **'Binary Mode'**
  String get binaryMode;

  /// No description provided for @maskSourceCaption.
  ///
  /// In en, this message translates to:
  /// **'Mask {width}×{height}'**
  String maskSourceCaption(int width, int height);

  /// No description provided for @maskBrushBadge.
  ///
  /// In en, this message translates to:
  /// **'{color} brush · {size} px'**
  String maskBrushBadge(String color, int size);

  /// No description provided for @maskOutputLabel.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get maskOutputLabel;

  /// No description provided for @maskOutputSummary.
  ///
  /// In en, this message translates to:
  /// **'Mask {width}×{height} · PNG (black & white)'**
  String maskOutputSummary(int width, int height);

  /// No description provided for @maskCompositeOutputSummary.
  ///
  /// In en, this message translates to:
  /// **'Composite {width}×{height} · PNG'**
  String maskCompositeOutputSummary(int width, int height);

  /// No description provided for @maskWillSaveTo.
  ///
  /// In en, this message translates to:
  /// **'Mask will save to {path}'**
  String maskWillSaveTo(String path);

  /// No description provided for @maskSaveComposite.
  ///
  /// In en, this message translates to:
  /// **'Save Composite'**
  String get maskSaveComposite;

  /// No description provided for @maskSaveMask.
  ///
  /// In en, this message translates to:
  /// **'Save Mask'**
  String get maskSaveMask;

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

  /// No description provided for @roughPrompt.
  ///
  /// In en, this message translates to:
  /// **'Rough Prompt / Ideas'**
  String get roughPrompt;

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
  /// **'Send'**
  String get optSend;

  /// No description provided for @optNewSession.
  ///
  /// In en, this message translates to:
  /// **'New Conversation'**
  String get optNewSession;

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

  /// No description provided for @optPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Optimized Prompt'**
  String get optPromptTitle;

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

  /// No description provided for @imageSizeRatio.
  ///
  /// In en, this message translates to:
  /// **'Ratio'**
  String get imageSizeRatio;

  /// No description provided for @imageSizeLongEdge.
  ///
  /// In en, this message translates to:
  /// **'Long edge'**
  String get imageSizeLongEdge;

  /// No description provided for @imageSizeCompute.
  ///
  /// In en, this message translates to:
  /// **'Calculate'**
  String get imageSizeCompute;

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

  /// No description provided for @optKbEntryTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The knowledge base\'s README.md takes up a large share of this model\'s context window. It is re-sent with every request and summarizing cannot shrink it — trim it, or pick a model with a larger window.'**
  String get optKbEntryTooLarge;

  /// No description provided for @optCompactedNotice.
  ///
  /// In en, this message translates to:
  /// **'Earlier messages were compacted into a summary to save context.'**
  String get optCompactedNotice;

  /// No description provided for @optKbDistillRequested.
  ///
  /// In en, this message translates to:
  /// **'Requested: distill this session\'s lessons into the knowledge base.'**
  String get optKbDistillRequested;

  /// No description provided for @optResultFeedbackAction.
  ///
  /// In en, this message translates to:
  /// **'Feedback to assistant'**
  String get optResultFeedbackAction;

  /// No description provided for @optResultFeedbackChatLabel.
  ///
  /// In en, this message translates to:
  /// **'Result feedback'**
  String get optResultFeedbackChatLabel;

  /// No description provided for @optResultFeedbackHint.
  ///
  /// In en, this message translates to:
  /// **'What about this image misses the mark?'**
  String get optResultFeedbackHint;

  /// No description provided for @optResultFeedbackHelper.
  ///
  /// In en, this message translates to:
  /// **'This result image joins the conversation with your feedback — the assistant iterates on v{version}.'**
  String optResultFeedbackHelper(int version);

  /// No description provided for @optDistillAction.
  ///
  /// In en, this message translates to:
  /// **'Distill session lessons'**
  String get optDistillAction;

  /// No description provided for @optDistillDisabledTooltip.
  ///
  /// In en, this message translates to:
  /// **'No prompt versions in this session yet — let the assistant optimize once first'**
  String get optDistillDisabledTooltip;

  /// No description provided for @optDistillCounts.
  ///
  /// In en, this message translates to:
  /// **'{versions} versions · {feedbacks} feedback'**
  String optDistillCounts(int versions, int feedbacks);

  /// No description provided for @optDistillAlreadyPending.
  ///
  /// In en, this message translates to:
  /// **'A distill request is already waiting to run.'**
  String get optDistillAlreadyPending;

  /// No description provided for @optResultImages.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get optResultImages;

  /// No description provided for @optResultNoFeedback.
  ///
  /// In en, this message translates to:
  /// **'No feedback yet'**
  String get optResultNoFeedback;

  /// No description provided for @optDistillDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Lessons written to the knowledge base'**
  String get optDistillDoneTitle;

  /// No description provided for @optSaveFinalPrompt.
  ///
  /// In en, this message translates to:
  /// **'Save final prompt to library'**
  String get optSaveFinalPrompt;

  /// No description provided for @optTimelineTitle.
  ///
  /// In en, this message translates to:
  /// **'Iteration timeline'**
  String get optTimelineTitle;

  /// No description provided for @optTimelineCount.
  ///
  /// In en, this message translates to:
  /// **'{count} versions'**
  String optTimelineCount(int count);

  /// No description provided for @optFeedbackShort.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get optFeedbackShort;

  /// No description provided for @optPromptVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get optPromptVersionLabel;

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

  /// No description provided for @optAskUserTitle.
  ///
  /// In en, this message translates to:
  /// **'The assistant has a question'**
  String get optAskUserTitle;

  /// No description provided for @optAskUserMultiHint.
  ///
  /// In en, this message translates to:
  /// **'Select all that apply'**
  String get optAskUserMultiHint;

  /// No description provided for @optAskUserOtherHint.
  ///
  /// In en, this message translates to:
  /// **'Other / add details...'**
  String get optAskUserOtherHint;

  /// No description provided for @optAskUserConfirm.
  ///
  /// In en, this message translates to:
  /// **'Send answers'**
  String get optAskUserConfirm;

  /// No description provided for @optAskUserAnswered.
  ///
  /// In en, this message translates to:
  /// **'Answered'**
  String get optAskUserAnswered;

  /// No description provided for @optAskUserDismissed.
  ///
  /// In en, this message translates to:
  /// **'Continued in chat'**
  String get optAskUserDismissed;

  /// No description provided for @optAgentSteps.
  ///
  /// In en, this message translates to:
  /// **'Agent process · {count} steps'**
  String optAgentSteps(int count);

  /// No description provided for @optAgentStepsImages.
  ///
  /// In en, this message translates to:
  /// **'viewed {count} reference images'**
  String optAgentStepsImages(int count);

  /// No description provided for @optAgentStepsDocs.
  ///
  /// In en, this message translates to:
  /// **'read {count} documents'**
  String optAgentStepsDocs(int count);

  /// No description provided for @optAgentStepsExpand.
  ///
  /// In en, this message translates to:
  /// **'Show all {count} steps'**
  String optAgentStepsExpand(int count);

  /// No description provided for @optAgentStepsCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse steps'**
  String get optAgentStepsCollapse;

  /// No description provided for @optPromptExpand.
  ///
  /// In en, this message translates to:
  /// **'Show full text'**
  String get optPromptExpand;

  /// No description provided for @optPromptCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get optPromptCollapse;

  /// No description provided for @optKbReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get optKbReady;

  /// No description provided for @optKbTreeStats.
  ///
  /// In en, this message translates to:
  /// **'{files} documents · {dirs} folders'**
  String optKbTreeStats(int files, int dirs);

  /// No description provided for @optKbContentUpdated.
  ///
  /// In en, this message translates to:
  /// **'Content updated {time}'**
  String optKbContentUpdated(String time);

  /// No description provided for @optKbRescan.
  ///
  /// In en, this message translates to:
  /// **'Rescan'**
  String get optKbRescan;

  /// No description provided for @optKbCitedThisRound.
  ///
  /// In en, this message translates to:
  /// **'Cited this round'**
  String get optKbCitedThisRound;

  /// No description provided for @optKbCitedAll.
  ///
  /// In en, this message translates to:
  /// **'All {count}'**
  String optKbCitedAll(int count);

  /// No description provided for @optKbCitedNone.
  ///
  /// In en, this message translates to:
  /// **'Nothing cited yet'**
  String get optKbCitedNone;

  /// No description provided for @optCtxTitle.
  ///
  /// In en, this message translates to:
  /// **'Context usage'**
  String get optCtxTitle;

  /// No description provided for @optCtxSystemPrompt.
  ///
  /// In en, this message translates to:
  /// **'System prompt'**
  String get optCtxSystemPrompt;

  /// No description provided for @optCtxTools.
  ///
  /// In en, this message translates to:
  /// **'Tool definitions'**
  String get optCtxTools;

  /// No description provided for @optCtxHistory.
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get optCtxHistory;

  /// No description provided for @optCtxRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get optCtxRemaining;

  /// No description provided for @optCtxWindowUnknown.
  ///
  /// In en, this message translates to:
  /// **'Window not set'**
  String get optCtxWindowUnknown;

  /// No description provided for @optCtxWindowUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get optCtxWindowUnlimited;

  /// No description provided for @optCtxWindowAssumed.
  ///
  /// In en, this message translates to:
  /// **'This model has no context window set — measured against the default assumption.'**
  String get optCtxWindowAssumed;

  /// No description provided for @optAttachedImages.
  ///
  /// In en, this message translates to:
  /// **'{count} reference images sent with the message'**
  String optAttachedImages(int count);

  /// No description provided for @optSendHint.
  ///
  /// In en, this message translates to:
  /// **'Enter to send · Shift+Enter for a new line'**
  String get optSendHint;

  /// No description provided for @optModeBadgeAgent.
  ///
  /// In en, this message translates to:
  /// **'{mode} · Agent'**
  String optModeBadgeAgent(String mode);

  /// No description provided for @optRefNumberingHint.
  ///
  /// In en, this message translates to:
  /// **'Numbers match the filenames cited in the prompt; the agent can view these images.'**
  String get optRefNumberingHint;

  /// No description provided for @optModeKnowledgeEditShort.
  ///
  /// In en, this message translates to:
  /// **'Edit KB'**
  String get optModeKnowledgeEditShort;

  /// No description provided for @optRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get optRunning;

  /// No description provided for @optRunningStep.
  ///
  /// In en, this message translates to:
  /// **'Running · step {count}'**
  String optRunningStep(int count);

  /// No description provided for @optAgentStepsRunning.
  ///
  /// In en, this message translates to:
  /// **'Agent process · running'**
  String get optAgentStepsRunning;

  /// No description provided for @optAgentStepWorking.
  ///
  /// In en, this message translates to:
  /// **'Working on the next step...'**
  String get optAgentStepWorking;

  /// No description provided for @optElapsedSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s elapsed'**
  String optElapsedSeconds(int seconds);

  /// No description provided for @optElapsedMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m {seconds}s elapsed'**
  String optElapsedMinutes(int minutes, int seconds);

  /// No description provided for @optChatBusyHint.
  ///
  /// In en, this message translates to:
  /// **'The agent is working — you can type again when it finishes...'**
  String get optChatBusyHint;

  /// No description provided for @optAbort.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get optAbort;

  /// No description provided for @optAbortHint.
  ///
  /// In en, this message translates to:
  /// **'Esc to stop'**
  String get optAbortHint;

  /// No description provided for @optKbSearching.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get optKbSearching;

  /// No description provided for @optKbCitedRunning.
  ///
  /// In en, this message translates to:
  /// **'in progress'**
  String get optKbCitedRunning;

  /// No description provided for @optSysPromptPick.
  ///
  /// In en, this message translates to:
  /// **'Choose a template'**
  String get optSysPromptPick;

  /// No description provided for @optSysPromptSearch.
  ///
  /// In en, this message translates to:
  /// **'Search templates...'**
  String get optSysPromptSearch;

  /// No description provided for @optSysPromptNone.
  ///
  /// In en, this message translates to:
  /// **'No template'**
  String get optSysPromptNone;

  /// No description provided for @optSysPromptUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved'**
  String get optSysPromptUnsaved;

  /// No description provided for @optSysPromptSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get optSysPromptSave;

  /// No description provided for @optSysPromptReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get optSysPromptReset;

  /// No description provided for @optSysPromptSaved.
  ///
  /// In en, this message translates to:
  /// **'Template saved'**
  String get optSysPromptSaved;

  /// No description provided for @optSysPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Write the instructions the assistant should follow...'**
  String get optSysPromptHint;

  /// No description provided for @optSysPromptChars.
  ///
  /// In en, this message translates to:
  /// **'{count} characters'**
  String optSysPromptChars(int count);

  /// No description provided for @optSysPromptTokens.
  ///
  /// In en, this message translates to:
  /// **'~{tokens} tokens'**
  String optSysPromptTokens(String tokens);

  /// No description provided for @optSysPromptNoTools.
  ///
  /// In en, this message translates to:
  /// **'This mode mounts no knowledge tools — the agent makes no tool calls.'**
  String get optSysPromptNoTools;

  /// No description provided for @kbEditNoChange.
  ///
  /// In en, this message translates to:
  /// **'This proposal changes nothing in the file.'**
  String get kbEditNoChange;

  /// No description provided for @kbEditPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Pending changes'**
  String get kbEditPendingTitle;

  /// No description provided for @kbEditWriteAll.
  ///
  /// In en, this message translates to:
  /// **'Write all'**
  String get kbEditWriteAll;

  /// No description provided for @kbEditDiscardAll.
  ///
  /// In en, this message translates to:
  /// **'Discard all'**
  String get kbEditDiscardAll;

  /// No description provided for @kbEditConfirmAll.
  ///
  /// In en, this message translates to:
  /// **'Write {count} changes'**
  String kbEditConfirmAll(int count);

  /// No description provided for @optKbDocCount.
  ///
  /// In en, this message translates to:
  /// **'{count} docs'**
  String optKbDocCount(int count);

  /// No description provided for @optKbSearchDocs.
  ///
  /// In en, this message translates to:
  /// **'Search documents...'**
  String get optKbSearchDocs;

  /// No description provided for @optKbTreeEmpty.
  ///
  /// In en, this message translates to:
  /// **'This knowledge base has no documents yet'**
  String get optKbTreeEmpty;

  /// No description provided for @optKbTreeScanFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the knowledge-base folder'**
  String get optKbTreeScanFailed;

  /// No description provided for @optKbTreeNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No document matches that'**
  String get optKbTreeNoMatch;

  /// No description provided for @optKbTreeChanged.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get optKbTreeChanged;

  /// No description provided for @optKbTreeAdded.
  ///
  /// In en, this message translates to:
  /// **'new'**
  String get optKbTreeAdded;

  /// No description provided for @optKbTreePending.
  ///
  /// In en, this message translates to:
  /// **'{count} changes awaiting confirmation'**
  String optKbTreePending(int count);

  /// No description provided for @kbWritePolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Write permissions'**
  String get kbWritePolicyTitle;

  /// No description provided for @kbWriteAllow.
  ///
  /// In en, this message translates to:
  /// **'Let the agent write to the knowledge base'**
  String get kbWriteAllow;

  /// No description provided for @kbWriteConfirmEach.
  ///
  /// In en, this message translates to:
  /// **'Confirm each write'**
  String get kbWriteConfirmEach;

  /// No description provided for @kbWriteBackup.
  ///
  /// In en, this message translates to:
  /// **'Keep a .bak copy before overwriting'**
  String get kbWriteBackup;

  /// No description provided for @kbWriteNoConfirmWarning.
  ///
  /// In en, this message translates to:
  /// **'With confirmation off, what the agent drafts is written to your files without you reading it first.'**
  String get kbWriteNoConfirmWarning;

  /// No description provided for @wbToolComparatorShort.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get wbToolComparatorShort;

  /// No description provided for @wbToolMaskShort.
  ///
  /// In en, this message translates to:
  /// **'Mask'**
  String get wbToolMaskShort;

  /// No description provided for @wbToolCropShort.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get wbToolCropShort;

  /// No description provided for @wbToolAssistantShort.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get wbToolAssistantShort;

  /// No description provided for @galleryViewWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get galleryViewWorkspace;

  /// No description provided for @galleryViewSourcesShort.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get galleryViewSourcesShort;

  /// No description provided for @galleryViewResultsShort.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get galleryViewResultsShort;

  /// No description provided for @galleryDropTitle.
  ///
  /// In en, this message translates to:
  /// **'Drop images here…'**
  String get galleryDropTitle;

  /// No description provided for @galleryEmptyWorkspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Drop files here'**
  String get galleryEmptyWorkspaceTitle;

  /// No description provided for @galleryEmptyWorkspaceDesc.
  ///
  /// In en, this message translates to:
  /// **'Drag images or videos in to add them to the temporary workspace'**
  String get galleryEmptyWorkspaceDesc;

  /// No description provided for @galleryEmptySourceDesc.
  ///
  /// In en, this message translates to:
  /// **'This source has no supported images'**
  String get galleryEmptySourceDesc;

  /// No description provided for @galleryScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning files…'**
  String get galleryScanning;

  /// No description provided for @wbGenerationConfig.
  ///
  /// In en, this message translates to:
  /// **'Generation settings'**
  String get wbGenerationConfig;

  /// No description provided for @selectionSendToAssistant.
  ///
  /// In en, this message translates to:
  /// **'Send to assistant'**
  String get selectionSendToAssistant;

  /// No description provided for @shareCount.
  ///
  /// In en, this message translates to:
  /// **'Share ({count})'**
  String shareCount(int count);

  /// No description provided for @selectionReorderHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder · the number is the order sent to the model'**
  String get selectionReorderHint;

  /// No description provided for @videoPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get videoPlay;

  /// No description provided for @videoPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get videoPause;

  /// No description provided for @videoMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get videoMute;

  /// No description provided for @videoUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get videoUnmute;

  /// No description provided for @videoRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get videoRetry;

  /// No description provided for @videoPlaybackFailed.
  ///
  /// In en, this message translates to:
  /// **'Can\'t play'**
  String get videoPlaybackFailed;

  /// No description provided for @videoPlaybackFailedReason.
  ///
  /// In en, this message translates to:
  /// **'File missing or encoding not supported: {name}'**
  String videoPlaybackFailedReason(String name);

  /// No description provided for @videoFrameOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get videoFrameOptional;

  /// No description provided for @videoDropOrPick.
  ///
  /// In en, this message translates to:
  /// **'Drop or click to pick'**
  String get videoDropOrPick;

  /// No description provided for @videoReferenceDropMax.
  ///
  /// In en, this message translates to:
  /// **'Drop reference images (max {count})'**
  String videoReferenceDropMax(int count);

  /// No description provided for @optErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'The request failed'**
  String get optErrorTitle;

  /// No description provided for @optNotViewed.
  ///
  /// In en, this message translates to:
  /// **'Not viewed yet'**
  String get optNotViewed;

  /// No description provided for @optTimelineCurrent.
  ///
  /// In en, this message translates to:
  /// **'current'**
  String get optTimelineCurrent;

  /// No description provided for @optKbPathInvalidDesc.
  ///
  /// In en, this message translates to:
  /// **'The path is no longer valid or can\'t be accessed'**
  String get optKbPathInvalidDesc;

  /// No description provided for @optKbEntryMissingShort.
  ///
  /// In en, this message translates to:
  /// **'Missing {file}'**
  String optKbEntryMissingShort(String file);

  /// No description provided for @optKbNotConfiguredShort.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get optKbNotConfiguredShort;

  /// No description provided for @cropEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'Pick an image in the gallery first'**
  String get cropEmptyDesc;

  /// No description provided for @maskEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'A mask is painted over an image'**
  String get maskEmptyDesc;

  /// No description provided for @maskLoadFailedDesc.
  ///
  /// In en, this message translates to:
  /// **'The file may have been moved or deleted'**
  String get maskLoadFailedDesc;
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
