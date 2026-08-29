# Agent / MCP 接入

打勾通过本地 STDIO MCP Server 向 Codex、Claude Code 和 Tencent WorkBuddy 提供笔记能力。MCP Server 不直接访问数据库，而是使用 Agent Token 请求现有 FastAPI 服务，因此继续遵守账号数据隔离。

## 前置条件

1. 启动打勾，确认 `http://127.0.0.1:8123/api/health` 可访问。
2. 进入“设置 → 账号 → Agent 接入”生成 Token。
3. 立即复制 Token；页面关闭后不再完整显示。

每个账号同时只有一个 Token。重置或停用后，原 Token 立即失效，所有已配置客户端都需要同步更新。

## 可用工具

| 工具 | 作用 | 是否写入 |
| --- | --- | --- |
| `list_notes` | 列出最近更新的个人笔记元数据 | 否 |
| `search_notes` | 搜索个人笔记并返回摘要 | 否 |
| `get_note` | 按 ID 读取完整笔记 | 否 |
| `capture_note` | 创建纯文本随手记 | 是 |
| `create_note` | 将 Markdown 转换为新笔记 | 是 |

第一版不提供修改、覆盖或删除已有笔记的工具，避免与浏览器中的 Yjs 协同文档产生冲突。

## Codex

在 Codex 设置中添加 STDIO Server，或编辑 `~/.codex/config.toml`：

```toml
[mcp_servers.workfollow]
command = "/打勾绝对路径/backend/.venv/bin/python"
args = ["-m", "app.mcp_server"]
cwd = "/打勾绝对路径/backend"
env = { WORKFOLLOW_AGENT_TOKEN = "wf_请替换", WORKFOLLOW_API_URL = "http://127.0.0.1:8123/api" }
default_tools_approval_mode = "writes"
```

保存后重启 Codex，在对话中输入 `/mcp` 确认 `workfollow` 已连接。

## Claude Code

```bash
claude mcp add workfollow --scope user \
  --env WORKFOLLOW_AGENT_TOKEN=wf_请替换 \
  --env WORKFOLLOW_API_URL=http://127.0.0.1:8123/api \
  -- /打勾绝对路径/backend/.venv/bin/python \
  -m app.mcp_server
```

如果希望随项目分享，可改为项目级 `.mcp.json`；不要将真实 Token 提交进仓库。

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

- `Agent Token 无效或已停用`：在账号设置重置 Token，然后更新所有客户端配置。
- `无法连接打勾 API`：确认打勾后端已启动，以及 `WORKFOLLOW_API_URL` 指向正确地址。
- MCP Server 启动失败：确认所配置的 Python 来自打勾 `backend/.venv`，且已安装最新 `requirements.txt`。
