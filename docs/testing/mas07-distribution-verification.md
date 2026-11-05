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

## 尚未完成

本地签名和本轮 Validate 通过不等于上传处理或审核通过。尚未上传、创建
TestFlight 构建或验证商店安装后的运行行为。当前 build 0 原样保留，正式上传前
需核对构建号及商店记录；隐私清单和其他 MAS 台账项仍独立待办。
MAS-07 因上传处理和 TestFlight 验收未完成而保持未勾选。

参考：[Apple 描述文件说明](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)、
[App Store 描述文件创建](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)。
