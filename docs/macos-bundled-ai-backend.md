# App 内置 AI 后端

原生 App 负责界面、本地业务数据、录音采集和文件保存。AI 后端负责提示词、模型调用、上下文处理及转写会话。它是 App 安装包的一部分，不启动旧版 Web 业务服务器。

## 安装与生命周期

- 安装一个 `WorkFollow.app`，同时包含 Python、LangChain 和 AI 模块。Node 和 Pi 使用本机安装，Pi 最低要求 Node.js 22.19.0，推荐安装 [Node.js 24 LTS](https://nodejs.org/zh-cn/download)。直接调用文字模型无需 Node，也无需另装 Python 或 Pi。
- App 启动时异步预热后端，所有窗口共用一个实例。AI 出错不影响本地待办、笔记或录音保存。
- 正常退出先完成原有数据保存，再关闭后端输入管道。后端取消请求、关闭转写和它启动的 Pi 进程组。
- App 意外退出会关闭管道，后端收到 EOF 后执行相同清理。后端异常退出会让当前请求失败；下一次用户操作重新启动后端，不自动重发模型请求。
- 程序资源位于 `Contents/Resources/AIBackend`；没有监听端口、系统守护服务或独立安装步骤。运行时使用 `-I -B`，不加载用户 Python 环境、不向 App 内写缓存。

## 引擎与配置

Pi 引擎来自本机安装，继续读取当前用户的 models.json 与登录信息；安装包不包含 Pi、Node、个人模型配置或凭据。旧设置中的 Homebrew Pi 路径在另一台 Mac 不存在时自动查找本机安装，高级选项仍可指定程序。

Finder 启动时会检查 PATH、官方及 Homebrew Node、用户目录 ~/.local/bin、nvm、Volta、fnm 和 mise 的常见位置，不执行登录 Shell。缺少或版本过低时提示欢迎清单中的「AI 配置说明」。安装后刷新模型即可重试；开发启动环境也可通过 WORKFOLLOW_NODE_PATH 指定 Node。

新手引导版本 7 包含 Node 下载、Pi 安装命令、models.json 示例及「打开 Pi 配置」。配置目录沿用 PI_CODING_AGENT_DIR 或当前用户 ~/.pi/agent；只为新文件写入示例，已有文件不覆盖。升级保留已有引导的完成状态。

LangChain 1.2 的文字引擎与 Web API 共用 `ai_service`、上下文预算和结构校验。通过同一后端协议选择 `engine: langchain`，并在请求的 `configuration` 中传入 `AISettings` 字段。该适配器不依赖 Web 的账号、数据库或 `.env`。设置页仅支持 OpenAI 兼容、OpenAI Responses 两种文字协议及多套模型，API Key 保存在钥匙串，详见 [文字模型配置](native-direct-model-settings.md)。

Pi 管理自己的上下文和压缩；外层不会再套一层 LangChain 压缩。LangChain 的长文分段、汇总和聊天压缩沿用已有模块。会议录音依然由原生端保存在本地；转写质量与讲话人能力取决于实际模型，本次架构调整不改变识别算法。

## 协议

UTF-8 JSON Lines，经 App 专属 stdin/stdout 管道传输；启动通知为 `{"ready":1}`。请求包含 `id`、`method`、`params`；响应包含相同 `id` 与 `result` 或 `error`。取消通知为 `cancel`，参数为原请求的 `requestID`。

| 方法 | 用途 |
| --- | --- |
| `health` | 协议与能力检查，无模型请求 |
| `models` | 查询 Pi 模型列表 |
| `text.tasks` | 提取待办、拆分子任务 |
| `text.summary` | 摘要优化，传入事实和展示选项 |
| `text.generate` / `chat` | 引擎适配及带上下文的对话 |
| `meeting.minutes` | 根据完整已确认对话编写纪要 |
| `meeting.prepare` / `meeting.transcribe` | 转写准备、批量音频转写 |
| `stream.open` / `stream.command` | 实时音频会话、追加、停止、取消 |

转写事件包含 `channel` 与 `event`。同一会话串行发送；音频包保留 sequence，ACK 超时重试由后端管理。stop 返回前先交付末句事件。原生端继续负责草稿确认、来源归属、五分钟纪要调度及手动编辑保护。

待办和摘要的提示词位于 `backend/app/ai_runtime/prompts.py`，LangChain 的分段规则位于 `ai_service.py`。原生端只发送场景数据并验证结果，应用待办草稿仍需用户确认。

## 构建

日用版 `macos-native/scripts/local-app.py build` 会准备运行环境、构建 App、嵌入后端、签署嵌套程序，最后验证完整安装包。`package-release.py` 的源码打包入口沿用这条流程。

首次构建需要联网下载固定版本 Python 及 LangChain/OpenAI 依赖，缓存位于仓库的 `.runtime-cache/ai-backend-v1`，不提交到 Git。不下载或复制 Node/Pi；旧缓存中的 Node、Pi 目录也不会被嵌入。Xcode 的资源阶段只复制已准备的缓存，不在编译时下载；直接 Xcode 开发前执行：

```sh
python3 macos-native/scripts/bundle-ai-backend.py prepare
```

仅支持 Apple 芯片 Mac。主程序、CLI、小组件和 Python 只构建或打包 arm64；Python universal2 依赖会在嵌入时裁成 arm64。旧缓存即使残留 Intel 或 Node 目录，也不会复制进安装包。签名前检查所有原生组件必须只有 arm64，嵌套动态库不能依赖 Homebrew 或构建机的 Python 路径，签名按内层到外层执行。

本机 Pi 自己维护其依赖；App 不再裁剪或复制 Pi 的依赖树。runtime.json 的 node: external 与 pi: external，以及 App 的 WorkFollowExternalNode / WorkFollowExternalPi 标记声明这两个外部程序。旧版内置运行时的 App 仍可进行备份与回退验证。

测试分三层：AI 核心和协议测试、原生调用与会议状态测试、安装包在简化 PATH 下的启动/退出检查。合成转写测试不调用付费模型，不能视为真实语音识别质量验收。

## 本机 Pi 版验证：构建 63

- 后端全量 179 项通过；原生相关 108 项执行，2 项真实模型测试跳过，其余通过；打包脚本 4 项通过。
- 新手引导中的 Node/Pi 安装命令在不同用户目录及含空格的安装前缀下验证，Pi 配置打开入口不会替换已有 models.json。
- 完整 App 在空 HOME、简化 PATH 下找到本机 Node/Pi，从隔离的 Pi 配置文件读取模型并完成实际 Pi 文字生成、合成转写末句与退出清理。缺少 Pi 或 Node 时提示安装说明，LangChain 的两种 OpenAI 协议仍可独立调用。
- Node、Pi、Anthropic SDK、Google Gemini SDK 均未打入新包。16 个内置 AI 源文件与工作区一致，完整签名和 ZIP 解压校验通过。
- App 约 182.1 MiB，Python 与 LangChain/OpenAI SDK 约 97.4 MiB；ZIP 约 80.2 MiB。本次生成预览包，未执行日用安装。

## 历史验证：构建 61（当时内置 Pi）

- 后端运行时与 Node 发现测试 13 项、原生 AI 与新手引导测试 35 项、打包脚本测试 4 项通过。安装命令在不同目录及含空格的 Homebrew 前缀中验证，已有 Pi 模型文件的内容保持不变。
- 完整包在空 HOME、简化 PATH 下自动找到本机 arm64 Node，完成模型列表、合成转写末句、四种文字协议、连续调用及 EOF 清理；另外强制指定不存在的 Node，确认安装提示和直接调用文字模型仍正常。
- 内置 AI 后端的 16 个源文件与工作区逐一比对一致。安装包不包含 Node，完整签名和 ZIP 解压校验通过。
- App 约 296.6 MiB，Pi 约 73.6 MiB，Python 及文字 SDK 约 134.3 MiB；ZIP 约 115.4 MiB。此前构建 60 的 App 约 446.2 MiB，ZIP 约 163.2 MiB。
- 本次生成预览包，未执行日用安装；模型调用测试均使用本地合成服务。

## 历史验证：构建 60（当时内置 Node）

- 后端运行时专项 9 项、原生 AI 调用与转写专项 16 项、打包脚本 4 项测试通过。
- 签名前遍历整个 App 的原生程序和动态库，确认全部只有 arm64；内置 CLI 可直接运行。内置 AI 源码与工作区的 15 个源文件逐一比对一致。
- 空 HOME、简化 PATH 下完成模型列表、合成转写末句、四种文字协议及连续调用检查。首次 EOF 测试在并行打包期间触发 5 秒超时；复测退出耗时 3.65 秒，另行确认没有残留的 Python 或 Pi 进程。
- App 从构建 59 的约 769.2 MiB 降至约 446.2 MiB；Pi 约 114.1 MiB、Node 约 107.3 MiB，合计约 221.4 MiB。Python 及文字模型 SDK 约 134.3 MiB，单独计入 App 体积。
- ZIP 从约 267.0 MiB 降至约 163.2 MiB，解压后的完整 App 已通过架构、签名与安装元数据校验。
- 这是仅支持 Apple 芯片的预览构建，未替换日用安装；未调用个人配置中的真实模型。

## 历史验证：构建 56（当时使用双架构）

- 后端全量测试 164 项通过；退出竞态修复后的 AI 运行时专项 9 项通过。
- 原生相关测试 94 项执行完成，其中 3 项真实模型调用测试跳过；最后的取消发送调整另有 10 项专项通过，其中 1 项真实模型测试跳过。
- 打包脚本 4 项测试通过。构建 56 的完整 App 在空 HOME、简化 PATH 下通过模型列表、合成实时转写、末句交付、LangChain 兼容 HTTP 调用及 EOF 关闭 Pi 进程检查。
- 动态库和动态库搜索路径检查通过，完整 App 签名验证通过。安装包内包含两种 CPU 架构，Intel 未做实机运行验证。
- 通用 App 的磁盘体积约 679 MiB。它包含两套 Python/Node 运行时和 Pi，体积显著增加；本次产物作为预览包，未替换日用 App。
