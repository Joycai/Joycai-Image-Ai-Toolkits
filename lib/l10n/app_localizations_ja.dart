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
  String get results => '結果';

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
  String modelsAndChannelsCount(int models, int channels) {
    return '$modelsモデル · $channelsチャンネル';
  }

  @override
  String get deselectAll => 'すべて選択解除';

  @override
  String get capabilities => '機能';

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
  String get contextUnlimited => '無制限';

  @override
  String get contextUnlimitedDesc => 'すべての候補を1回のリクエストで送信（バッチ分割なし）';

  @override
  String get contextMax => '最大コンテキスト';

  @override
  String contextTokens(String size) {
    return '$size tokens';
  }

  @override
  String get contextWindowHint => 'コンテキストが大きいほど、1回のリクエストでより多くの画像を分析できます。';

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
  String get quality => '品質';

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
  String get taskSubmitted => 'タスクがキューに送信されました';

  @override
  String get comparator => '比較ツール';

  @override
  String get compareModeSync => '同期モード';

  @override
  String get compareModeSwap => 'スワップモード';

  @override
  String get sendToComparator => '比較ツールに送信';

  @override
  String get sendToComparatorRaw => 'Before (RAW) として設定';

  @override
  String get sendToComparatorAfter => 'After (結果) として設定';

  @override
  String get sendToFirstFrame => 'Set as First Frame (Video)';

  @override
  String get sendToLastFrame => 'Set as Last Frame (Video)';

  @override
  String get sendToVideoReferences => 'Add to Video References';

  @override
  String get sendToSelection => '選択に追加';

  @override
  String get sendToOptimizer => 'プロンプト最適化に送信';

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
  String get saveToTempSuccess => '画像が一時ワークスペースに保存されました';

  @override
  String get overwriteSuccess => '元のファイルが更新されました';

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
  String get undo => '元に戻す';

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
    return 'マスク保存エラー: $error';
  }

  @override
  String get promptOptimizer => 'プロンプト最適化';

  @override
  String get refinerModel => 'リファイナーモデル';

  @override
  String get systemPrompt => 'システムプロンプト';

  @override
  String get preset => 'プリセット';

  @override
  String get customSysPromptHint => 'このセッション用のカスタムシステムプロンプトを入力...';

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
  String get optAgentWorking => '最適化中...';

  @override
  String get optToolListImages => '参照画像リストを確認しました';

  @override
  String optToolViewImage(String name) {
    return '参照画像を確認しました：$name';
  }

  @override
  String optPromptVersion(int version) {
    return '最適化プロンプト v$version';
  }

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
}
