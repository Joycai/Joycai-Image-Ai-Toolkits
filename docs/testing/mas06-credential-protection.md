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
macOS 重启或 TestFlight 升级实测。探针没有 Flutter 引擎，完整 App 的旧库迁移、MCP
请求及 Keychain 锁定/恢复组合仍需在独立签名 App 中补充验收。

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

## 未关闭的验收项

- 完整 Flutter 商店配置的隔离旧库迁移、保存、重启、MCP 和锁定恢复端到端验收。
- 最终分发安装/TestFlight、证书续期后的访问；包装密钥永久丢失后的明确凭据重录流程。
- 新增 CryptoKit 本地加密的出口合规复核。此前 ASC 构建和问卷属于旧代码，本轮未修改。
