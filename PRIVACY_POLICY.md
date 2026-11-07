# Privacy Policy / 隐私政策

Last updated: November 8, 2026 · 最后更新：2026 年 11 月 8 日

## English

### 1. Scope and operator

This policy describes Joycai Image AI Toolkits, maintained by Joycai (the “app”, “we”). Features and file-access permissions vary by platform and distribution channel. It covers the app, not the independent services you configure or websites you visit.

The app does not require a Joycai account. We do not operate a cloud service that automatically receives your prompts, media, API credentials or local database. The current app does not include advertising, cross-app tracking or an automatic analytics/crash-report upload service. Local usage and cost statistics are for your own records. This does **not** mean the app never sends data over the network: AI features and downloads contact the services described below.

### 2. Data used and why

| Data | Purpose and handling |
| --- | --- |
| Prompts, conversations, reference images, masks, and supported video/audio inputs | Provide the AI operation you invoke; relevant content is sent to the configured AI endpoint. Responses, task state and history may be saved locally. |
| Knowledge-base files and assistant context | Read the folders/files you configure and supply relevant content to assistant requests. Conversation history, notes and tool results may become part of the request. |
| File names, paths and media metadata | Browse, organize, import, export and rename files. AI-assisted operations may include relevant names, metadata or media in requests. Ordinary local browsing does not by itself upload the entire directory to an AI service. |
| API keys, endpoint addresses, proxy settings and credentials | Authenticate and route requests to your configured service. Stored locally; the relevant endpoint receives its authentication credential. |
| Task records, model settings, usage and cost estimates | Run queues, restore work, display history and calculate local statistics. Previously queued work may make network requests when resumed or retried. |
| Website URLs and cookies you supply | Retrieve pages/media using the downloader. Cookies can grant access to your website account; they are used for the requested website operation, not advertising tracking by Joycai. |
| Local diagnostic logs | Diagnose failures. Optional API debugging can record request/response content, URLs and errors. Known credential fields are masked and large payloads truncated, but logs can still contain personal or sensitive information. |

### 3. Recipients and network access

**AI services.** Requests go to the endpoint configured for the selected channel/model, which may be a provider, a relay, or a local server. The recipient can receive prompts, relevant conversation/knowledge context, attachments, generation parameters and authentication data. Provider names shown in presets do not guarantee that a custom endpoint belongs to that provider. Review the actual endpoint and its privacy terms before sending content. Providers and relays have their own retention, training, deletion and international-processing practices; we do not promise that they retain nothing or never use content for training.

**AI sharing controls.** In versions with the AI data-sharing prompt, the app asks for explicit permission before its first connection to an AI recipient. The prompt identifies the actual recipient, describes the data and purposes, and links to this policy. The local decision covers subsequent requests, including batches, retries, resumed work and MCP-triggered operations. Changing the configured endpoint, service type, recipient or proxy requires a new decision. You can revoke permission in **Settings → About → AI data sharing**, or enable a fresh prompt after declining. Revocation blocks future requests; it cannot recall data or cancel processing already accepted upstream. Decisions are stored locally, excluded from settings backups and cleared when importing another installation. Earlier builds without these controls require stopping tasks and removing credentials to prevent further requests.

**Downloads and external links.** Websites, media hosts and configured proxies receive the requests needed to retrieve content. Optional font downloads contact jsDelivr; the system font does not require that download. Opening GitHub, release notes or other external links contacts the relevant website/browser. Network recipients can see your IP address and ordinary request metadata. Depending on their locations, processing may occur outside your country.

**MCP integrations.** If enabled, the local MCP server accepts authenticated clients on the loopback address. Clients can invoke supported tools, initiate AI requests and receive results within the configured access scope. Treat the MCP token and authorized clients as access to those capabilities. Clients may further process received information under their own policies.

We do not sell your personal data or use your content for our own advertising or model training. Information you deliberately send to project support is received by the project and the support platform; send only what is needed to address your request.

### 4. Local storage and security

Settings, credentials, conversations and records are stored locally. Mac App Store builds with credential protection encrypt channel API keys, proxy passwords and MCP tokens in SQLite using a device-local key held in Apple Keychain. Existing plaintext values are migrated after encryption and read-back verification succeed; a failed migration preserves the original values. Windows packaged builds with the Windows credential-protection implementation (including sideloaded MSIX) encrypt the same three fields using Windows user-scoped Data Protection API (DPAPI). Windows manages its protection keys; the app does not export them. Failed migration blocks dependent startup. Unpackaged Windows, other unprotected distributions and older versions retain their existing plaintext credential storage. This is not protection against an attacker controlling your signed-in account or the app process. Remembered website cookies and other database content are not covered by this encryption. File permissions and the macOS sandbox provide additional access restrictions where applicable. HTTPS uses transport encryption when the endpoint supports it; a custom HTTP endpoint does not provide that protection, even after you consent to sharing.

The Mac App Store build uses its application container and user-authorized external directories. Imported reference/drop media and queued-task snapshots may be copied into persistent private storage; generated results use the chosen output folder or a persistent application folder when necessary. Other builds use their platform-specific application data location; portable storage is available only on unpackaged Windows. Windows builds with package-local storage use the package family's LocalState/Joycai directory under the user's local application data, disable portable mode and offer explicit source-preserving import.

An exported settings backup redacts known API-key, cookie and secret-setting fields, but can still contain prompts, paths, usage records or secrets you placed in ordinary text fields. It is not a complete media backup. A direct database copy or installation migration can contain credentials. Migration preserves the source installation's data, including any older plaintext credentials. Copying encrypted databases is not a supported credential-transfer method. The Mac device-only Keychain key is not included in settings backups or synced by the app; Windows recovery depends on Windows user/profile protection. Use redacted settings exports and re-enter credentials when moving installations. Do not open encrypted databases with older app versions. On Windows, explicitly choosing credential reset first retains a sensitive recovery database snapshot, then clears channel keys, proxy password and MCP token and disables MCP; other records remain. This snapshot is not redacted and must be deleted separately when no longer needed. Copies you place in cloud-synced folders are also subject to that storage provider's practices.

### 5. Retention, deletion and your choices

- Local settings, histories and persistent media generally remain until you remove them. Clearing a task/history entry, removing a reference from the UI, or clearing temporary cache does **not** necessarily remove persistent media copies, exported files or backups. Uninstalling the app does not guarantee removal of external outputs or remaining application data.
- Remembered downloader cookies default to 30 days since last use. You can choose no storage, 7 days, 30 days, or retention until cleared. Expired entries are removed when cookie storage is accessed; turning storage off clears remembered entries.
- API debug logging is optional and off by default. Cleanup runs when new logs are created and the directory exceeds 50 entries; it removes older/excess entries. This is not a guaranteed seven-day deletion deadline. Disabling logging does not erase existing logs.
- Removing saved encrypted credentials deletes their active database values; the device-local wrapping key may remain in Keychain. This does not erase old database copies, filesystem snapshots or backups. Contact us before deleting a wrapping key, because remaining encrypted credentials would become unreadable.
- Remove saved credentials or change channel settings to stop using a provider, and stop pending tasks that could still send requests. Revoke exposed API keys at the provider. Disable MCP to stop accepting new client requests. These actions do not undo data already transmitted or processing already accepted by a provider.
- Remove directories from the relevant feature configuration to stop using them. The current macOS build retains security-scoped directory bookmarks and does not provide a dedicated bookmark-revocation control; removing a configured path is not the same as erasing its stored permission. Contact us for help resetting saved permissions. Copies already imported into the app remain until deleted.
- Use the available record/file deletion controls for data you no longer need. To remove remaining private copies or the entire local database, close the app and remove the corresponding application data only after preserving anything you want to keep. Separately remove output files, migration sources, exports and backups. Contact us if you need help identifying the appropriate files.
- We cannot remotely erase a database that exists only on your device or delete data held by an independent provider. For access/deletion requests concerning that provider, use its privacy contact. For information you sent to project support, contact us through the channel below.

Content-safety reporting opens an email addressed to joycai@joycai.cn, with no automatic prompt, image, log or credential attachment. If no mail handler opens, you can copy the address and contact us separately. Review anything you choose to include.

### 6. Changes and contact

We update this policy when data practices change and revise the date above. For privacy questions and requests, contact **Joycai** at [joycai@joycai.cn](mailto:joycai@joycai.cn). You may also use [the project’s issue tracker](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/issues) for non-sensitive questions. Issues are public; do not post API keys, cookies, private images, full databases or unreviewed logs. Send only the information needed for your request, including when contacting us by email.

## 简体中文

### 1. 适用范围与维护方

本政策适用于由 Joycai 维护的 Joycai Image AI Toolkits（下称“应用”或“我们”）。不同平台和分发渠道的功能及文件权限可能不同。本政策说明应用自身的行为，不代替您配置的独立服务或访问的网站的政策。

应用不要求注册 Joycai 账号。我们没有运营自动接收您提示词、素材、API 凭据或本地数据库的云服务。当前应用不包含广告、跨应用追踪或自动上传分析/崩溃报告的服务；本地用量与费用统计供您自己查看。这**不代表应用不联网**：AI 功能和下载会联系下文所述服务。

### 2. 使用哪些数据及用途

| 数据 | 用途与处理方式 |
| --- | --- |
| 提示词、对话、参考图、蒙版及功能支持的视频/音频输入 | 完成您发起的 AI 操作，相关内容会发送至配置的 AI 端点；响应、任务状态和历史可能保存在本地。 |
| 知识库文件与助手上下文 | 读取您配置的目录/文件，将相关内容用于助手请求；对话历史、笔记和工具结果也可能成为请求的一部分。 |
| 文件名、路径与媒体元数据 | 浏览、整理、导入、导出和重命名文件；AI 辅助操作可能发送相关名称、元数据或素材。普通本地浏览本身不会将整个目录上传给 AI 服务。 |
| API Key、端点地址、代理设置与凭据 | 向您配置的服务认证并路由请求；保存在本地，相应端点会收到其认证凭据。 |
| 任务记录、模型设置、用量与费用估算 | 执行队列、恢复工作、展示历史及本地统计；已排队任务恢复或重试时可能继续联网。 |
| 您提供的网站 URL 与 Cookie | 下载器据此获取网页/素材；Cookie 可能允许访问您的网站账号，用于相应网站操作，而非 Joycai 广告追踪。 |
| 本地诊断日志 | 排查故障；可选 API 调试会记录请求/响应内容、URL 和错误。已知凭据字段会遮蔽，大型载荷会截断，但日志仍可能包含个人或敏感信息。 |

### 3. 接收方与网络访问

**AI 服务。** 请求发送至所选通道/模型配置的端点，可能是原厂服务、中转服务或本地服务器。接收方可能收到提示词、相关对话/知识库上下文、附件、生成参数和认证信息。预设中的服务商名称不保证自定义端点属于该服务商。发送前请检查实际端点及其隐私条款。服务商和中转方的数据保留、模型训练、删除及跨境处理规则各不相同；我们不承诺其不保留内容或不将内容用于训练。

**AI 共享控制。** 在包含 AI 数据共享提示的版本中，应用会在首次连接 AI 接收方前请求明确许可。提示会展示实际接收方、数据类型与用途，并提供本政策入口。本地决定适用于后续请求，包括批量、重试、恢复任务及 MCP 发起的操作；配置的端点、服务类型、接收方或代理变化后需重新确认。可在 **设置 → 关于 → AI 数据共享** 撤回授权，或在拒绝后启用下次询问。撤回会阻止后续请求，但无法收回已发送的数据，也无法取消服务商已经受理的处理。决定保存在本机，不随设置备份导出，导入其他安装的数据时会清除。尚无这些控制的旧版本需停止任务并移除凭据以防止后续请求。

**下载与外链。** 网站、媒体托管方及配置的代理会收到获取内容所需的请求。可选字体下载会访问 jsDelivr；使用系统字体无需进行该下载。打开 GitHub、更新日志等外链会访问相应网站/浏览器。网络接收方可以获知您的 IP 地址和常规请求元数据；数据可能在您所在国家或地区以外处理。

**MCP 集成。** 启用后，本地 MCP 服务器在回环地址接受通过认证的客户端。客户端可在配置的访问范围内调用支持的工具、发起 AI 请求并接收结果。请将 MCP 令牌和授权客户端视为能够访问这些功能的主体。客户端可能依据自身政策继续处理收到的信息。

我们不出售您的个人数据，也不将您的内容用于我们自身的广告或模型训练。您主动提供给项目支持的信息由项目及反馈平台接收；请仅提供处理请求所需的信息。

### 4. 本地存储与安全

设置、凭据、对话和记录保存在本地。具备凭据保护功能的 Mac App Store 版使用 Apple 钥匙串保存的本机密钥，对 SQLite 中的通道 API Key、代理密码和 MCP Token 加密。旧明文值在加密及读回校验成功后迁移；迁移失败时保留原值。具备 Windows 凭据保护实现的打包版本（包括旁加载 MSIX）使用 Windows 用户级数据保护 API（DPAPI）加密同样三类字段。保护密钥由 Windows 管理，应用不导出；迁移失败会阻止依赖凭据的启动流程。未打包 Windows、其他未启用保护的发行版及旧版本保留原有明文凭据存储方式。这不能防御已控制当前登录账户或应用进程的攻击者。网站 Cookie 和其他数据库内容不在此加密范围内。适用时，文件权限和 macOS 沙盒提供额外访问限制。端点支持 HTTPS 时使用传输加密；自定义 HTTP 端点即使已获共享授权，也不提供这种保护。

Mac App Store 版使用应用容器和用户授权的外部目录。导入的参考图、拖入素材及排队任务快照可能复制到持久化私有目录；生成结果保存在所选输出目录，必要时使用持久化应用目录保底。其他版本使用相应平台的应用数据位置；便携存储仅适用于未打包 Windows。具备包内独立数据路径实现的 Windows 版本使用用户本地应用数据中所属包家族的 LocalState/Joycai 目录，禁用便携模式，并提供保留源数据的显式导入。

设置备份导出会清除已知 API Key、Cookie 和秘密设置字段，但仍可能包含提示词、路径、用量记录，或您写入普通文本字段的秘密；它不是完整的媒体备份。直接复制数据库或进行整库迁移可能包含凭据。迁移会保留源安装的数据，包括原有的明文凭据。复制加密数据库不是受支持的凭据迁移方式；Mac 仅限本机的钥匙串密钥不包含在设置备份中，应用也不会同步该密钥；Windows 恢复取决于 Windows 用户及配置文件保护机制。迁移安装时应使用脱敏设置导出并重新输入凭据，不要用旧版应用打开加密数据库。在 Windows 上明确选择重置凭据后，应用先保留含敏感信息的恢复数据库快照，再清除通道密钥、代理密码和 MCP Token，并关闭 MCP；其他记录保留。该快照未脱敏，不再需要时应单独删除。您将副本放入云同步目录时，也适用该存储服务商的处理规则。

### 5. 保留、删除与您的选择

- 本地设置、历史和持久化素材通常保留至您删除。清除任务/历史记录、从界面移除参考图或清理临时缓存，**不一定删除**持久化素材副本、导出文件或备份。卸载应用也不保证删除外部输出或剩余应用数据。
- 下载器记住的 Cookie 默认保留至最后使用后 30 天；可选择不保存、7 天、30 天或保留至手动清除。访问 Cookie 存储时清理过期条目；关闭保存会清除已记住的条目。
- API 调试日志为可选项，默认关闭。创建新日志且目录超过 50 个条目时触发清理，移除较旧或超量条目；这不是保证七天内删除的时限。关闭日志不会删除已有日志。
- 删除已保存的加密凭据会移除当前数据库中的值；本机包装密钥可能仍保留在钥匙串中。这不会清除旧数据库副本、文件系统快照或备份。删除包装密钥前请先联系我们确认，因为剩余加密凭据将无法读取。
- 可删除保存的凭据或修改通道配置以停止使用服务商，同时停止仍可能发送请求的待处理任务。泄露的 API Key 应在服务商处撤销。关闭 MCP 可停止接受新的客户端请求。这些操作不能撤回已经发送的数据或服务商已接受的处理任务。
- 可从相应功能配置中移除目录以停止使用。当前 macOS 版本会保留安全作用域目录书签，尚无专门的书签撤销入口；移除配置路径不等于清除已保存的权限。需要重置权限时请联系我们协助。已经导入应用的副本仍需另行删除。
- 使用已有的记录/文件删除功能清理不需要的数据。若需删除剩余私有副本或整个本地数据库，请先保留所需内容、退出应用，再删除对应应用数据。输出文件、迁移源、导出文件和备份需分别清理；不确定文件位置时可联系我们协助确认。
- 我们无法远程删除仅存于您设备上的数据库，也无法删除独立服务商持有的数据。有关该服务商的访问/删除请求请联系其隐私联系人；有关您提供给项目支持的信息，请通过下述渠道联系我们。

内容安全报告会打开收件人为 joycai@joycai.cn 的邮件，不自动附加提示词、图片、日志或凭据。无法打开邮件程序时可复制地址另行联系；请检查您主动附加的内容。

### 6. 更新与联系

数据处理方式变化时，我们会更新本政策及上方日期。隐私问题和相关请求请联系 **Joycai**：[joycai@joycai.cn](mailto:joycai@joycai.cn)。非敏感问题也可通过[项目问题反馈入口](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/issues)提交。该入口为公开页面，请勿提交 API Key、Cookie、私人图片、完整数据库或未经检查的日志。包括邮件联系在内，请仅提供处理请求所需的信息。
