# MAS-06 凭据保护验证

日期：2026-11-05。分支：`codex/mas06-keychain`，基线 `dea5e21`（MAS-05 已合并）。
实现约定见 [凭据保护](../architecture/credential-protection.md)。

## 自动化与界面

- `dart format lib test tool`：927 个 Dart 文件，最终无格式变化。
- `flutter analyze`：No issues found。
- `flutter test -x screenshots`：3511 通过、10 跳过。
- 新增 7 项隔离 SQLite 测试，覆盖三类旧明文迁移、幂等重开、迁移中断回滚与重试、
  API Key/MCP Token 轮换失败保留旧值、Keychain 缺失、备份脱敏与原值保留、旧备份导入
  加密、外来密文拒绝、渠道合并/删除/设置重置。初始化仅在无密文时允许创建包装密钥。
- 新增恢复页交互测试：重试期间不能重复执行，失败后可重试，不渲染错误详情。
- 32 张恢复页截图（390/834/1024/1440 × 明暗 × 四语言）无溢出；实际查看四宽度
  明暗代表图及英文/日文/繁体长文案。使用仓库现有主题、组件和字体夹具，未取得历史
  设计原稿；这是窄桌面布局检查，不声称原生手机验收。

测试只使用内存数据库、合成凭据或明确隔离的测试容器；没有读取实际数据库或运行正式 App。

## 原生签名探针

`tool/macos/credential_protection_probe.swift` 与生产
`macos/Runner/CredentialProtection.swift` 一同编译。通过 `canImport(FlutterMacOS)`
只省略 Flutter 通道注册，CryptoKit 和 SecItem 实现没有替换为 mock。

- 独立 Bundle ID：`cn.joycai.mas06.acceptance.20261105`。
- Apple Development 签名，Team `H9WK585493`，App Sandbox 与 Hardened Runtime 开启。
- application-identifier 和唯一 Keychain 访问组都为该团队前缀加独立 Bundle ID。
- 容器路径由原生 API 获取并断言包含测试 Bundle ID，合成密文文件仅写入该容器。
- 验收后精确删除测试 service/account 的包装密钥；确认没有重新生成。

| 实测场景 | 结果 |
|---|---|
| 首次初始化、加密、解密 | 通过；同一合成值两次加密得到不同密文。 |
| 新进程读取 | 通过；读取上一个进程留下的密文。 |
| 密文最后一字节被篡改 | 解密失败，通过。 |
| CFBundleVersion 从 1 改成 2，保持团队、Bundle ID、访问组并重新签名 | strict 签名有效，新进程可读原密文，通过。 |
| 删除测试 Keychain 项后解密 | 失败，通过；不自动重建。 |
| 删除测试 Keychain 项后尝试加密保存 | 失败，通过；再次 SecItem 查询仍为 item-not-found。 |

这里的升级验证是同证书、同身份的本地开发签名版本更新；不是证书续期、团队转移、
macOS 重启或 TestFlight 升级实测。探针没有 Flutter 引擎；完整应用的补验结果见下节。

初次只有证书、没有匹配的描述文件时，macOS 拒绝启动探针（No matching profile found）。
命令行自动配置曾返回 No Accounts；用户确认登录并注册本机后，通过 Xcode 界面构建
独立探针成功，生成开发描述文件。没有放宽系统安全策略或改用 legacy Keychain 绕过。

本地证据位于 gitignored `build/mas06-native/`：`SignedProbe.app`、`acceptance.log`、
`Probe.xcodeproj` 与测试签名配置；不要提交证书、描述文件或应用包。

## 本地商店归档

本轮验证现有商店分发描述文件与新增 Keychain entitlement 的匹配，未上传、未提交审核。
命令行将 profile 指定到所有目标会令 Swift package 资源 bundle 报错，因此使用一次性
工程副本，仅在 Runner Release 配置选择 Apple Distribution 和现有商店描述文件；
插件目标保持原配置。传入 `MACOSX_DEPLOYMENT_TARGET=14.0`，归档位于
`build/mas06-distribution/Joycai.xcarchive`，使用后移除一次性工程。

最终 Archive 成功；Apple Distribution 签名的应用通过 deep/strict 验证，沙盒开启、
不含 `get-task-allow`。application-identifier 与唯一 Keychain 访问组均为
`H9WK585493.cn.joycai.joycaiImageAiToolkits`，与嵌入商店描述文件匹配。
校验结果保存于归档目录下的 `verification.json` 和 `signature.txt`。

版本仍是 4.31.6（build 0）；这不是可再次上传的递增构建号。本轮没有安装该归档。

## 完整应用实机补验（2026-11-05）

分支 `codex/mas06-native-acceptance`，基线 `e4ee519`（PR #402 已合并）。
使用完整 Flutter Release 应用、生产入口/状态/任务/MCP/SQLite/Keychain 路径，
Apple Development 签名，独立 Bundle ID `cn.joycai.mas06full.r20261105a`。
沙盒与 Hardened Runtime 开启，唯一 Keychain 访问组是团队前缀加该测试 ID；
嵌入开发描述文件匹配，deep/strict 签名验证通过。

夹具入口只在上述 Bundle ID 且容器路径含该 ID 时创建 v52 合成旧库，包含渠道 API Key、
代理密码与 MCP Token。测试图片为仓库图标，AI 服务仅监听 `127.0.0.1:63639`，
MCP 仅监听 `127.0.0.1:63640`。没有读取正式数据库、启动正式应用或调用付费 AI。
本次针对已进入沙盒的旧库做凭据迁移；站外目录授权和复制流程沿用 MAS-02 的证据。

测试专用 Swift 副本在隔离容器的拒绝标志存在时，为真实 SecItem 查询指定未授权访问组，
得到原生 `-34018`；删除标志后恢复原查询。生产 Swift 未加入故障开关。
这是**访问组拒绝/恢复**，不是模拟返回码，也不是 Keychain 锁定。
夹具只向本机诊断服务发出合成令牌、凭据匹配布尔值、原始字段哈希和任务状态；
它不进入正式构建。

| 场景 | 实测结果 |
|---|---|
| v52 旧明文库首次迁移遇到 SecItem 拒绝 | 显示凭据恢复页；三类原始字段哈希保持不变；MCP 未启动、无 AI 请求。schema 已升级至 53，凭据迁移可独立重试。 |
| 恢复 Keychain 访问并点击真实“重试” | 进入主界面；三类字段均变为加密封装，业务读接口与原测试值匹配，MCP 启动。 |
| JSON 备份 | 不含测试 API Key、代理密码、MCP Token 或密文封装。 |
| MCP 鉴权与生成 | 正确令牌通过鉴权，错误令牌 403；实际共享授权弹窗显示本机接收方，允许后生成完成，模拟服务验证解密后的 API Key 正确。 |
| 应用进程重启 | 三类密文字段哈希不变，凭据可读、MCP 自动恢复；已完成任务仍在，结果文件存在于测试容器持久目录，未重复发送生成请求。 |
| 成功轮换 MCP Token | 新令牌通过鉴权，旧令牌 403，数据库保存新密文。 |
| 运行中拒绝访问后保存代理密码 | 保存失败，原密文字段哈希不变；恢复后保存成功，重启仍可读取新值。 |
| 令牌轮换写入失败（修复后） | 原密文与内存连接配置均保持不变，MCP 停止并报告 settings；恢复访问、重新加载后原令牌正常鉴权。 |
| 运行中拒绝访问后 MCP 生成 | 使用有效测试令牌返回脱敏 operationFailed，不发出 AI 请求；恢复后同 requestId 可成功生成。 |
| 最终构建重启 | 轮换后令牌、三类密文及 3 个已完成任务保留；MCP get_generation 确认结果 available=true。模拟服务合计仅收到 3 次预期生成请求。 |
| 手动锁屏后解锁 | 用户确认完成锁屏/解锁；确认前 150 次连续采样进程 PID 一致，Keychain 状态均为 0、凭据值匹配、MCP 鉴权均通过，解锁后主界面正常。 |
| 已加密旧库在拒绝访问状态下重启 | 显示恢复页，密文及任务保留、MCP 未启动；恢复访问并点击“重试”重新进入应用。 |

HTTP 400 在本验收中指已通过 bearer 鉴权、无 MCP session 的 GET 被 SDK 拒绝；
生成能力另通过完整 MCP initialize/tools/call 流程验证，未把 HTTP 400 当作工具调用成功。

正常锁屏保持可用符合 `AfterFirstUnlockThisDeviceOnly`：首次解锁后可访问直到设备重启，
适合后台任务。[Apple 可访问性说明](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly)。
这与原生访问组拒绝测试分别记录，不把锁屏误写为 `errSecInteractionNotAllowed` 实测。
未锁定用户登录钥匙串；该文件钥匙串与应用使用的 data-protection Keychain 不同。

### 实机发现并修复

1. `PRAGMA secure_delete = ON` 返回结果行，Darwin/FMDB 的 `executeUpdate` 抛出
   “not an error”，导致完整应用启动黑屏。改用 `rawQuery`。新增回归适配器刻画
   Darwin 对结果行的约束；修复前测试失败，修复后及原生迁移重试通过。
2. MCP 轮换写入被 Keychain 拒绝时，数据库旧令牌不变，但原实现提前替换内存令牌，
   导致显示尚未保存的连接配置。改为保存成功后才替换内存；失败时保持旧配置、停止监听，
   添加保存失败及重新加载的回归测试。

修复后门禁：927 个 Dart 文件格式检查通过，analyze 为 No issues found，
完整非截图测试 3513 通过、10 跳过；两处新增回归均包含在内。
最终隔离签名构建成功、deep/strict 签名验证通过。

本地证据在 gitignored `build/mas06-full-20261105/`，含隔离夹具、签名验证、
迁移/重启状态快照、MCP 工具返回、合成请求日志和门禁输出。
证书、私钥、描述文件、应用包和测试诊断令牌不提交 Git。

## 未关闭的验收项

- 最终分发安装/TestFlight、证书续期后的访问；包装密钥永久丢失后的明确凭据重录流程。
- 新增 CryptoKit 本地加密的出口合规复核。此前 ASC 构建和问卷属于旧代码，本轮未修改。
- macOS 重启后首次解锁之前的 Keychain 不可用状态；本轮不重启用户电脑或锁定登录钥匙串。
