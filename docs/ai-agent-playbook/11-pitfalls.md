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

## B. 协议层 · 会响但难排查类

9. **MiniMax Anthropic 端点：turn 停在搜索结果上报 `end_turn`，且拒收自己发的块。**
   兼容层「响应侧抄全了、请求侧没抄」的典型。对策：以「结果之后模型说话了吗」为续跑
   判据；续跑退化为纯文本 transcript（见 05 篇）。

10. **tool_calls 流式拼接键用 id → 交错调用拼错。**
    id 自身也可能分片。对策：按 `index` 分组，id 累积拼接。

11. **强制 tool_choice 撞上思考模型/被砍档端点。**
    对策：结构化输出必有「强制失败→JSON mode」降级链，降级路径仍带原生 JSON 参数；
    回退判定正则要求「能力词 + not supported」**同现**——裸子串会把无关上游错误
    （"does not support streaming for this region"）也吞进回退，翻倍花钱且掩盖真错。

12. **`json_object` 的 "json" 字面量前置条件。**
    prompt 里没有 "JSON" 字样会报错或产生无限空白流。对策：检测 prompt，缺则追加 cue；
    prompt 可编辑的系统不能把它当既成事实。

13. **兼容层把思维链塞进正文 `<think>…</think>`，标签跨 chunk 分片。**
    对策：状态机切分器——只认响应开头、`danglingPrefix` 扣住可能成为标签的尾巴、
    流结束未闭合按 reasoning flush；切出的思考只展示不回传。

14. **Anthropic base URL 约定与 OpenAI 生态相反。**
    OpenAI/Gemini 的 base 自带版本段，Anthropic 的 base 是根地址（客户端补 `/v1/messages`）。
    对策：不对称归一化；绝不给 OpenAI base「修复性」补 `/v1`（中继合法路由在 /v1 之下）。

15. **鉴权头两套一等约定（Anthropic 生态）。**
    `x-api-key` 与 `Authorization: Bearer` 各有网关只认一种。对策：compat 端点提供
    default/bearer/both 三模式；官方端点只给 default（api.anthropic.com 拒绝双凭证）。

16. **usage 口径：Anthropic 三桶要相加、Gemini 思考在 candidatesTokenCount 之外。**
    直接读 `input_tokens` 会少报一个数量级；只读 candidates 会漏掉最贵的思考。
    对策：归一化为 input/output/cached（cached 是 input 子集）三字段再入库。

## C. Runtime 与工具系统

17. **中断把会话永久搞坏。**
    现象：停止任务后每个 provider 拒绝后续请求，只能新建对话。
    原因：assistant 的 tool_calls 已入历史，k<N 的 tool 回复=永久畸形转录。
    对策：abort 中途逐个补 `[not run]` 桩、配平后才抛 AbortError；外加
    `repairToolCallPairing` 在每次追加历史前兜底。

18. **助手「只给方案不动手」。**
    原因 A：agent 指令拼在首轮 user 层，活不过第一轮——必须并入 **system 层**。
    原因 B：所需工具根本不存在，或轮数中途用尽。对策：补齐工具、放宽 maxRounds、
    上限时用卡片问作者（extend/finish/pause）而非硬停。

19. **一次性提示变常驻指令。**
    「本轮别再调工具」「快用 write_note 落盘」等提示留在持久 history 里成永久禁令/命令。
    对策：**发出即撤**——请求发出后 finally 里 splice 掉。同类事故：作者中断后敲的
    "continue" 混进 tool_result 信封被跨 39 轮反复重发（对策：合并时给作者文本打标签）。

20. **工具轮叙述混进正文。**
    「我先去找文件列表。」被插进用户文档。对策：onOutputText 用**快照**语义，工具轮
    结束整段回滚，只累计以散文收束的轮。

21. **base64 图片挤爆请求体而 token 估算无感。**
    估算按计费口径记平价，payload 却是 MB 级且跨轮存续。对策：trimHistory 图片优先、
    无条件、上限 N 张；会话序列化时全部剥离图片。

22. **plan 门控越权洞：file-scoped 步骤放行了无 file 的调用。**
    「delete Ava / armor.md」（删一个文件）授权了删整个实体。对策：步骤声明了 file，
    调用就必须给出同一个 file。

23. **审批 apply 不重定位 → 改写作者从未批准的文字。**
    卡片挂着时作者可能一直在打字。对策：apply 时重新 `find` 定位——消失或出现多于
    一处都以拒绝回模型；apply 抛错一律 resolve 成拒绝，绝不吞错报成功。

24. **悬挂的审批 Promise 永久卡死后续运行。**
    对策：每次运行 finally 必 `rejectAll(runId)`；runId=本次运行的 AbortController 对象，
    保证并行运行互不误杀。

25. **备份失败照写 → 不可恢复的破坏。**
    对策：「备份失败=写入失败」（backup throw 即写入不发生）；二进制/整目录删除用
    rename-into-backups 而非 unlink。

26. **空 projectPath = 全盘可读。**
    路径包含校验是前缀测试，空前缀包含一切绝对路径。对策：显式拒绝空 projectPath；
    一切模型可控路径参数过 `isPathWithin` 式校验。

27. **模型给的正则会卡死 UI 线程。**
    搜索工具只做字面匹配、明确拒绝正则（病态 pattern 无法中断）。

28. **模块级常量冻结运行时配置。**
    注册表 import 时求值一次，动态 enum（如分类表）必须在下发时**拷贝后**注入，
    不能 mutate 共享常量。

29. **运行快照与磁盘漂移。**
    move/delete 后同一运行的下一个调用解析到不存在的目录。对策：写工具落盘后手工回填
    快照；细粒度工具从磁盘读当前状态而非快照。

30. **一次读取附带全部图片 → 35MB 请求超时。**
    对策：读实体只回文件名+文字描述，真要看再按名取一张；单图字节上限。

## D. 子代理与上下文管理

31. **搜索子代理永远不联网。**
    原因：`withholdTools` 把「没有本地工具」和「该收尾了」并成一个判断，而 search
    子代理本地工具恒为空。对策：`serverTools: "final-round-off"|"off"|"always"` 独立
    策略字段，search 用 always。

32. **子代理产出取到空。**
    runtime 成文轮直接 return，最终文本从不进 history——事后翻 messages 必空。
    对策：产出只能经 `onOutputText` 回调捕获（快照赋值）。

33. **委托产出整块回填 = 把堆叠换个地方堆。**
    对策：落盘 note，tool result 只回「路径 + ≤800 字符摘要」，细节走 read_note 分页。

34. **「启用」当「可用」用，双输。**
    search 绑了不能上网的模型时，路由照样关掉主模型联网——作者失去主模型联网又什么都
    没换回来。对策：单一判断函数（开关+绑定+模型存在+能力前置条件），所有调用点共用；
    设置面板警告但不阻止，下游必须再验。

35. **子代理 AbortError 转成 tool error → 作者的「停止」被读成「搜索失败」而重试。**
    对策：AbortError 是唯一重抛的异常，其余转模型可读的错误文本。

36. **密钥缺失降级空串 → 要逆向工程的 401。**
    对策：解析层直接返回指路的配置错误（"去 Settings → Providers 粘 key"），绝不发无钥请求。

37. **`Boolean(handle)` 恒真的假守卫。**
    routeTools 收 `hasWorkspace: boolean` 而调用方总是无条件构造 handle。
    对策：守卫参数要传**能真正为空的东西**（handle 本身，undefined 才是没有）。

38. **嵌套日志顶掉主日志行。**
    子跑 round 也从 1 开始，去重键只有 round/toolCallId 会互相覆盖。
    对策：事件去重键带 `parentStep`。

39. **ASCII slug 白名单让中文笔记全坍缩进 `note.md` 互相覆盖。**
    对策：Unicode 属性类 `\p{L}\p{N}` 清洗、按码点截断、绝不静默覆盖（撞名加后缀并告知）。

40. **task_progress 悄悄创建无名工作区。**
    它的 ensure() 既建了任务又满足了「要求先有计划」的检查。对策：只有 task_plan
    （真标题）与 write_note（中性标题）能建仓。

41. **步骤数据双事实源打架。**
    JSON 和正文各存一份步骤，作者手改后不一致。对策：步骤只存在于正文复选框，
    1 基序号寻址；JSON 注释头只放机器状态。

42. **task.md 小节按标题文本定位 → 换语言后写错位置。**
    对策：语言无关 HTML 注释锚点（`<!-- task-steps -->`）。

43. **同轮并发写丢更新。**
    模型一轮可发多个 tool call。对策：工作区写入过模块级 Promise 链串行化，
    且链放在 workspace 层（写者不止工具，暂停/恢复也在写）。

44. **恢复对话而非恢复任务。**
    旧 history 里的 "continue" 被当新指令自我强化。对策：resume 种子 = task.md +
    notes 索引 + sourceRefs 过期清单，**不重放旧 wire history**。

45. **压缩把网络抖动变成坏会话。**
    摘要失败后仍折叠。对策：失败返回 null、history 一字不动、只在成功后换入新数组。

46. **压缩杀死 prompt cache。**
    触发线与目标线太近导致每轮都压，每压一次前缀作废。对策：0.7 触发 / 0.45 目标的
    宽间隙；summary 消息紧贴 system 之后，稳定前缀最大化。

47. **轮边界按索引记录 → repair/trim 后错位。**
    对策：一切 meta 按**消息对象身份**记录；序列化时身份→索引，反序列化重连，
    解析不到的引用丢弃而非猜测。

48. **旧格式事件打崩整个 UI。**
    会话 blob 比写它的代码活得久，事件载荷实际是 wire format。对策：迁移函数，
    认不出的条目丢弃（丢一行日志值得，丢一个会话不值得）。

49. **GC 豁免未完成任务 ⇒ 无界增长。**
    对策：「未收尾优先保留但不豁免」的排序 GC；绝不删当前运行持有的任务。

50. **恢复失败留下「在跑」的僵尸任务。**
    对策：乐观置回 in_progress 后，若启动失败再置回 paused——不留一个声称在跑的任务。

## E. 文档与调研方法

51. **指南页 ≠ 参考页。** 判断能力边界看 API 参考页；大文档抓原文自己搜（网页摘要工具
    连续漏掉 295KB 参考页里的关键定义，curl+grep 一次找到）。
52. **兼容层文档四条规律**：结构照抄；扩展在响应侧；枚举是子集；最需要确认的部分
    （流式格式、错误通道、回传规则）不写且滞后上游一年。推论：兼容层文档不能当能力
    清单——「没列」按「未知、需实测」处理。
