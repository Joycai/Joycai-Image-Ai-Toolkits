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
  String get fileAlreadyExists => 'この名前のファイルは既に存在します';

  @override
  String get noFilesFound => 'ファイルが見つかりません';

  @override
  String get switchViewMode => '表示モードを切り替え';

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
  String get rulesInstructions => '名前変更ルール/指示';

  @override
  String get generateSuggestions => '提案を生成';

  @override
  String get noSuggestions => 'まだ提案は生成されていません';

  @override
  String get searchFilesHint => 'ファイル名を検索…';

  @override
  String get deselectAllDirectories => 'すべてのディレクトリ選択を解除';

  @override
  String get applyRenames => '名前の変更を適用';

  @override
  String get additionalInstructions => '追加指示（任意）';

  @override
  String get aiRenameInstructionsHint => '例：元の拡張子を保持、ピンインに変換…';

  @override
  String get noTemplateSelected => 'テンプレート未選択';

  @override
  String get selectTemplateFirst => '先に名前変更テンプレートを選択してください。';

  @override
  String get generatingSuggestions => '提案を生成中…';

  @override
  String get renamePreviewTitle => '名前変更プレビュー';

  @override
  String conflictsFound(int count) {
    return '$count件の競合';
  }

  @override
  String get conflictDuplicateTarget => '変更後のファイル名が重複しています';

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
  String addToStagingCount(int count) {
    return 'ステージングに追加 · $count 件';
  }

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
  String get stagingNoTarget => '対象フォルダー未選択';

  @override
  String get stagingTargetHint =>
      '左カラムのフォルダーを右クリックして「ここへ移動 / コピー」を選ぶか、ファイルをフォルダーへドラッグします。';

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
  String pasteMoveTitle(String folder) {
    return '$folder へ移動';
  }

  @override
  String pasteCopyTitle(String folder) {
    return '$folder へコピー';
  }

  @override
  String get pasteNoDestination => '先に対象フォルダーを指定してください';

  @override
  String get pasteDestinationGone => '対象フォルダーが存在しません';

  @override
  String get pasteNothingToDo => '転送するファイルがありません';

  @override
  String get conflictsTitle => '名前の衝突を解決';

  @override
  String get conflictSkip => 'スキップ';

  @override
  String get conflictOverwrite => '上書き';

  @override
  String get conflictRename => '両方保持';

  @override
  String get conflictApplyToRest => '残りすべてに適用';

  @override
  String get conflictReasonExists => '対象フォルダーに既にあります';

  @override
  String get conflictReasonDuplicate => '別のステージング項目と同名';

  @override
  String get conflictReasonSameLocation => 'すでにこのフォルダー内';

  @override
  String get conflictReasonMissing => '元ファイルが存在しません';

  @override
  String get pasteCrossVolumeWarning =>
      '別ドライブへの転送: コピー後に削除するため時間がかかり、途中で止まることがあります。';

  @override
  String get pasteRunningMove => '移動中…';

  @override
  String get pasteRunningCopy => 'コピー中…';

  @override
  String pasteProgressCount(int done, int total) {
    return '$done / $total';
  }

  @override
  String get pasteDoneTitle => '転送が完了しました';

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
  String renameEditingHint(int row) {
    return '$row 行目を編集中';
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
  String get renameActionAccept => '採用';

  @override
  String get renameActionSkip => 'スキップ';

  @override
  String get renameActionEdit => '名前を編集';

  @override
  String get renameActionUndo => 'スキップを取消';

  @override
  String get renameConflictAutoRename => '改名';

  @override
  String get renameNoModelsTitle => '利用できるモデルがありません';

  @override
  String get renameNoModelsDesc =>
      '一括リネームには画像を読んで名前を作るチャットモデルが必要です。まず「モデルとチャネル」で利用可能なチャネルを設定してください。';

  @override
  String get renameGoToSettings => '設定を開く';

  @override
  String renameBatchFailed(int batch, String reason) {
    return 'バッチ $batch が失敗 · $reason';
  }

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
  String pasteProgressItems(
    int done,
    int total,
    String doneSize,
    String totalSize,
  ) {
    return '$done / $total 件 · $doneSize / $totalSize';
  }

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
  String conflictWriteInfo(String size, String date) {
    return '書き込み · $size · $date';
  }

  @override
  String conflictExistingInfo(String size, String date) {
    return '既存 · $size · $date';
  }

  @override
  String get conflictOverwriteWarning => '対象のファイルは置き換えられます。元に戻せません';

  @override
  String conflictApplyRestCount(int count) {
    return '残り $count 件にも同じ選択を適用';
  }

  @override
  String get conflictApplyAndContinue => '適用して続行';

  @override
  String dragMoveHint(int count) {
    return '$count 件を移動 · Ctrl でコピー';
  }

  @override
  String get showInSystem => 'システムで表示';

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
  String get noTasks => 'No active tasks';

  @override
  String get sidebar => 'サイドバー';

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
  String get enterUrlToStart => 'URLと要件を入力して開始してください。';

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
  String get manualHtmlHint => 'レンダリングされたHTMLをここに貼り付けます（F12 -> 外部HTMLをコピー）';

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
  String get usage => '使用状況';

  @override
  String get tokenUsageMetrics => 'トークン使用状況メトリクス';

  @override
  String get clearAllUsage => 'すべての使用状況データをクリアしますか？';

  @override
  String get clearUsageWarning => 'これにより、データベースからすべてのトークン使用状況レコードが完全に削除されます。';

  @override
  String get modelsLabel => 'モデル：';

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
  String get models => 'モデル';

  @override
  String get modelManagement => 'モデル管理';

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
  String get addFirstModel => '最初のLLMモデルを追加して始めましょう';

  @override
  String get addNewModel => '新しいモデルを追加';

  @override
  String get deleteModel => 'モデルを削除';

  @override
  String get deleteModelConfirmTitle => 'モデルを削除しますか？';

  @override
  String deleteModelConfirmMessage(String name) {
    return '「$name」を削除してもよろしいですか？';
  }

  @override
  String get addLlmModel => 'LLMモデルを追加';

  @override
  String get editLlmModel => 'LLMモデルを編集';

  @override
  String get modelIdLabel => 'モデル ID';

  @override
  String get displayName => '表示名';

  @override
  String get type => 'タイプ';

  @override
  String get tag => 'タグ';

  @override
  String get inputFeeLabel => '入力料金（\$/Mトークン）';

  @override
  String get outputFeeLabel => '出力料金（\$/Mトークン）';

  @override
  String get paidModel => '有料モデル';

  @override
  String get freeModel => '無料モデル';

  @override
  String get billingMode => '請求モード';

  @override
  String get perToken => '100万トークンあたり';

  @override
  String get perRequest => 'リクエストあたり';

  @override
  String get requestFeeLabel => 'リクエスト料金（\$/リクエスト）';

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
  String get priceConfig => '価格設定';

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
  String get stepProtocol => 'プロトコルを選択';

  @override
  String get stepProvider => 'プロバイダーを選択';

  @override
  String get stepApiKey => 'APIキー';

  @override
  String get stepConfig => '追加設定';

  @override
  String get stepPreview => 'プレビュー';

  @override
  String get protocolOpenAI => 'OpenAI互換（REST）';

  @override
  String get protocolOpenAIDesc => '標準のOpenAI REST API互換性';

  @override
  String get protocolGoogle => 'Google GenAI（REST）';

  @override
  String get protocolGoogleDesc => '公式Google Gemini REST API';

  @override
  String get protocolMidjourney => 'Midjourney プロキシ';

  @override
  String get protocolMidjourneyDesc =>
      'midjourney-proxy / NewAPI の /mj/* インターフェース';

  @override
  String get protocolAnthropic => 'Anthropic Messages';

  @override
  String get protocolAnthropicDesc => 'Claude ネイティブの /v1/messages インターフェース';

  @override
  String get midjourneyEndpointHint =>
      'ホストのルートURL（例: https://your-newapi.com）を入力してください。/mj/* パスは自動的に追加されます。';

  @override
  String get providerOpenAIOfficial => 'OpenAI公式';

  @override
  String get providerGoogleOfficial => 'Google GenAI公式';

  @override
  String get providerGoogleCompatible => 'Google GenAI（OpenAI互換）';

  @override
  String get providerGoogleCompatibleDesc => 'OpenAIエンドポイント経由のGoogle Gemini';

  @override
  String get providerDashScopeDesc =>
      'dashscope.aliyuncs.com/compatible-mode · OpenAI 形式のリクエスト · Qwen チャット + qwen-image / Wan ネイティブ画像 + Wan 動画';

  @override
  String get providerDashScopeCompat => 'Alibaba DashScope（OpenAI 互換）';

  @override
  String get providerDashScopeNative => 'Alibaba DashScope（ネイティブ）';

  @override
  String get providerDashScopeNativeDesc =>
      'dashscope.aliyuncs.com/api/v1 · Alibaba 独自のリクエスト形式 · qwen-audio はこの経路のみ';

  @override
  String get endpointOverrideHint =>
      '選択したプロバイダーの既定値です。中継・ゲートウェイ・国際版ホストに変更できます。';

  @override
  String get providerQianwen => 'Qianwen プラットフォーム';

  @override
  String get providerQianwenDesc =>
      'platform.qianwenai.com · DashScope と同一 API — Qwen チャット + qwen-image / wan2.7 画像生成';

  @override
  String get providerCustom => 'カスタムプロバイダー';

  @override
  String get providerCustomDesc => 'セルフホストまたはサードパーティプロバイダー';

  @override
  String get providerGroupOther => 'その他';

  @override
  String get stepConnection => '接続とキー';

  @override
  String get sectionAppearance => '外観';

  @override
  String get moreColors => 'その他の色';

  @override
  String get protocolXai => 'xAI (Grok) API';

  @override
  String get providerXaiOfficial => 'xAI 公式';

  @override
  String get providerXaiOfficialDesc =>
      'api.x.ai · Grok チャット + ネイティブ Imagine 動画';

  @override
  String get providerNewApiOpenAI => 'New API（OpenAI 形式）';

  @override
  String get providerNewApiGemini => 'New API（Gemini 形式）';

  @override
  String get providerNewApiDesc => 'New API リレー · ベアラートークン認証';

  @override
  String get providerAnthropicOfficial => 'Anthropic 公式';

  @override
  String get providerAnthropicOfficialDesc => 'api.anthropic.com · Claude';

  @override
  String get providerNewApiAnthropic => 'New API（Anthropic 形式）';

  @override
  String get providerMiniMaxAnthropic => 'MiniMax（Anthropic 形式）';

  @override
  String get providerMiniMaxDesc => 'OpenAI 互換 /v1 エンドポイント';

  @override
  String get newApiBaseUrl => 'New API ベース URL';

  @override
  String get newApiBaseHint => 'New API のホストを入力してください。バージョンパスは自動的に追加されます';

  @override
  String get customEndpointHint => 'カスタムエンドポイントURLを入力してください';

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
  String get enterApiKey => 'APIキーを入力してください';

  @override
  String get apiKeyStorageNotice => 'キーはローカルに保存され、当社のサーバーには送信されません。';

  @override
  String get nameHint => '例：本番API';

  @override
  String get enableDiscoveryDesc => 'このエンドポイントから利用可能なモデルを自動的にリストアップする';

  @override
  String get tagHint => '例：GPT4, Local, など';

  @override
  String get bindTag => 'タグをバインド';

  @override
  String get previewReady => 'このチャンネルを追加する準備ができましたか？';

  @override
  String get feeGroupDesc => 'モデルの請求基準を定義して、使用コストを正確に計算します。';

  @override
  String get feeGroupEditorSubtitle => 'モデルの請求基準を設定します';

  @override
  String get noFeeGroups => 'まだ料金グループが作成されていません';

  @override
  String get pricePerMillion => '100万トークンあたりの価格';

  @override
  String get pricePerRequest => 'リクエストあたりの価格';

  @override
  String get tokenBilling => 'トークン請求';

  @override
  String get requestBilling => 'リクエスト請求';

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
  String get modelSaveRequirementHint => 'チャンネル・名前・ID の 3 項目がそろうと保存できます。';

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
      '回答前にモデルがどれだけ考えるか。デフォルト＝何も送信しない（エンドポイント任せ）。他のレベルは出力トークンを消費します。OpenAI・Anthropic 形式のチャネルに適用。';

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
  String get addChannelSubtitle => 'まず「どこか」を選び、次に接続情報を入力';

  @override
  String get searchProviders => 'プロバイダーを検索…';

  @override
  String get noProviderMatch => '一致するプロバイダーがありません';

  @override
  String get resetToDefault => '既定値に戻す';

  @override
  String get apiKeyRequired => 'このプロバイダーはチャンネル追加に API キーが必要です';

  @override
  String get endpointRequired => 'エンドポイント URL を入力してください';

  @override
  String get probeRetry => '再試行';

  @override
  String get customColor => 'カスタムカラー';

  @override
  String get stepConnectionAppearance => '接続と外観';

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
  String get previewInList => 'リストでの見え方';

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
  String get variantHintGoogle =>
      'Google は同じモデルを 2 通りで提供します。切り替えると下のアドレスが書き換わります。';

  @override
  String get variantHintMiniMax =>
      'MiniMax は 2 つのインターフェースを提供しています。どちらかを選択（後から変更可）。';

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
  String get variantMiniMaxAnthropic => 'Anthropic 面';

  @override
  String get variantNewApiOpenAI => 'OpenAI 形式';

  @override
  String get variantNewApiGemini => 'Gemini 形式';

  @override
  String get variantNewApiAnthropic => 'Anthropic 形式';

  @override
  String get channelPresetLabel => 'プロバイダプリセット';

  @override
  String get channelPresetHint =>
      'プリセットは下の項目をまとめて入力するだけです。入力後も個別に編集でき、編集内容が上書きされることはありません。';

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
  String get protocolFieldHint => 'プロトコルファミリーは 5 つ。保存済みのどの種別もここで表現できます。';

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
  String get protocolAutoHelper => 'チャネルのプロバイダーに従い、プロバイダー変更時に自動で再解決されます。';

  @override
  String protocolStaleHelper(String name) {
    return '以前の選択「$name」は現在のプロバイダーでは利用できないため、自動に戻りました。';
  }

  @override
  String get protocolOpenAICompat => 'OpenAI 互換';

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
  String get protocolVideoTask => '非同期動画タスク';

  @override
  String get protocolStreamIgnoredAsync => '非同期タスクはストリーミングを使用しないため、この設定は無視されます';

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
  String get saveFavoritePrompts => 'お気に入りのプロンプトやリファイナーのシステムプロンプトをここに保存します';

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
  String get setAsRefiner => 'リファイナーとして設定';

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
  String get selectRenameTemplate => '名前変更テンプレートを選択';

  @override
  String get selectCategory => 'カテゴリを選択';

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
  String selectionModeCount(int count) {
    return '選択モード（$count）';
  }

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
  String get preferHighPerformanceGpu => '高性能GPUを優先';

  @override
  String get preferHighPerformanceGpuDesc =>
      'Windowsにディスクリート（専用）GPUでの実行を要求します。次回起動時に反映されます。';

  @override
  String get reduceVisualEffects => '視覚効果を減らす';

  @override
  String get reduceVisualEffectsDesc => 'ぼかし効果を無効にして、内蔵GPUや低性能GPUでも滑らかに動作させます。';

  @override
  String get googleGenAiSettings => 'Google GenAI REST設定';

  @override
  String get openAiApiSettings => 'OpenAI API REST設定';

  @override
  String get standardConfig => '標準設定';

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
  String get importNow => '今すぐインポート';

  @override
  String get importOptions => 'インポートオプション';

  @override
  String get notInBackup => 'バックアップファイルで利用できません';

  @override
  String get importSettingsTitle => '設定をインポートしますか？';

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
  String get importModeDesc =>
      'プロンプトのインポート方法を選択してください:\n\nマージ: ライブラリに新しいアイテムを追加します。\n置換: 現在のライブラリを削除し、インポートされたデータを使用します。';

  @override
  String get merge => 'マージ';

  @override
  String get replaceAll => 'すべて置換';

  @override
  String get applyOverwrite => '適用（上書き）';

  @override
  String get applyAppend => '適用（追加）';

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
  String get clearDownloaderCache => 'ダウンローダーキャッシュをクリア';

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
  String get downloaderCacheCleared => 'ダウンローダーのキャッシュがクリアされました。';

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
  String get taskSummary => 'タスクの概要';

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
  String get clearAllConfirm => '実行中でないすべてのタスクを削除します。この操作は元に戻せません。';

  @override
  String get cancelAllPending => 'すべての保留中をキャンセル';

  @override
  String get cancelTask => 'タスクをキャンセル';

  @override
  String get removeFromList => 'リストから削除';

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
  String get latestLog => '最新ログ:';

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
  String get statusCancelled => 'キャンセル済み';

  @override
  String get retryTask => '再試行';

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
  String get setupWizardTitle => 'ようこそセットアップ';

  @override
  String get welcomeMessage => 'Joycai Image AI Toolkitsへようこそ！セットアップを始めましょう。';

  @override
  String get getStarted => '始める';

  @override
  String get stepAppearance => '外観';

  @override
  String get stepStorage => 'ストレージ';

  @override
  String get stepApi => 'インテリジェンス (API)';

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
  String get googleGenAiFree => 'Google GenAI (無料)';

  @override
  String get googleGenAiPaid => 'Google GenAI (有料)';

  @override
  String get openaiApi => 'OpenAI API';

  @override
  String get filenamePrefix => 'ファイル名のプレフィックス';

  @override
  String get openaiEndpointHint => 'ヒント: OpenAI互換のエンドポイントは通常「/v1」で終わります';

  @override
  String get googleEndpointHint =>
      'ヒント: Google GenAIのエンドポイントは通常「/v1beta」で終わります（内部処理）';

  @override
  String get workbench => 'ワークベンチ';

  @override
  String get imageProcessing => '画像処理';

  @override
  String get wbModeImage => '画像';

  @override
  String get wbModeVideo => '動画';

  @override
  String get wbTools => 'ツール';

  @override
  String get sourceGallery => 'ソースギャラリー';

  @override
  String get sourceExplorer => 'ソースエクスプローラー';

  @override
  String get tempWorkspace => '一時ワークスペース';

  @override
  String get processResults => '処理結果';

  @override
  String get resultCache => '結果キャッシュ';

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
  String get backToAll => 'すべてに戻る';

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
  String get dropFilesHere => 'ここに画像をドロップして一時ワークスペースに追加';

  @override
  String get noImagesSelected => '画像が選択されていません';

  @override
  String get imageLoadFailed => '画像の読み込みに失敗しました';

  @override
  String get selectSourceDirectory => 'ソースディレクトリを選択';

  @override
  String get removeFolderTooltip => 'フォルダを削除';

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
  String get deleteFile => 'ファイルを削除';

  @override
  String get deleteFileConfirmTitle => 'ファイルを削除しますか？';

  @override
  String deleteFileConfirmMessage(String filename) {
    return '「$filename」を削除してもよろしいですか？';
  }

  @override
  String get moveToTrash => 'ゴミ箱に移動';

  @override
  String get permanentlyDelete => '完全に削除';

  @override
  String get deleteSuccess => '削除に成功しました';

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
  String get qualityLow => '低';

  @override
  String get qualityMedium => '中';

  @override
  String get qualityHigh => '高';

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
  String get optimizePromptWithImage => '画像からプロンプトを最適化';

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
  String get saveMaskToTemp => 'マスクをワークスペースに保存';

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
  String get refinerIntro => 'AIを使用して画像を分析し、プロンプトを洗練させます。';

  @override
  String get roughPrompt => 'ラフなプロンプト / アイデア';

  @override
  String get optimizedPrompt => '最適化されたプロンプト';

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
  String get optSend => '送信 (Ctrl+Enter)';

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
  String get optEmptyChat =>
      'ラフなプロンプトやアイデアを送信して開始します。AIは必要に応じて参照画像を確認し、複数ターンで結果を調整できます。';

  @override
  String get optViewed => 'AI が閲覧済み';

  @override
  String get optRemoveImage => '画像を削除';

  @override
  String get optEmptyImagesHint =>
      'ギャラリーで画像を右クリックし、「プロンプトアシスタントに送信」を選択すると追加できます。';

  @override
  String get videoGeneration => '動画生成';

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
  String get dropFirstFrameHere => '開始フレーム画像をここにドロップ';

  @override
  String get dropLastFrameHere => '終了フレーム画像をここにドロップ';

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
  String get filesAppSuffix => ' (ファイル App)';

  @override
  String get tapToPick => 'タップして選択';

  @override
  String get goToGallery => 'ギャラリーへ';

  @override
  String get binaryModeActive => 'バイナリモード有効 — クリーンなマスクエクスポートのため背景非表示';

  @override
  String get imageSizePickerTitle => '画像サイズ';

  @override
  String get imageSizeAuto => '自動';

  @override
  String get imageSizeAutoDesc => 'モデルにサイズを任せる';

  @override
  String get imageSizePresets => 'プリセット';

  @override
  String get imageSizeCustom => 'カスタム';

  @override
  String get imageSizeRatio => '比率';

  @override
  String get imageSizeLongEdge => '長辺';

  @override
  String get imageSizeCompute => '計算';

  @override
  String get imageSizeWidth => '幅';

  @override
  String get imageSizeHeight => '高さ';

  @override
  String get imageSizeSnapHint => '適用時、両辺は 16 ピクセルの倍数に自動でスナップされます。';

  @override
  String get sizeRuleMultiple16 => '両辺が 16 の倍数';

  @override
  String sizeRuleMaxEdge(int long) {
    return '長辺 ${long}px ≤ 3840';
  }

  @override
  String sizeRuleAspect(String ratio) {
    return 'アスペクト比 $ratio ≤ 3:1';
  }

  @override
  String sizeRulePixels(String mp) {
    return '総画素 $mp は 0.66–8.29 MP の範囲内';
  }

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
  String get optModeSystemPrompt => 'システムプロンプト';

  @override
  String get optModeKnowledge => 'ナレッジベース';

  @override
  String get knowledgeBase => 'ナレッジベース';

  @override
  String get optKbNotConfigured => 'ナレッジベースが未設定または無効です。設定でフォルダを選択してください。';

  @override
  String get optModeSwitchConfirm => 'モードを切り替えると新しい会話が開始されます。続行しますか？';

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
  String get optKbDistillRequested => 'リクエスト済み：今回の調整で得た知見をナレッジベースへ整理します。';

  @override
  String get optResultFeedbackAction => 'アシスタントに報告';

  @override
  String get optResultFeedbackChatLabel => '生成結果の報告';

  @override
  String get optResultFeedbackHint => 'この画像のどこが期待と違いますか？';

  @override
  String optResultFeedbackHelper(int version) {
    return 'この結果画像は報告と一緒に会話へ送られ、アシスタントが v$version を基に調整を続けます。';
  }

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
  String get optModeKnowledgeEdit => 'ナレッジ編集';

  @override
  String optToolWriteKnowledge(String name) {
    return 'ナレッジ更新の提案：$name';
  }

  @override
  String get kbEditProposedCreate => '新規ファイル';

  @override
  String get kbEditProposedUpdate => 'ファイル更新';

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
  String optModeBadgeAgent(String mode) {
    return '$mode · エージェント';
  }

  @override
  String get optRefNumberingHint =>
      '番号はプロンプトで引用されるファイル名に対応します。エージェントはこれらの画像を参照できます。';

  @override
  String get optModeKnowledgeEditShort => 'ナレッジ編集';

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
  String get optSysPromptTemplate => 'テンプレート';

  @override
  String get optSysPromptPick => 'テンプレートを選択';

  @override
  String get optSysPromptSearch => 'テンプレートを検索…';

  @override
  String get optSysPromptNone => 'テンプレート未選択';

  @override
  String get optSysPromptUnsaved => '未保存';

  @override
  String get optSysPromptSave => '保存';

  @override
  String get optSysPromptReset => 'リセット';

  @override
  String get optSysPromptSaved => 'テンプレートを保存しました';

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
  String get optSysPromptNoTools =>
      'このモードではナレッジツールを読み込まないため、agent はツールを呼び出しません。';

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
}
