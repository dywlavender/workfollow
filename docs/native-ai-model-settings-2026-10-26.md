# 统一 AI 模型设置

设置窗口新增“AI 模型”页，分别选择语音转写、文字处理模型。模型列表及认证仍在 Pi 中维护，App 不保存另一份模型目录或认证信息。

## 使用

1. 在 Pi 配置模型、服务商和认证。
2. 打开 WorkFollow“设置 → AI 模型”，自动读取 Pi 模型列表。
3. 从两个下拉框选择语音和文字模型。Pi 列表更新后点击“刷新列表”。

语音用于会议转写；文字用于会议纪要、周报、提取待办和任务拆分。文字可选择“跟随 Pi 默认模型”。选择保存为完整 `provider/model-id`，区分不同服务商的同名模型。

Pi 程序路径、自定义音频扩展放在默认收起的高级选项。录音或转写期间禁用语音模型和音频通道设置；文字模型更改从下一次调用生效。

会议页、周报页及待办 AI 的配置入口统一打开此页面，不再各自提供手输模型窗口。

## 查询与兼容

- 通过 Pi RPC 的 `get_available_models` 读取结构化模型信息，不解析终端表格，也不发送生成请求。
- 仅使用服务商、模型 ID、名称和输入类型，不把其他模型响应字段保存到 App。
- 列表读取在后台执行，支持取消和超时。刷新失败保留上次列表及已选模型。
- 保留原有配置及其存储格式；旧的短模型 ID 只在唯一匹配时映射到列表项，不擅自改选服务商。已移除的模型保留当前配置并提示重新选择。
- Pi 当前模型元数据会把部分语音模型也标为 `text`。语音候选因此结合内置转写通道的兼容能力筛选，文字候选排除 ASR 和实时语音专用模型。自定义音频扩展可使用 Pi 的其他注册模型。
- 模型出现在目录中不代表其服务渠道当前可用；本批验证模型查询和选择，不宣称先前的生成服务错误已解决。

## 验证

2026-10-26：相关 XCTest 共 46 项，43 项通过、3 项内容生成或音频服务集成测试按默认开关跳过，0 失败。

新增验证包含结构化查询、同名模型区分、场景筛选、刷新替换、读取失败保留原选择、超时与取消、独立配置保存及重启读取。真实已安装 Pi 的模型目录查询通过，未调用内容生成。

两个原生设置窗口交互用例通过：文字下拉选择后保存且不影响语音选择；读取失败时保留原模型并显示错误。浅色和深色渲染结果已检查。预览使用测试模型；原生 TabView 顶部标签未被离屏捕获完整显示，不将捕获图作为整个系统设置窗口的人工验收。

构建包：`/private/tmp/wf-native-ai-model-settings-20261026-build/Build/Products/Debug/WorkFollow.app`。日用 App 尚未替换。

日志：`/private/tmp/wf-native-ai-model-settings-20261026-tests.log`。设置内容预览：`/private/tmp/wf-native-ai-model-settings-20261026-light.png`；深色错误状态：`/private/tmp/wf-native-ai-model-settings-20261026-dark-error.png`。

复现：

```sh
WORKFOLLOW_DERIVED_DATA=/private/tmp/wf-native-ai-model-settings-build WORKFOLLOW_DISABLE_SWIFT_SANDBOX=1 PI_MODEL_CATALOG_INTEGRATION=1 macos-native/scripts/run-tests.sh PiModelCatalogTests AIModelSettingsInteractionTests MeetingModelConfigurationTests MeetingStoreTests SummaryPiOptimizerTests AITaskDraftTests AITaskComposerInteractionTests
```
