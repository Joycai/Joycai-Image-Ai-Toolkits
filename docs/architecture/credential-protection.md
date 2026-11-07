# Credential protection · MAS-06 / WIN-03

## 范围与存储约定

macOS 商店配置（`Platform.isMacOS && !AppDistribution.direct`）在任何实时数据库访问前
配置 `MacCredentialProtection`。保护渠道 API Key、代理密码和 MCP Token。
未打包的 Windows 站外配置及其他平台保留原有存储方式；打包 Windows 使用下文 DPAPI。
文件权限和 JSON 导出脱敏仍适用于所有配置。
这不是整库加密：提示词、素材路径、下载 Cookie 等不在本次加密范围内。

采用 Apple CryptoKit AES-256-GCM（随机 nonce、认证标签）。SQLite 的原有字段保存
`joycai-secret:v1:<base64 combined box>`，业务模型和网络调用仍接收明文。
包装密钥只存于 data-protection Keychain 的 generic-password 项：

- service：`<Bundle ID>.credentials`；account：`wrapping-key-v1`。
- 不启用 iCloud 同步，使用 `AfterFirstUnlockThisDeviceOnly`，适配后台任务。
  首次解锁后到设备重启前保持可用，普通锁屏不应被当作 Keychain 不可访问。
  data-protection Keychain 与登录文件钥匙串不同，不能用锁定后者冒充此项验收。
- 每次从 Keychain 读取，不在 Dart 或磁盘保存包装密钥副本。
- 使用应用默认访问组；商店 Debug/Profile/Release 声明
  `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)`。站外 entitlement 不增加此组。
- 更新必须保持 Team/App Identifier Prefix、Bundle ID、默认访问组和 service/account 稳定。
  **只有证书存在不足以保证可用**：本地开发签名也需要授权该组的开发描述文件。

使用包装密钥而不是给每一行一个 Keychain 引用，是为了让渠道合并、全库恢复、轮换、
删除仍具有 SQLite 事务的回滚语义，不产生需要跨系统事务补偿的逐凭据 Keychain 孤儿。
删除渠道或重置设置会删除凭据密文，保留包装密钥；不是安全擦除整个设备或历史备份。

## 迁移、恢复与失败

MAS-06 将数据库版本提升到 53，WIN-03 进一步提升到 54，列定义不变。当前版本显式拒绝
降级；旧版若没有降级处理器，不能仅依赖版本号阻止误读密文，禁止将加密数据库交给旧版。
升级和新建都在 `DatabaseService` 发布连接之前完成凭据迁移/校验；
`onUpgrade` / `onCreate` 不在 schema 回调里触发平台通道。

迁移使用 `rawQuery` 开启 SQLite `secure_delete`（该 PRAGMA 返回结果行，Darwin 的
`executeUpdate` 会拒绝），在一个事务内封装旧明文并逐值读回核对；全部成功
才提交。失败回滚原始行、关闭连接、清除打开中的 Future，允许重试。提交后执行 WAL
checkpoint/truncate，减少 SQLite 中的旧值残留；不承诺清除 APFS 快照、SSD 残留或
用户原先的站外数据副本。站外整库迁入沙盒后，在首次打开目标库时走同一迁移。

已有密文每次启动都验证；缺失/不可访问的 Keychain 项或认证标签错误不会触发清空、
明文降级或把密文当成密码。仅在启动检查确认数据库没有密文时允许初始化包装密钥；普通加密与解密操作均不会新建包装密钥。启动失败时显示四语言恢复页，
支持重试；恢复前不启动 AppState、任务队列或 MCP。运行中保存失败保留数据库原值。

渠道新增、编辑、合并，以及代理密码/MCP Token 保存均经过保护层。业务读接口解密。
轮换写入新的随机密文，数据库提交失败时旧值保留。MCP 先停止监听，保存成功后才
替换内存令牌；保存失败保持旧连接配置并停止服务，恢复访问后重新加载或轮换。包装密钥不会随单个凭据轮换。

JSON 导出仍将凭据留空，不导出包装密钥或密文。恢复脱敏备份保留本机原有密文；旧备份
中的非空明文 API Key/代理密码先加密再入库；拒绝把外来密文当作可移植凭据导入。
MCP Token、授权和开关仍不从外部备份导入。跨设备应使用脱敏 JSON 并重新输入凭据，
不能只复制加密 SQLite。`ThisDeviceOnly` 不是跨设备凭据恢复机制。

如果包装密钥确实已丢失，已有密文不能恢复。本轮不提供自动清库或销毁密钥的恢复按钮，
需要先保留数据库并单独设计明确的凭据重录流程；不能把不可逆丢失伪装成“尚未配置”。

## 安全与验收边界

异常信息只包含固定诊断文本，不携带凭据、密文或系统返回详情。既有 LLM 请求日志脱敏
继续生效。凭据使用时仍存在应用内存中，本方案不抵御已控制当前用户或应用进程的攻击者。

新增 CryptoKit 本地加密需要在下次上传前复核出口合规问卷；先前上传构建的结论不能直接
套用到本次代码。本轮不更改 App Store Connect、不上传、不提交审核。

验证记录见 [MAS-06 验证](../testing/mas06-credential-protection.md)。
Apple 接口依据：[数据保护 Keychain](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain)、
[默认访问组](https://developer.apple.com/documentation/security/ksecattraccessgroup)、
[CryptoKit AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)。

## WIN-03 · Windows packaged credential protection

Runtime package identity enables `WindowsCredentialProtection` before database,
AppState, tasks or MCP startup, including sideloaded direct MSIX. Unpackaged Windows
keeps its prior plaintext/portable behavior. Unknown identity cannot select direct
storage or plaintext fallback. Mac CryptoKit/Keychain envelopes and signing are unchanged.

The Windows envelope is `joycai-secret:win-dpapi:v1:<base64 DPAPI blob>`. Native
`CryptProtectData` / `CryptUnprotectData` use user scope, `CRYPTPROTECT_UI_FORBIDDEN`
and a fixed application/version entropy string for domain separation. No
`CRYPTPROTECT_LOCAL_MACHINE`, application wrapping-key file, certificate or UI prompt
is used. DPAPI owns its master keys; `prepare` verifies a synthetic round trip, and
bootstrap validates every stored envelope. The native adapter returns generic errors.
See [CryptProtectData](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata).

Schema **54** records the Windows envelope format; this build explicitly rejects
database downgrades. The installed sqflite adapter silently downgrades without a
handler, so an older build cannot be assumed to enforce the version stamp. Never
open an encrypted database in an older application; package-local isolation and
source-preserving import keep the existing direct installation's database untouched.
No SQL columns change; both create and upgrade use the existing post-open migration.
The transaction verifies ciphertext round trips and reads stored rows back from SQLite
before committing. All `joycai-secret:` values, including unknown versions and other
platforms, are treated as encrypted: an unsupported protector, direct reader or foreign
backup import rejects them. Normal JSON backup stays redacted. Copying encrypted SQLite
is not a supported credential transfer mechanism. User profile/domain DPAPI recovery
rules can vary; this is not a promise that every cross-device copy is undecryptable.

Windows failure recovery preserves Retry and adds an explicitly confirmed reset of
channel keys, proxy password and MCP token. Before resetting, verify DPAPI availability,
save a WAL-aware `VACUUM INTO` snapshot under `credential-recovery/before-reset-*`, and
check its SQLite integrity. Then clear only those credential fields transactionally
and disable MCP. Snapshot failure leaves original credentials unchanged. Other data
remains; users re-enter credentials in Settings. The retained snapshot may contain
sensitive data and is not an export for sharing. Mac recovery continues to offer Retry
without this Windows reset action.

Audit boundary: downloader cookies remain plaintext in `downloader_cookies`, governed
by the existing retention/off controls; they are not protected by this adapter. Debug
logs mask named keys, authorization headers and credential URL parameters, but logs
can still contain user prompts and media metadata. Native errors and recovery errors
never include ciphertext, keys or OS error details. This is not whole-database encryption
or protection against another process already controlling the same Windows account.
Cookie disclosure/retention and public privacy wording must be reviewed in WIN-05.

Automated/native and installed-package limits are recorded in
[Windows validation](../testing/windows-store-storage-security.md).
