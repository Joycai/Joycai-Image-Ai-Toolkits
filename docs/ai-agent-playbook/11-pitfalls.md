# 11 · 坑大全（现象 → 原因 → 对策）

全部来自 simple-ai-writer 的代码注释、设计文档与真实事故记录。按主题分组，组内大致按
危险程度排序——**静默失败在前**（不会报错、只能靠对照发现的最危险）。每条都可以当作
新项目的回归测试清单。

## A. 协议层 · 静默失败类

1. **Anthropic 不回传 thinking block → 思考静默消失。**
   现象：无任何报错，模型只是不再思考（唯一判据：响应里还有没有 thinking block）。
   原因：Anthropic 对不合法思考历史的反应是静默剥离而非 400（DeepSeek 相反：不回传就 400）。
   对策：工具轮 assistant 消息原样带回全部 thinking/redacted_thinking 块（含 signature，
   顺序不动）；`redacted_thinking` 只有不透明 data 也要回。

2. **Gemini 中继发 snake_case 图片字段 → 图片静默不可见。**
   原因：proto3 JSON 让官方 `inline_data`/`inlineData` 两种都收，中继只收文档写的那种，
   未识别键被忽略而非拒绝。
   对策（可移植规则）：面向兼容层时，在「官方两种都收」的地方**选中继文档写的那一种**。

3. **换模型不剥 thinking block → 静默计费。**
   别的模型不拒绝、静默忽略、照 input 计费。对策：回传载体带 `modelId`，不匹配整组丢弃。

4. **`display` 默认 omitted → 付了全额思考费拿不到一个字。**
   当前代 Claude 的 thinking 默认 `"omitted"`（省延迟不省钱）。对策：恒发
   `display:"summarized"`（schema 里没这个字段的方言除外——文档没写的不发）。

5. **静默截断 prompt（ollama 等本地栈）。**
   现象：200 + 看似正常的回复，system 指令悄悄没了。原因：超窗从头部丢弃。
   对策：发送前 `ContextSizeError` 估算拦截 + 探测 truncation check + 读实际生效的 `num_ctx`。

6. **HTTP 200 + 体内错误的两种拼法。**
   SSE 体内 `data:{"error":...}`；MiniMax `base_resp.status_code`。只认一种会把过期密钥
   读成正常空回复。对策：两条错误通道都解析；**「200 且没有任何内容」当可疑而非成功**。

7. **内容拦截在半截文本后到达。**
   Gemini blocked finishReason / Anthropic `refusal` / OpenAI `content_filter` 都可能在
   文本已开始流出后到。对策：一律 throw 而非当正常结束——已交付的文本需要作废。

8. **`stream_options.include_usage` 是兼容层最先没实现的东西。**
   现象：usage 全 0 不报错。对策：照发，但把 0 当「没报」处理；探测标 `no-usage-reported`。

9. **同一端点、两代模型，思考控制字段与默认值都不同（千问 DashScope）。**
   现象：默认关思考的商业款（qwen3-max 一类）永远不思考，无任何报错；或强度设置
   在老款上静默无效。原因：老款/商业款的开关是顶层 `enable_thinking`（SDK 文档写在
   `extra_body`，落 wire 即顶层字段），新款（3.7+）接受标准 `reasoning_effort` 且与
   `thinking_budget` 互斥；默认值按代分裂（3.5+ 默认开、商业款默认关）。
   对策：厂商开关做成作者声明的 `switch` 方言（① 族拼法 `enable_thinking`，见 03 篇），
   声明后停发 `reasoning_effort`，未声明的默认路径逐字节不变；另注意部分开源模型
   思考模式强制 `stream: true`。

10. **① 族兼容层的服务端搜索无痕——不生效完全无症状（千问 enable_search）。**
   现象：`enable_search: true` 发了，但无法从响应判断搜没搜——千问文档明载
   Chat Completions 模式**不返回搜索来源、不支持角标**，答案直接吸收检索结果。
   于是「字段没生效」和「搜了但没痕迹」在客户端完全同相。
   对策：执行日志对这条线诚实地**什么都不显示**（不要伪造事件）；验证只能靠
   时效性问题对比开关前后的答案；把「生效与否」列入实测清单而不是当作既成事实。

## B. 协议层 · 会响但难排查类

11. **MiniMax Anthropic 端点：turn 停在搜索结果上报 `end_turn`，且拒收自己发的块。**
   兼容层「响应侧抄全了、请求侧没抄」的典型。对策：以「结果之后模型说话了吗」为续跑
   判据；续跑退化为纯文本 transcript（见 05 篇）。

12. **tool_calls 流式拼接键用 id → 交错调用拼错。**
    id 自身也可能分片。对策：按 `index` 分组，id 累积拼接。

13. **强制 tool_choice 撞上思考模型/被砍档端点。**
    对策：结构化输出必有「强制失败→JSON mode」降级链，降级路径仍带原生 JSON 参数；
    回退判定正则要求「能力词 + not supported」**同现**——裸子串会把无关上游错误
    （"does not support streaming for this region"）也吞进回退，翻倍花钱且掩盖真错。
    砍档还有**动态**变体：千问文档明载思考开启时 `tool_choice` 只剩 `auto|none`，
    思考关着时 forced 合法——预判降级的触发条件要**跟着砍档条件走**：端点常态砍档
    （MiniMax `switch` 端点）就无条件降；随开关砍就按请求判定，精确到「本次真的
    发出 `enable_thinking: true`」（`off` 发 false、`default` 什么都不发且这类模型
    思考默认关，两者都留 forced 合法，见 04 篇 §4）。

14. **`json_object` 的 "json" 字面量前置条件。**
    prompt 里没有 "JSON" 字样会报错或产生无限空白流。对策：检测 prompt，缺则追加 cue；
    prompt 可编辑的系统不能把它当既成事实。

15. **兼容层把思维链塞进正文 `<think>…</think>`，标签跨 chunk 分片。**
    对策：状态机切分器——只认响应开头、`danglingPrefix` 扣住可能成为标签的尾巴、
    流结束未闭合按 reasoning flush；切出的思考只展示不回传。

16. **Anthropic base URL 约定与 OpenAI 生态相反。**
    OpenAI/Gemini 的 base 自带版本段，Anthropic 的 base 是根地址（客户端补 `/v1/messages`）。
    对策：不对称归一化；绝不给 OpenAI base「修复性」补 `/v1`（中继合法路由在 /v1 之下）。

17. **鉴权头两套一等约定（Anthropic 生态）。**
    `x-api-key` 与 `Authorization: Bearer` 各有网关只认一种。对策：compat 端点提供
    default/bearer/both 三模式；官方端点只给 default（api.anthropic.com 拒绝双凭证）。

18. **usage 口径：Anthropic 三桶要相加、Gemini 思考在 candidatesTokenCount 之外。**
    直接读 `input_tokens` 会少报一个数量级；只读 candidates 会漏掉最贵的思考。
    对策：归一化为 input/output/cached（cached 是 input 子集）三字段再入库。

## C. Runtime 与工具系统

19. **中断把会话永久搞坏。**
    现象：停止任务后每个 provider 拒绝后续请求，只能新建对话。
    原因：assistant 的 tool_calls 已入历史，k<N 的 tool 回复=永久畸形转录。
    对策：abort 中途逐个补 `[not run]` 桩、配平后才抛 AbortError；外加
    `repairToolCallPairing` 在每次追加历史前兜底。

20. **助手「只给方案不动手」。**
    原因 A：agent 指令拼在首轮 user 层，活不过第一轮——必须并入 **system 层**。
    原因 B：所需工具根本不存在，或轮数中途用尽。对策：补齐工具、放宽 maxRounds、
    上限时用卡片问作者（extend/finish/pause）而非硬停。

21. **一次性提示变常驻指令。**
    「本轮别再调工具」「快用 write_note 落盘」等提示留在持久 history 里成永久禁令/命令。
    对策：**发出即撤**——请求发出后 finally 里 splice 掉。同类事故：作者中断后敲的
    "continue" 混进 tool_result 信封被跨 39 轮反复重发（对策：合并时给作者文本打标签）。

22. **工具轮叙述混进正文。**
    「我先去找文件列表。」被插进用户文档。对策：onOutputText 用**快照**语义，工具轮
    结束整段回滚，只累计以散文收束的轮。

23. **base64 图片挤爆请求体而 token 估算无感。**
    估算按计费口径记平价，payload 却是 MB 级且跨轮存续。对策：trimHistory 图片优先、
    无条件、上限 N 张；会话序列化时全部剥离图片。

24. **plan 门控越权洞：file-scoped 步骤放行了无 file 的调用。**
    「delete Ava / armor.md」（删一个文件）授权了删整个实体。对策：步骤声明了 file，
    调用就必须给出同一个 file。

25. **审批 apply 不重定位 → 改写作者从未批准的文字。**
    卡片挂着时作者可能一直在打字。对策：apply 时重新 `find` 定位——消失或出现多于
    一处都以拒绝回模型；apply 抛错一律 resolve 成拒绝，绝不吞错报成功。

26. **悬挂的审批 Promise 永久卡死后续运行。**
    对策：每次运行 finally 必 `rejectAll(runId)`；runId=本次运行的 AbortController 对象，
    保证并行运行互不误杀。

27. **备份失败照写 → 不可恢复的破坏。**
    对策：「备份失败=写入失败」（backup throw 即写入不发生）；二进制/整目录删除用
    rename-into-backups 而非 unlink。

28. **空 projectPath = 全盘可读。**
    路径包含校验是前缀测试，空前缀包含一切绝对路径。对策：显式拒绝空 projectPath；
    一切模型可控路径参数过 `isPathWithin` 式校验。

29. **模型给的正则会卡死 UI 线程。**
    搜索工具只做字面匹配、明确拒绝正则（病态 pattern 无法中断）。

30. **模块级常量冻结运行时配置。**
    注册表 import 时求值一次，动态 enum（如分类表）必须在下发时**拷贝后**注入，
    不能 mutate 共享常量。

31. **运行快照与磁盘漂移。**
    move/delete 后同一运行的下一个调用解析到不存在的目录。对策：写工具落盘后手工回填
    快照；细粒度工具从磁盘读当前状态而非快照。

32. **一次读取附带全部图片 → 35MB 请求超时。**
    对策：读实体只回文件名+文字描述，真要看再按名取一张；单图字节上限。

## D. 子代理与上下文管理

33. **搜索子代理永远不联网。**
    原因：`withholdTools` 把「没有本地工具」和「该收尾了」并成一个判断，而 search
    子代理本地工具恒为空。对策：`serverTools: "final-round-off"|"off"|"always"` 独立
    策略字段，search 用 always。

34. **子代理产出取到空。**
    runtime 成文轮直接 return，最终文本从不进 history——事后翻 messages 必空。
    对策：产出只能经 `onOutputText` 回调捕获（快照赋值）。

35. **委托产出整块回填 = 把堆叠换个地方堆。**
    对策：落盘 note，tool result 只回「路径 + ≤800 字符摘要」，细节走 read_note 分页。

36. **整文件载荷把「图片够用」的代码放大成分钟级卡顿。**
    现象：给模型附整份 PDF（① 族 file 内容块）时 UI 卡死数分钟。
    原因：图片路径常见的 `binary += String.fromCharCode(...)` 累加式 base64 是
    **二次方**的——12MB 图片帽下看不出来，150MB 文件（DashScope 的单文件上限）
    直接爆炸。同理适用于一切「借用图片管线处理大文件」的地方。
    对策：分块 `fromCharCode` push 进数组、末尾一次 `join` 再 `btoa`（线性）；
    载荷类 ref 在委托执行器里**就地读取并做包含校验**（`.ai-writer`/项目外拒绝——
    文件是模型当文本读的文档，read_file 挡外泄的论证原样适用），并保留端点自己的
    尺寸/份数上限作为拒绝阈值而不是静默截断。

37. **「启用」当「可用」用，双输。**
    search 绑了不能上网的模型时，路由照样关掉主模型联网——作者失去主模型联网又什么都
    没换回来。对策：单一判断函数（开关+绑定+模型存在+能力前置条件），所有调用点共用；
    设置面板警告但不阻止，下游必须再验。

38. **子代理 AbortError 转成 tool error → 作者的「停止」被读成「搜索失败」而重试。**
    对策：AbortError 是唯一重抛的异常，其余转模型可读的错误文本。

39. **密钥缺失降级空串 → 要逆向工程的 401。**
    对策：解析层直接返回指路的配置错误（"去 Settings → Providers 粘 key"），绝不发无钥请求。

40. **`Boolean(handle)` 恒真的假守卫。**
    routeTools 收 `hasWorkspace: boolean` 而调用方总是无条件构造 handle。
    对策：守卫参数要传**能真正为空的东西**（handle 本身，undefined 才是没有）。

41. **嵌套日志顶掉主日志行。**
    子跑 round 也从 1 开始，去重键只有 round/toolCallId 会互相覆盖。
    对策：事件去重键带 `parentStep`。

42. **ASCII slug 白名单让中文笔记全坍缩进 `note.md` 互相覆盖。**
    对策：Unicode 属性类 `\p{L}\p{N}` 清洗、按码点截断、绝不静默覆盖（撞名加后缀并告知）。

43. **task_progress 悄悄创建无名工作区。**
    它的 ensure() 既建了任务又满足了「要求先有计划」的检查。对策：只有 task_plan
    （真标题）与 write_note（中性标题）能建仓。

44. **步骤数据双事实源打架。**
    JSON 和正文各存一份步骤，作者手改后不一致。对策：步骤只存在于正文复选框，
    1 基序号寻址；JSON 注释头只放机器状态。

45. **task.md 小节按标题文本定位 → 换语言后写错位置。**
    对策：语言无关 HTML 注释锚点（`<!-- task-steps -->`）。

46. **同轮并发写丢更新。**
    模型一轮可发多个 tool call。对策：工作区写入过模块级 Promise 链串行化，
    且链放在 workspace 层（写者不止工具，暂停/恢复也在写）。

47. **恢复对话而非恢复任务。**
    旧 history 里的 "continue" 被当新指令自我强化。对策：resume 种子 = task.md +
    notes 索引 + sourceRefs 过期清单，**不重放旧 wire history**。

48. **压缩把网络抖动变成坏会话。**
    摘要失败后仍折叠。对策：失败返回 null、history 一字不动、只在成功后换入新数组。

49. **压缩杀死 prompt cache。**
    触发线与目标线太近导致每轮都压，每压一次前缀作废。对策：0.7 触发 / 0.45 目标的
    宽间隙；summary 消息紧贴 system 之后，稳定前缀最大化。

50. **轮边界按索引记录 → repair/trim 后错位。**
    对策：一切 meta 按**消息对象身份**记录；序列化时身份→索引，反序列化重连，
    解析不到的引用丢弃而非猜测。

51. **旧格式事件打崩整个 UI。**
    会话 blob 比写它的代码活得久，事件载荷实际是 wire format。对策：迁移函数，
    认不出的条目丢弃（丢一行日志值得，丢一个会话不值得）。

52. **GC 豁免未完成任务 ⇒ 无界增长。**
    对策：「未收尾优先保留但不豁免」的排序 GC；绝不删当前运行持有的任务。

53. **恢复失败留下「在跑」的僵尸任务。**
    对策：乐观置回 in_progress 后，若启动失败再置回 paused——不留一个声称在跑的任务。

## E. 文档与调研方法

54. **指南页 ≠ 参考页。** 判断能力边界看 API 参考页；大文档抓原文自己搜（网页摘要工具
    连续漏掉 295KB 参考页里的关键定义，curl+grep 一次找到）。
55. **兼容层文档四条规律**：结构照抄；扩展在响应侧；枚举是子集；最需要确认的部分
    （流式格式、错误通道、回传规则）不写且滞后上游一年。推论：兼容层文档不能当能力
    清单——「没列」按「未知、需实测」处理。

## F. 图像生成（详见 13 篇）

56. **短时效签名 URL 直接入库 → 图库静默腐烂。**
    现象：生成当时一切正常，几小时后图全部 404（DashScope 明文 24 小时过期，
    多数中继更短）。对策：拿到 URL 当场下载内联成字节；已计费的图值得一次重试；
    下载校验 content-type（200 + HTML 错误页会写出打不开的 `.png` 而 UI 报成功）。
57. **「Unsupported parameter …」prose 命中降级正则 → 二次计费重生成。**
    编辑降级（重试为纯生成）是另一次全价调用，宽松方向的误判直接翻倍账单。
    对策：结构化 code/param 优先——`param` 存在即「请求被理解了」，不是路由缺失；
    只有指名模型的（`param:"model"`、model_not_found 类 code）才降级；模型自己
    回的文字（NoImageError）永远不算证据。
58. **DashScope 错误在顶层 `{code,message}` 而非 `{error:{…}}` → 结构化信息丢失。**
    后果：`DataInspectionFailed`（内容审核拒绝）丢掉 code 后掉进 prose 正则，
    可能被误读成「端点不能编辑」。对策：错误 body 解析兼容两种形状；任务失败时
    code/message 嵌在 `output` 里，抛错时把 `output` 整段作为错误 body。
59. **尺寸分隔符方言：DashScope 写 `宽*高`，通用代码 `split("x")` 静默解析失败。**
    现象：按宽高比挑尺寸永远落回 sizes[0]，无任何报错。对策：解析分隔符放宽
    `/[x*×]/`；发出前按端点拼写归一（`1024x1024` → `1024*1024`）。
60. **异步出图任务挂死后无从排查；「停止」按钮要等下一次轮询才生效。**
    对策：task_id 提交成功后立刻写 API 日志（mid-call note，等成功日志就永远
    拿不到了）；一个总 deadline 罩住提交+轮询+下载全程，与用户 signal 合成后
    喂给每次 fetch **和轮询间的 sleep**——sleep 本身可被 abort 打断。

## G. ② Responses 族与中转站（详见 02 §7、06 §4）

61. **中转站静默改写 effort / temperature。**
    现象：200、输出正常，但发 `max` 回显 `none` 且 0 推理 token；发 `none` 回显 `medium`；
    `temperature:0.5` 回显 `1.0`。原因：中转站/档位/后端替你改了参数，客户端分不清是谁。
    对策：终止响应回显比对，不一致记 `wireRewrites` 进 API 日志与执行日志；只报告不重试；回显缺失不报。
62. **不发 system 就被注入几千 token 的系统提示。**
    现象：输入 token 莫名 4.4K–9K，输出不受影响。原因：New API 中转站在 `instructions`（Chat 面是 system 消息）
    缺失时注入 Codex 系统提示。对策：永远显式发 system；② 族 `instructions` 恒发，哪怕空串。
63. **`text.format` 显式 `strict:true` → 中转站整个丢掉 format。**
    现象：回显 `{type:"text"}`，输出不按 schema，无报错。对策：json_schema 不发 `strict` 键
    （官方省略即自动 strict），schema 仍 strictify。
64. **② 族工具定义省略 `strict` → 端点自动 strict，非 strict schema 被改写契约。**
    现象：带可选字段/未声明 `additionalProperties` 的工具开始 400 或参数被强制全填。
    对策：工具定义显式 `strict:false`（与 63 方向相反，同一个自动 strict 事实）。
65. **`max_output_tokens` 被无视 → 截断永远不会报。**
    现象：设了上限照样写完、`status: completed`，`incomplete` 从不出现。对策：不依赖端点执行输出上限；
    截断相关逻辑（如 JSON 解析失败的归因）不能假设"没报截断 = 没超长"。
66. **Grok 4.5 / 4.6 拒 effort `none`——「关闭」芯片必 400。**
    原因：这两款关不掉思考；全系还拒 `max`。对策：菜单不按型号裁剪、让端点 400 说话，但 UI 提示写明；
    实测套件按型号选"最便宜可接受的档位"，别让一个已知 400 拖红无关用例。
67. **xAI 拒总像素 < 512 的图片（测试夹具太小）。**
    现象：16×16 夹具 400 `below the minimum of 512 pixels`，看起来像图片输入不支持。对策：夹具至少 32×32。
68. **原生 tool search 的回传条目没带回 → 加载过的工具下一轮静默消失。**
    原因：OpenAI 要求下一轮 `input` 带 `tool_search_output`（及 `additional_tools`），只回传
    reasoning / function_call / message 的实现会丢掉它们，且回传缺失无报错。对策：采用原生机制前先扩充回传名单。
69. **Gemini 请求带 `defer_loading` 字段 → 整个请求被拒。**
    原因：③ 族无按需加载，且不忽略这个字段。对策：延迟标记只在支持的族的 adapter 里拼，跨族共享的工具定义里不放。
70. **DashScope `web_extractor` 单独声明被拒。**
    现象：② 面 HTTP 200 后首个事件 `response.failed`（`must be executed with web_search tool`）。
    对策：抓取存成搜索的附加档，单独出现时归一化丢弃，发送前再归一化一次。
71. **OpenAI 搜索的 `open_page` 被当成 search 解析 → 日志里一串空查询空结果。**
    原因：`open_page` / `find_in_page` 只带 `url`，没有 queries / sources；`search` 有时只给单数 `query`。
    对策：按 `action.type` 分支解析，queries 缺失退回 `query`。

## H. 可观测性与实测方法（详见 06 §4.2、§8）

72. **包装层装日志钩子时替换了调用方的钩子 → 调用方静默收不到回调。**
    现象：live 实测里所有请求体断言读到 `undefined`，一半"失败"不是端点的错。
    对策：包装一律串联 `own(x); caller?.(x)`，单测钉住调用方钩子仍被调用。
73. **live 实测"全部 skipped"被当成通过。**
    原因：`describe.skipIf(!KEY)` 在 key 没进 env 时静默全跳；key 写在交互 shell 的配置文件里，
    工具/CI 的非交互 shell 不加载。对策：0 passed 即查 env；每条命令经登录 shell 或显式 export 加载 key，key 不进仓库。
