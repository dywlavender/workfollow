# 文字模型与本机 Pi

“设置 → AI 模型 → 文字处理”有两个独立入口：

- **直接调用**：使用 App 内置 LangChain，在 App 页面填写模型配置。
- **Pi**：使用本机已安装的 Pi，模型、地址和认证读取 Pi 自己的配置文件。语音转写也使用本机 Pi。

## 直接调用

填写模型 ID、API URL 和 API Key，选择协议，测试连接后保存。支持保存多套配置和下拉切换。

| 协议 | 默认 API URL | 请求方式 |
| --- | --- | --- |
| OpenAI 兼容 | `https://api.openai.com/v1` | Chat Completions |
| OpenAI Responses | `https://api.openai.com/v1` | Responses |

可以使用其他服务商的 OpenAI 兼容地址，网关路径前缀会保留。完整的 `/chat/completions` 或 `/responses` 地址也会规范化。模型 ID 按服务商提供的名称填写。

本地兼容服务如 `http://localhost:11434/v1` 未要求认证时，Key 可留空。高级选项可设置上下文窗口和最大输出。Responses 关闭服务端存储，不使用 previous_response_id；上下文、长文分段与压缩由本地后端维护。

非敏感配置保存在原生数据目录的 `modules/ai-models.json`，Key 保存在 macOS 钥匙串，不写入业务备份。迁移到其他 Mac 后需重新填写 Key。切换协议或 URL 主机会清空编辑框里的旧 Key；保存前不影响当前配置。

旧 Anthropic/Gemini 配置仍能读取，不会丢失或被覆盖；当前调用仅支持上面两种协议，需要选择服务商提供的兼容协议及地址后再保存。

## 本机 Pi

Node 和 Pi 不随 App 打包。欢迎清单的“AI 配置说明”包含 Node.js 24 LTS 下载、Pi 安装命令及 models.json 示例；已安装可用环境可直接复用。

Pi 安装到用户目录的命令使用 `npm install --global --prefix "$HOME/.local" @earendil-works/pi-coding-agent@0.86.1`，引导的完整命令还会处理 Homebrew node@24 的 PATH 并验证版本。App 能在 Finder 启动时找到官方、Homebrew、用户目录和常见 Node 版本管理器的程序，也可在 Pi 高级选项指定路径。

Pi 模型文件默认是 `~/.pi/agent/models.json`，`PI_CODING_AGENT_DIR` 可指定其他目录。“打开 Pi 配置”只为不存在的文件创建示例，已有文件保持原样。编辑保存后，在设置中点击“刷新 Pi 模型”，分别选择文字与语音模型。App 不把 LangChain 页面保存的 Key 或模型同步到 Pi。

Pi 的模型及认证由 Pi 管理；App 只通过 RPC 调用它，并关闭自己启动的会话。Pi 使用自己的上下文与压缩。语音能力取决于 App 当前转写通道支持的模型，普通聊天模型不能直接作为语音模型。

## 运行环境

App 内置 Python、LangChain 1.2.18 和 langchain-openai 1.0.3。直接调用无需安装 Node 或 Pi。每次请求拥有自己的 HTTP 客户端，连续调用不会因上次请求结束而关闭共享连接。

## 历史验证：构建 59（当时支持四种直接调用协议）

构建 59 已生成并通过完整签名、ZIP 解压验证。后端全量 179 项通过；相关原生测试执行 100 项，97 项通过，3 项真实模型测试按设置跳过。真实窗口内完成了编辑模型名称、点击保存和 Key 遮挡检查。

四种协议使用本地模拟服务验证了 SDK 请求路径、认证、连续调用、错误处理、输出截断和上下文压缩。完整 App 在空 HOME、简化 PATH 下再次完成四种协议的测试连接和生成，并验证退出清理；未使用个人 Key 或付费模型。这些检查不等于真实服务商模型质量验收。

构建 59 当时的预览 ZIP 约 267 MiB，通用 App 约 769 MiB，包含两种 CPU 运行环境。后续构建改为仅支持 Apple 芯片，运行环境与依赖只保留 arm64，详见 [内置后端构建说明](macos-bundled-ai-backend.md)。
