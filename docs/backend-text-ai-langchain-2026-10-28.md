# Python 后端文字 AI

本文描述现有 Web API 的文字 AI 接口，使用 Python LangChain 1.2.18。Web API 在 FastAPI 进程内运行这些接口，支持 OpenAI Chat Completions、OpenAI Responses、Anthropic 和 Gemini 协议，可配置不同服务商的地址。各协议适配与原生 App 共用，详见 [文字模型配置](native-direct-model-settings.md)。

macOS 原生 App 通过随应用安装的 AI 专用后端调用 Pi；该后端也复用这里的 LangChain 核心，并且不启动 Web 的数据库和账号系统，详见 [App 内置 AI 后端](macos-bundled-ai-backend.md)。下面的登录认证和 `.env` 配置仅适用于 Web API。

## 配置

安装 `backend/requirements.txt` 后，在项目现有 `.env` 中配置并重启后端：

```dotenv
WORKFOLLOW_AI_ENABLED=true
WORKFOLLOW_AI_BASE_URL=https://your-provider.example/v1
WORKFOLLOW_AI_API_KEY=your-own-provider-key
WORKFOLLOW_AI_MODEL=your-model-id
WORKFOLLOW_AI_PROTOCOL=openai_chat
WORKFOLLOW_AI_ANTHROPIC_WORKSPACE_ID=
WORKFOLLOW_AI_CONTEXT_WINDOW=32768
WORKFOLLOW_AI_MAX_OUTPUT_TOKENS=2048
WORKFOLLOW_AI_CONTEXT_MARGIN=1024
WORKFOLLOW_AI_TIMEOUT_SECONDS=90
WORKFOLLOW_AI_MAX_CHUNKS=32
WORKFOLLOW_AI_SUMMARY_TRIGGER_RATIO=0.7
WORKFOLLOW_AI_SUMMARY_KEEP_RATIO=0.2
```

地址需替换成实际服务商的 OpenAI 兼容地址。配置作用于这一后端实例，当前每个实例使用一个默认服务和模型，不是每用户独立的密钥设置。

上下文窗口必须填写模型实际支持的值。默认关闭 AI；没有配置时正常业务仍然可用，生成接口返回 503。配置查询不会返回密钥。无需复制任何 Pi 登录信息。

## API

所有接口沿用现有用户登录认证；现有 Agent Token 的接口权限范围保持原样。接口出现在后端 `/docs` 的 `ai` 分组。

### `GET /api/ai/config`

返回是否启用、是否配置、服务地址、默认模型、上下文窗口、输出预算、有效输入预算以及历史压缩比例。此接口只读取配置，不请求模型。

### `POST /api/ai/generate`

```json
{
  "action": "extract_tasks",
  "title": "项目讨论",
  "content": "明天提交验收方案。",
  "referenceDate": "2026-10-28",
  "timeZone": "Asia/Shanghai",
  "existingTitles": [],
  "options": {
    "length": "normal",
    "style": "plain",
    "profession": "",
    "hint": ""
  }
}
```

`action` 支持：

- `extract_tasks`：从正文提取候选待办，每项必须有可核对的连续原文引用。会议已有纪要也可作为普通文字输入。
- `breakdown_task`：拆分下一步子任务，合并重复候选，保留明确日期。
- `improve_summary`：按长度、语言风格和补充要求优化摘要。

`length` 为 `brief` / `normal` / `detailed`，`style` 为 `plain` / `warm` / `formal`。

响应中的 `tasks` 包含 `title`、安排日期 `date`、独立截止日期 `due`、`priority` 和 `quote`；摘要通过 `text` 返回。日期为 `YYYY-MM-DD` 或带时区的 ISO8601。相对日期以请求的 `referenceDate` 为准，缺省时按 `timeZone` 的当前日期处理。

这些接口只返回草稿，不创建或修改数据库中的任务与笔记。客户端继续负责预览、确认保存和撤销。

### `POST /api/ai/chat`

```json
{
  "instructions": "请根据当前讨论整理项目执行计划。",
  "messages": [
    {"role": "user", "content": "交付日期为11月2日，验收还没有完成。"}
  ]
}
```

响应返回 `text` 和可续用的 `messages`。下一轮应使用响应中的 `messages` 追加新的用户消息，并带上相同的 `instructions`，而不是持续重送原始全量历史。

会话上下文由调用方持有；后端不共享不同请求的聊天历史，也不在这一接口中建立持久化会话。若客户端需要重启恢复，应保存返回的上下文，并把完整原始记录另行保留。当前没有新增聊天界面。

## 上下文策略

- 输入预算等于模型窗口减去输出预算和预留空间；所有实际模型请求（包括历史压缩请求）经过同一个预算检查。
- 对未知兼容模型采用保守的 UTF-8 字节估算，分块另计 JSON 转义开销；响应中的 `estimatedInputTokens` 是单次模型调用的最大估算值，不是账单 Token 数。
- 超长正文按段落或句子分块。任务提取使用少量重叠，避免切掉行动与日期的关联；摘要分块不重叠。
- 分块任务结果按标题去重并验证原文引用、日期和结构；摘要分层合并，无法在预算内合并时明确返回错误，避免静默截掉末尾。
- 多轮历史使用 LangChain 的 `SummarizationMiddleware`。默认在可用历史预算的 70% 触发，保留近期约 20% 的内容；较旧内容用摘要替换。压缩提示要求保留目标、日期、任务状态、已完成工作和后来修正的结论。
- 关闭中间件默认的压缩前截断。首次提交的历史也必须处于预算范围内，不能把任意长的单个消息交给会话压缩；长文应走 `generate`。超限返回 413，原始输入不会被后台覆盖。
- LangChain 1.2 的压缩默认会把部分异常转成错误摘要；这里会保留失败状态并中断后续生成，不把错误文本当成有效记忆继续运行。调用方仍持有原始上下文，可重试。
- `modelCalls` 统计逻辑模型调用（包含压缩和合并），`chunks` 统计正文分块，`compacted` 表示本次聊天是否压缩了历史。服务商内部重试不视为新的逻辑模型调用。

输出达到模型长度上限、返回无效 JSON、无效日期或缺少原文依据时，结果不予采用。一次请求有整体超时，长文分块数及合并轮数均受限制。

## 验证

新增测试覆盖真实 LangChain 适配器的 HTTP 请求格式（模拟兼容服务）、登录认证、长文末尾保留与去重、JSON 转义预算、摘要合并、真实 LangChain 历史压缩、不修改原输入、无效输出、超限拒绝和整体超时。测试不需要真实服务密钥，不发送用户数据。

运行：

```sh
cd backend
python -m pytest tests/test_ai_service.py tests/test_ai_api.py
```

按项目测试规范使用隔离数据库；不要将测试服务指向日用数据目录。
