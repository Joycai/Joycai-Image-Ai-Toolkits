# MAS-07 · 本地商店分发验证

日期：2026-11-05（北京时间）。代码基线：PR #394，提交 `05c9e37`。
本次仅创建本地 Archive / pkg 并检查签名，没有上传到 App Store Connect，
没有安装或运行商店包，没有访问生产数据库或触发任务。

## 实际结果

| 项目 | 结果 |
|---|---|
| Bundle ID | `cn.joycai.joycaiImageAiToolkits` |
| Team ID | `H9WK585493` |
| 版本 / 构建号 | `4.31.6` / `0` |
| 架构 / 最低系统 | arm64、x86_64 / macOS 14.0 |
| 应用证书 | Apple Distribution: Cai Zhengxu (H9WK585493) |
| 安装包证书 | 3rd Party Mac Developer Installer: Cai Zhengxu (H9WK585493) |
| 描述文件 | Joycai Image AI Toolkits Store Distribution |
| 描述文件有效期 | 至 2027-11-05 09:47:47（北京时间） |
| Archive / Export | 均成功；导出方式 `app-store-connect`，目的地 `export` |
| 应用签名 | 从最终 pkg 解包后，`codesign --verify --deep --strict` 通过 |
| 安装包签名 | `pkgutil --check-signature` 返回上述安装包证书及 Apple 证书链 |
| 权限 | App Sandbox、持久目录书签开启，Hardened Runtime 开启，`get-task-allow` 不存在 |

通过 `security cms -D` 解码最终应用内的 `Contents/embedded.provisionprofile`。
核对其 TeamIdentifier、应用标识、有效期，以及 DeveloperCertificates 中的证书
与实际应用签名叶证书 SHA-1 完全匹配；描述文件没有 ProvisionedDevices 或
ProvisionsAllDevices。应用的 application-identifier 和 team-identifier 与 profile 一致。
沙盒文件权限不一定逐项出现在 profile 中，不以整份 entitlement 字典相等作为校验规则。

## 本地导出步骤

先准备 Flutter Release 配置，明确使用沙盒分发模式：

```sh
env -u XCODE_XCCONFIG_FILE flutter build macos --release \
  --dart-define=JOYCAI_DIRECT_DISTRIBUTION=false
```

项目自动签名用于 Archive；导出时再用商店分发证书重签：

```sh
env -u XCODE_XCCONFIG_FILE xcodebuild \
  -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/mas-distribution-20261105/Joycai.xcarchive \
  -allowProvisioningUpdates MACOSX_DEPLOYMENT_TARGET=14.0 archive

env -u XCODE_XCCONFIG_FILE xcodebuild -exportArchive \
  -archivePath build/mas-distribution-20261105/Joycai.xcarchive \
  -exportPath build/mas-distribution-20261105/export \
  -exportOptionsPlist build/mas-distribution-20261105/ExportOptions.plist
```

首次 Archive 未指定部署版本时，生成的 FlutterGeneratedPluginSwiftPackage 声明
macOS 12.0，而 fc-native-video-thumbnail-product 要求 13.0，导致归档失败。
传入与当前 Runner 一致的 `MACOSX_DEPLOYMENT_TARGET=14.0` 后成功；没有修改生成包。
后续独立商店流水线应保留这一设置并重新验证，不修改站外发布工作流。

本机安装描述文件到 Xcode 的 `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`。
本次 ExportOptions 设置如下，具体证书指纹与 profile UUID 在本机填入：

| Key | Value |
|---|---|
| method | `app-store-connect` |
| destination | `export`（不是 upload） |
| signingStyle | `manual` |
| teamID | `H9WK585493` |
| signingCertificate | 所选 Apple Distribution 证书的 SHA-1 |
| installerSigningCertificate | `3rd Party Mac Developer Installer: Cai Zhengxu (H9WK585493)` |
| provisioningProfiles | Bundle ID → 对应商店 profile UUID |
| manageAppVersionAndBuildNumber | `false` |
| uploadSymbols | `false` |

导出后用 `pkgutil --expand-full` 解包到独立构建目录进行检查，不安装包。
本地证据位于 `build/mas-distribution-20261105/`：`Joycai.xcarchive`、
`export/Joycai Image AI Toolkits.pkg`、`ExportOptions.plist`、`verification.json`。
这些生成物、证书、私钥及描述文件均不提交到 Git。

## 2026-11-05 · App Store Connect Validate 复验

首次在 Xcode Organizer 使用独立 **Validate App → Custom** 流程时，验证报告
归档缺少有效的 `LSApplicationCategoryType`。工程虽已设置
`INFOPLIST_KEY_LSApplicationCategoryType=public.app-category.photography`，但使用
显式 `Runner/Info.plist` 的实际产物没有该键。修复是在 `macos/Runner/Info.plist`
直接加入 `LSApplicationCategoryType=public.app-category.photography`。

重新 Archive 至 `build/mas-category-fix-20261105/Joycai.xcarchive`，确认归档内
Info.plist 已含摄影分类，然后再次使用独立 Validate App 流程。手动选择 Apple
Distribution 和现有商店描述文件；关闭 Upload symbols 和 Manage version and
build number，保留 `4.31.6 (0)`。Xcode 最终显示：

> App validation complete: Joycai Image AI Toolkits 4.31.6 (0) validated.
> Your app successfully passed all validation checks.

本轮 Validate 通过，没有执行 Distribute App / Upload、TestFlight 分发或提交审核。
命令行 `method=validation,destination=export` 被 Xcode 拒绝（要求 upload 目标），
因此实际复验通过 Organizer 独立 Validate 入口完成，不把该命令行失败当作应用错误。

修复后门禁：format 910 文件无变化；analyze 无问题；非截图测试 3476 通过、10 跳过；
plist lint、diff 检查通过，Archive 成功。未启动应用或触碰用户数据库。

## 2026-11-05 · 上传处理与出口合规声明

用户授权上传后，通过 Xcode 上传已通过 Validate 的 `4.31.6 (0)`。
App Store Connect 的构建上传状态为「完成」，元数据的二进制文件状态为「已验证」。
应用 ID 为 `6830950645`，构建 ID 为 `54beccc1-8dc0-40f1-accb-b129f2946975`。
最初状态「缺少出口合规证明」，补充下述问卷后变为「准备提交」（90 天后过期）。
没有提交 App Review / TestFlight 审核，没有创建测试群组或添加测试员。

### 加密使用检查与填写依据

- `LLMModelConfig.buildClient` 使用 `package:http` 的 IOClient / Dart HttpClient；
  媒体下载、抓取也使用 HttpClient。HTTPS 提供标准 TLS 传输加密。
- 本机 Dart SDK 的 `secure_socket_patch.dart` 明确使用 BoringSSL；因此不能把
  Dart HTTPS 描述为「仅使用 Apple 操作系统内置加密」。
- `package:crypto` 的 SHA-256 用于媒体去重、迁移完整性、任务参数摘要及用量幂等；
  MD5 用于缩略图缓存键。它们不是文件内容加密功能。
- MCP 使用 `Random.secure` 生成 bearer token，监听 127.0.0.1 并比较认证值；
  没有自定义加密隧道。当前业务没有接入 SDK 自带的 OAuth 客户端功能。
- API 返回的 `encrypted_content` 是服务商生成并由应用保留/回传的数据，不是
  应用实现的自有加密算法。源码及依赖检查未发现应用提供自定义密码算法、VPN、
  端到端消息加密、加密数据库或加密文件导出功能。

App Store Connect 当前构建问卷按事实选择「代替在 Apple 操作系统中使用或访问加密，
或与这些操作同时使用的标准加密算法」。下一题「是否在法国分发」由用户明确选择
**暂不在法国分发**，随后保存，后台不再要求出口合规信息。

此答案不自动修改商店销售地区：正式发布前必须核对销售范围不包含法国；如以后
计划法国分发、增加加密功能或更换网络实现，应重新检查声明和文稿要求。
本轮不修改 `ITSAppUsesNonExemptEncryption`，避免把地域条件或第三方 TLS 实现
简单归为「完全不使用加密」。声明成功不等于所有地区均已取得合规许可。

依据：[Apple 加密文稿要求](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)、
[Apple 构建问卷流程](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation/)。

## 尚未完成

上传处理和当前出口合规问卷已完成；尚未进行 TestFlight 安装验收或提交审核。
正式发布前仍需核对销售地区、商店版本记录和其他 MAS 台账项目。
MAS-07 保持未整体勾选，不能将当前构建的「准备提交」状态当作审核通过。
