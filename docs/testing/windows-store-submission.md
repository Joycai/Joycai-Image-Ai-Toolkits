# Windows Store submission materials (WIN-05)

Prepared 2026-11-08 for the Windows Store preparation branch, version 4.31.8.
**Draft; not approved for submission.** No Partner Center account/product has been
supplied. WIN-04 blocks production packaging. Listing claims must be reconciled
with the routes actually accepted for the final candidate; preparation builds are
not release candidates. No upload, enrollment, pricing or market choice is made here.

## Public listing copy

Proposed title: **Joycai Image AI Toolkits** (reservation pending).
Proposed category: **Photo & video** (publisher confirmation and portal selection pending).
The app supports English, Simplified Chinese, Traditional Chinese and Japanese;
package tags are en-US, zh-CN, zh-TW and ja-JP. These are not market selections.

### English

AI features require a compatible third-party service or local server. Hosted services
may require their own account, API key and separate payment; service fees are not
included with this app. Joycai generates text, images and video live using your
configured AI services. Available features depend on the chosen service and model.

Organize an AI media workflow in one Windows desktop app: manage models and channels,
prepare prompts and reference images, queue image and video tasks, and review results
and local usage estimates. Browse local media, save reusable prompts, and use the
prompt assistant to refine ideas. Local records stay on your computer; AI operations
send the relevant content to the recipient shown in the sharing prompt.

Review AI output before using or sharing it. Results may be inaccurate or inappropriate.
Report content concerns from Settings → About. No Joycai account is required.

### 简体中文

AI 功能需要兼容的第三方服务或本地服务器。云端服务可能要求单独的账号、API Key 和付费，
服务费用不包含在本应用中。Joycai 使用您配置的 AI 服务实时生成文本、图片和视频，
可用功能取决于所选服务及模型。

在一个 Windows 桌面应用中管理模型与通道、准备提示词和参考图、安排图片及视频任务，
并查看结果和本地用量估算。浏览本地素材、保存常用提示词，使用提示词助手完善创意。
本地记录保存在您的电脑上；AI 操作会将相关内容发送至共享提示中展示的接收方。

使用或分享前请检查 AI 输出，结果可能不准确或不适当。可通过设置 → 关于报告内容问题。
无需注册 Joycai 账号。

### 繁體中文

AI 功能需要相容的第三方服務或本機伺服器。雲端服務可能要求獨立帳號、API Key 及付費，
服務費用不包含在本應用程式中。Joycai 使用您設定的 AI 服務即時產生文字、圖片和影片，
可用功能取決於所選服務及模型。

在一個 Windows 桌面應用程式中管理模型與通道、準備提示詞和參考圖、安排圖片及影片任務，
並查看結果與本機用量估算。瀏覽本機素材、儲存常用提示詞，使用提示詞助手完善創意。
本機記錄儲存在您的電腦上；AI 操作會將相關內容傳送至共享提示中顯示的接收方。

使用或分享前請檢查 AI 輸出，結果可能不準確或不適當。可透過設定 → 關於回報內容問題。
無需註冊 Joycai 帳號。

### 日本語

AI 機能には、互換性のある外部サービスまたはローカルサーバーが必要です。
クラウドサービスでは別途アカウント、API キー、料金が必要になる場合があります。
サービス料金は本アプリに含まれません。Joycai は設定した AI サービスを使って
テキスト、画像、動画をリアルタイムに生成します。利用できる機能はサービスとモデルによって異なります。

Windows デスクトップでモデルとチャネルを管理し、プロンプトと参照画像を準備し、
画像や動画のタスクをキューに追加して、結果とローカルの使用量見積もりを確認できます。
ローカルの素材を閲覧し、よく使うプロンプトを保存し、プロンプトアシスタントでアイデアを整理できます。
ローカルの記録はお使いのコンピューターに保存されます。AI 操作に必要な内容は、共有確認に表示される送信先へ送られます。

AI の出力は不正確または不適切な場合があります。利用・共有する前に確認してください。
コンテンツに関する問題は「設定 → このアプリについて」から報告できます。Joycai アカウントは不要です。

## Contacts, privacy and requirements

Support/content-safety/privacy email: **joycai@joycai.cn**, confirmed by maintainer.
Support URL: https://github.com/Joycai/Joycai-Image-Ai-Toolkits/issues
(public; no secrets or private media).
Privacy URL: https://github.com/Joycai/Joycai-Image-Ai-Toolkits/blob/main/PRIVACY_POLICY.md

The GitHub connector retrieved the main-branch privacy document on 2026-11-08;
it still has the November 5 text. An anonymous HTTP request also returned 200 and
confirmed that date. The November 8 Windows changes become available
at that URL only after merge. Verify anonymous access and the updated text before
submission. The existing Settings → About privacy link and AI consent link point
to this URL; no runtime link changes are needed. Installed browser launch remains
part of WIN-06. Reporting attaches no content automatically.

Package target: Windows desktop x64; manifest minimum 10.0.17763.0 (Windows 10 1809).
This is a manifest floor, **not evidence of tested OS support**. WIN-06 must establish
the supported Windows range before advertising it. ARM64/x86 native builds are not
prepared. Internet access is required for remote services; local servers must be
separately installed/configured. Keyboard/mouse desktop operation is intended.
RAM, disk-space and graphics requirements need measurement on the final package;
do not invent minimums. Downloaded models are not bundled with the app.

## Capability explanation for certification

| Manifest capability | Proposed explanation |
| --- | --- |
| runFullTrust | Flutter Win32 desktop executable uses native window integration, SQLite, user-selected file read/write, drag/drop, media plugins, notifications and Windows DPAPI. It is not an AppContainer conversion and does not require an elevated application launch. |
| internetClient | User-initiated AI requests, job polling, result/media downloads and optional font downloads; recipients are documented in the privacy policy. |
| privateNetworkClientServer | Configured local/private-network AI endpoints and optional authenticated loopback MCP integration. MCP is not intended as a remotely exposed server. |

These match the inspected preparation manifest. No broadFileSystemAccess,
microphone or webcam capability is declared. Full-trust file access is not limited
by absence of those declarations. Confirm the exact candidate's capabilities and
explain any changes; Microsoft decides restricted-capability acceptance.

## Declarations and publisher decisions

| Field | Prepared answer / remaining action |
| --- | --- |
| Live generative AI | Yes: interactive text assistance and generated image/video content. Declare in metadata and applicable Partner Center fields. Attach final WIN-04 disposition evidence. |
| Age rating | Complete the IARC questionnaire against final enabled content and interactions; no rating has been assigned. Do not infer a child-safe rating from Gemini thresholds. |
| Content facts | User-entered prompts, imported media, remote generated content, streaming previews and optional local MCP clients. No project-operated public social feed; external services still need assessment. |
| Account eligibility | Publisher must confirm legal identity, account type and business status in Partner Center; project branding does not prove eligibility. |
| Markets | Unselected. Confirm provider availability, content/privacy obligations and applicable regional requirements for each selected market. Do not default to worldwide. |
| Commerce | App price and availability unconfirmed; external provider charges disclosed above. Confirm provider terms permit the offered integration. |
| Identity/version | Reserved name, Package/Identity Name, Publisher CN, publisher display name and highest prior version remain pending. |
| Cryptography | Windows DPAPI protects three credential fields; HTTPS protects supported network traffic. Answer applicable export questions from final implementation and selected markets. No export classification is asserted here. |

Microsoft's [Store policies](https://learn.microsoft.com/en-us/windows/apps/publish/store-policies)
require accurate listings, testable service access, privacy disclosure and live-AI
disclosure/reporting. Review account-type and regional provisions for the publisher.
The [MSIX age-rating process](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/age-ratings)
uses the Partner Center IARC questionnaire. Account registration remains a prerequisite;
see [getting started](https://learn.microsoft.com/en-us/windows/apps/publish/get-started).
Sources checked 2026-11-08; recheck when submitting.

## Actual Windows screenshots — pending candidate

Capture the installed accepted candidate in an isolated test profile, using rights-cleared
media and no personal paths, keys, logs or account identifiers. Keep original PNGs and
record package SHA-256, version, OS, language, display scaling and capture date.
Use desktop captures at 1920×1080 where practical; validate portal requirements before
upload. Do not substitute Mac captures, generated mockups or widget-harness images.

| Planned file per listing language | Scene and caption |
| --- | --- |
| 01-workbench.png | Prepare prompts and reference images |
| 02-tasks.png | Follow image/video tasks and review results |
| 03-prompts.png | Organize reusable prompts |
| 04-sharing.png | Review AI recipients and sharing choices |

Translate captions for each listing and omit any feature not enabled in the accepted
candidate. Current recovery/widget screenshots are engineering evidence only. **No
Store screenshots have been captured or approved.** Installed capture depends on
WIN-04 acceptance and the isolated environment required by WIN-06.

## Reviewer instructions draft

Before submitting, privately provide the exact candidate version/hash, supported OS,
accepted provider endpoint/model IDs, working revocable test credentials, quota/cost
limit, expiration and maintenance contact in certification notes. Never commit those
credentials or put them in listing text/screenshots. No test account or budget is
currently supplied, so reviewer access is **not yet validated**.

1. Launch as a standard Windows user. Complete first-run setup without importing
   personal data; select an empty output directory. Packaged portable mode is unavailable.
2. Add the supplied accepted channel in Models using the private certification values.
   Explain any separate service prerequisites in those notes; do not use a paid personal key.
3. In Workbench select the supplied image model, enter “A blue ceramic cup on a plain
   wooden table” and start one task. Confirm recipient/data disclosure before allowing.
   Verify the result, saved output and task state. Record expected quota consumption.
4. Use the supplied video model and supported duration with “A blue paper boat drifting
   on calm water”; observe polling, completion and playback. Skip only if video is removed
   from the final candidate and listing. Add exact settings after live acceptance.
5. Revoke AI sharing in Settings → About. Start another request and confirm no further
   sends until explicitly permitted. Review offline/denied access behavior.
6. Use content reporting in Settings → About. Confirm address-only email and copy-address
   fallback; do not send a report merely to test the button. Open the privacy link.
7. Close/relaunch and check saved settings/output. Run WIN-02/WIN-03/WIN-06 installed
   checks separately; these instructions are not a claim those checks passed.

## Rights and dependency review

Repository LICENSE is MIT, copyright 2026 BigBaicai; retain its notice. This does not
establish rights to every asset, bundled native library or service output.
`pubspec.yaml` bundles `assets/icon/icon.png` and prompt JSON presets. Maintainer must
confirm icon/preset provenance and rights to screenshot media before submission.

Flutter's third-party license UI exists under Settings → About. The previous WIN-03
preparation output contains `data/flutter_assets/NOTICES.Z`; decompression succeeded
(1,424,244 UTF-8 bytes), including Flutter, sqlite3, video_player_win,
fc_native_video_thumbnail and win32 entries. This is not a complete
license sign-off for a future package. Reconcile final `pubspec.lock`, generated notices
and native DLL inventory (including SQLite and media plugins), record license/version
and source URL for each shipped component, and retain required notices in the artifact.

Optional fonts are downloaded rather than bundled: Noto Sans SC (Expo Google Fonts),
HarmonyOS Sans (IKKI2000 mirror), and MiSans (dsrkafuu mirror), via jsDelivr in
`font_service.dart`. Upstream license/redistribution terms and mirror provenance need
verification; a mirror URL is not proof of rights. Review any font notice obligations
and remedy them before release. No new font or dependency was added for WIN-05.

## Acceptance status

Privacy wording and draft submission materials prepared; source review confirms
plaintext cookies, optional sensitive logs, preserved import sources and unredacted
recovery snapshots are disclosed. No runtime/build behavior changes in WIN-05.

Still required: updated public policy after merge and anonymous-link check; final
route restrictions/transport policy; rights/license clearance; accepted installed
screenshots; publisher/product/market/price fields; IARC and AI declarations in the
portal; private working reviewer access with adequate agreed quota; WIN-06 evidence.
WIN-05 stays open until those dependencies are resolved.
