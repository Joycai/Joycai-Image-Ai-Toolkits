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
  String get applyRenames => '名前の変更を適用';

  @override
  String get addToSelection => '選択に追加';

  @override
  String get removeFromSelection => '選択から削除';

  @override
  String imagesSelected(int count) {
    return '$count個選択済み';
  }

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
  String get outputTokens => '出力トークン';

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
  String get clearAll => 'すべてクリア';

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
  String get enableDiscovery => 'モデル検出を有効にする';

  @override
  String get filterModels => 'モデルをフィルター...';

  @override
  String get tagColor => 'タグの色';

  @override
  String deleteChannelConfirm(String name) {
    return 'チャンネル「$name」を削除してもよろしいですか？関連するすべてのモデルのリンクが解除されます。';
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
  String get modelIdLabel => 'モデルID（例：gemini-pro）';

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
  String get outputPrice => '出力価格（\$/Mトークン）';

  @override
  String get requestPrice => 'リクエスト価格（\$/リクエスト）';

  @override
  String get priceConfig => '価格設定';

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
  String get selectAll => 'すべて選択';

  @override
  String get deselectAll => 'すべて選択解除';

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
  String get providerOpenAIOfficial => 'OpenAI公式';

  @override
  String get providerGoogleOfficial => 'Google GenAI公式';

  @override
  String get providerGoogleCompatible => 'Google GenAI（OpenAI互換）';

  @override
  String get providerGoogleCompatibleDesc => 'OpenAIエンドポイント経由のGoogle Gemini';

  @override
  String get providerCustom => 'カスタムプロバイダー';

  @override
  String get providerCustomDesc => 'セルフホストまたはサードパーティプロバイダー';

  @override
  String get customEndpointHint => 'カスタムエンドポイントURLを入力してください';

  @override
  String get openaiV1Hint => 'ヒント：OpenAI互換のエンドポイントは通常「/v1」で終わります';

  @override
  String get googleV1BetaHint => 'ヒント：Google GenAIのエンドポイントは通常「/v1beta」で終わります';

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
  String get model => 'モデル';

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
  String get cancelAllPending => 'すべての保留中をキャンセル';

  @override
  String get cancelTask => 'タスクをキャンセル';

  @override
  String get removeFromList => 'リストから削除';

  @override
  String get images => '画像';

  @override
  String filesCount(int count) {
    return '$count ファイル';
  }

  @override
  String runningCount(int count) {
    return '$count 実行中';
  }

  @override
  String plannedCount(int count) {
    return '$count 計画中';
  }

  @override
  String get latestLog => '最新のログ:';

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
    return '同時実行制限: $limit';
  }

  @override
  String retryCount(int count) {
    return '再試行回数: $count';
  }

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
  String get stepApi => 'インテリジェンス（API）';

  @override
  String get setupCompleteMessage => 'すべて設定完了です！制作をお楽しみください。';

  @override
  String get skip => 'スキップ';

  @override
  String get storageLocationDesc => '生成された画像が保存される場所を選択します。';

  @override
  String get addChannelOptional => '最初のAIプロバイダーチャネルを追加します（オプション）。';

  @override
  String get configureModelOptional => '新しいチャネルのモデルを設定します（オプション）。';

  @override
  String get googleGenAiFree => 'Google GenAI（無料）';

  @override
  String get googleGenAiPaid => 'Google GenAI（有料）';

  @override
  String get openaiApi => 'OpenAI API';

  @override
  String get filenamePrefix => 'ファイル名プレフィックス';

  @override
  String get openaiEndpointHint => 'ヒント：OpenAI互換のエンドポイントは通常「/v1」で終わります';

  @override
  String get googleEndpointHint =>
      'ヒント：Google GenAIのエンドポイントは通常「/v1beta」で終わります（内部処理）';

  @override
  String get workbench => 'ワークベンチ';

  @override
  String get imageProcessing => '画像処理';

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
  String get directories => 'ディレクトリ';

  @override
  String get addFolder => 'フォルダを追加';

  @override
  String get noFolders => 'フォルダが追加されていません';

  @override
  String get clickAddFolder => '「フォルダを追加」をクリックして画像のスキャンを開始します。';

  @override
  String get noImagesFound => '画像が見つかりません';

  @override
  String get noResultsYet => 'まだ結果がありません';

  @override
  String get importFromGallery => 'ギャラリーからインポート';

  @override
  String get takePhoto => '写真を撮る';

  @override
  String get clearTempWorkspace => 'ワークスペースをクリア';

  @override
  String get dropFilesHere => 'ここに画像をドロップして一時ワークスペースに追加します';

  @override
  String get noImagesSelected => 'No images selected';

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
  String get deleteFile => 'Delete File';

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
  String get deleteSuccess => '正常に削除されました';

  @override
  String deleteFailed(String error) {
    return '削除に失敗しました：$error';
  }

  @override
  String get modelSelection => 'モデル選択';

  @override
  String get selectAModel => 'タスクを送信する前にモデルを選択してください';

  @override
  String get aspectRatio => 'アスペクト比';

  @override
  String get resolution => '解像度';

  @override
  String get prompt => 'プロンプト';

  @override
  String get promptHint => 'ここにプロンプトを入力...';

  @override
  String get prefixHint => 'オプションのファイル名プレフィックス';

  @override
  String get processPrompt => 'プロンプトを処理';

  @override
  String processImages(int count) {
    return '$count枚の画像を処理';
  }

  @override
  String get taskSubmitted => 'タスクがキューに送信されました';

  @override
  String get comparator => '比較ツール';

  @override
  String get compareModeSync => '同期モード';

  @override
  String get compareModeSwap => 'スワップモード';

  @override
  String get sendToComparator => 'Send to Comparator';

  @override
  String get sendToComparatorRaw => '前として設定（RAW）';

  @override
  String get sendToComparatorAfter => '後として設定（結果）';

  @override
  String get sendToSelection => 'Add to Selection';

  @override
  String get sendToOptimizer => 'Send to Prompt Optimizer';

  @override
  String get optimizePromptWithImage => '画像でプロンプトを最適化';

  @override
  String get selectFromLibrary => 'ライブラリから選択';

  @override
  String get metadataSelectedNone => '画像メタデータが選択されていません';

  @override
  String get labelRaw => 'RAW';

  @override
  String get labelAfter => '後';

  @override
  String get cropAndResize => '切り抜きとサイズ変更';

  @override
  String get overwriteSource => 'オリジナルを上書き';

  @override
  String get overwriteConfirmTitle => 'オリジナルファイルを上書きしますか？';

  @override
  String get overwriteConfirmMessage => 'この操作はオリジナルファイルを永久に置き換えます。よろしいですか？';

  @override
  String get saveToTempSuccess => '画像が一時ワークスペースに保存されました';

  @override
  String get overwriteSuccess => 'オリジナルファイルが更新されました';

  @override
  String get custom => 'カスタム';

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
  String get undo => 'Undo';

  @override
  String get saveToTemp => 'ワークスペースに保存';

  @override
  String get saveMaskToTemp => 'マスクをワークスペースに保存';

  @override
  String get binaryMode => 'バイナリモード';

  @override
  String get maskSaved => 'マスクがワークスペースに保存されました';

  @override
  String maskSaveError(String error) {
    return 'マスクの保存中にエラーが発生しました：$error';
  }

  @override
  String get promptOptimizer => 'プロンプトオプティマイザ';

  @override
  String get refinerModel => 'リファイナーモデル';

  @override
  String get systemPrompt => 'システムプロンプト';

  @override
  String get refinerIntro => 'AIを使用して画像を分析し、プロンプトを改良します。';

  @override
  String get roughPrompt => 'ラフなプロンプト/アイデア';

  @override
  String get optimizedPrompt => '最適化されたプロンプト';

  @override
  String get applyToWorkbench => 'ワークベンチに適用';

  @override
  String get promptApplied => 'プロンプトがワークベンチに適用されました';

  @override
  String refineFailed(String error) {
    return '改良に失敗しました：$error';
  }

  @override
  String get executionLogs => '実行ログ';

  @override
  String get saveToPhotos => '写真に保存';

  @override
  String get saveToGallery => 'ギャラリーに保存';

  @override
  String get savedToPhotos => '写真に保存しました';

  @override
  String saveFailed(String error) {
    return '保存に失敗しました：$error';
  }

  @override
  String get iosSandboxActive => 'iOSサンドボックスがアクティブです';

  @override
  String get iosSandboxDesc =>
      'iOSでは、トップツールバーの「ギャラリーからインポート」ボタンを使用して、一時ワークスペースに画像を追加してください。';

  @override
  String get mobileSandboxActive => 'モバイルストレージの制限';

  @override
  String get mobileSandboxDesc =>
      'モバイルデバイスでは、OSによって直接のフォルダアクセスが制限される場合があります。トップツールバーの「ギャラリーからインポート」ボタンを使用することをお勧めします。';

  @override
  String get filesAppSuffix => '（ファイルアプリ）';
}
