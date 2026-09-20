// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get fileBrowser => 'ファイルブラウザ';

  @override
  String get rename => '名前を変更';

  @override
  String get renameFile => 'ファイル名を変更';

  @override
  String get newFilename => '新しいファイル名';

  @override
  String get renameSuccess => '名前の変更に成功しました';

  @override
  String renameFailed(String error) {
    return '名前の変更に失敗しました: $error';
  }

  @override
  String get renameHintKeys => 'Enter で確定 · Esc でキャンセル';

  @override
  String get renameExtensionLocked => '拡張子';

  @override
  String get renameExtensionUnlock => 'ロックを解除して拡張子を編集';

  @override
  String get renameExtensionRelock => '拡張子をロック';

  @override
  String renameConflict(String name) {
    return '$name はこのフォルダーに既にあります';
  }

  @override
  String renameTooLong(int max) {
    return '名前が $max 文字を超えています';
  }

  @override
  String get fileAlreadyExists => 'この名前のファイルは既に存在します';

  @override
  String get noFilesFound => 'ファイルが見つかりません';

  @override
  String get sortBy => '並べ替え';

  @override
  String get sortName => '名前';

  @override
  String get sortDate => '更新日';

  @override
  String get sortType => 'ファイルの種類';

  @override
  String get sortAsc => '昇順';

  @override
  String get sortDesc => '降順';

  @override
  String get catAll => 'すべて';

  @override
  String get catImages => '画像';

  @override
  String get catVideos => '動画';

  @override
  String get catAudio => '音声';

  @override
  String get catText => 'テキスト';

  @override
  String get catOthers => 'その他';

  @override
  String get openWithSystemDefault => 'システムのデフォルトで開く';

  @override
  String get aiBatchRename => 'AI一括名前変更';

  @override
  String get generateSuggestions => '提案を生成';

  @override
  String get searchFilesHint => 'ファイル名を検索…';

  @override
  String get deselectAllDirectories => 'すべてのディレクトリ選択を解除';

  @override
  String get aiRenameInstructionsHint => '例：元の拡張子を保持、ピンインに変換…';

  @override
  String get noTemplateSelected => 'テンプレート未選択';

  @override
  String get selectTemplateFirst => '先に名前変更テンプレートを選択してください。';

  @override
  String get addToSelection => '選択に追加';

  @override
  String get removeFromSelection => '選択から削除';

  @override
  String imagesSelected(int count) {
    return '$count個選択済み';
  }

  @override
  String get featureLimitedOnMobile => 'モバイルでは機能が制限されています';

  @override
  String get fileBrowserDesktopOnlyDesc =>
      'OSのサンドボックス制限により、高度なファイルブラウザと一括名前変更機能はデスクトップ版のみで使用できます。';

  @override
  String get fileBrowseriOSHint => '生成した画像の管理には、システムの「ファイル」アプリをご使用ください。';

  @override
  String get fileBrowserAndroidHint => 'ファイルの整理には、デバイスのファイルマネージャーをご使用ください。';

  @override
  String get stagingArea => 'ステージング';

  @override
  String get addToStaging => 'ステージングに追加';

  @override
  String get removeFromStaging => 'ステージングから削除';

  @override
  String get stagedBadge => 'ステージ済み';

  @override
  String get clearStaging => 'クリア';

  @override
  String get stagingEmptyTitle => 'ステージングは空です';

  @override
  String get stagingEmptyDesc =>
      'ファイルを選んで「ステージングに追加」を押すと、動かしたいファイルをここに控えます。印を付けるだけで、ファイルは移動しません。フォルダーの切り替え、絞り込み、アプリの再起動でも消えません。';

  @override
  String get stagingTarget => '対象フォルダー';

  @override
  String get stagingNoTarget => '未指定';

  @override
  String get stagingTargetHint =>
      '左カラムで閲覧するフォルダーにチェックを入れると、そこが対象フォルダーになります。フォルダーを右クリックして「ここへ移動 / コピー」を選ぶか、ファイルをフォルダーへドラッグすることもできます。';

  @override
  String stagingRestored(int count) {
    return '前回のセッションから $count 件を復元';
  }

  @override
  String get stagingSameAsTarget => '対象と同じ · 実行時にスキップ';

  @override
  String get stagingMissing => '見つかりません';

  @override
  String stagingClearMissing(int count) {
    return '無効な項目を削除 ($count)';
  }

  @override
  String get moveHere => 'ここへ移動';

  @override
  String get copyHere => 'ここへコピー';

  @override
  String moveCountHere(int count) {
    return '$count 件をここへ移動';
  }

  @override
  String copyCountHere(int count) {
    return '$count 件をここへコピー';
  }

  @override
  String stagingItemsCount(int count) {
    return '$count 件';
  }

  @override
  String stagingMissingCount(int count) {
    return '$count 件が無効';
  }

  @override
  String stagingAtTargetCount(int count) {
    return '$count 件は対象内（スキップ）';
  }

  @override
  String get onlyThisDirectory => 'このフォルダーのみ表示';

  @override
  String get pasteNoDestination => '先に対象フォルダーを指定してください';

  @override
  String get pasteDestinationGone => '対象フォルダーが存在しません';

  @override
  String get pasteNothingToDo => '転送するファイルがありません';

  @override
  String get conflictsTitle => '名前の衝突';

  @override
  String get conflictSkip => 'スキップ';

  @override
  String get conflictOverwrite => '上書き';

  @override
  String get conflictRename => '両方保持';

  @override
  String get conflictReasonExists => '対象フォルダーに既にあります';

  @override
  String get conflictReasonDuplicate => '別のステージング項目と同名';

  @override
  String get conflictReasonSameLocation => 'すでにこのフォルダー内';

  @override
  String get conflictReasonMissing => '元ファイルが存在しません';

  @override
  String pasteProgressCount(int done, int total) {
    return '$done / $total';
  }

  @override
  String get pasteCancelledTitle => '転送を中止しました';

  @override
  String pasteSucceededCount(int count) {
    return '$count 件成功';
  }

  @override
  String pasteSkippedCount(int count) {
    return '$count 件スキップ';
  }

  @override
  String pasteFailedCount(int count) {
    return '$count 件失敗';
  }

  @override
  String renameSubtitleFiles(int files, int dirs) {
    return '$files 件 · $dirs フォルダー';
  }

  @override
  String get renameSectionModel => 'モデル';

  @override
  String get renameSectionTemplate => '命名テンプレート';

  @override
  String get renameSectionInstructions => '追加指示';

  @override
  String renameBatchEstimate(int files, int size, int batches) {
    return '$files 件 · 1 バッチ $size 件 · 約 $batches バッチ';
  }

  @override
  String get renameStopGenerating => '生成を中断';

  @override
  String get renameRegenerate => '再生成';

  @override
  String get renameFilterAll => 'すべて';

  @override
  String get renameFilterConflicts => '衝突';

  @override
  String get renameFilterSkipped => 'スキップ済み';

  @override
  String get renameNextConflict => '次の衝突へ';

  @override
  String get renameEmptyTitle => 'まだ提案はありません';

  @override
  String renameEmptyDesc(int files, int batches, int size) {
    return '左でモデルと命名テンプレートを選び「提案を生成」を押します。$files 件は $size 件ずつ $batches バッチで送信され、生成中でも順に確認できます。';
  }

  @override
  String get renameGenerating => '提案を生成中';

  @override
  String renameBatchProgress(int batch, int total, int done, int files) {
    return 'バッチ $batch / $total · $done / $files 件生成';
  }

  @override
  String get renameStop => '中断';

  @override
  String renameProducedHint(int count) {
    return '$count 件生成済み · 生成完了までは確認のみ';
  }

  @override
  String renameSuggestionsCount(int count) {
    return '提案 $count 件';
  }

  @override
  String renameSkippedCount(int count) {
    return 'スキップ $count 件';
  }

  @override
  String renameConflictsPending(int count) {
    return '未解決の衝突 $count 件 · 適用されません';
  }

  @override
  String renameApplyCount(int count) {
    return '$count 件を適用';
  }

  @override
  String renameApplyShort(int count) {
    return '$count 件適用';
  }

  @override
  String get renameDuplicateBadge => '名前が重複';

  @override
  String get renameSkippedBadge => 'スキップ';

  @override
  String get renameRenamedBadge => '改名済み';

  @override
  String get renameActionSkip => 'スキップ';

  @override
  String get renameActionEdit => '名前を編集';

  @override
  String get renameActionUndo => 'スキップを取消';

  @override
  String get renameConflictAutoRename => '改名';

  @override
  String get renameOverwriteDuplicateHint =>
      'この名前はリスト内の別の行が使う予定です。ディスク上にはまだ存在しないため、上書きする対象がありません。どちらかを改名するかスキップしてください。';

  @override
  String get renameNoModelsTitle => '利用できるモデルがありません';

  @override
  String get renameNoModelsDesc =>
      '一括リネームには画像を読んで名前を作るチャットモデルが必要です。まず「モデルとチャネル」で利用可能なチャネルを設定してください。';

  @override
  String get renameGoToSettings => '設定を開く';

  @override
  String renameBatchFailedDesc(int kept, int missing) {
    return '生成済みの $kept 件は保持されます。未生成の $missing 件は個別に再試行できます';
  }

  @override
  String get renameRetryBatch => '再試行';

  @override
  String get renameEditConfig => '設定を編集';

  @override
  String get renameTemplateLabel => 'テンプレート';

  @override
  String pasteMovingCount(int count) {
    return '$count 件を移動中';
  }

  @override
  String pasteCopyingCount(int count) {
    return '$count 件をコピー中';
  }

  @override
  String pasteRoute(String from_, String to) {
    return '$from_ → $to';
  }

  @override
  String get pasteCrossVolumeTag => '別ドライブ';

  @override
  String pasteCurrentFile(String name) {
    return '$name をコピー中';
  }

  @override
  String get pasteRollbackNote =>
      '別ドライブへの移動はコピー後に削除します。中止すると進行中のコピーは削除され、元ファイルはそのまま残ります。';

  @override
  String get pasteRunInBackground => 'バックグラウンドで実行';

  @override
  String get pasteMoveDone => '移動が完了しました';

  @override
  String get pasteCopyDone => 'コピーが完了しました';

  @override
  String pasteElapsed(int count, String time) {
    return '$count 件 · $time';
  }

  @override
  String get pasteStatSucceeded => '成功';

  @override
  String get pasteStatSkipped => 'スキップ（対象と同じ）';

  @override
  String get pasteStatFailed => '失敗';

  @override
  String get pasteRetry => '再試行';

  @override
  String pasteKeptInStaging(int kept, int moved) {
    return '失敗・スキップの $kept 件はステージングに残り、成功した $moved 件は取り除かれました。';
  }

  @override
  String get pasteExportLog => 'ログを書き出す';

  @override
  String pasteLogSaved(String path) {
    return 'ログを $path に保存しました';
  }

  @override
  String conflictsSubtitle(int count, int total, String folder) {
    return '$count / $total 件が $folder の既存名と衝突';
  }

  @override
  String get conflictsIntro => '項目ごとに選ぶか、下のチェックで残りにも同じ選択を適用します。';

  @override
  String get conflictPending => '未決定';

  @override
  String get conflictOverwriteWarning => '対象のファイルは置き換えられます。元に戻せません';

  @override
  String conflictApplyRestCount(int count) {
    return '残り $count 件にも同じ選択を適用';
  }

  @override
  String get conflictApplyAndContinue => '適用して続行';

  @override
  String get showInSystem => 'システムで表示';

  @override
  String get newSubfolder => '新しいサブフォルダー';

  @override
  String get newFolderDefaultName => '新しいフォルダー';

  @override
  String get moveFolderTo => '移動先…';

  @override
  String get removeFromList => 'リストから削除';

  @override
  String get rootCannotMove => 'ルートフォルダーは移動できません';

  @override
  String get deleteFolderTitle => 'フォルダーを削除しますか？';

  @override
  String get trashFolderTitle => 'ゴミ箱に移動しますか？';

  @override
  String get deleteFolderEmptyDesc => 'このフォルダーは空です。削除すると元に戻せません。';

  @override
  String get trashFolderEmptyDesc => 'このフォルダーは空です。削除後はシステムのゴミ箱から復元できます。';

  @override
  String get deleteIrreversibleNote => 'この操作は元に戻せません';

  @override
  String get trashRestorableNote => 'システムのゴミ箱から復元できます';

  @override
  String get inventorySubfolders => 'サブフォルダー';

  @override
  String get inventoryFiles => 'ファイル';

  @override
  String get inventorySize => 'サイズ';

  @override
  String get inventoryCounting => '集計中…';

  @override
  String deleteFolderCount(int count) {
    return '$count 項目を削除';
  }

  @override
  String trashFolderCount(int count) {
    return '$count 項目をゴミ箱へ';
  }

  @override
  String get moveToTrash => 'ゴミ箱に移動';

  @override
  String get trashFileTitle => 'ゴミ箱に移動しますか？';

  @override
  String trashFilesTitle(int count) {
    return '$count 件のファイルをゴミ箱に移動しますか？';
  }

  @override
  String get deleteFileTitle => '完全に削除しますか？';

  @override
  String deleteFilesTitle(int count) {
    return '$count 件のファイルを完全に削除しますか？';
  }

  @override
  String deleteFromFolders(int count) {
    return '$count 個のフォルダから';
  }

  @override
  String deleteMoreFiles(int count) {
    return '他 $count 件';
  }

  @override
  String deleteTotalSize(String size) {
    return '合計 $size';
  }

  @override
  String trashFileCount(int count) {
    return '$count 件をゴミ箱へ';
  }

  @override
  String deleteFileCount(int count) {
    return '$count 件を完全に削除';
  }

  @override
  String deleteFiles(int count) {
    return '$count 件のファイルを削除';
  }

  @override
  String fileTrashed(String name) {
    return '$name をゴミ箱に移動しました';
  }

  @override
  String filesTrashed(int count) {
    return '$count 件のファイルをゴミ箱に移動しました';
  }

  @override
  String fileDeleted(String name) {
    return '$name を削除しました';
  }

  @override
  String filesDeleted(int count) {
    return '$count 件のファイルを削除しました';
  }

  @override
  String filesDeletePartial(int done, int failed, String error) {
    return '$done 件を削除、$failed 件失敗：$error';
  }

  @override
  String get folderNameEmpty => '名前を入力してください';

  @override
  String folderNameIllegalChars(String chars) {
    return '名前に $chars は使えません';
  }

  @override
  String get folderNameReserved => 'システムの予約名です';

  @override
  String get folderNameExists => '同名のフォルダーがすでにあります';

  @override
  String get folderPathRegistered => 'このパスはすでにリストにあります';

  @override
  String get moveFolderIntoSelf => 'フォルダーを自身の中に移動することはできません';

  @override
  String get moveFolderSameParent => 'フォルダーはすでにその場所にあります';

  @override
  String get moveFolderTargetExists => '移動先に同名の項目があります';

  @override
  String dragMoveFolderHint(String name) {
    return '「$name」を移動';
  }

  @override
  String dragCopyFolderHint(String name) {
    return '「$name」をコピー';
  }

  @override
  String folderMovingTitle(String name) {
    return 'フォルダー $name を移動中';
  }

  @override
  String folderCopyingTitle(String name) {
    return 'フォルダー $name をコピー中';
  }

  @override
  String folderTransferItems(int count) {
    return '$count 項目';
  }

  @override
  String get folderMoveCrossVolumeNote =>
      '別のドライブです。先にコピーし、すべて到着してから元を削除します。キャンセルしても失われるものはありません。';

  @override
  String get folderMoveCancelledTitle => '移動をキャンセルしました';

  @override
  String get folderCopyCancelledTitle => 'コピーをキャンセルしました';

  @override
  String folderTransferStoppedAt(int done, int total) {
    return '$done / $total 項目で停止';
  }

  @override
  String get folderMoveStatCopied => '移動先にコピー済み';

  @override
  String get folderMoveStatPending => '未開始';

  @override
  String get folderMoveStatSourceKept => '元に保持';

  @override
  String get folderMoveCancelledDesc =>
      '元のフォルダーはそのまま残っています。コピー済みのファイルは移動先に残るので、後で再度ドロップすれば同名の項目は個別に処理されます。';

  @override
  String get showDestinationInSystem => '移動先をシステムで表示';

  @override
  String get gotIt => 'OK';

  @override
  String folderCreated(String name) {
    return '$name を作成しました';
  }

  @override
  String folderRenamed(String name) {
    return '$name に名前を変更しました';
  }

  @override
  String folderDeleted(String name) {
    return '$name を削除しました';
  }

  @override
  String folderTrashed(String name) {
    return '$name をゴミ箱に移動しました';
  }

  @override
  String folderMoved(String name, String target) {
    return '$name を $target に移動しました';
  }

  @override
  String folderCopied(String name, String target) {
    return '$name を $target にコピーしました';
  }

  @override
  String folderOpFailed(String error) {
    return '操作に失敗しました: $error';
  }

  @override
  String get browserViewGrid => 'グリッド';

  @override
  String get browserViewList => 'リスト';

  @override
  String get browserSearchEscHint => 'Esc でクリア';

  @override
  String get browserNoFilesHint => '別のフィルターを試すか、検索をクリアしてください';

  @override
  String browserFoldersCount(int count) {
    return '$count 個のフォルダー';
  }

  @override
  String browserScanningCount(int count) {
    return '$count 個のファイルをスキャン中…';
  }

  @override
  String get browserDragFootnote => 'フォルダーへドラッグで移動 · Ctrl を押しながらでコピー';

  @override
  String get stagingDropHint => '左列のフォルダーにドロップしてステージに追加';

  @override
  String renameBatchFailedTitle(int batch) {
    return 'バッチ $batch が失敗しました';
  }

  @override
  String get conflictIncoming => '移動元';

  @override
  String get conflictAlreadyThere => '既存';

  @override
  String conflictUndecidedCount(int count) {
    return '未決定 $count 件';
  }

  @override
  String get browserGroupByFolder => 'フォルダーごとにグループ化';

  @override
  String get browserGroupByFolderHint => '2 つ以上のフォルダーを選択時に有効。フォルダー内で並べ替え';

  @override
  String get appTitle => 'Joycai Image AI Toolkits';

  @override
  String get save => '保存';

  @override
  String get update => '更新';

  @override
  String get cancel => 'キャンセル';

  @override
  String get close => '閉じる';

  @override
  String get minimizeWindow => '最小化';

  @override
  String get maximizeWindow => '最大化';

  @override
  String get restoreWindow => '元のサイズに戻す';

  @override
  String get closeWindow => '閉じる';

  @override
  String get expandEditor => '拡大編集';

  @override
  String get back => '戻る';

  @override
  String get next => '次へ';

  @override
  String get finish => '完了';

  @override
  String get exit => '終了';

  @override
  String get add => '追加';

  @override
  String get edit => '編集';

  @override
  String get delete => '削除';

  @override
  String get remove => '削除';

  @override
  String get clear => 'クリア';

  @override
  String get refresh => '更新';

  @override
  String get preview => 'プレビュー';

  @override
  String get share => '共有';

  @override
  String get status => 'ステータス';

  @override
  String get started => '開始';

  @override
  String get finished => '完了';

  @override
  String get config => '設定';

  @override
  String get logs => 'ログ';

  @override
  String get copy => 'コピー';

  @override
  String get copyFilename => 'ファイル名をコピー';

  @override
  String get openInFolder => 'フォルダで開く';

  @override
  String get openInPreview => 'プレビューで開く';

  @override
  String copiedToClipboard(String text) {
    return 'コピーしました: $text';
  }

  @override
  String selectedCount(int count) {
    return '$count個選択済み';
  }

  @override
  String shareFiles(int count) {
    return '選択した$count個のアイテムを共有';
  }

  @override
  String get comingSoon => '近日公開';

  @override
  String get viewAll => 'すべて表示';

  @override
  String get white => '白';

  @override
  String get black => '黒';

  @override
  String get red => '赤';

  @override
  String get green => '緑';

  @override
  String get refine => 'リファイン';

  @override
  String get apply => '適用';

  @override
  String get metadata => 'メタデータ';

  @override
  String get filterPrompts => 'プロンプトをフィルター...';

  @override
  String shareFailed(String error) {
    return '共有に失敗しました: $error';
  }

  @override
  String get more => 'もっと見る';

  @override
  String get confirm => '確認';

  @override
  String get moreSheetDesktopOnlyNote =>
      'ファイルブラウザと画像ダウンローダーはデスクトップ／タブレットでのみ利用できます。';

  @override
  String get consoleIdle => 'アイドル';

  @override
  String consoleFailedCount(int count) {
    return '$count 件失敗';
  }

  @override
  String get logSearchHint => 'ログを絞り込む…';

  @override
  String get logLevelError => 'エラー';

  @override
  String get logLevelRunning => '実行';

  @override
  String get logLevelSuccess => '成功';

  @override
  String get goToSettings => '設定へ';

  @override
  String get actionImport => 'インポート';

  @override
  String get actionExport => 'エクスポート';

  @override
  String get actionOpen => '開く';

  @override
  String get actionClear => 'クリア';

  @override
  String get actionRun => '実行';

  @override
  String get actionChange => '変更';

  @override
  String get experimental => '試験的';

  @override
  String dropAtPosition(int position) {
    return '$position 番目に置く';
  }

  @override
  String get dropAtEnd => '最後に置く';

  @override
  String reorderPositionOf(int position, int count) {
    return '$count 件中 $position 番目';
  }

  @override
  String get reorderOffFiltered =>
      'リストが絞り込まれている間は並べ替えできません。行メニューの「上へ / 下へ」を使ってください。';

  @override
  String get dragKeepToScroll => 'ドラッグを続けるとスクロールします';

  @override
  String get dropRelease => '離して追加';

  @override
  String get dropFirstFrame => '最初のフレームをドロップ';

  @override
  String get dropLastFrame => '最後のフレームをドロップ';

  @override
  String get dropSetAsFirstFrame => '最初のフレームに設定しました';

  @override
  String get dropSetAsLastFrame => '最後のフレームに設定しました';

  @override
  String dropAddedToReferences(int count, int max) {
    return '参考画像に追加しました · $count / $max';
  }

  @override
  String get dropImagesOnly => '画像のみ';

  @override
  String dropReferenceLimit(int count) {
    return '参考画像は $count 枚まで';
  }

  @override
  String get galleryDropSystemHint => 'ファイルマネージャーからドラッグすることもできます';

  @override
  String dropMoveTo(String name) {
    return '$name に移動';
  }

  @override
  String dropCopyTo(String name) {
    return '$name にコピー';
  }

  @override
  String dropCopyItemsTo(int count, String name) {
    return '$count 件を $name にコピー';
  }

  @override
  String dragMoveItems(int count) {
    return '$count 件を移動';
  }

  @override
  String dragCopyItems(int count) {
    return '$count 件をコピー';
  }

  @override
  String get dropRejectIntoItself => 'フォルダーをそれ自身の中には移動できません';

  @override
  String get dropRejectSameFolder => 'すでにこのフォルダーにあります';

  @override
  String get dropRejectRoot => 'ルートフォルダーにはファイルを置けません';

  @override
  String get dropRejectReadOnly => 'このフォルダーは読み取り専用です';

  @override
  String dropAddedToReferencesUnlimited(int count) {
    return '参考画像に追加しました · $count';
  }

  @override
  String get dropReplacesFrame => '現在のフレームを置き換えます';

  @override
  String get dropRejectNameTaken => '同じ名前のフォルダーがすでにあります';

  @override
  String get browserDragFootnoteMac => 'フォルダーにドラッグで移動 · ⌥ を押しながらでコピー';

  @override
  String get folderOutlineLabel => 'フォルダーナビ';

  @override
  String get folderOutlineShowOnly => 'このフォルダーのみ表示';

  @override
  String get folderOutlineRemove => '表示から外す';

  @override
  String get folderOutlineReveal => 'フォルダーツリーで表示';

  @override
  String get folderOutlineReauthorize => '再認証';

  @override
  String folderOutlineFilesCount(int count) {
    return '$count 件のファイル';
  }

  @override
  String get downloader => 'ダウンローダー';

  @override
  String get imageDownloader => '画像ダウンローダー';

  @override
  String get url => 'URL';

  @override
  String get prefix => 'プレフィックス';

  @override
  String get websiteUrl => 'ウェブサイトURL';

  @override
  String get websiteUrlHint => 'https://example.com';

  @override
  String get whatToFind => '何を探しますか？';

  @override
  String get whatToFindHint => '例：すべての商品ギャラリー画像';

  @override
  String get analysisModel => '分析モデル';

  @override
  String get advancedOptions => '詳細オプション';

  @override
  String get analyzing => '分析中...';

  @override
  String get urlRequired => '有効なウェブサイト URL を入力してください。';

  @override
  String get requirementRequired => '探したい画像の要件（説明）を入力してください。';

  @override
  String get manualHtmlRequired => '手動モードでは、まず HTML コンテンツを貼り付けてください。';

  @override
  String get findImages => '画像を探す';

  @override
  String get noImagesDiscovered => 'まだ画像が見つかっていません。';

  @override
  String get addToQueue => 'キューに追加';

  @override
  String addedToQueue(int count) {
    return '$count個の画像をダウンロードキューに追加しました。';
  }

  @override
  String get setOutputDirFirst => '最初に設定で出力ディレクトリを設定してください。';

  @override
  String get cookiesHint => 'クッキー（RawまたはNetscape形式）';

  @override
  String get selectImagesToDownload => 'ダウンロードする画像を選択';

  @override
  String get importCookieFile => 'クッキーファイルをインポート';

  @override
  String get cookieFileInvalid =>
      'サポートされていないクッキーファイル形式です。Netscape形式またはrawテキストを使用してください。';

  @override
  String cookieImportSuccess(int count) {
    return '$count個のクッキーを正常にインポートしました。';
  }

  @override
  String get saveOriginHtml => '元のHTMLを保存';

  @override
  String htmlSavedTo(String path) {
    return 'HTMLを保存しました: $path';
  }

  @override
  String get manualHtmlMode => '手動HTMLモード';

  @override
  String get cookieHistory => 'クッキー履歴';

  @override
  String get noCookieHistory => 'クッキー履歴が保存されていません';

  @override
  String get pasteFromClipboard => 'クリップボードから貼り付け';

  @override
  String get openRawImage => '元の画像を開く';

  @override
  String downloaderFoundSelected(int found, int selected) {
    return '$found件見つかりました · $selected件選択中';
  }

  @override
  String get guideStep1Title => '1 · URLを入力';

  @override
  String get guideStep1Desc => 'ギャラリーや記事ページを貼り付け';

  @override
  String get guideStep2Title => '2 · 要件を記述';

  @override
  String get guideStep2Desc => '探したい画像をAIに伝える';

  @override
  String get guideStep3Title => '3 · 選んでダウンロード';

  @override
  String get guideStep3Desc => 'まとめて選択してキューに追加';

  @override
  String get copyLogs => 'ログをコピー';

  @override
  String downloaderFoundCount(int count) {
    return '$count 件見つかりました';
  }

  @override
  String get downloaderAdvancedSubtitle => 'この画面からのダウンロードにのみ適用';

  @override
  String get copyImageUrl => '画像の URL をコピー';

  @override
  String get manualHtmlEmptyTitle => 'HTML がまだ貼り付けられていません';

  @override
  String get manualHtmlEmptyDesc =>
      'ブラウザーでページのソースを表示して全選択・コピーし、上の貼り付けを押してください。';

  @override
  String get cookieHistoryUse => '使用';

  @override
  String get cookieRetention => 'Cookie を記憶';

  @override
  String get cookieRetentionOff => '記憶しない';

  @override
  String get cookieRetentionWeek => '7 日';

  @override
  String get cookieRetentionMonth => '30 日';

  @override
  String get cookieRetentionForever => '消去するまで';

  @override
  String get cookieRetentionNote =>
      'この端末に暗号化せずに保存され、バックアップには含まれません。「記憶しない」にすると今ある記録も消去します。';

  @override
  String get cookieHistoryForget => '削除';

  @override
  String get cookieHistoryClearAll => 'すべて消去';

  @override
  String cookieHistoryPairs(int count) {
    return '$count 組';
  }

  @override
  String get cookieHistoryEmptyDesc => '貼り付けた Cookie はここに記録され、同じサイトで再利用できます。';

  @override
  String get usage => '使用状況';

  @override
  String get tokenUsageMetrics => 'トークン使用状況メトリクス';

  @override
  String get clearAllUsage => 'すべての使用状況データをクリアしますか？';

  @override
  String get clearUsageWarning => 'これにより、データベースからすべてのトークン使用状況レコードが完全に削除されます。';

  @override
  String get rangeLabel => '範囲：';

  @override
  String get today => '今日';

  @override
  String get lastWeek => '先週';

  @override
  String get lastMonth => '先月';

  @override
  String get thisYear => '今年';

  @override
  String get inputTokens => '入力トークン';

  @override
  String get cachedInputTokens => 'キャッシュ入力';

  @override
  String get specBilled => '仕様別';

  @override
  String get outputTokens => '出力トークン';

  @override
  String get cacheHitRate => 'キャッシュヒット率';

  @override
  String get cacheHitRateHint => '入力トークンのうちプロンプトキャッシュから提供された割合';

  @override
  String get estimatedCost => '推定コスト';

  @override
  String clearDataForModel(String modelId) {
    return '$modelIdのデータをクリアしますか？';
  }

  @override
  String clearModelDataWarning(String modelId) {
    return 'これにより、モデル「$modelId」に関連するすべての使用状況レコードが削除されます。';
  }

  @override
  String get clearModelData => 'モデルデータをクリア';

  @override
  String get usageByGroup => 'グループ別の使用状況';

  @override
  String get usageColumnDetail => '内訳';

  @override
  String get usageColumnTime => '時刻';

  @override
  String get usageColumnCost => 'コスト';

  @override
  String get yesterday => '昨日';

  @override
  String usageRecordCount(int count) {
    return '$count 件';
  }

  @override
  String usageItemCount(int count) {
    return '$count 項目';
  }

  @override
  String get noUsageInRange => '選択した期間の使用状況データはありません。';

  @override
  String get loadMore => 'さらに読み込む';

  @override
  String get invalidPriceValue => '0以上の有効な数値を入力してください';

  @override
  String get usageLoadingRecords => '使用記録を集計中…';

  @override
  String get noUsageInRangeHint => '別の期間を選ぶか、先にタスクを実行してください。';

  @override
  String usageLoadMoreStatus(int pageSize, int shown, int total) {
    return '1 ページ $pageSize 件 · $shown / $total 件表示';
  }

  @override
  String usageUnitsImage(String n) {
    return '$n 枚';
  }

  @override
  String usageUnitsSecond(String n) {
    return '$n 秒';
  }

  @override
  String usageUnitsClip(String n) {
    return '$n 本';
  }

  @override
  String usageRequests(int n) {
    return '$n 回';
  }

  @override
  String get usageSpecColumn => '仕様';

  @override
  String usageUnmatched(int n) {
    return '$n 件のリクエストがどの料金にも一致せず、0 として計算';
  }

  @override
  String get usageGoFixRates => '料金を追加';

  @override
  String get usageUnitPrice => '単価';

  @override
  String get models => 'モデル';

  @override
  String get feeManagement => '料金管理';

  @override
  String get modelsTab => 'モデル';

  @override
  String get channelsTab => 'チャンネル';

  @override
  String get addChannel => 'チャンネルを追加';

  @override
  String get editChannel => 'チャンネルを編集';

  @override
  String get basicInfo => '基本情報';

  @override
  String get configuration => '設定';

  @override
  String get tagAndAppearance => 'タグと外観';

  @override
  String get billing => '請求';

  @override
  String get channelType => 'チャンネルタイプ';

  @override
  String get probeChannel => '接続テスト';

  @override
  String get probeOk => '接続・認証に成功しました';

  @override
  String get probeModels => '個のモデル';

  @override
  String get probeConnectedNoModels =>
      '接続できました。このエンドポイントにはモデル一覧がありませんが、一部の中継では正常です。';

  @override
  String get probeAuthFailed => 'エンドポイントは応答しましたが、API キーを拒否しました。';

  @override
  String get probeNotAnApi =>
      'この URL は本 API 以外のもの（HTML ページなど）を返しました。ベース URL を確認してください。';

  @override
  String get probeUnreachable => 'エンドポイントから応答がありません';

  @override
  String get probeNotSupported => 'このチャネル種別では接続テストを利用できません。';

  @override
  String get enableDiscovery => 'モデル検出を有効にする';

  @override
  String get filterModels => 'モデルをフィルター...';

  @override
  String get tagColor => 'タグの色';

  @override
  String deleteChannelConfirm(String name) {
    return 'チャンネル「$name」を削除してもよろしいですか？このチャンネルのモデルも一緒に削除されます。';
  }

  @override
  String get modelManager => 'モデルマネージャー';

  @override
  String get name => '名前';

  @override
  String get addModel => 'モデルを追加';

  @override
  String get editModel => 'モデルを編集';

  @override
  String get noModelsConfigured => 'モデルが設定されていません';

  @override
  String countModels(int count) {
    return '$countモデル';
  }

  @override
  String get deleteModel => 'モデルを削除';

  @override
  String get deleteModelConfirmTitle => 'モデルを削除しますか？';

  @override
  String deleteModelConfirmMessage(String name) {
    return '「$name」を削除してもよろしいですか？';
  }

  @override
  String get modelIdLabel => 'モデル ID';

  @override
  String get displayName => '表示名';

  @override
  String get type => 'タイプ';

  @override
  String get tag => 'タグ';

  @override
  String get billingMode => '請求モード';

  @override
  String get perToken => 'トークン別';

  @override
  String get perRequest => '回数別';

  @override
  String get requestCount => 'リクエスト数';

  @override
  String get requests => 'リクエスト';

  @override
  String get feeGroups => '料金グループ';

  @override
  String get feeGroup => '料金グループ';

  @override
  String get channels => 'チャンネル';

  @override
  String get channel => 'チャンネル';

  @override
  String get noFeeGroup => '料金グループなし';

  @override
  String get inputPrice => '入力価格（\$/Mトークン）';

  @override
  String get cacheInputPrice => '入力価格・キャッシュヒット（\$/Mトークン）';

  @override
  String get cacheInputPriceHint => '未入力の場合、キャッシュヒットは「入力価格」で課金されます';

  @override
  String get requestPriceHint => '成功したリクエストごとに課金され、トークン使用量とは無関係です。';

  @override
  String get cachePriceFollowsInput => 'キャッシュヒットは「入力価格」で課金されます';

  @override
  String get outputPrice => '出力価格（\$/Mトークン）';

  @override
  String get requestPrice => 'リクエスト価格（\$/リクエスト）';

  @override
  String get priceLabelInput => '入力';

  @override
  String get priceLabelCache => 'キャッシュ';

  @override
  String get priceLabelOutput => '出力';

  @override
  String get priceLabelRequest => 'リクエスト';

  @override
  String get addFeeGroup => '料金グループを追加';

  @override
  String get editFeeGroup => '料金グループを編集';

  @override
  String deleteFeeGroupConfirm(String name) {
    return '料金グループ「$name」を削除しますか？';
  }

  @override
  String get groupName => 'グループ名';

  @override
  String get fetchModels => 'モデルを取得';

  @override
  String get discoveringModels => 'モデルを検出中...';

  @override
  String get selectModelsToAdd => '追加するモデルを選択';

  @override
  String get searchModels => 'モデル名またはIDを検索...';

  @override
  String modelsDiscovered(int count) {
    return '$count個のモデルを検出';
  }

  @override
  String addSelected(int count) {
    return '選択したものを追加($count)';
  }

  @override
  String get alreadyAdded => '既に追加済み';

  @override
  String get noNewModelsFound => '新しいモデルが見つかりませんでした。';

  @override
  String fetchFailed(String error) {
    return 'モデルの取得に失敗しました：$error';
  }

  @override
  String get stepProvider => 'プロバイダーを選択';

  @override
  String get protocolOpenAIDesc => '標準のOpenAI REST API互換性';

  @override
  String get protocolGoogleDesc => '公式Google Gemini REST API';

  @override
  String get protocolMidjourney => 'Midjourney プロキシ';

  @override
  String get protocolMidjourneyDesc =>
      'midjourney-proxy / NewAPI の /mj/* インターフェース';

  @override
  String get protocolAnthropicDesc => 'Claude ネイティブの /v1/messages インターフェース';

  @override
  String get midjourneyEndpointHint =>
      'ホストのルートURL（例: https://your-newapi.com）を入力してください。/mj/* パスは自動的に追加されます。';

  @override
  String get providerDashScopeDesc =>
      'dashscope.aliyuncs.com/compatible-mode · OpenAI 形式のリクエスト · Qwen チャット + qwen-image / Wan ネイティブ画像 + Wan 動画';

  @override
  String get providerDashScopeCompat => 'Alibaba DashScope（OpenAI 互換）';

  @override
  String get providerVolcengineArk => 'Volcengine Ark（火山方舟）';

  @override
  String get providerDashScopeNative => 'Alibaba DashScope（ネイティブ）';

  @override
  String get providerDashScopeNativeDesc =>
      'dashscope.aliyuncs.com/api/v1 · Alibaba 独自のリクエスト形式 · qwen-audio はこの経路のみ';

  @override
  String get providerCustom => 'カスタムプロバイダー';

  @override
  String get providerCustomDesc => 'セルフホストまたはサードパーティプロバイダー';

  @override
  String get stepConnection => '接続とキー';

  @override
  String get moreColors => 'その他の色';

  @override
  String get protocolXai => 'xAI (Grok) API';

  @override
  String get providerXaiOfficialDesc =>
      'api.x.ai · Grok チャット + ネイティブ Imagine 動画';

  @override
  String get providerNewApiOpenAI => 'New API（OpenAI 形式）';

  @override
  String get providerNewApiOpenAIResponses => 'New API（OpenAI Responses 形式）';

  @override
  String get providerNewApiGemini => 'New API（Gemini 形式）';

  @override
  String get providerNewApiDesc => 'New API リレー · ベアラートークン認証';

  @override
  String get providerNewApiAnthropic => 'New API（Anthropic 形式）';

  @override
  String get providerMiniMaxAnthropic => 'MiniMax（Anthropic 形式）';

  @override
  String get providerMiniMaxDesc => 'OpenAI 互換 /v1 エンドポイント';

  @override
  String get providerVolcengineArkDesc => 'Seedream 画像生成 · Doubao チャット';

  @override
  String get newApiBaseUrl => 'New API ベース URL';

  @override
  String get newApiBaseHint => 'New API のホストを入力してください。バージョンパスは自動的に追加されます';

  @override
  String get openaiV1Hint => 'ヒント：OpenAI互換のエンドポイントは通常「/v1」で終わります';

  @override
  String get googleV1BetaHint => 'ヒント：Google GenAIのエンドポイントは通常「/v1beta」で終わります';

  @override
  String get anthropicV1Hint => 'ヒント：Anthropic のエンドポイントは通常「/v1」で終わります';

  @override
  String get dashscopeApiV1Hint =>
      'ヒント：DashScope ネイティブのエンドポイントは「/api/v1」で終わります';

  @override
  String get apiKeyStorageNotice =>
      'キーは暗号化されずにこの端末のアプリのデータベースに保存され、アカウントのファイル権限でのみ保護されます。バックアップには含まれず、このプロバイダーにのみ送信されます。';

  @override
  String get nameHint => '例：本番API';

  @override
  String get enableDiscoveryDesc => 'このエンドポイントから利用可能なモデルを自動的にリストアップする';

  @override
  String get tagHint => '例：GPT4, Local, など';

  @override
  String get previewReady => 'このチャンネルを追加する準備ができましたか？';

  @override
  String get feeGroupDesc => 'モデルの請求基準を定義して、使用コストを正確に計算します。';

  @override
  String get noFeeGroups => 'まだ料金グループが作成されていません';

  @override
  String feeGroupModelCount(int count) {
    return '$count 個のモデル';
  }

  @override
  String get feeGroupUnused => '使用しているモデルなし';

  @override
  String get model => 'モデル';

  @override
  String modelsAndChannelsCount(int models, int channels) {
    return '$modelsモデル · $channelsチャンネル';
  }

  @override
  String get deselectAll => 'すべて選択解除';

  @override
  String get capabilities => '機能';

  @override
  String get cardPreview => 'カードプレビュー';

  @override
  String get capabilityStreamingShort => 'ストリーミング';

  @override
  String get capabilityStandardShort => '標準リクエスト';

  @override
  String get supportsStreaming => 'ストリーミング対応';

  @override
  String get supportsStreamingDesc => 'モデルがサーバー送信イベント（SSE）に対応する場合は有効化';

  @override
  String get supportsStandardRequest => '標準リクエスト対応';

  @override
  String get supportsStandardRequestDesc => '標準的な JSON/REST リクエストの場合は有効化';

  @override
  String get contextWindow => 'コンテキストウィンドウ';

  @override
  String get contextUnset => '未設定';

  @override
  String get contextUnsetDesc => '保守的なデフォルトを使用します。モデルの実際の上限が不明な場合はこれを選んでください。';

  @override
  String get contextSpecify => '指定';

  @override
  String get contextUnlimited => '無制限';

  @override
  String get contextUnlimitedDesc =>
      'すべての候補を1回のリクエストで送信し、プロンプトアシスタントをウィンドウサイズで制限しません。';

  @override
  String get contextMax => '最大コンテキスト';

  @override
  String contextTokens(String size) {
    return '$size tokens';
  }

  @override
  String get contextWindowHint =>
      'リクエストごとの画像バッチ分割と、プロンプトアシスタントのナレッジベース読み取り・要約の予算に使われます。';

  @override
  String get contextSliderHint =>
      '8k〜1M の 9 段階。ドラッグは近くのプリセットに吸着し、目盛りラベルをタップするとそこへ移動します。入力欄は 128k / 1m の短縮表記を受け付け、↑↓ で隣のプリセット、⇧↑↓ で主要プリセットのみを移動します。入力した値が優先され、プリセットの間では比例した位置に止まります。';

  @override
  String get contextTokensUnit => 'tokens';

  @override
  String get outputCap => '最大出力';

  @override
  String get outputCapAuto => '自動';

  @override
  String get outputCapSpecify => '上限を指定';

  @override
  String get outputCapAutoDesc =>
      '上限を送らず、ホスト側の既定に任せます。中継サービスの既定は 4k–8k のことが多く、プロンプトアシスタントの 1 回の納品は 6–8k トークンです。返答が途中で切れる場合は上限を指定してください。';

  @override
  String get outputCapAutoAnthropicDesc =>
      'Anthropic 形式では上限が必須のため、未指定時は 8192 を送ります。思考と本文がこの上限を共有します。推論を有効にする場合は 32k 以上の指定を推奨します。';

  @override
  String get outputCapSpecifyDesc =>
      '毎回のリクエストに付けて送ります。思考と本文が共有します。8k 未満ではプロンプトアシスタントが途中で切れやすくなります。Claude と GPT-5 系は 64k–128k まで指定できます。';

  @override
  String get outputCapSliderHint =>
      '4k〜128k の 6 段階。入力欄は 64k の省略表記を受け付け、←→ で隣の段階へ移動します。入力した値が優先されます。';

  @override
  String get outputCapSpecifyInvalid => '正の整数を入力してください。空欄または 0 は保存できません。';

  @override
  String outputCapExceedsWindow(String window) {
    return 'コンテキストウィンドウ（$window トークン）以上です。ウィンドウを超える分は効きません。ホスト型のエンドポイントはリクエストを拒否し、ローカル実行環境は黙って切り詰めます。保存はできますが、両方の値を確認してください。';
  }

  @override
  String outputCapDefault(String size) {
    return '既定 $size';
  }

  @override
  String outputCapChip(String size) {
    return '出力 $size';
  }

  @override
  String get outputCapThinkingHint =>
      'このモデルは推論が有効です。思考トークンは本文より先にこの上限を消費するため、本文に必要な分より余裕を持たせてください。';

  @override
  String outputCapStarvesThinking(String min) {
    return '$min トークン未満では Anthropic 形式のモデルに思考予算が収まらず、リクエストは思考なしで（何も告げずに）送られます。';
  }

  @override
  String get contextPresets => 'プリセット';

  @override
  String contextStatusPreset(String label) {
    return '= $label · プリセット';
  }

  @override
  String contextStatusBetween(String lo, String hi) {
    return '≈ $lo–$hi';
  }

  @override
  String contextStatusBelow(String label) {
    return '< $label';
  }

  @override
  String contextStatusAbove(String label) {
    return '> $label';
  }

  @override
  String get agentBehavior => 'エージェント動作';

  @override
  String get forceViewAllImages => 'すべての参考画像を確認';

  @override
  String get forceViewAllImagesDesc =>
      'エージェントは結果を提出する前にすべての参考画像を確認します。小規模なローカルモデルに推奨。';

  @override
  String get reasoningEffort => '推論強度';

  @override
  String get reasoningEffortDesc =>
      '回答前にモデルがどれだけ考えるか。デフォルト＝何も送信しない（エンドポイント任せ）。他のレベルは出力トークンを消費します。OpenAI・Anthropic 形式のチャネルに適用。Anthropic 形式では Claude 4.6 以降にレベルを output_config.effort として送信します。「最高」は最新世代のモデルのみ受け付け、400 でレベルが指摘された場合は一段下げてください。';

  @override
  String get reasoningEffortDefault => 'デフォルト（送信しない）';

  @override
  String get reasoningEffortOff => 'オフ';

  @override
  String get reasoningEffortLow => '低';

  @override
  String get reasoningEffortMedium => '中';

  @override
  String get reasoningEffortHigh => '高';

  @override
  String get reasoningEffortMax => '最高';

  @override
  String get reasoningEffortDefaultShort => 'デフォルト';

  @override
  String get reasoningEffortOn => 'オン';

  @override
  String get reasoningEffortUnavailable => '利用不可';

  @override
  String get enableThinking => '拡張思考';

  @override
  String get enableThinkingDesc =>
      '回答前にモデルに推論させます。出力トークンを消費し、Anthropic 形式のチャンネルのみ対応。';

  @override
  String get enableWebSearch => 'サーバー側ウェブ検索';

  @override
  String get enableWebSearchDesc =>
      '回答中にプロバイダー自身がウェブ検索を実行します。追加トークンとして課金され、代理でページを取得します。';

  @override
  String get enableWebSearchTracelessHint =>
      'このプロトコルでは検索の痕跡が残りません。出典や引用は返されず、実際に検索が行われたかも確認できません。';

  @override
  String get noProviderMatch => '一致するプロバイダーがありません';

  @override
  String get apiKeyRequired => 'このプロバイダーはチャンネル追加に API キーが必要です';

  @override
  String get endpointRequired => 'エンドポイント URL を入力してください';

  @override
  String get probeRetry => '再試行';

  @override
  String get customColor => 'カスタムカラー';

  @override
  String get channelListPreview => '一覧プレビュー';

  @override
  String get pickerNoMatches => '一致する項目がありません';

  @override
  String pickerMatchCount(int count) {
    return '$count 件を表示';
  }

  @override
  String get selectAChannel => 'チャンネルを選択';

  @override
  String get searchChannels => 'チャンネル名またはタグを検索...';

  @override
  String get kindChat => 'チャット';

  @override
  String get kindImage => '画像';

  @override
  String get kindVideo => '動画';

  @override
  String get kindMultimodal => 'マルチモーダル';

  @override
  String reasoningChip(String level) {
    return '推論·$level';
  }

  @override
  String get webSearchChip => 'ウェブ検索';

  @override
  String get viewAllImagesChip => '全参考画像';

  @override
  String countGroups(int count) {
    return '$count 組';
  }

  @override
  String get providerGroupVendor => 'ベンダー';

  @override
  String get providerGroupVendorHint => '公式接続 · アドレス入力済み';

  @override
  String get providerGroupRelay => '中継';

  @override
  String get providerGroupRelayHint => 'プロトコル既知 · アドレスは自分で';

  @override
  String get providerGroupCustom => 'カスタム';

  @override
  String get providerGroupCustomHint => 'アドレス自入力 + プロトコル明示';

  @override
  String get providerGroupLocal => 'ローカル';

  @override
  String get providerGroupLocalHint => '既定は localhost';

  @override
  String get providerNeedKeyOnly => 'キーのみ';

  @override
  String get providerNeedEndpoint => 'アドレス必須';

  @override
  String get providerNeedKeyless => 'キー不要';

  @override
  String get providerCustomOpenAIDesc => 'OpenAI チャット面を提供する任意のホスト';

  @override
  String get providerCustomGoogleDesc => 'Google GenAI 面を提供する任意のホスト';

  @override
  String get providerCustomAnthropicDesc => 'Anthropic Messages 面を提供する任意のホスト';

  @override
  String get variantTitleGoogle => '接続方式';

  @override
  String get variantTitleMiniMax => 'インターフェース';

  @override
  String get variantTitleNewApi => 'APIフォーマット';

  @override
  String get variantTitleGeneric => '接続方式';

  @override
  String get variantTitleOpenAI => 'チャットインターフェース';

  @override
  String get variantHintGoogle =>
      'Google は同じモデルを 2 通りで提供します。切り替えると下のアドレスが書き換わります。';

  @override
  String get variantHintOpenAI =>
      'アドレスとキーは同じです。このチャンネルのチャットモデルが既定で使うインターフェースを決めます。個別のモデルはモデル編集で切り替えられます。';

  @override
  String get variantHintMiniMax =>
      'MiniMax は 2 つのインターフェースを提供しています。どちらかを選択（後から変更可）。';

  @override
  String get variantHintArk =>
      '2 種類のキーは互換性がありません：プランのキーは /api/plan/v3 のみ、従量課金のキーは /api/v3 のみで使えます。切り替えはアドレスだけを書き換えます。';

  @override
  String get variantHintNewApi => 'ホストはご自身で入力。バージョンパスは選んだフォーマットに追従します。';

  @override
  String get variantHintGeneric => '切り替えると下のアドレスが書き換わります。';

  @override
  String get variantGoogleNative => 'GenAI ネイティブ';

  @override
  String get variantGoogleOpenAI => 'OpenAI 互換面';

  @override
  String get variantMiniMaxOpenAI => 'OpenAI 面';

  @override
  String get variantArkPayg => '従量課金';

  @override
  String get variantArkPlan => 'サブスクリプションプラン';

  @override
  String get variantMiniMaxAnthropic => 'Anthropic 面';

  @override
  String get variantOpenAIChat => 'Chat Completions';

  @override
  String get variantOpenAIResponses => 'Responses';

  @override
  String get variantNewApiOpenAI => 'OpenAI 形式';

  @override
  String get variantNewApiOpenAIResponses => 'OpenAI Responses 形式';

  @override
  String get variantNewApiGemini => 'Gemini 形式';

  @override
  String get variantNewApiAnthropic => 'Anthropic 形式';

  @override
  String get channelPresetLabel => 'プロバイダプリセット';

  @override
  String get changePreset => 'プリセットを変更';

  @override
  String get presetUnmatched => '該当プリセットなし';

  @override
  String get presetUnmatchedHint =>
      'このチャンネルは旧バージョンで作成された、現在は提供されていない種別です。そのままでも動作します。「プリセットを変更」すると下の項目が上書きされます。';

  @override
  String get presetEndpointModified => 'アドレス変更済み';

  @override
  String get restorePresetEndpoint => 'プリセット値に戻す';

  @override
  String get changePresetOverlayHint =>
      '選択するとプロトコルとアドレスがプリセット値で上書きされます（キー・名前・タグはそのまま）。';

  @override
  String get protocolField => 'APIプロトコル';

  @override
  String get deprecatedLabel => '非推奨';

  @override
  String get apiKeyOptional => '任意';

  @override
  String get apiKeyLocalPlaceholder => 'ローカルサービスは通常不要';

  @override
  String get apiKeyLocalNote =>
      '空欄で構いません。ローカルサービスにリバースプロキシ認証を付けている場合は、そのキーを入力してください。';

  @override
  String get searchProvidersAlias => 'プロバイダを検索、「Qwen」でも可';

  @override
  String providerCountSummary(int count, int groups) {
    return '$count プロバイダ · $groups グループ';
  }

  @override
  String providerVariantCount(int count) {
    return '$count 通り';
  }

  @override
  String get requestMethod => 'リクエスト方式';

  @override
  String get interfaceProtocol => 'API プロトコル';

  @override
  String get protocolAuto => '自動';

  @override
  String protocolAutoResolved(String name) {
    return '自動 · 現在は「$name」で解決';
  }

  @override
  String get protocolAutoHelper => 'チャネルとモデル種別に従い、どちらかを変更すると自動で再解決されます。';

  @override
  String protocolStaleHelper(String name) {
    return '以前の選択「$name」は現在のプロバイダーでは利用できないため、自動に戻りました。';
  }

  @override
  String get protocolOpenAICompat => 'OpenAI 互換';

  @override
  String get protocolOpenAIResponses => 'OpenAI Responses';

  @override
  String get protocolOpenAIResponsesDesc =>
      '同じアドレスとキーで使える OpenAI の新しいインターフェース。ツール呼び出しの間もモデルの推論を保持します。';

  @override
  String get reasoningEffortResponsesHint =>
      'reasoning.effort として送信されます。Grok 4.5 と 4.6 は推論をオフにできず「オフ」は拒否されます。どの Grok も「最大」は受け付けません。レベルを名指しした 400 が返ったら別のレベルを選んでください。';

  @override
  String get protocolAnthropicCompat => 'Anthropic 互換';

  @override
  String get protocolDashScopeNative => 'DashScope ネイティブ';

  @override
  String get protocolDashScopeNativeDesc =>
      'Alibaba 独自のリクエスト形式。qwen-audio はこの経路のみ';

  @override
  String get protocolImageSync => '同期生成';

  @override
  String get protocolImageSyncDesc => '1 回のリクエストで画像を直接返します';

  @override
  String get protocolImageAsync => '非同期タスク';

  @override
  String get protocolImageAsyncDesc => '送信後に結果をポーリング。生成中はキャンセル可能';

  @override
  String get protocolChatImage => 'チャット経由で画像を返す';

  @override
  String get protocolChatImageDesc => '画像はチャットの返信で返されます。多くの中継サービスはこの方式です';

  @override
  String get protocolImagesApiDesc => 'OpenAI の画像 API、gpt-image シリーズ';

  @override
  String get protocolImagenDesc => 'Google の画像生成専用 API';

  @override
  String get protocolVideosApiDesc => 'OpenAI の動画タスク API（Sora 形式）';

  @override
  String get protocolVeoDesc => 'Google の動画タスク API';

  @override
  String get protocolXaiImages => 'xAI 画像';

  @override
  String get protocolXaiVideos => 'xAI 動画';

  @override
  String get protocolMinimaxImages => 'MiniMax 画像';

  @override
  String get protocolArkImages => 'Ark 画像';

  @override
  String get protocolArkImagesDesc => 'Seedream のネイティブ画像エンドポイント。参照画像は JSON で同送';

  @override
  String get protocolMinimaxVideo => 'MiniMax 動画';

  @override
  String protocolAutoMenuDesc(String name) {
    return 'チャネルとモデル種別に従い、現在は「$name」に解決';
  }

  @override
  String protocolUnrecognizedAuto(String name) {
    return 'このモデル ID は認識できないため、チャネルの既定方式で送信します。中継サービスが「$name」を使う場合は手動で選択してください。';
  }

  @override
  String protocolUnrecognizedSingle(String name) {
    return 'このモデル ID は認識できないため、パラメータは「$name」の既定値に従います。';
  }

  @override
  String get protocolParamsLabel => 'パラメータ';

  @override
  String get protocolParamsNone => '専用パラメータはなく、プロンプトと参照画像のみ';

  @override
  String get protocolParamReferenceLimit => '参照画像の上限';

  @override
  String protocolSendVia(String name) {
    return '「$name」で送信';
  }

  @override
  String get protocolOnlyOneWay => '· このチャネルはこの方式のみ';

  @override
  String protocolNoSurface(String format, String kind) {
    return 'このチャネルは $format 形式で、$kindの API がありません。モデルは保存できますが、ワークベンチには表示されません。';
  }

  @override
  String protocolChatImageUnlikely(String format) {
    return '$format 形式はほとんど画像を返しません。成功するかは中継サービス次第です。';
  }

  @override
  String protocolStaleKindHelper(String kind, String name) {
    return '種別が「$kind」に変わったため、以前の選択「$name」は適用されず、自動に戻りました。';
  }

  @override
  String protocolStreamIgnored(String name) {
    return '「$name」はストリーミングを使用しないため、この設定は無視されます';
  }

  @override
  String get protocolAutoSuffix => '· 自動';

  @override
  String get protocolBackToAuto => '自動に戻す';

  @override
  String get contextImageUnsetDesc => '画像モデルはコンテキスト予算を使いません。未設定のままで構いません。';

  @override
  String get contextVideoUnsetDesc => '動画モデルはコンテキスト予算を使いません。未設定のままで構いません。';

  @override
  String get protocolVideoTask => '非同期動画タスク';

  @override
  String get protocolAsyncQueueNote => '送信後はタスクキューでポーリングされ、生成中はキャンセルできます。';

  @override
  String get protocolPinStale => '選択は無効';

  @override
  String protocolStaleTooltip(String name) {
    return '以前の選択「$name」は利用できないため、自動で実行しています。';
  }

  @override
  String get channelReorderHandleTooltip => 'ドラッグして並べ替え';

  @override
  String get channelOrderSaveFailed => '並び順を保存できませんでした。元の順序に戻しました';

  @override
  String wizardStepCounter(int current, int total) {
    return 'ステップ $current / $total';
  }

  @override
  String get wizardStepsAdaptNote => 'プロバイダーの接続方式に応じてステップが変わります';

  @override
  String providerNoMatchHint(String query) {
    return '「$query」は一覧にありません。「カスタム」グループでエンドポイントを入力し、OpenAI 互換を選んでください。';
  }

  @override
  String get providerUseCustom => 'カスタムとして追加';

  @override
  String get probeSkippableNote => '省略可。次のステップで名前とタグを設定できます';

  @override
  String endpointPresetValue(String endpoint) {
    return 'プリセット値：$endpoint';
  }

  @override
  String get variantResultLabel => '結果';

  @override
  String get probeOkNext => 'すぐにモデル検出を有効にできます';

  @override
  String get probeNoModelsNext =>
      'エンドポイントとキーは有効ですが、モデル一覧が空です。Model ID を手動で追加してください。';

  @override
  String get probeAuthFailedNext => 'キーが完全にコピーされているか、期限切れでないか確認してください。';

  @override
  String get probeNotAnApiNext =>
      'HTML ページが返りました。コンソールの URL かもしれません。API エンドポイントは通常 /v1 か /v1beta で終わります。';

  @override
  String get probeUnreachableNext =>
      'DNS の解決に失敗したかタイムアウトしました。URL、プロキシ、ネットワークを確認してください。';

  @override
  String get probeUpstreamError => 'エンドポイントは応答しましたが、現在リクエストを拒否しています';

  @override
  String get probeUpstreamErrorNext =>
      'レート制限（429）またはサーバーエラー（5xx）です。URL とキーは問題なさそうです。しばらくしてから再試行してください。';

  @override
  String get probeNotSupportedNext =>
      'このプロトコルにはモデル一覧がないため、タスクを送信して確認するしかありません。';

  @override
  String get previewEmptyKeyNote => 'キーは未入力です。あとでチャネル編集から追加できます。';

  @override
  String get presetShortHint => 'エンドポイントとプロトコルをワンタップで入力';

  @override
  String get deleteChannel => 'チャネルを削除';

  @override
  String get discoveryOffEffect => 'オフにすると、このチャネルでは「モデル取得」が無効になります';

  @override
  String get protocolUnavailable => '利用不可';

  @override
  String get reasoningEffortUnsupported =>
      'このモデルは推論パラメーターを受け付けないため、スライダーは「オフ」のままです。対応するモデルに切り替えると有効になります。';

  @override
  String get modelIdRequiredTitle => 'Model ID は空にできません';

  @override
  String get modelIdRequiredDesc => '唯一の必須項目です。名前を空にすると ID が表示名になります。';

  @override
  String get contextSpecifyInvalid => '正の整数を入力してください。空欄や 0 は保存できません。';

  @override
  String get addModelSubtitle => '手動で追加する場合、必須は ID だけです';

  @override
  String get addModelIdHelper => '空欄では保存できません。名前が空なら ID を使います。';

  @override
  String get addModelDefaultsNote =>
      'プロトコル、コンテキストウィンドウ、機能スイッチは Auto / 既定のままです。まず追加して一度動かし、必要なものだけ固定してください。';

  @override
  String get modelNameOptionalHint => '空欄でも可';

  @override
  String get moveUp => '上へ移動';

  @override
  String get moveDown => '下へ移動';

  @override
  String get channelReorderFootnote =>
      'ホバーでハンドル表示 · ドラッグで並べ替え · 右クリックか Alt+↑/↓ でも可';

  @override
  String get noModelsConfiguredHint => '「モデル取得」で検出するか、手動で追加してください。';

  @override
  String get addModelManually => '手動で追加';

  @override
  String get selectAChannelHint => '左でチャネルを選ぶと、ここにそのモデルが表示されます。';

  @override
  String noModelsMatchQuery(String query) {
    return '「$query」に一致するモデルはありません';
  }

  @override
  String get noFeeGroupsHint => 'グループを作成し、モデルを割り当ててください。';

  @override
  String get noNewModelsFoundHint => 'このチャネルが返したモデルはすべて一覧にあります。';

  @override
  String get discoveryCapabilitiesNote =>
      '検出されたモデルは ID と種類だけを持ちます。機能、コンテキストウィンドウ、料金グループはモデルごとに設定します。';

  @override
  String deleteChannelTitle(String name) {
    return 'チャネル「$name」を削除しますか？';
  }

  @override
  String deleteChannelModelsNote(int count) {
    return 'モデル $count 件も削除されます';
  }

  @override
  String get deleteChannelBody =>
      'これらのモデルを使うワークベンチの設定は「モデル未選択」になります。送信済みのタスクには影響しません。使用記録はモデル名で残ります。';

  @override
  String get newFeeGroup => '新しいグループ';

  @override
  String get cachePriceBlankPlaceholder => '空欄 = 入力価格と同じ';

  @override
  String get fetchFailedTitle => '接続に失敗しました';

  @override
  String get channelDefaultFeeGroup => '既定の料金グループ';

  @override
  String get channelDefaultFeeGroupHint => 'このチャンネルに追加したモデルは、最初にこのグループに入ります';

  @override
  String get modelIdTakenTitle => 'このチャンネルには同じ Model ID がすでにあります';

  @override
  String get modelIdTakenDesc =>
      'Model ID はチャンネル内で一意である必要があります。ID を変えるか、すでにあるモデルを編集してください。';

  @override
  String get perSpec => '仕様別';

  @override
  String get specUnitImage => '枚あたり';

  @override
  String get specUnitSecond => '秒あたり';

  @override
  String get specUnitClip => '本あたり';

  @override
  String get specUnitSuffixImage => '/枚';

  @override
  String get specUnitSuffixSecond => '/秒';

  @override
  String get specUnitSuffixClip => '/本';

  @override
  String get specUnitNoteImage => '1 枚 = 1 単位';

  @override
  String get specUnitNoteSecond => '1 秒 = 1 単位';

  @override
  String get specUnitNoteClip => '1 本 = 1 単位';

  @override
  String get specUnitLabel => '単位';

  @override
  String get specDimSize => 'サイズ / 解像度';

  @override
  String get specDimQuality => '品質';

  @override
  String get specDimSeconds => '長さ（秒）';

  @override
  String get specAnyValue => '指定なし';

  @override
  String get specGroupImageSizes => '画像サイズ';

  @override
  String get specGroupVideoRes => '動画解像度';

  @override
  String get specOtherRates => 'その他の仕様';

  @override
  String get specOtherRatesSub => '未掲載のサイズ · 品質 · 長さ';

  @override
  String get specAddRate => '料金を追加';

  @override
  String get specCustomValue => 'カスタム…';

  @override
  String get specCustomHint => '大文字小文字は正規化されます（2k → 2K）';

  @override
  String specPriceLabel(String suffix) {
    return '単価 \$$suffix';
  }

  @override
  String get specPricePlaceholder => '単価を入力';

  @override
  String get specPriorityRule => '空欄は「指定なし」。複数行に一致する場合は条件の多い行を優先します。';

  @override
  String specPriceMissing(int n) {
    return '$n 行目の単価が未入力です。保存前に入力してください。';
  }

  @override
  String specDuplicateRow(int a, int b, String cond) {
    return '$a 行目と $b 行目の条件が同じです（$cond）。1 行削除するか条件を変えてください。';
  }

  @override
  String get specOtherBlankHint => '空欄の場合、未掲載の仕様は 0 として計算します。';

  @override
  String get specOnlyOtherHint => '「その他の仕様」だけの場合は「回数別」と同じ動作です。';

  @override
  String get specSwitchToRequest => '回数別に切り替え';

  @override
  String specSummary(String unit, int n, String min, String max) {
    return '$unit · $n 段階 · $min–$max';
  }

  @override
  String specSummaryEmpty(String unit) {
    return '$unit · 0 段階';
  }

  @override
  String get specOtherZero => 'その他の仕様は 0';

  @override
  String get modelCardBilling => '課金';

  @override
  String get specUnitSuffixRequest => '/回';

  @override
  String get filterFeeGroups => '料金グループを絞り込む…';

  @override
  String get reorderFeeGroups => '並べ替え';

  @override
  String get feeGroupPickTitle => '編集するグループを選択';

  @override
  String get feeGroupPickText =>
      'グループカードか編集ボタンを押すと、ここにエディタが開きます。「新しいグループ」もここに開きます。';

  @override
  String get feeGroupReorderTitle => '左のハンドルをドラッグして並べ替え';

  @override
  String get feeGroupReorderText =>
      '順序はモデル・チャンネル編集の料金グループ選択にも反映されます。離すと保存されます。';

  @override
  String get feeGroupReorderNote => '絞り込み中は並べ替えできません。離すと順序が保存されます。';

  @override
  String get feeGroupReorderHint => 'グループを長押ししてドラッグ。離すと順序が保存されます。';

  @override
  String get deleteGroup => 'グループを削除';

  @override
  String deleteFeeGroupInUse(int count) {
    return '$count 個のモデルが料金グループなしになります。';
  }

  @override
  String get editGroupTitle => 'グループを編集';

  @override
  String get feeGroupNamePlaceholder => 'グループ名を入力';

  @override
  String get tokenPriceHint =>
      '100 万トークン単位で課金。キャッシュ入力が未入力なら入力価格で計算。画像 / 動画モデルは「仕様別」を使ってください。';

  @override
  String get discardChangesTitle => '未保存の変更を破棄しますか？';

  @override
  String get discardChangesBody => '別のグループに切り替えると、ここでの変更は失われます。';

  @override
  String get discard => '破棄';

  @override
  String get modelsUsingGroup => '使用中のモデル';

  @override
  String get sortModels => '並べ替え';

  @override
  String get modelSortDefault => '既定の順序';

  @override
  String get modelSortDefaultHint => 'チャンネルから取得した順序、または手動で並べた順序';

  @override
  String get modelSortName => '名前';

  @override
  String get modelSortKind => '種類';

  @override
  String get modelSortAdded => '追加日時';

  @override
  String get sortAscending => '昇順';

  @override
  String get sortDescending => '降順';

  @override
  String modelSortTooltip(String key, String direction) {
    return '並べ替え：$key · $direction';
  }

  @override
  String get modelGroupByChannel => 'チャンネルごとにグループ化';

  @override
  String get modelGroupByChannelHint => 'オフにすると、すべてのチャンネルのモデルが 1 つのリストになります';

  @override
  String get routeDashScopeShort => 'DashScope';

  @override
  String get routeDashScopeFull => 'DashScope ネイティブ';

  @override
  String get routeSectionTitle => 'ルート';

  @override
  String get routeScopeModel => 'モデル';

  @override
  String routeScopeThisRoute(String route) {
    return 'このルート · $route';
  }

  @override
  String get routePrimarySuffix => 'メイン';

  @override
  String channelMergeBannerTitle(int count) {
    return '$count 組のチャンネルを統合できます';
  }

  @override
  String get channelMergeBannerReason => '同じプラットフォーム・ホスト・キーで、プロトコルだけが異なります';

  @override
  String get channelMergeBannerAction => '確認';

  @override
  String get mergeDialogTitle => 'チャンネルを統合';

  @override
  String mergeDialogProgress(
    int index,
    int total,
    String platform,
    String host,
  ) {
    return '$index / $total · $platform · $host';
  }

  @override
  String get mergeKeep => '残す';

  @override
  String get mergeAbsorb => '統合後に削除';

  @override
  String get mergeRoutesAfter => '統合後のルート';

  @override
  String get mergeRouteAdded => '統合';

  @override
  String mergeReferencesNote(String what, String channel) {
    return '$whatが残すモデルを指すようになります。統合したモデルは「$channel」側の名前・料金グループ・コンテキスト設定を保ちます。';
  }

  @override
  String mergeReferencesNone(String channel) {
    return '統合で消えるモデルを指す保存済みの項目はありません。統合したモデルは「$channel」側の名前・料金グループ・コンテキスト設定を保ちます。';
  }

  @override
  String mergeRefSelections(int count) {
    return '選択中のモデル $count 件';
  }

  @override
  String mergeRefRecords(int count) {
    return '$count 件の使用記録';
  }

  @override
  String mergeRefLinks(int count) {
    return 'アシスタントの会話内の $count 件のモデルリンク';
  }

  @override
  String get mergeRefSeparator => '、';

  @override
  String get mergeRefLast => 'と';

  @override
  String mergeModelJoin(String route) {
    return '同名モデルを統合 · $route のパラメータを引き継ぎ';
  }

  @override
  String get mergeModelJoinMedia => '同名モデルを統合';

  @override
  String mergeModelMove(String route) {
    return '移動 · $route に固定';
  }

  @override
  String get mergeIrreversible =>
      '統合は元に戻せません。キーの一致はこの端末のメモリ内で比較しており、キー自体は表示も記録もしません。';

  @override
  String get mergeSkip => 'このグループをスキップ';

  @override
  String get mergeConfirm => '統合';

  @override
  String get mergeDone => 'チャンネルを統合しました';

  @override
  String get routeHost => 'ホスト';

  @override
  String get routeHostHint => 'スキームとホスト、ポートまで。各ルートのパスは下で設定します。';

  @override
  String get routeTableCaption => 'プロトコルごとに 1 本まで · 先頭がメイン';

  @override
  String routePathDefault(String path) {
    return '既定 $path';
  }

  @override
  String routePathEdited(String path) {
    return '変更済み · 既定 $path';
  }

  @override
  String get routePathOwnHost => '独自ホスト';

  @override
  String routePathHostItself(String path) {
    return 'ホストそのもの · 既定 $path';
  }

  @override
  String get routePathHostItselfHint => '（ホストそのもの）';

  @override
  String get routeUseHostItself => 'ホストそのものを使う';

  @override
  String get routeRestoreDefault => '既定に戻す';

  @override
  String get routeOfficialLocked => '公式アドレス（固定）';

  @override
  String get routeTest => 'このルートをテスト';

  @override
  String get routeMakePrimary => 'メインにする';

  @override
  String get routeIsPrimary => 'すでにメインです';

  @override
  String get routeRemove => 'このルートをオフ';

  @override
  String routeEnable(String route) {
    return '$route を有効にする';
  }

  @override
  String routeInUse(int count) {
    return '$count 個のモデルが使用中のためオフにできません';
  }

  @override
  String get routeOnlyOne => 'チャンネルには少なくとも 1 本のルートが必要です';

  @override
  String routePinnedSnack(int count, String route) {
    return '$count 個のモデルは $route のままです';
  }

  @override
  String routeMovedSnack(int count, String route) {
    return '$count 個のモデルを $route に移しました：元のルートが削除されたため';
  }

  @override
  String get routesToCreate => '作成するルート';

  @override
  String get routeFeatureWebSearch => 'ウェブ検索';

  @override
  String get routeFeaturePromptCache => 'プロンプトキャッシュ';

  @override
  String get routesToCreateHint => '使わないものは後でチャンネル編集からオフにできます';

  @override
  String get routeKeyShared => '1 つのキーをすべてのルートで共有します';

  @override
  String routeWizardNote(String route) {
    return '新しいモデルはメインルート（$route）を使います。別のルートにするにはモデル編集上部のルートバーで切り替えます。パラメータはルートごとに独立です。';
  }

  @override
  String routeSwitchTitle(String route) {
    return '$route に切り替え · 次のパラメータが変わります';
  }

  @override
  String get routeSwitchUnset => '未設定 · 送信しない';

  @override
  String routeSwitchNote(String route) {
    return '$route のパラメータはそのルートに残り、戻すと元どおりになります。Web 検索はモデルの許可で、ルートでは変わりません。';
  }

  @override
  String get routeSwitchConfirm => '切り替え';

  @override
  String get routeWebSearchPerRoute => 'ルート別';

  @override
  String get routeWebSearchNotSent =>
      '現在のルートは Web 検索を送信しません。スイッチはオンのまま、送信できるルートで有効になります。';

  @override
  String get routeWebSearchSends => 'このルートで送信されます';

  @override
  String get routeWebSearchCannot => 'このルートでは送信できません';

  @override
  String get routeWebSearchUntested => '送信はしますが、このプラットフォームでは未検証です';

  @override
  String get routeWebSearchUntestedNote =>
      '現在のルートはウェブ検索を送信しますが、このプラットフォームが実行するかは未検証です。返信に検索の形跡がなければ、検証済みのルートに切り替えてください。';

  @override
  String get platformDashScope => 'Alibaba DashScope';

  @override
  String get platformCustom => 'カスタム';

  @override
  String get routePrimaryCantRemove => 'メインルートはオフにできません。先に別のルートをメインにしてください';

  @override
  String get routeEnableShort => '有効にする';

  @override
  String mergeFailed(String error) {
    return '統合に失敗しました。何も変更していません：$error';
  }

  @override
  String get prompts => 'プロンプト';

  @override
  String get promptLibrary => 'プロンプトライブラリ';

  @override
  String get newPrompt => '新しいプロンプト';

  @override
  String get editPrompt => 'プロンプトを編集';

  @override
  String get noPromptsSaved => 'プロンプトが保存されていません';

  @override
  String get createFirstPrompt => '最初のプロンプトを作成';

  @override
  String get deletePromptConfirmTitle => 'プロンプトを削除しますか？';

  @override
  String deletePromptConfirmMessage(String title) {
    return '「$title」を削除してもよろしいですか？';
  }

  @override
  String get title => 'タイトル';

  @override
  String get tagCategory => 'タグ（カテゴリ）';

  @override
  String get promptContent => 'プロンプトの内容';

  @override
  String get userPrompts => 'ユーザープロンプト';

  @override
  String get refinerPrompts => 'リファイナープロンプト';

  @override
  String get systemTemplates => 'システムテンプレート';

  @override
  String get templateType => 'テンプレートタイプ';

  @override
  String get typeRename => '一括名前変更';

  @override
  String get typeRefiner => 'プロンプトリファイナー';

  @override
  String get categoriesTab => 'カテゴリ';

  @override
  String get addCategory => 'カテゴリを追加';

  @override
  String get editCategory => 'カテゴリを編集';

  @override
  String get library => 'ライブラリ';

  @override
  String get refiner => 'リファイナー';

  @override
  String get selectionMode => '選択モード';

  @override
  String nSelected(int count) {
    return '$count 件を選択';
  }

  @override
  String get categorize => '分類';

  @override
  String get bulkCategorize => '一括分類';

  @override
  String get selectCategoriesToApply => '選択したプロンプトに適用するカテゴリを選択：';

  @override
  String deleteNPromptsConfirm(int count) {
    return '$count 件のプロンプトを削除しますか？';
  }

  @override
  String get actionCannotBeUndone => 'この操作は取り消せません。';

  @override
  String deleteCategoryConfirmMessage(String name) {
    return 'カテゴリ「$name」を削除しますか？プロンプトは General に移動されます。';
  }

  @override
  String get moveToTop => '先頭へ移動';

  @override
  String get moveToBottom => '末尾へ移動';

  @override
  String get addSystemTemplateHint => 'リファイナーまたは一括名前変更用のシステムテンプレートをここに追加します。';

  @override
  String importFailed(String error) {
    return 'インポートに失敗しました：$error';
  }

  @override
  String get filterAll => 'すべて';

  @override
  String get newTemplate => '新しいテンプレート';

  @override
  String get reorderDisabledWhileFiltered => 'フィルターまたは検索中は並べ替えできません';

  @override
  String get matchModeLabel => '一致';

  @override
  String get matchAny => 'いずれか';

  @override
  String get matchAllTags => 'すべて';

  @override
  String promptFilterSummary(int count, int matches) {
    return '$count 個のカテゴリで絞り込み · $matches 件一致';
  }

  @override
  String get promptEditorSubtitle => '保存するとワークベンチからワンクリックで適用できます';

  @override
  String get categoryColorHint => '色はカテゴリを見分けるためだけに使います';

  @override
  String promptCount(int count) {
    return '$count 件のプロンプト';
  }

  @override
  String get categoryDeleteNote => 'カテゴリを削除すると、そのプロンプトは General に移り、削除はされません。';

  @override
  String importFileSummary(String file, int count) {
    return '$file · $count 件';
  }

  @override
  String importMergeDetail(int current) {
    return '既存の $current 件を残し、重複しないものを追加';
  }

  @override
  String importReplaceDetail(int current, int count) {
    return '既存の $current 件を削除し、ファイルの $count 件だけを残す';
  }

  @override
  String get promptLibraryEmptyHint =>
      'ワークベンチでよく使うプロンプトを保存すれば、次からワンクリックで適用できます。';

  @override
  String get colorPresets => 'プリセット';

  @override
  String get presetOutput => '出力';

  @override
  String get presetOutputPrompt => 'プロンプト';

  @override
  String get presetOutputAnalysis => '分析テキスト';

  @override
  String get presetOutputAnalysisShort => '分析';

  @override
  String get presetOutputPromptHelp =>
      'アシスタントは結果をバージョン付きのプロンプトカードとして渡し、ワンクリックでワークベンチに適用できます。';

  @override
  String get presetOutputAnalysisHelp =>
      'アシスタントはこのプリセットが定める構成で会話の中に直接回答し、結果はコピーできます。明示的に頼めば、プロンプトも別に出せます。';

  @override
  String get settings => '設定';

  @override
  String get appearance => '外観';

  @override
  String get connectivity => '接続性';

  @override
  String get application => 'アプリケーション';

  @override
  String get proxySettings => 'プロキシ設定';

  @override
  String get enableProxy => 'グローバルプロキシを有効にする';

  @override
  String get proxyUrl => 'プロキシURL (ホスト:ポート)';

  @override
  String get proxyUsername => 'プロキシユーザー名 (オプション)';

  @override
  String get proxyPassword => 'プロキシパスワード (オプション)';

  @override
  String get language => '言語';

  @override
  String get themeAuto => '自動';

  @override
  String get themeLight => 'ライト';

  @override
  String get themeDark => 'ダーク';

  @override
  String get themeColor => 'テーマカラー';

  @override
  String get themeColorHintCards =>
      '各カードの左半分がライトモード、右半分がダークモードで、ボタン・スイッチ・選択行はそのモードで実際に描かれる色で表示されます。2 つの色は別々に調整済みです。ライトはやや深めで白い文字が読め、ダークはやや明るく鮮やかで、その上の文字は同系色の濃いインクになります。';

  @override
  String get themeColorHintDots =>
      '各テーマカラーには調整済みの 2 色があります。ライトモードでは深い方、ダークモードでは明るく鮮やかな方が使われます。長押しで色の値を確認できます。';

  @override
  String themeColorPair(String light, String dark) {
    return 'ライト $light · ダーク $dark';
  }

  @override
  String get themeColorCustom => 'カスタム…';

  @override
  String get font => 'フォント';

  @override
  String get fontSystem => 'システムデフォルト';

  @override
  String get fontDownloadTitle => 'フォントをダウンロード';

  @override
  String get fontDownloadPrompt =>
      'このフォントはアプリに同梱されていないため、使用する前に一度ダウンロードする必要があります。';

  @override
  String get fontDownloadAction => 'ダウンロード';

  @override
  String get fontDownloading => 'フォントをダウンロード中…';

  @override
  String get fontDownloadFailed => 'フォントのダウンロードに失敗しました。接続を確認して再試行してください。';

  @override
  String get renderingGpu => '描画に使用中のGPU';

  @override
  String get renderingGpuUnavailable => '取得できませんでした';

  @override
  String get openGraphicsSettings => 'Windowsのグラフィック設定';

  @override
  String get reduceVisualEffects => '視覚効果を減らす';

  @override
  String get reduceVisualEffectsDesc => 'ぼかし効果を無効にして、内蔵GPUや低性能GPUでも滑らかに動作させます。';

  @override
  String get endpointUrl => 'エンドポイントURL';

  @override
  String get apiKey => 'APIキー';

  @override
  String get outputDirectory => '出力ディレクトリ';

  @override
  String get notSet => '未設定';

  @override
  String get dataManagement => 'データ管理';

  @override
  String get exportSettings => '設定をエクスポート';

  @override
  String get importSettings => '設定をインポート';

  @override
  String get openAppDataDirectory => 'アプリデータディレクトリを開く';

  @override
  String get mcpServerSettings => 'MCPサーバー設定';

  @override
  String get enableMcpServer => 'MCPサーバーを有効にする';

  @override
  String get port => 'ポート';

  @override
  String get resetAllSettings => 'すべての設定をリセット';

  @override
  String get confirmReset => 'すべての設定をリセットしますか？';

  @override
  String get resetWarning => 'これにより、すべての設定、モデル、追加されたフォルダが削除されます。この操作は元に戻せません。';

  @override
  String get resetEverything => 'すべてをリセット';

  @override
  String get settingsExported => '設定が正常にエクスポートされました';

  @override
  String get settingsImported => '設定が正常にインポートされました';

  @override
  String get exportOptions => 'エクスポートオプション';

  @override
  String get includeDirectories => 'ディレクトリ設定を含める';

  @override
  String get includeDirectoriesDesc => 'ワークベンチ/ブラウザのディレクトリと出力パス';

  @override
  String get includePrompts => 'プロンプトを含める';

  @override
  String get includePromptsDesc => 'ユーザーおよびシステムのプロンプトライブラリ';

  @override
  String get includeUsage => '使用状況メトリクスを含める';

  @override
  String get includeUsageDesc => 'APIトークン消費履歴';

  @override
  String get exportNow => '今すぐエクスポート';

  @override
  String get importOptions => 'インポートオプション';

  @override
  String get notInBackup => 'バックアップファイルで利用できません';

  @override
  String get importSettingsConfirm =>
      'これにより、現在のすべてのモデル、チャンネル、カテゴリが置き換えられます。\n\n注意：スタンドアロンのプロンプトライブラリはこのインポートの影響を受けません。プロンプトデータ管理にはプロンプト画面を使用してください。';

  @override
  String get importAndReplace => 'インポートして置換';

  @override
  String get importErrorPromptsOnly =>
      'これはプロンプトライブラリのエクスポートファイルであり、完全なバックアップではありません。プロンプト画面からインポートしてください。';

  @override
  String get importErrorNotABackup =>
      'このファイルは有効なバックアップではありません。「設定をエクスポート」で作成したファイルを選択してください。';

  @override
  String get importErrorNewerSchema =>
      'このバックアップは新しいバージョンのアプリで作成されました。アプリを更新してからインポートしてください。';

  @override
  String get importMode => 'インポートモード';

  @override
  String get merge => 'マージ';

  @override
  String get replaceAll => 'すべて置換';

  @override
  String get portableMode => 'ポータブルモード';

  @override
  String get portableModeDesc => 'データベースとキャッシュをアプリケーションフォルダに保存します（再起動が必要）';

  @override
  String get restartRequired => '再起動が必要です';

  @override
  String get restartMessage => 'データストレージの場所の変更を適用するには、アプリケーションを再起動する必要があります。';

  @override
  String get enableNotifications => 'システム通知を有効にする';

  @override
  String get runSetupWizard => 'セットアップウィザードを実行';

  @override
  String get clearTempFiles => '一時ファイルを削除';

  @override
  String get clearCookieHistory => 'Cookie 履歴を消去';

  @override
  String get clearCookieHistoryNote => 'ダウンローダーが記憶したサイトの Cookie';

  @override
  String get clearCookieHistoryConfirm =>
      'ダウンローダーが記憶したサイトの Cookie をすべて消去しますか？キューに追加済みのダウンロードには影響しません。';

  @override
  String get cookieHistoryCleared => 'Cookie 履歴を消去しました。';

  @override
  String get clearTempFilesConfirmTitle => '一時ファイルを削除しますか？';

  @override
  String clearTempFilesConfirmMessage(String size) {
    return 'マスク、切り抜きのコピー、ダウンローダーのキャッシュ、動画サムネイル $size を削除します。一時ワークスペース内でこれらを参照している項目も併せて取り除かれます。ご自身のフォルダ内のファイルはそのままです。';
  }

  @override
  String tempFilesCleared(String size) {
    return '$size を解放しました。';
  }

  @override
  String get enableApiDebug => 'APIデバッグログを有効にする';

  @override
  String get apiDebugDesc =>
      'トラブルシューティングのために生のAPIリクエストとレスポンスをファイルに記録します。警告：マスクされていない場合、APIキーなどの機密データが記録される可能性があります。';

  @override
  String get openLogFolder => 'ログフォルダを開く';

  @override
  String get iosOutputRecommend =>
      '推奨：iOSではデフォルトのままにしてください。アプリのフォルダは「ファイル」アプリで表示されます。';

  @override
  String get knowledgeBaseFolder => 'ナレッジベースフォルダ';

  @override
  String get kbOpenFolder => 'フォルダを開く';

  @override
  String get kbInvalidDir => 'フォルダが見つかりません';

  @override
  String get kbMissingEntry => 'フォルダに README.md が見つかりません';

  @override
  String get assistantContextRatio => 'アシスタント要約しきい値';

  @override
  String get assistantContextRatioDesc =>
      'プロンプトアシスタントは、コンテキスト使用量がモデルのウィンドウのこの割合に達すると会話を要約し、作業を続ける余地を空けます。コンテキストウィンドウが設定されたモデルにのみ適用されます。';

  @override
  String get kbSubAgent => 'ナレッジベース・サブエージェント';

  @override
  String get kbSubAgentDesc =>
      'アシスタントがナレッジベースの調査をサブエージェントに委任できるようにします。サブエージェントは独立したコンテキストでファイルを読み、メインの会話を軽く保ちます。実験的機能。';

  @override
  String get kbSubAgentModel => 'サブエージェントのモデル';

  @override
  String get kbSubAgentModelFollow => 'セッションのモデルに従う';

  @override
  String get kbSubAgentModelMissing => 'バインドされたモデルは存在しません。再選択するまで委任は無効になります。';

  @override
  String get assistantRetention => 'アシスタント会話の保持数';

  @override
  String get assistantRetentionDesc => 'この数を超えた古いプロンプトアシスタントの会話は自動的に削除されます';

  @override
  String get about => 'アプリについて';

  @override
  String aboutVersion(Object version) {
    return 'バージョン $version';
  }

  @override
  String get aboutGithubRepo => 'GitHub リポジトリ';

  @override
  String get aboutViewSource => 'ソースコードとリリースを表示';

  @override
  String get aboutLicense => 'ライセンス';

  @override
  String aboutCopyright(Object year, Object holder) {
    return 'Copyright © $year $holder. MITライセンスの下で公開されています。';
  }

  @override
  String aboutVersionBuild(Object version, Object build) {
    return 'バージョン $version · ビルド $build';
  }

  @override
  String get aboutChangelog => '変更履歴';

  @override
  String get aboutChangelogNote => '各リリースの変更点';

  @override
  String get aboutThirdParty => 'サードパーティライセンス';

  @override
  String get aboutThirdPartyNote => 'このアプリが使用しているオープンソースコンポーネント';

  @override
  String get aboutFeedback => '問題を報告';

  @override
  String get aboutFeedbackNote => '送信前に下の実行情報とログの抄録を添付してください';

  @override
  String get aboutActionOpen => '開く';

  @override
  String get aboutActionView => '表示';

  @override
  String get aboutRuntime => '実行情報';

  @override
  String get aboutRuntimeHint => '問題を報告するときはこのブロックをそのまま issue に貼り付けてください。';

  @override
  String get aboutRuntimeCopied => '実行情報をコピーしました';

  @override
  String get aboutMetaVersion => 'バージョン';

  @override
  String get aboutMetaEngine => 'エンジン';

  @override
  String get aboutMetaPlatform => 'プラットフォーム';

  @override
  String get aboutMetaDataDir => 'データディレクトリ';

  @override
  String get aboutModelNotice =>
      'このアプリはモデルの重みを含みません。生成物の権利帰属とコンプライアンスは各プロバイダーの利用規約に従います。';

  @override
  String get themeMode => 'テーマモード';

  @override
  String get visualEffects => 'エフェクト';

  @override
  String get settingsGroupNotifications => '通知とログ';

  @override
  String get settingsGroupDirectories => 'ディレクトリ';

  @override
  String get settingsGroupAssistant => 'アシスタント';

  @override
  String get customAccentTitle => 'カスタムテーマカラー';

  @override
  String get customAccentHint => 'リングをドラッグするか hex 値を貼り付け';

  @override
  String get customAccentDerived => '導出されたペア';

  @override
  String get customAccentPassed => '白文字で読めます。ボタンは白文字のままです。';

  @override
  String get customAccentInkFallback => 'この色では白文字が読みにくいため、ボタンは同じ色相の濃いインクを使います。';

  @override
  String get customAccentFailed => 'この色はコントラストの基準を満たせません。';

  @override
  String get fontFollowSystem => 'OS に従う';

  @override
  String get fontNotDownloaded => '未ダウンロード';

  @override
  String get fontDownloadedOffline => 'ダウンロード済み · オフラインで利用可';

  @override
  String get languageFollowSystem => 'システムの言語に従う';

  @override
  String get exportSettingsNote => 'ディレクトリ・プロンプト・使用記録は任意。API キーは含まれません';

  @override
  String get clearTempFilesNote => 'マスク · 切り抜きのコピー · ダウンローダーのキャッシュ · 動画サムネイル';

  @override
  String get resetAllSettingsNote => '初回起動の状態に戻します';

  @override
  String get resetIrreversible => '元に戻せません';

  @override
  String get proxyAppliesToAll => 'すべてのチャネルのリクエストに適用';

  @override
  String get notificationsDesc => 'タスクの完了・失敗時に通知します';

  @override
  String get mcpServerDesc => '外部ツールから MCP 経由でこのアプリを呼び出せるようにします';

  @override
  String get mcpComingSoon => '近日公開（このバージョンでは未実装）';

  @override
  String get shortcutNavigateToDestination => '1〜8 番目のページへ';

  @override
  String get shortcutShowShortcutPanel => 'キーボードショートカット';

  @override
  String get shortcutOpenSettings => '設定';

  @override
  String get shortcutFocusSearch => 'ファイルを検索';

  @override
  String get shortcutRefresh => '再読み込み';

  @override
  String get shortcutToggleLeftPanel => 'フォルダ欄の表示切り替え';

  @override
  String get shortcutToggleStaging => 'ステージング欄の表示切り替え';

  @override
  String get shortcutToggleConfigPanel => 'パラメータ欄の表示切り替え';

  @override
  String get shortcutExitSearch => '検索を終了';

  @override
  String get shortcutSelectWorkbenchTool => 'ツールを切り替え';

  @override
  String get shortcutPreview => 'プレビューを開く';

  @override
  String get shortcutRename => '名前を変更';

  @override
  String get shortcutDelete => '削除';

  @override
  String get shortcutRenameFolder => 'フォルダ名を変更';

  @override
  String get shortcutDeleteFolder => 'フォルダを削除';

  @override
  String get shortcutSelectAll => 'すべて選択';

  @override
  String get shortcutClearSelection => '選択を解除';

  @override
  String get shortcutCopyFileName => 'ファイル名をコピー';

  @override
  String get shortcutRevealInFileManager => 'フォルダで表示';

  @override
  String get shortcutOpenWithSystem => '既定のアプリで開く';

  @override
  String get shortcutNewSubfolder => 'サブフォルダを作成';

  @override
  String get shortcutsTitle => 'キーボードショートカット';

  @override
  String get shortcutsGroupGlobal => '全体';

  @override
  String get shortcutsGroupScreen => 'このページ';

  @override
  String get shortcutsGroupFiles => 'ファイル操作';

  @override
  String get shortcutsPaneTree => 'フォルダツリー';

  @override
  String get shortcutsPaneGrid => 'ファイルグリッド';

  @override
  String get shortcutsPaneGallery => 'ギャラリー';

  @override
  String get shortcutsPaneStaging => 'ステージング';

  @override
  String shortcutsActiveRegion(String region) {
    return 'アクティブ領域：$region';
  }

  @override
  String get shortcutsInactiveRegion => '現在は非アクティブ';

  @override
  String get shortcutsActiveRegionNote =>
      'この一群はアクティブ領域（アクセント色の上辺が付いている部分）にのみ作用します。フォルダツリーかグリッドをクリックすると切り替わります。';

  @override
  String get shortcutsClose => '閉じる';

  @override
  String get shortcutsCustomise => 'キー割り当てのカスタマイズ';

  @override
  String get shortcutsCustomiseLater => '次のフェーズで';

  @override
  String get tasks => 'タスク';

  @override
  String get taskQueueManager => 'タスクキューマネージャー';

  @override
  String get noTasksInQueue => 'キューにタスクがありません';

  @override
  String get submitTaskFromWorkbench => 'ワークベンチからタスクを送信して、ここに表示します。';

  @override
  String taskId(String id) {
    return 'タスクID: $id';
  }

  @override
  String get pendingTasks => '保留中';

  @override
  String get processingTasks => '処理中';

  @override
  String get completedTasks => '完了';

  @override
  String get failedTasks => '失敗';

  @override
  String get clearCompleted => '完了済みをクリア';

  @override
  String get clearAll => 'すべてクリア';

  @override
  String get cancelAllPending => 'すべての保留中をキャンセル';

  @override
  String get cancelTask => 'タスクをキャンセル';

  @override
  String get images => '画像';

  @override
  String filesCount(int count) {
    return '$count 個のファイル';
  }

  @override
  String runningCount(int count) {
    return '$count 個実行中';
  }

  @override
  String plannedCount(int count) {
    return '$count 個計画済み';
  }

  @override
  String get taskCompletedNotification => 'タスク完了';

  @override
  String get taskFailedNotification => 'タスク失敗';

  @override
  String taskCompletedBody(String id) {
    return 'タスク $id が正常に完了しました。';
  }

  @override
  String taskFailedBody(String id) {
    return 'タスク $id の処理に失敗しました。';
  }

  @override
  String get queueSettings => 'キュー設定';

  @override
  String concurrencyLimit(int limit) {
    return '並列処理制限: $limit';
  }

  @override
  String taskTotalCount(int count) {
    return '全 $count 件';
  }

  @override
  String get retryTask => '再試行';

  @override
  String get resumeVideoJob => '元のジョブを再開';

  @override
  String queuedPosition(int position) {
    return '待機 $position 番目';
  }

  @override
  String tookDuration(String duration) {
    return '所要時間 $duration';
  }

  @override
  String retryCount(int count) {
    return '再試行回数: $count';
  }

  @override
  String get viewTaskLog => 'ログを表示';

  @override
  String get taskLogTitle => 'タスクログ';

  @override
  String get taskLogLive => 'リアルタイム';

  @override
  String get noTaskLog => 'このタスクのログはありません。';

  @override
  String get noTaskLogHint => 'このアップデート前に実行したタスクはログを保存していません。';

  @override
  String get taskLogCopied => 'ログをクリップボードにコピーしました';

  @override
  String get copyPrompt => 'プロンプトをコピー';

  @override
  String taskLogLineCount(int count) {
    return '$count 行';
  }

  @override
  String get goToWorkbench => 'ワークベンチへ';

  @override
  String get copyAll => 'すべてコピー';

  @override
  String get copiedAll => 'クリップボードにコピーしました';

  @override
  String get noLogsYet => 'このタスクにはまだログがありません';

  @override
  String get sourceFiles => '元ファイル';

  @override
  String get requestParameters => 'リクエストパラメータ';

  @override
  String get outputPaths => '出力ファイル';

  @override
  String get copyError => 'エラーをコピー';

  @override
  String taskTotalShort(int count) {
    return '計 $count';
  }

  @override
  String get statusShortRunning => '実行';

  @override
  String get statusShortPending => '待機';

  @override
  String get statusShortDone => '完了';

  @override
  String get statusShortFailed => '失敗';

  @override
  String get sortNewestFirst => '新しい順';

  @override
  String get sortOldestFirst => '古い順';

  @override
  String get sortSection => '並べ替え';

  @override
  String get pinActiveTasks => '実行中と待機中を上部に固定';

  @override
  String get restByCreatedTime => '残りは作成時刻順';

  @override
  String get createdAt => '作成';

  @override
  String get cancelledByUser => 'キャンセル済み · 手動';

  @override
  String get noRunningTasks => '実行中のタスクはありません';

  @override
  String get noPendingTasks => '待機中のタスクはありません';

  @override
  String get noCompletedTasks => '完了したタスクはありません';

  @override
  String get noFailedTasks => '失敗したタスクはありません';

  @override
  String filteredEmptyHint(int count) {
    return 'この絞り込みに該当するタスクはありません。他の $count 件のタスクは影響を受けません。';
  }

  @override
  String get viewAllTasks => 'すべて表示';

  @override
  String get durationLabel => '所要時間';

  @override
  String get clearAllTasksTitle => 'すべてのタスクを消去しますか？';

  @override
  String clearAllRunningNote(int count) {
    return '実行中のタスク $count 件を含みます';
  }

  @override
  String get clearAllKeepsFiles =>
      '実行中のタスクはそのままです。生成済みのファイルは出力フォルダーに残り、キューの記録だけが消去されます。';

  @override
  String get taskNoOutputsFailed => '出力はありません。書き込み前にタスクが失敗しました。';

  @override
  String get noTaskLogCancelledHint => '開始前にキャンセルされたため、ログはありません。';

  @override
  String get setupWizardTitle => 'ようこそセットアップ';

  @override
  String get welcomeMessage => 'Joycai Image AI Toolkitsへようこそ！セットアップを始めましょう。';

  @override
  String get getStarted => '始める';

  @override
  String get stepStorage => 'ストレージ';

  @override
  String get setupCompleteMessage => 'すべての準備が整いました！創作をお楽しみください。';

  @override
  String get skip => 'スキップ';

  @override
  String get storageLocationDesc => '生成された画像が保存される場所を選択します。';

  @override
  String get addChannelOptional => '最初のAIプロバイダーチャネルを追加します（オプション）。';

  @override
  String get configureModelOptional => '新しいチャネルのモデルを設定します（オプション）。';

  @override
  String get filenamePrefix => 'ファイル名のプレフィックス';

  @override
  String get workbench => 'ワークベンチ';

  @override
  String get wbModeImage => '画像';

  @override
  String get wbModeVideo => '動画';

  @override
  String get wbTools => 'ツール';

  @override
  String get tempWorkspace => '一時ワークスペース';

  @override
  String get processResults => '処理結果';

  @override
  String get sectionSources => 'ソース';

  @override
  String get sectionResults => '結果';

  @override
  String get sectionWorkspace => 'ワークスペース';

  @override
  String get allSources => 'すべてのソース';

  @override
  String get allResults => 'すべての結果';

  @override
  String get directories => 'ディレクトリ';

  @override
  String get addFolder => 'フォルダを追加';

  @override
  String get noFolders => 'フォルダが追加されていません';

  @override
  String get clickAddFolder => '「フォルダを追加」をクリックして、画像のスキャンを開始します。';

  @override
  String get noImagesFound => '画像が見つかりません';

  @override
  String get noResultsYet => '結果がありません';

  @override
  String get selectAll => 'すべて選択';

  @override
  String get importFromGallery => 'ギャラリーからインポート';

  @override
  String get takePhoto => '写真を撮る';

  @override
  String get clearTempWorkspace => 'ワークスペースをクリア';

  @override
  String get clearTempWorkspaceConfirmTitle => 'ワークスペースをクリアしますか？';

  @override
  String clearTempWorkspaceConfirmMessage(int count) {
    return '一時ワークスペースから $count 件すべてを取り除きます。ファイル自体は削除されません。';
  }

  @override
  String get removeFromWorkspace => '一時ワークスペースから外す';

  @override
  String get noImagesSelected => '画像が選択されていません';

  @override
  String get imageLoadFailed => '画像の読み込みに失敗しました';

  @override
  String get selectSourceDirectory => 'ソースディレクトリを選択';

  @override
  String get removeFolderConfirmTitle => 'フォルダを削除しますか？';

  @override
  String removeFolderConfirmMessage(String folderName) {
    return 'リストから「$folderName」を削除してもよろしいですか？';
  }

  @override
  String get thumbnailSize => 'サムネイルサイズ';

  @override
  String get thumbnailDisplay => 'サムネイル表示';

  @override
  String get thumbnailFitContain => 'フィット（全体表示）';

  @override
  String get thumbnailFitCover => 'フィル（切り抜き）';

  @override
  String deleteFailed(String error) {
    return '削除に失敗しました: $error';
  }

  @override
  String get modelSelection => 'モデル選択';

  @override
  String get selectAModel => 'モデルを選択';

  @override
  String get aspectRatio => 'アスペクト比';

  @override
  String get resolution => '解像度';

  @override
  String get imageSizeLabel => 'サイズ';

  @override
  String get quality => '品質';

  @override
  String get promptExtend => 'プロンプト拡張';

  @override
  String get promptExtendOn => 'オン';

  @override
  String get promptExtendOff => 'オフ';

  @override
  String get optionAuto => '自動';

  @override
  String get paramImageTask => 'タスク';

  @override
  String get paramMaxImages => '組画像の上限';

  @override
  String get paramOutputFormat => '形式';

  @override
  String get paramOptimizeMode => 'プロンプト最適化';

  @override
  String get paramWebSearch => 'Web 検索';

  @override
  String get paramWatermark => '透かし';

  @override
  String get taskGenerate => '生成';

  @override
  String get taskLayers => 'レイヤー分解';

  @override
  String get taskTransparent => '透過編集';

  @override
  String maxImagesUpTo(int count) {
    return '最大 $count 枚';
  }

  @override
  String get optimizeStandard => '標準';

  @override
  String get optimizeFast => '高速';

  @override
  String get qualityLow => '低';

  @override
  String get qualityMedium => '中';

  @override
  String get qualityHigh => '高';

  @override
  String get qualityXhigh => '超高';

  @override
  String get qualityMax => '最高';

  @override
  String get mjVersion => 'バージョン';

  @override
  String get mjMode => 'モード';

  @override
  String get mjStylize => 'スタイル化';

  @override
  String get mjChaos => 'カオス';

  @override
  String get referenceImagesNotSupported =>
      'このモデルは参照画像に対応していません。選択した画像は無視されます。';

  @override
  String referenceImagesLimited(int count) {
    return 'このモデルは参照画像を最大 $count 枚まで使用できます。残りは無視されます。';
  }

  @override
  String get prompt => 'プロンプト';

  @override
  String get promptHint => 'プロンプトをここに入力...';

  @override
  String get promptHistory => 'プロンプト履歴';

  @override
  String get noPromptHistory => '履歴はまだありません';

  @override
  String get noPromptHistoryDesc => '送信したプロンプトがここに表示されます。';

  @override
  String get usePrompt => 'このプロンプトを使う';

  @override
  String get applyPromptWarning => 'エディタの現在のプロンプトを置き換えます。';

  @override
  String get clearPromptHistory => '履歴を消去';

  @override
  String get clearPromptHistoryConfirm => 'すべての履歴を消去しますか？この操作は取り消せません。';

  @override
  String get timeJustNow => 'たった今';

  @override
  String timeMinutesAgo(int count) {
    return '$count 分前';
  }

  @override
  String timeHoursAgo(int count) {
    return '$count 時間前';
  }

  @override
  String timeDaysAgo(int count) {
    return '$count 日前';
  }

  @override
  String get prefixHint => '例：result';

  @override
  String get processPrompt => 'プロンプトを処理';

  @override
  String processImages(int count) {
    return '$count枚の画像を処理';
  }

  @override
  String get useStreaming => 'ストリーミングを使用';

  @override
  String get useStreamingDesc => 'リアルタイム AI 応答（対応時）';

  @override
  String get compressReferenceImages => '参考画像を圧縮';

  @override
  String get compressReferenceImagesDesc => '3MB を超える画像を JPEG に再エンコード';

  @override
  String get taskSubmitted => 'タスクがキューに送信されました';

  @override
  String get comparator => '比較ツール';

  @override
  String get compareLayoutSideBySide => '左右に並べる';

  @override
  String get compareLayoutStacked => '上下に並べる';

  @override
  String get compareLayoutSlider => 'スライダー比較';

  @override
  String get compareSyncTransform => 'ズーム・パンを同期';

  @override
  String get comparatorEmptyHint => 'ファイルブラウザやタスク結果から送信するか、ライブラリから2枚選択してください';

  @override
  String get comparatorPickRaw => '元画像を選択';

  @override
  String get comparatorPickAfter => '結果画像を選択';

  @override
  String comparatorZoomSynced(int percent) {
    return 'ズーム $percent% · 同期中';
  }

  @override
  String comparatorZoomIndependent(int percent) {
    return 'ズーム $percent% · 個別';
  }

  @override
  String comparatorSizeReduction(String percent) {
    return 'サイズ $percent 削減';
  }

  @override
  String comparatorSizeIncrease(String percent) {
    return 'サイズ $percent 増加';
  }

  @override
  String get fileSize => 'ファイルサイズ';

  @override
  String get sendToComparator => '比較ツールに送信';

  @override
  String get sendToComparatorRaw => 'Before (RAW) として設定';

  @override
  String get sendToComparatorAfter => 'After (結果) として設定';

  @override
  String get sendToFirstFrame => '動画の最初のフレームに設定';

  @override
  String get sendToLastFrame => '動画の最後のフレームに設定';

  @override
  String get sendToVideoReferences => '動画の参照画像に追加';

  @override
  String get sendToSelection => '選択に追加';

  @override
  String get sendToOptimizer => 'プロンプトアシスタントに送信';

  @override
  String get menuQuickMask => 'マスク';

  @override
  String get menuQuickCrop => '切り抜き';

  @override
  String get menuQuickAssistant => 'アシスタント';

  @override
  String get menuSetAs => '設定先';

  @override
  String get menuSetAsRaw => 'Before (RAW)';

  @override
  String get menuSetAsAfter => 'After';

  @override
  String get menuSetAsFirstFrame => '最初のフレーム';

  @override
  String get menuSetAsLastFrame => '最後のフレーム';

  @override
  String get menuFileGroup => 'ファイル';

  @override
  String get menuExportGroup => 'エクスポート';

  @override
  String get selectFromLibrary => 'ライブラリから選択';

  @override
  String get metadataSelectedNone => '画像メタデータが選択されていません';

  @override
  String get labelRaw => 'RAW';

  @override
  String get labelAfter => 'AFTER';

  @override
  String get cropAndResize => '切り抜きとサイズ変更';

  @override
  String get overwriteSource => '元のファイルを上書き';

  @override
  String get overwriteConfirmTitle => '元のファイルを上書きしますか？';

  @override
  String get overwriteConfirmMessage => 'この操作により、元のファイルが完全に置き換えられます。よろしいですか？';

  @override
  String get overwriteConfirmSaveCopyInstead => '代わりにコピーを保存';

  @override
  String get overwriteConfirmSubtitle => 'この操作は取り消せません';

  @override
  String get overwriteConfirmKeepOriginalHint => '元の画像を残す場合は「コピーを保存」をご利用ください。';

  @override
  String overwriteUnsupportedFormat(String format) {
    return '$format ファイルは上書きできません。この形式は読み込み専用です。「コピーを保存」をご利用ください。';
  }

  @override
  String get saveToTempSuccess => '画像が一時ワークスペースに保存されました';

  @override
  String get overwriteSuccess => '元のファイルが更新されました';

  @override
  String get custom => 'カスタム';

  @override
  String get cropResizeFreeRatio => 'フリー';

  @override
  String get resize => 'サイズ変更';

  @override
  String get maintainAspectRatio => 'アスペクト比を維持';

  @override
  String get width => '幅';

  @override
  String get height => '高さ';

  @override
  String get sampling => 'サンプリング';

  @override
  String get reset => 'リセット';

  @override
  String cropResizeOriginalInfo(int width, int height, String size) {
    return '元画像 $width×$height · $size';
  }

  @override
  String cropResizeCanvasLabel(String name) {
    return '$name（元画像プレビュー）';
  }

  @override
  String get cropResizeCropOnly => '切り抰き';

  @override
  String cropResizeCropAndScale(int percent) {
    return '切り抰き + 拡大縮小 $percent%';
  }

  @override
  String get cropResizeOutputPreview => '出力プレビュー';

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
    return 'コピーの保存先: $path';
  }

  @override
  String get cropResizeTempWorkspaceLabel => '一時ワークスペース';

  @override
  String get saveCopy => 'コピーを保存';

  @override
  String get cropResizeSaveDestinationHint => 'ワークスペースへ';

  @override
  String get cropResizeResample => 'リサンプル';

  @override
  String get fitToWindow => 'ウィンドウに合わせる';

  @override
  String get drawMask => 'マスクを描画';

  @override
  String get maskEditor => 'マスクエディタ';

  @override
  String get brushSize => 'ブラシサイズ';

  @override
  String get maskColor => 'マスクの色';

  @override
  String get maskOpacity => 'マスクの不透明度';

  @override
  String get undo => '元に戻す';

  @override
  String get saveToTemp => 'ワークスペースに保存';

  @override
  String get binaryMode => 'バイナリモード';

  @override
  String maskSourceCaption(int width, int height) {
    return 'マスク $width×$height';
  }

  @override
  String maskBrushBadge(String color, int size) {
    return '$colorのブラシ · $size px';
  }

  @override
  String get maskOutputLabel => '出力';

  @override
  String maskOutputSummary(int width, int height) {
    return 'マスク $width×$height · PNG（白黒）';
  }

  @override
  String maskCompositeOutputSummary(int width, int height) {
    return '合成画像 $width×$height · PNG';
  }

  @override
  String maskWillSaveTo(String path) {
    return 'マスクの保存先 $path';
  }

  @override
  String get maskSaveComposite => '合成画像を保存';

  @override
  String get maskSaveMask => 'マスクを保存';

  @override
  String get maskSaved => 'マスクがワークスペースに保存されました';

  @override
  String maskSaveError(String error) {
    return 'マスク保存エラー: $error';
  }

  @override
  String get promptOptimizer => 'プロンプトアシスタント';

  @override
  String get refinerModel => 'リファイナーモデル';

  @override
  String get systemPrompt => 'システムプロンプト';

  @override
  String get roughPrompt => 'ラフなプロンプト / アイデア';

  @override
  String get applyToWorkbench => 'ワークベンチに適用';

  @override
  String get promptApplied => 'プロンプトがワークベンチに適用されました';

  @override
  String refineFailed(String error) {
    return '最適化に失敗しました: $error';
  }

  @override
  String get optChatHint => 'アイデアやラフなプロンプトを入力...';

  @override
  String get optSend => '送信';

  @override
  String get optNewSession => '新しい会話';

  @override
  String get optToolListImages => '参照画像リストを確認しました';

  @override
  String optToolViewImage(String name) {
    return '参照画像を確認しました：$name';
  }

  @override
  String get optPromptTitle => '最適化プロンプト';

  @override
  String get optCopy => 'コピー';

  @override
  String get optPromptCopied => 'プロンプトをコピーしました';

  @override
  String get optViewed => 'AI が閲覧済み';

  @override
  String get optRemoveImage => '画像を削除';

  @override
  String get optEmptyImagesHint =>
      'ギャラリーで画像を右クリックし、「プロンプトアシスタントに送信」を選択すると追加できます。';

  @override
  String get referenceImages => '参照画像';

  @override
  String get firstFrame => '最初のフレーム';

  @override
  String get lastFrame => '最後のフレーム';

  @override
  String get generateVideo => '動画を生成';

  @override
  String get frames => 'フレーム';

  @override
  String get videoResolution => '動画解像度';

  @override
  String get videoAspectRatio => '動画アスペクト比';

  @override
  String get videoSeconds => '長さ';

  @override
  String get videoQualityStandard => '標準';

  @override
  String get videoQualityHigh => '高画質';

  @override
  String get openInSystemPlayer => 'システムプレイヤーで開く';

  @override
  String get dropVideoReferenceHere => 'スタイル/内容参照用の画像をここにドロップ';

  @override
  String get executionLogs => '実行ログ';

  @override
  String get saveToPhotos => '写真に保存';

  @override
  String get saveToGallery => 'ギャラリーに保存';

  @override
  String get savedToPhotos => '写真に保存されました';

  @override
  String saveFailed(String error) {
    return '保存に失敗しました: $error';
  }

  @override
  String get iosSandboxActive => 'iOSサンドボックス有効';

  @override
  String get iosSandboxDesc =>
      'iOSでは、上部のツールバーにある「ギャラリーからインポート」ボタンを使用して、一時ワークスペースに画像を追加してください。';

  @override
  String get mobileSandboxActive => 'モバイルストレージの制限';

  @override
  String get mobileSandboxDesc =>
      'モバイルデバイスでは、OSによって直接のフォルダアクセスが制限される場合があります。上部のツールバーにある「ギャラリーからインポート」ボタンを使用することをお勧めします。';

  @override
  String get tapToPick => 'タップして選択';

  @override
  String get goToGallery => 'ギャラリーへ';

  @override
  String get binaryModeActive => 'バイナリモード有効 — クリーンなマスクエクスポートのため背景非表示';

  @override
  String get imageSizeAuto => '自動';

  @override
  String get imageSizeCustom => 'カスタム';

  @override
  String get imageSizeRatio => '比率';

  @override
  String get imageSizeLongEdge => '長辺';

  @override
  String get imageSizeWidth => '幅';

  @override
  String get imageSizeHeight => '高さ';

  @override
  String get safetySettings => 'セーフティ設定';

  @override
  String get safetySettingsDesc =>
      'Gemini コンテンツフィルタのしきい値。各リクエストに適用されます（厳格 → 寛容）。Veo/Imagen は非対応。';

  @override
  String get safetyCategoryHarassment => 'ハラスメント';

  @override
  String get safetyCategoryHateSpeech => 'ヘイトスピーチ';

  @override
  String get safetyCategorySexuallyExplicit => '性的表現';

  @override
  String get safetyCategoryDangerousContent => '危険なコンテンツ';

  @override
  String get safetyThresholdBlockLowAndAbove => 'ほとんどブロック';

  @override
  String get safetyThresholdBlockMediumAndAbove => '一部ブロック';

  @override
  String get safetyThresholdBlockOnlyHigh => '少しブロック';

  @override
  String get safetyThresholdBlockNone => 'ブロックしない';

  @override
  String get safetyThresholdOff => 'フィルタ無効';

  @override
  String get optModeSystemPrompt => 'タスクプリセット';

  @override
  String get optModeKnowledge => 'ナレッジベース';

  @override
  String get knowledgeBase => 'ナレッジベース';

  @override
  String get optKbNotConfigured => 'ナレッジベースが未設定または無効です。設定でフォルダを選択してください。';

  @override
  String get optToolListKnowledge => 'ナレッジベースのファイル一覧を確認';

  @override
  String optToolReadKnowledge(String name) {
    return 'ナレッジを読み込み: $name';
  }

  @override
  String get optHistory => '会話履歴';

  @override
  String get optNoHistory => '保存された会話はまだありません';

  @override
  String get optDeleteSessionConfirm => 'この会話を完全に削除しますか？';

  @override
  String get optKbEntryTooLarge =>
      'ナレッジベースの README.md がこのモデルのコンテキストウィンドウの大部分を占めています。毎回のリクエストで再送され、要約でも縮められません。内容を減らすか、より大きなウィンドウのモデルを選んでください。';

  @override
  String get optCompactedNotice => 'コンテキスト節約のため、以前のメッセージは要約に圧縮されました。';

  @override
  String get optRoundLimitNotice =>
      'アシスタントはこのメッセージのステップ上限に達し、最終的な回答を出す前に停止しました。続けるには「続けて」などのメッセージを送ってください。';

  @override
  String get optTruncatedTail => '返答は出力上限で途中終了しました';

  @override
  String get optOpenModelSettings => 'モデル設定で最大出力を調整';

  @override
  String get optTruncatedTitle => '納品が出力上限で途中終了しました';

  @override
  String get optTruncatedBody =>
      '納品中に 2 回連続でモデルの出力トークン上限に達したため、このターンを停止し、途中で切れたツール呼び出しは実行していません。モデル設定の「最大出力」を引き上げてください。プロンプトアシスタントの 1 回の納品は 6–8k トークンで、思考と本文がこの上限を共有します。';

  @override
  String get optAdjustOutputCap => '最大出力を調整';

  @override
  String get optKbDistillRequested => 'リクエスト済み：今回の調整で得た知見をナレッジベースへ整理します。';

  @override
  String get optResultFeedbackAction => 'アシスタントに報告';

  @override
  String get optResultFeedbackChatLabel => '生成結果の報告';

  @override
  String get optResultFeedbackHint => 'この画像のどこが期待と違いますか？';

  @override
  String get optFeedbackSatisfied => '満足';

  @override
  String get optFeedbackUnsatisfied => '不満';

  @override
  String get optFeedbackReasonPromptMismatch => 'プロンプトと不一致';

  @override
  String get optFeedbackReasonComposition => '構図';

  @override
  String get optFeedbackReasonColorLight => '色彩 / 光';

  @override
  String get optFeedbackReasonDetail => 'ディテール崩れ';

  @override
  String get optFeedbackReasonStyle => 'スタイルのずれ';

  @override
  String get optFeedbackHintSatisfied =>
      'どこが良かったか書いておくと、アシスタントは次回もその処理を保ちます（任意）';

  @override
  String get optFeedbackHintUnsatisfied => 'どこが期待と違いましたか？具体的なほど助かります（任意）';

  @override
  String get optFeedbackRunPromptLabel => 'この実行のプロンプト';

  @override
  String get optFeedbackFooterNote => 'このプロンプトの実行記録に保存され、アシスタントが修正時に参照します';

  @override
  String get optSendFeedback => 'フィードバックを送信';

  @override
  String optFeedbackSendShortcut(String modifier) {
    return '${modifier}Enter で送信';
  }

  @override
  String optFeedbackRunToday(String time) {
    return '今日 $time';
  }

  @override
  String get optResultFeedbackSent => 'アシスタントにフィードバックを送信しました';

  @override
  String get optDistillAction => '今回の知見をまとめる';

  @override
  String get optDistillDisabledTooltip =>
      'このセッションにはまだプロンプト版がありません。先に一度最適化してください';

  @override
  String optDistillCounts(int versions, int feedbacks) {
    return '$versions 版 · フィードバック $feedbacks 件';
  }

  @override
  String get optDistillAlreadyPending => 'まとめリクエストはすでに実行待ちです。';

  @override
  String get optResultImages => '結果画像';

  @override
  String get optResultNoFeedback => '未報告';

  @override
  String get optDistillDoneTitle => '今回の知見をナレッジベースに書き込みました';

  @override
  String get optSaveFinalPrompt => '最終プロンプトをライブラリへ保存';

  @override
  String get optTimelineTitle => 'イテレーション履歴';

  @override
  String optTimelineCount(int count) {
    return '$count 版';
  }

  @override
  String get optFeedbackShort => 'フィードバック';

  @override
  String get optPromptVersionLabel => 'プロンプト';

  @override
  String get optImageMissing => 'この会話の一部の参照画像が見つかりません。再追加すると引き続き使用できます。';

  @override
  String get optRetry => '再試行';

  @override
  String get optModeKnowledgeEdit => 'メンテナンス';

  @override
  String optToolWriteKnowledge(String name) {
    return 'ナレッジ更新の提案：$name';
  }

  @override
  String get kbEditProposedCreate => '新規ファイル';

  @override
  String get kbEditProposedUpdate => 'ファイル更新';

  @override
  String kbEditScopeReplace(String heading) {
    return 'セクション $heading を置換';
  }

  @override
  String kbEditScopeAppend(String heading) {
    return 'セクション $heading に追記';
  }

  @override
  String get kbEditScopeAppendEnd => 'ファイル末尾に追記';

  @override
  String get kbEditApply => '書き込む';

  @override
  String get kbEditReject => '破棄';

  @override
  String get kbEditApplied => 'ディスクに書き込みました';

  @override
  String get kbEditRejected => '破棄しました';

  @override
  String get kbEditFailedShort => '書き込みに失敗しました';

  @override
  String kbEditShow(int chars) {
    return '内容を表示（$chars 文字）';
  }

  @override
  String get kbEditHide => '内容を隠す';

  @override
  String kbEditShrinkWarning(int oldChars, int newChars) {
    return '新しい内容は現在のファイルよりかなり短くなっています（$oldChars → $newChars 文字）。書き込む前に内容が完全か確認してください。';
  }

  @override
  String kbEditFailed(String error) {
    return '書き込みに失敗しました：$error';
  }

  @override
  String kbScaffoldAlreadyInit(String name) {
    return '初期化済みです。このフォルダには $name があり、変更されません。';
  }

  @override
  String get kbScaffoldCreate => '初期化';

  @override
  String kbScaffoldConfirm(String path) {
    return '$path をナレッジベースとして初期化します。サンプルのルールファイルが作成されます。続行しますか？';
  }

  @override
  String kbScaffoldDone(int created) {
    return 'ナレッジベースを初期化しました：$created 件作成。';
  }

  @override
  String kbScaffoldFailed(String error) {
    return 'ナレッジベースを作成できませんでした：$error';
  }

  @override
  String get optAskUserTitle => 'アシスタントからの確認事項';

  @override
  String get optAskUserMultiHint => '複数選択可';

  @override
  String get optAskUserOtherHint => 'その他 / 補足...';

  @override
  String get optAskUserConfirm => '回答を送信';

  @override
  String get optAskUserAnswered => '回答済み';

  @override
  String get optAskUserDismissed => 'チャットで継続';

  @override
  String optAgentSteps(int count) {
    return 'エージェント処理 · $count ステップ';
  }

  @override
  String optAgentStepsImages(int count) {
    return '参照画像 $count 枚を確認';
  }

  @override
  String optAgentStepsDocs(int count) {
    return 'ドキュメント $count 件を読了';
  }

  @override
  String optAgentStepsExpand(int count) {
    return '全 $count ステップを表示';
  }

  @override
  String get optAgentStepsCollapse => 'ステップを折りたたむ';

  @override
  String get optPromptExpand => '全文を表示';

  @override
  String get optPromptCollapse => '折りたたむ';

  @override
  String get optKbReady => '初期化済み';

  @override
  String optKbTreeStats(int files, int dirs) {
    return 'ドキュメント $files 件 · フォルダ $dirs 個';
  }

  @override
  String optKbContentUpdated(String time) {
    return '内容更新 $time';
  }

  @override
  String get optKbRescan => '再スキャン';

  @override
  String get optKbCitedThisRound => '今回の参照';

  @override
  String optKbCitedAll(int count) {
    return '全 $count 件';
  }

  @override
  String get optKbCitedNone => '参照はまだありません';

  @override
  String get optCtxTitle => 'コンテキスト使用量';

  @override
  String get optCtxSystemPrompt => 'システムプロンプト';

  @override
  String get optCtxTools => 'ツール定義';

  @override
  String get optCtxHistory => '会話履歴';

  @override
  String get optCtxRemaining => '残りウィンドウ';

  @override
  String get optCtxWindowUnknown => 'ウィンドウ未設定';

  @override
  String get optCtxWindowUnlimited => '無制限';

  @override
  String get optCtxWindowAssumed => 'このモデルはコンテキストウィンドウが未設定です。既定値で概算しています。';

  @override
  String optAttachedImages(int count) {
    return '参照画像 $count 枚をメッセージと共に送信';
  }

  @override
  String get optSendHint => 'Enter で送信 · Shift+Enter で改行';

  @override
  String get optRefNumberingHint =>
      '番号はプロンプトで引用されるファイル名に対応します。エージェントはこれらの画像を参照できます。';

  @override
  String get optRefReorderHint =>
      'カードをドラッグして並べ替えます。番号はアシスタントに渡す順序で、プロンプトが引用する番号でもあります。';

  @override
  String get optRefReorderHintTouch =>
      'カードを長押ししてからドラッグで並べ替えます。番号はアシスタントに渡す順序です。';

  @override
  String get optRefReorderLocked => 'アシスタントが応答中です。終了後に並べ替えられます。';

  @override
  String get optRunning => '実行中';

  @override
  String optRunningStep(int count) {
    return '実行中 · ステップ $count';
  }

  @override
  String get optAgentStepsRunning => 'Agent の処理 · 実行中';

  @override
  String get optAgentStepWorking => '次のステップを実行中…';

  @override
  String optAgentStepStreaming(int count) {
    return 'モデルが出力中… $count 文字受信';
  }

  @override
  String optElapsedSeconds(int seconds) {
    return '経過 ${seconds}s';
  }

  @override
  String optElapsedMinutes(int minutes, int seconds) {
    return '経過 ${minutes}m ${seconds}s';
  }

  @override
  String get optChatBusyHint => 'Agent が実行中です。完了後に入力できます…';

  @override
  String get optAbort => '中断';

  @override
  String get optAbortHint => 'Esc で中断';

  @override
  String get optKbSearching => '検索中';

  @override
  String get optKbCitedRunning => '実行中';

  @override
  String get optSysPromptPick => 'タスクプリセットを選択';

  @override
  String get optSysPromptSearch => 'プリセットを検索…';

  @override
  String get optSysPromptUnsaved => '未保存';

  @override
  String get optSysPromptSave => '保存';

  @override
  String get optSysPromptReset => 'リセット';

  @override
  String get optSysPromptSaved => 'プリセットを保存しました';

  @override
  String get optSysPromptHint => 'アシスタントに従わせたい指示を書いてください…';

  @override
  String optSysPromptChars(int count) {
    return '$count 文字';
  }

  @override
  String optSysPromptTokens(String tokens) {
    return '約 $tokens tokens';
  }

  @override
  String get optSysPromptNoKb =>
      'このモードではナレッジベースを参照しません。アシスタントは参考画像の確認や質問は行います。';

  @override
  String get kbEditNoChange => 'この提案はファイルの内容を変更しません。';

  @override
  String get kbEditPendingTitle => '未確認の変更';

  @override
  String get kbEditWriteAll => 'すべて書き込む';

  @override
  String get kbEditDiscardAll => 'すべて破棄';

  @override
  String kbEditConfirmAll(int count) {
    return '$count 件を書き込む';
  }

  @override
  String optKbDocCount(int count) {
    return '$count 件';
  }

  @override
  String get optKbSearchDocs => 'ドキュメントを検索…';

  @override
  String get optKbTreeEmpty => 'このナレッジベースにはまだドキュメントがありません';

  @override
  String get optKbTreeScanFailed => 'ナレッジベースのフォルダーを読み取れませんでした';

  @override
  String get optKbTreeNoMatch => '該当するドキュメントがありません';

  @override
  String get optKbTreeChanged => '変更';

  @override
  String get optKbTreeAdded => '新規';

  @override
  String optKbTreePending(int count) {
    return '未確認の変更 $count 件';
  }

  @override
  String get kbWritePolicyTitle => '書き込み権限';

  @override
  String get kbWriteAllow => 'agent のナレッジベース書き込みを許可';

  @override
  String get kbWriteConfirmEach => '書き込み前に個別確認';

  @override
  String get kbWriteBackup => '上書き前に .bak を残す';

  @override
  String get kbWriteNoConfirmWarning =>
      '個別確認をオフにすると、agent が作成した内容が確認なしでファイルに書き込まれます。';

  @override
  String get wbToolComparatorShort => '比較';

  @override
  String get wbToolMaskShort => 'マスク';

  @override
  String get wbToolCropShort => 'クロップ';

  @override
  String get wbToolAssistantShort => 'アシスタント';

  @override
  String get wbToolGalleryShort => 'ギャラリー';

  @override
  String get galleryViewWorkspace => 'ワークスペース';

  @override
  String get galleryViewSourcesShort => 'ソース';

  @override
  String get galleryViewResultsShort => '結果';

  @override
  String get galleryDropTitle => 'ここに画像をドロップ…';

  @override
  String get galleryEmptyWorkspaceTitle => 'ここにファイルをドロップ';

  @override
  String get galleryEmptyWorkspaceDesc => '画像や動画をドラッグして一時ワークスペースに追加';

  @override
  String get galleryEmptySourceDesc => 'このソースには対応する画像がありません';

  @override
  String get galleryScanning => 'ファイルをスキャン中…';

  @override
  String get wbGenerationConfig => '生成設定';

  @override
  String get selectionSendToAssistant => 'アシスタントへ送る';

  @override
  String shareCount(int count) {
    return '共有 ($count)';
  }

  @override
  String get selectionReorderHint => 'ドラッグで並べ替え · 番号がモデルに送る順番です';

  @override
  String get videoPlay => '再生';

  @override
  String get videoPause => '一時停止';

  @override
  String get videoMute => 'ミュート';

  @override
  String get videoUnmute => 'ミュート解除';

  @override
  String get videoRetry => '再試行';

  @override
  String get videoPlaybackFailed => '再生できません';

  @override
  String videoPlaybackFailedReason(String name) {
    return 'ファイルがないか、エンコードに対応していません：$name';
  }

  @override
  String get videoFrameOptional => '任意';

  @override
  String get videoDropOrPick => 'ドロップまたはクリックで選択';

  @override
  String videoReferenceDropMax(int count) {
    return '参照画像をドロップ（最大 $count 枚）';
  }

  @override
  String get optErrorTitle => 'リクエストに失敗しました';

  @override
  String get optNotViewed => 'まだ見ていません';

  @override
  String get optTimelineCurrent => '現在';

  @override
  String get optKbPathInvalidDesc => 'パスが無効か、アクセスできません';

  @override
  String optKbEntryMissingShort(String file) {
    return '$file がありません';
  }

  @override
  String get optKbNotConfiguredShort => '未設定';

  @override
  String get cropEmptyDesc => '先にギャラリーで画像を選んでください';

  @override
  String get maskEmptyDesc => 'マスクは画像の上に描きます';

  @override
  String get maskLoadFailedDesc => 'ファイルが移動または削除された可能性があります';

  @override
  String layerCanvasTitle(String name) {
    return 'レイヤー · $name';
  }

  @override
  String layerCanvasSubtitle(int width, int height, int count) {
    return 'ベース $width×$height · $count レイヤー';
  }

  @override
  String layerCanvasSubtitleShort(int width, int height, int count) {
    return '$width×$height · $count レイヤー';
  }

  @override
  String get layerShowBounds => '境界を表示';

  @override
  String get layerFit => '全体表示';

  @override
  String get layerExport => '合成画像を書き出す';

  @override
  String get layerListLabel => 'レイヤー';

  @override
  String layerListCount(int count) {
    return '$count + ベース';
  }

  @override
  String get layerBase => 'ベース';

  @override
  String get layerShowAll => 'すべて表示';

  @override
  String get layerShow => 'レイヤーを表示';

  @override
  String get layerHide => 'レイヤーを隠す';

  @override
  String layerPosition(int x, int y) {
    return '位置 $x, $y';
  }

  @override
  String layerSize(int width, int height) {
    return 'サイズ $width×$height';
  }

  @override
  String layerOrdinal(int index) {
    return 'レイヤー $index';
  }

  @override
  String layerUnnamed(int index) {
    return 'レイヤー $index';
  }

  @override
  String get layerOpenThis => 'このレイヤーを開く';

  @override
  String get layerExported => '合成画像を書き出しました';

  @override
  String layerExportFailed(String error) {
    return '合成画像を書き出せませんでした：$error';
  }

  @override
  String get layerSetUnavailable => 'このレイヤーのファイルが見つかりません';

  @override
  String get menuOpenLayers => 'レイヤーを開く';

  @override
  String menuLayerCount(int count) {
    return '$count レイヤー';
  }

  @override
  String get imageSizeTitle => '画像サイズ';

  @override
  String get imageSizeNotSet => 'サイズ未指定';

  @override
  String get imageSizeHintGpt => 'モデルに任せる';

  @override
  String imageSizeHintQwenShort(String tier) {
    return '入力画像に合わせる · $tier';
  }

  @override
  String imageSizeHintQwen(String size, String tier) {
    return 'テキスト生成は $size、編集は入力画像の比率のまま $tier の面積に縮小';
  }

  @override
  String imageSizeHintWan(String tier) {
    return '$tier を送信';
  }

  @override
  String imageSizeKeywordHint(String ratio) {
    return '$ratio · キーワードで送信';
  }

  @override
  String get imageSizeTierSection => '大きさ';

  @override
  String get imageSizeTierAreaTarget => '面積の目安 · キーワードではない';

  @override
  String imageSizeSnapped(int step, String old, String value) {
    return '$step の倍数にスナップ：$old → $value';
  }

  @override
  String imageSizeClampedDown(
    String old,
    String ratio,
    String mp,
    String max,
    int step,
    String value,
  ) {
    return '$old は $ratio で $mp MP、上限 $max MP を超過。$step グリッドで $value まで下げました';
  }

  @override
  String imageSizeClampedUp(
    String old,
    String ratio,
    String mp,
    String min,
    int step,
    String value,
  ) {
    return '$old は $ratio で $mp MP、下限 $min MP を下回る。$step グリッドで $value まで上げました';
  }

  @override
  String imageSizeNoSolution(String limit) {
    return 'アスペクト比が $limit を超過：このモデルでは解がありません';
  }

  @override
  String imageSizeRatioOverLimit(String ratio, String limit) {
    return 'アスペクト比 $ratio が $limit を超過';
  }

  @override
  String get imageSizeOutOfRange => 'このサイズはモデルの受け付ける範囲外です';

  @override
  String imageSizeFixTo(String value) {
    return '$value にする';
  }

  @override
  String imageSizeNotWrittenBack(String value) {
    return '未反映：閉じると直前の有効なサイズ $value のままです';
  }

  @override
  String get imageSizeTypingHint => '入力中 · フォーカスを外すか Enter で確認';

  @override
  String get imageSizeSwap => '縦横を入れ替え';

  @override
  String imageSizeFellBack(String value, String model, String sentinel) {
    return '$value は $model では無効なため「$sentinel」に戻しました';
  }

  @override
  String imageSizeBillingTier(String tier) {
    return '$tier で課金';
  }

  @override
  String imageSizeBillingCrossed(String tier, String area, String next) {
    return '$tier の面積（$area）を超えるため $next で課金 · 規格別課金';
  }

  @override
  String get imageSizeRulesAllPass => 'すべて適合';

  @override
  String get imageSizeRulesPending => '確認待ち';

  @override
  String get imageSizeRuleFails => '不適合';

  @override
  String imageSizeRuleMaxEdgeShort(int max) {
    return '長辺 ≤ $max';
  }

  @override
  String imageSizeRuleMinEdgeShort(int min) {
    return '短辺 ≥ $min';
  }

  @override
  String imageSizeAreaRef(int edge) {
    return '面積の基準 $edge²';
  }

  @override
  String get imageSizeRecommendTable => '公式の推奨表';

  @override
  String get imageSizeRecommendCorner => '比率 \\ 段階';

  @override
  String get imageSizeRecommendHint =>
      'セルを選ぶと比率と大きさが同時に決まります。1:1 の行は段階キーワード、ほかはピクセルを送信。';

  @override
  String get imageSizeLockRatio => '比率を固定';

  @override
  String get imageSizeFooter => '即時反映 · Esc で元に戻す · Enter で閉じる';

  @override
  String get imageSizeFooterBlocked => 'Esc で元に戻す';

  @override
  String get imageSizeFooterTyping => 'Enter で確定';

  @override
  String get imageSizeDone => '完了';

  @override
  String get imageSizeRatioDerived => '派生 · 幅と高さに追従';

  @override
  String get imageSizeRatioAccepted => 'カスタム · 受理';

  @override
  String get optModeKnowledgeWrite => 'プロンプト作成';

  @override
  String get optModeUseFor => '用途';

  @override
  String optModeBadge(String basis, String detail) {
    return '$basis · $detail';
  }

  @override
  String get optPresetBuiltinName => '汎用最適化';

  @override
  String get optModeLocked => 'アシスタントが応答中 · モードはロックされています';

  @override
  String optModeSwitchTitle(String mode) {
    return '「$mode」に切り替えますか？';
  }

  @override
  String get optModeSwitchBody =>
      'タスクプリセットとナレッジベースの会話はつなげられないため、切り替えると新しい会話が始まります。現在の会話は保存済みで、「会話履歴」からいつでも戻れます。';

  @override
  String get optModeSwitchStart => '新しい会話を始める';

  @override
  String get optPresetCustom => 'カスタム指示';

  @override
  String get optPresetBuiltinBadge => '組み込み';

  @override
  String get optPresetBuiltinDesc => '専用の指示なし：ラフなアイデアを、そのまま使える画像・動画プロンプトに整えます。';

  @override
  String get optPresetBuiltinLocked => '組み込みの指示は編集できません';

  @override
  String get optPresetSaveAs => 'プリセットとして保存…';

  @override
  String get optPresetEditInstructions => '指示を表示 / 編集';

  @override
  String get optPresetViewInstructions => '指示を表示';

  @override
  String get optPresetManage => 'プロンプトライブラリでプリセットを管理';

  @override
  String get optPresetDiscardTitle => '未保存の変更を破棄しますか？';

  @override
  String optPresetDiscardBody(String name) {
    return '「$name」の指示には未保存の変更があります。プリセットを切り替えると失われます。';
  }

  @override
  String get optPresetDiscardAction => '変更を破棄';

  @override
  String get optEmptyPresetTitle => '今回は何をしますか？';

  @override
  String get optEmptyPresetSub =>
      'タスクプリセットを選んで、アイデアをアシスタントに送ってください。必要に応じて参考画像を確認し、何度でもやり取りできます。';

  @override
  String optEmptyPresetAll(int count) {
    return 'すべてのプリセット（$count）…';
  }

  @override
  String get optEmptyPresetCreate => 'プロンプトライブラリでプリセットを作成';

  @override
  String get optEmptyKbTitle => 'ナレッジベースに沿ってプロンプトを書く';

  @override
  String get optEmptyKbSub => 'アシスタントはまずナレッジベースのファイルマップを読み、今回必要なルール文書だけを開きます。';

  @override
  String get optEmptyKbExample1 => 'ナレッジベースのルールに沿って、プロンプトを書いてください：';

  @override
  String get optEmptyKbExample2 => 'ナレッジベースと照らして、このプロンプトの問題点を確認してください：';

  @override
  String get optEmptyKbExample3 => '参考画像の人物を見て、ナレッジベースのテンプレートで完全なプロンプトにしてください。';

  @override
  String get optEmptyKbEditTitle => 'ナレッジベースをメンテナンスする';

  @override
  String get optEmptyKbEditSub =>
      '追加・修正したい内容を伝えてください。変更はすべて diff で確認してから書き込まれます。';

  @override
  String get optEmptyKbEditExample1 => 'この種の画の書き方を記録する文書を追加してください：';

  @override
  String get optEmptyKbEditExample2 => 'ナレッジベース内に矛盾するルールがないか確認してください。';

  @override
  String get optEmptyKbEditExample3 =>
      'エントリファイルのファイルマップを実際のディレクトリに合わせて更新してください。';

  @override
  String get optLeftDocs => '文書';

  @override
  String optLeftRefs(int count) {
    return '参考画像 · $count';
  }

  @override
  String get optKbUseMaintainNotice =>
      '「メンテナンス」に切り替えました · アシスタントはナレッジベースの変更を提案できます';

  @override
  String get optKbUseWriteNotice =>
      '「プロンプト作成」に切り替えました · アシスタントはナレッジベースの変更を提案しなくなります';

  @override
  String get optPresetOutputPromptValue => 'プロンプト · カードで渡す';

  @override
  String get optPresetOutputAnalysisValue => '分析テキスト · 会話の中で回答';

  @override
  String get optEmptyAnalysisTitle => '今回は何を見ますか？';

  @override
  String get optEmptyAnalysisSub =>
      'どの参考画像を見て、何を取り出すのかを伝えてください。アシスタントはこのプリセットが定める構成でそのまま回答します。';

  @override
  String get optEmptyAnalysisExample1 => '参考画像 1 の内容を読み取ってください';

  @override
  String get optEmptyAnalysisExample2 => '参考画像 1 と 2 を合わせて、服のデザイン構造を説明してください';

  @override
  String get optEmptyAnalysisExample3 => '画像のほかに、次の情報を補足します：';

  @override
  String get optChatHintAnalysis => 'どの画像を見て、何を取り出すかを入力…';

  @override
  String optResultMeta(int count) {
    return '$count 文字 · Markdown';
  }

  @override
  String get optImagesNotOfferedTitle => 'このモデルは画像を見られません';

  @override
  String optImagesNotOfferedBody(int count) {
    return '$count 枚の参考画像はこのモデルに渡されておらず、回答は入力した文章だけに基づきます。右側で画像を扱えるモデルに切り替えるか、モデル設定で画像入力の可否を確認してください。';
  }

  @override
  String get optImagesNotOfferedAction => 'モデル設定を開く';
}
