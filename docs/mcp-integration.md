# Agent / MCP 接入

打勾通过本地 STDIO MCP Server 向 Codex、Claude Code 和 Tencent WorkBuddy 提供笔记和待办能力。MCP Server 不直接访问数据库，而是使用 Agent Token 请求 FastAPI；已有内容的修改继续进入 Yjs 协同文档，因此浏览器和 Agent 共享同一份实时状态。

## 前置条件

1. 安装最新后端依赖并执行数据库迁移：

   ```bash
   cd /打勾绝对路径/backend
   .venv/bin/pip install -r requirements.txt
   .venv/bin/alembic upgrade head
   ```

   使用项目根目录的 `start.command` 时，这两步会自动执行。
2. 启动打勾。Agent 的查询和新建依赖 FastAPI；修改已有笔记或任务还依赖 8124 端口的协同服务。推荐直接运行项目根目录的 `./start.command`，不要只启动前端。
3. 确认 `http://127.0.0.1:8123/api/health` 可访问。
4. 进入“设置 → 账号 → Agent 接入”生成 Token。
5. 立即复制 Token；页面关闭后不再完整显示。

每个账号同时只有一个 Token。重置或停用后，原 Token 立即失效，所有已配置客户端都需要同步更新。

Agent Token 只允许访问本文列出的笔记、搜索和待办接口，不能用于删除笔记、管理用户或调用其他账号管理接口。

## 可用工具

| 工具 | 作用 | 是否写入 |
| --- | --- | --- |
| `list_notes` | 列出最近更新的个人笔记元数据 | 否 |
| `search_notes` | 搜索个人笔记并返回摘要 | 否 |
| `get_note` | 按 ID 读取完整笔记 | 否 |
| `capture_note` | 创建纯文本随手记 | 是 |
| `create_note` | 将 Markdown 转换为新笔记 | 是 |
| `append_note` | 向已有笔记末尾安全追加 Markdown | 是 |
| `replace_note` | 安全替换已有笔记正文和可选标题 | 是 |
| `list_tasks` | 列出或搜索待办摘要，可按日期和完成状态过滤 | 否 |
| `get_task` | 读取任务和正文/元数据版本 | 否 |
| `create_task` | 新建待办 | 是 |
| `replace_task_body` | 安全替换任务正文 | 是 |
| `update_task_metadata` | 更新标题、优先级、截止时间或标签 | 是 |
| `set_task_completed` | 完成或恢复任务 | 是 |

`get_note` 返回 `version`；`get_task` 分别返回 `bodyVersion` 和 `metadataVersion`。修改工具必须带回对应版本。若期间浏览器或另一个 Agent 已修改文档，接口返回冲突且不会覆盖新内容，调用方应重新读取后再决定如何修改。所有 Agent 写请求都会记录到“设置 → 账号 → Agent 接入”的最近写操作中；记录不保存正文或 Token。

## Codex

在 Codex 的“设置 → MCP servers”中添加 STDIO Server，或编辑 `~/.codex/config.toml`：

```toml
[mcp_servers.workfollow]
command = "/打勾绝对路径/backend/.venv/bin/python"
args = ["-m", "app.mcp_server"]
cwd = "/打勾绝对路径/backend"
env = { WORKFOLLOW_AGENT_TOKEN = "wf_请替换", WORKFOLLOW_API_URL = "http://127.0.0.1:8123/api" }
default_tools_approval_mode = "writes"
```

`writes` 表示读取可直接执行，新增和修改前由 Codex 请求确认。这里没有设置 `required = true`，因为打勾是本地服务：未启动打勾时，不应阻止 Codex 本身启动。

保存后重启 Codex，在对话中输入 `/mcp`，确认 `workfollow` 已连接。随后可以直接使用自然语言，例如：

```text
用 WorkFollow 搜索标题或正文包含“周会”的笔记，只返回标题和 ID。
```

```text
读取 WorkFollow 中 ID 为 xxx 的笔记并总结；不要修改原笔记。
```

```text
先读取 WorkFollow 中标题为“项目计划”的笔记，再把下面内容追加到末尾：……
```

```text
列出 WorkFollow 中今天未完成的任务。直接按今天日期和未完成状态过滤，不要先读取全部任务。
```

不必在提示词中手写 `get_note`、`append_note` 等工具名。修改已有内容时，MCP Server 会要求 Codex 先读取当前版本，避免静默覆盖浏览器或其他 Agent 的新编辑。

`list_tasks` 只返回标题、状态、时间、优先级、清单和标签等摘要，避免把所有任务正文及成员资料一次送入模型。需要正文或版本信息时，再按 ID 调用 `get_task`。

## Claude Code

```bash
claude mcp add workfollow --scope user \
  --env WORKFOLLOW_AGENT_TOKEN=wf_请替换 \
  --env WORKFOLLOW_API_URL=http://127.0.0.1:8123/api \
  --env PYTHONPATH=/打勾绝对路径/backend \
  -- /打勾绝对路径/backend/.venv/bin/python \
  -m app.mcp_server
```

`PYTHONPATH` 用于保证从任意工作目录启动 Claude Code 时都能导入后端的 `app` 模块。如果希望随项目分享，可改为项目级 `.mcp.json`；不要将真实 Token 提交进仓库。

## Tencent WorkBuddy

在用户级 `~/.workbuddy/mcp.json` 或项目级 `<项目>/.workbuddy/mcp.json` 中配置：

```json
{
  "mcpServers": {
    "workfollow": {
      "command": "/打勾绝对路径/backend/.venv/bin/python",
      "args": ["-m", "app.mcp_server"],
      "cwd": "/打勾绝对路径/backend",
      "env": {
        "WORKFOLLOW_AGENT_TOKEN": "wf_请替换",
        "WORKFOLLOW_API_URL": "http://127.0.0.1:8123/api"
      }
    }
  }
}
```

## 排查

- `/mcp` 中没有 `workfollow`：确认配置已经保存，并完全重启 Codex。
- `Agent Token 无效或已停用`：在账号设置重置 Token，然后更新所有客户端配置。
- `无法连接打勾 API`：确认打勾后端已启动，以及 `WORKFOLLOW_API_URL` 指向正确地址。
- 查询正常但修改已有内容失败：确认 8124 协同服务也已启动；最简单的处理是改用根目录 `start.command` 启动整套服务。
- MCP Server 启动失败：确认所配置的 Python 来自打勾 `backend/.venv`，且已安装最新 `requirements.txt`。
- 修改返回版本冲突：说明浏览器或另一个 Agent 已先完成修改。让 Agent 重新读取后再修改，不要反复提交旧版本。
