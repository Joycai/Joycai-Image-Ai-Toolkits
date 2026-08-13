# LLM API 对接知识库

> **这个目录写"业内是什么样"，不写"本项目怎么选"。**
>
> 两者混在一起是本项目此前的问题：`provider-standards.md` 里那些关于三个协议族
> 实际差异的描述，本身是通用知识，却被写在一份"重构方案"里，跟着那次重构的
> 结论一起过期。所以这里立一条硬规矩：
>
> - **`docs/api/`** — 协议事实。四个协议族各自长什么样、彼此差在哪、第三方
>   兼容层的坑在哪。不含本项目的取舍、不含 `src/` 的文件名。
> - **`docs/*-plan.md`** — 本项目的方案与取舍。引用这里的事实，不复制。
>
> 判断标准：**换一个项目还成立的，写这里；只对本项目成立的，写那边。**

## 四个协议族

业内主流的模型 API body 形状收敛成了四种。它们不是"同一件事的四种方言"——
消息容器、system 的放法、工具结果的关联方式、流式的机制各不相同，一个 adapter
换不到另一族去。

| # | 协议族 | 端点 | 谁在用 |
| --- | --- | --- | --- |
| 1 | **OpenAI Chat Completions** | `POST /v1/chat/completions` | OpenAI + 事实上全行业的兼容层 |
| 2 | **OpenAI Responses** | `POST /v1/responses` | OpenAI 自家新接口（有状态） |
| 3 | **Google GenAI** | `POST /v1beta/models/{model}:generateContent` | Gemini Developer API / Vertex AI |
| 4 | **Anthropic Messages** | `POST /v1/messages` | Claude API / Bedrock / Vertex |

Chat Completions 和 Responses 同属 OpenAI 却分成两族，是因为它们的差别
（`input` vs `messages`、扁平 vs 嵌套的工具定义、类型化事件流 vs delta 拼接、
服务端存不存状态）比 Gemini 与 Anthropic 之间的差别还大。合并会让后面每一张
对照表都要开例外。

详见 [`landscape.md`](landscape.md)。

## 三个正交的轴

对接一个端点时要同时回答三个互不相关的问题，混为一谈是大多数踩坑的来源：

1. **协议族** —— body 长什么样。上面那四个。
2. **部署** —— 同一族的 body，换个地方托管：URL 形状、鉴权方式、模型标识都会变，
   body 基本不变。Azure OpenAI、Vertex AI、Bedrock 属于这一轴。
3. **马甲** —— 谁"兼容"了谁。第三方厂商与中继绝大多数选择兼容
   **Chat Completions**，但兼容 ≠ 等价：各家有私有扩展（DeepSeek 的
   `reasoning_content`、OpenRouter 的 `provider` 路由）也有缺失（`stream_options`、
   `/models`、工具调用）。这一轴的知识没有任何官方文档会写，只能自己攒。

## 本目录不覆盖

- **AWS Bedrock Converse** —— 它其实是第五种独立 body（见
  [`landscape.md`](landscape.md) §7），但需要 SigV4 签名，本项目短期不会接。
  记录存在性即可，不展开。
- **MCP** —— 工具与上下文的协议，与模型 API 正交，不在这一层。
- **OpenAI Realtime / 各家语音通道** —— WebSocket/WebRTC，不是请求-响应模型。
- **Embedding / rerank / 微调端点** —— 另一组端点，与对话补全无关。

## 索引

| 文件 | 内容 | 状态 |
| --- | --- | --- |
| [`landscape.md`](landscape.md) | 四族总览、逐族骨架、部署变体、马甲层清单 | ✅ |
| `messages.md` | 消息结构、system 的四种放法、多模态 part 形状 | 待写 |
| [`tools.md`](tools.md) | 工具定义 / 调用 / 结果回传 / tool_choice 四族对照，含配对硬要求 | ✅ |
| [`streaming.md`](streaming.md) | SSE 机制、结束原因、**失败怎么送达**（四种「看起来成功」的失败） | ✅ |
| [`reasoning.md`](reasoning.md) | 思考强度、思维链取回、以及**回传义务**（唯一会让请求被拒的一件） | ✅ |
| [`usage.md`](usage.md) | token 计数的两个口径陷阱、输出上限、上下文窗口为何只能靠探测 | ✅ |
| [`structured.md`](structured.md) | JSON mode / schema / 强制 tool_choice 的四族做法，含 `json_object` 的隐藏前置条件 | ✅ |

## 接一个新协议族时，先看这三条

两轮实践（① 族与 ④ 族）下来重复出现的形态，比任何单条协议事实都耐用：

**① 先问"失败会不会响"。** 这决定了紧迫性与验证方式：

| 族 | 做错了会怎样 |
| --- | --- |
| ① DeepSeek 系 | 工具轮不回传 `reasoning_content` → **400**，会逼你修 |
| ④ Anthropic | 工具轮不回传 thinking block → **静默关掉思考**，没有任何现象 |
| ③ Gemini | 不回传 `thoughtSignature` → 多轮工具调用失效 |

**静默的那种最危险**：它不会自己暴露，只能靠对照文档发现，也只能靠"响应里
还有没有 thinking block"这类间接观察来验证。

**② 再问"默认值是什么"，而且要按模型问。** 三族都有"同一段代码在两代模型上
行为相反且都不报错"的情况：Anthropic 的思考默认值分两派、`display` 默认
`omitted`（拿不到文本却照全额计费）、Gemini 2.5 Pro 关不掉思考。**"省略字段
= 用默认"从来不是一个统一的答案。**

**③ 最后问"兼容层砍了什么"。** 四个样本（New API × 2、MiniMax × 2）的共同
规律见 [`landscape.md`](landscape.md) §7。最狠的一次是 MiniMax 的 ④ 族端点
**砍掉了 `tool_choice` 的强制档**，直接让"强制工具调用"这个四族官方都有的
手段失效。**兼容层文档不能当能力清单**：没列既可能是不支持，也可能只是没跟上。

**④ 一条读文档的方法：指南页与参考页要分开读。**

- **指南页**（`docs/*`）反映"官方希望你怎么用"。它会为了推新 surface 而不提
  旧的 —— Gemini 3 的思考指南只讲 Interactions API，读完会以为经典
  `generateContent` 上没法配思考。
- **参考页**（`api/*`）反映"接口实际接受什么"。`ThinkingConfig` 在参考页里
  定义得完整无缺。

**判断能力边界看参考页，不看指南页。**

配套的一条操作习惯：**大文档要抓原文自己搜**。那份参考页 295KB，网页摘要工具
连着两次都没扫到 `ThinkingConfig`；`curl` 下来 grep 一次就找到了。摘要在这个
量级会整节丢失，而丢掉的恰好可能是唯一的权威定义。

相关的本项目方案文档：

- [`../provider-layering.md`](../provider-layering.md) — 本项目的分层模型
  （协议族 / 端点 / 模型 + 探测维）与"新参数放哪一层"的裁决依据
- [`../provider-standards.md`](../provider-standards.md) — 本项目怎么把协议族 ×
  official/compat 落成 6 个 `ApiStandard` 值
- [`../reasoning-plan.md`](../reasoning-plan.md) — 本项目怎么加思考强度与思维链（① 族，已实现）
- [`../anthropic-plan.md`](../anthropic-plan.md) — ④ 族的审计与接入（已实现）
- [`../gemini-plan.md`](../gemini-plan.md) — ③ 族的盘点与接入（已实现）
- [`../thinking-verification.md`](../thinking-verification.md) — 三族思考支持的**实测清单**（全部未验证）

## 写作约定

- **每条协议事实都要能被一次 HTTP 请求验证。** 写不出请求骨架的描述说明还没搞清楚。
- **区分"文档写了"和"实际如此"。** 兼容层的行为常与文档不符；实测结论标注
  「实测」并写明日期与端点，别与官方文档混排。
- **不写 `src/` 的路径。** 需要指向实现时，在方案文档里指，不在这里指——否则
  这份知识会随重构烂掉。
- **过期比缺失更糟。** 模型代次相关的结论（哪些模型支持哪个档位之类）写"截至
  某日期"，或干脆不写具体型号，只写机制。
