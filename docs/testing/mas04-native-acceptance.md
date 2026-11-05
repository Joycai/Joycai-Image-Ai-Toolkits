# MAS-04 独立签名沙盒实机验收

日期：2026-11-05。基线：`8eda35a47d91f3d2c63ced54321758b8630183d6`（PR #399）。
环境：macOS 27.2（26B123）、arm64，Flutter Release，应用 4.31.6（build 0）。

## 隔离与签名

- 独立 Bundle ID：`cn.joycai.mas04acceptance.r20261105a`；安装副本为
  `build/mas04-acceptance-20261105/Joycai MAS04 Acceptance.app`。
- 使用 Apple Development 证书签名，Team ID `H9WK585493`，Hardened Runtime 开启；
  保留 Release App Sandbox 权限，应用与内嵌框架 deep/strict 签名验证通过。
  这是本地开发签名运行验收，不代表商店分发签名、描述文件或 TestFlight 安装验收。
- 使用同一系统账户下的独立应用容器，不是独立 macOS 用户。没有启动正式应用，
  没有读取、修改或迁移用户实际数据库、素材、密钥和设置。
- 终端直接读取测试容器 SQLite 被系统拒绝后，没有扩大系统隐私权限。
  使用 gitignored 测试入口：先断言 Bundle ID 与沙盒目录，再在空库中写入一个合成渠道、
  模型和假凭据，然后调用未修改的生产 `main()`。每秒将测试库授权/任务状态报告给本机服务。
  该入口没有替换授权 presenter、网络 gate、队列、MCP 或数据库实现，没有自动授权。
- 模拟 AI 仅监听 `127.0.0.1:63539`；独立 MCP 仅使用 `127.0.0.1:63540/mcp`。
  提示词以 MAS04 synthetic 开头，返回图片取自仓库图标，没有付费 AI 请求。
  诊断上报与 AI 请求分开计数，以下计数只统计模拟 AI 端点收到的请求。

## 实测结果

| 场景 | 观察与证据 |
|---|---|
| 首次 MCP 请求 | 本地显示实际接收方、数据类别、用途和撤回说明；未决定时 AI 请求数为 0。 |
| 授权未决时重启 | 第一任务 processing、第二任务 pending 时终止精确匹配的测试进程。重启后第一任务标记 interrupted，第二任务恢复并再次要求本地授权；请求数仍为 0。 |
| 拒绝 | 点击拒绝，恢复任务 failed，MCP 错误 consentRequired、retrySafe=false；设置显示已阻止，决定持久化 allowed=false，请求数为 0。 |
| 下次询问 | 设置可清除决定并显示尚无决定；后续请求再次出现授权弹窗。解锁后两轮补测弹窗均正常，等待/关闭零发送，允许后仅新增一条请求；早先异常见下文。 |
| 允许 | 在本地弹窗允许后，allowed=true 保存，任务完成；模拟服务仅收到 1 条 images/generations 请求。结果位于独立沙盒 media/results 持久目录。 |
| 允许后重启 | 新进程恢复授权，无需重复同意即可完成第二个任务；请求总数为 2，设置显示已允许。 |
| 撤回 | 设置点击撤回后显示已阻止；新 MCP 任务失败并返回 consentRequired、retrySafe=false；请求总数保持 2。 |
| 撤回后重启 | 再次新进程启动，新 MCP 任务仍失败并返回 consentRequired；请求总数保持 2。 |
| MCP 边界 | tools/list 只有模型、生成、查询、取消和图片读取工具，无远程授权工具；不携带认证的请求返回 HTTP 403。已有结果可查询且 available=true、PNG 1024×1024。 |

进程序列：11414 → 15269 → 15935 → 16566；解锁补测进程为 22381。

## 观察项与边界

- 一次“下次询问”后提交 `MAS04-allow`，未操作允许/拒绝便在下一次界面观察中看到
  已阻止，任务错误 consentRequired。再次清除并提交 `MAS04-allow-second` 后弹窗正常、
  明确点击允许后成功。尚不能确定第一次是弹窗关闭/自动化交互因素还是应用问题；
  不将该次异常作为通过证据。解锁后在同一签名副本补测两轮：
  `MAS04-retest-1` 弹窗持续等待、决定为空、请求总数保持 2；明确关闭后保存拒绝。
  `MAS04-retest-2` 再次正常弹窗，等待时总数仍为 2；明确允许后任务 completed，
  总数变为 3。最后重新撤回，界面显示已阻止。原现象未复现、原因未定，保留观察，
  不认定为已修复缺陷，也未发现越权发送。
- 未决 processing 任务重启后采用现有保守 interrupted 提示（可能已计费），虽然本次
  模拟服务证明尚未发送；pending 任务则恢复并重新询问。没有自动重发 interrupted 任务。
- 本轮只实测本机模拟图像协议和 MCP 入口；批量、视频、助手、不同厂商和地址变化
  的覆盖来自已有自动化测试，不声称全部完成原生实机验收。
- 测试入口是独立夹具构建；最终无夹具的商店产物仍应做安装及发布前复核。
  没有上传构建或提交审核。

## 本地证据

证据位于 gitignored `build/mas04-acceptance-20261105/`：
`signature.txt`、`build.log`、`instrumented-build.log`、`native_main.dart`、
`before-pending-restart.json`、`after-pending-restart.json`、`after-denial.json`、
`after-allow.json`、`after-allowed-restart.json`、`after-revoke.json`、
`after-revoked-restart.json`、`requests.jsonl`、`mcp-*.json`。
只包含合成测试数据，测试凭据不用于正式服务。本轮未修改生产代码。

标准入口已恢复为 `lib/main.dart`，无夹具的商店配置 Release 重新构建成功（81.2 MB）；
未运行该正式 Bundle ID 产物。独立测试副本在可访问系统证书信任链的环境中再次通过
`codesign --verify --deep --strict`。本轮只改验收文档，未重复运行源码测试门禁。

锁屏等待期间曾停止独立测试应用与本机模拟服务；解锁补测结束后再次停止，
保留独立测试容器及证据。新增证据：`retest-1-pending.json`、`retest-1-closed.json`、
`retest-2-pending.json`、`retest-2-allowed.json`、`retest-final-revoked.json` 与
`retest-consent.png`。两轮补测未修改或重新构建测试应用。
