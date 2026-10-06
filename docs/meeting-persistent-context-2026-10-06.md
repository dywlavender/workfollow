# Pi 常驻音频上下文实验

## 范围

实验扩展位于 `macos-native/scripts/tests/meeting-persistent-experiment.mjs`，不打包到 Native，不改变正式会议录音生命周期。所有模型调用仍在 Pi 内完成。使用 macOS 合成的 Tingting / Eddy 两种声线，重复虚构四轮对话，总计 81.28 秒；音频仅在内存和进程管道中流转，未使用麦克风、未保存录音。

## 实测

第一次报告：`meeting-speech-persistent-2026-10-06.json`。

- 前三段完成，覆盖约 32.28 秒，服务端 session ID 相同，requestCount 为 1 / 2 / 3。
- 三段各返回两条发言；已观察的 A / B 标签暂时一致。
- 延迟分别为 1435 / 1032 / 1049 ms，不包括等待录音分段的时间。
- 第四段失败，原版错误信息未区分连接、响应或解析阶段，因此不能反推第一次失败原因。
- 未完成全程转写和纪要验收；前三段一致不能证明长会议讲话人身份稳定。

复测报告：`meeting-speech-persistent-diagnostic-2026-10-06.json`。

- 增加不含音频、认证信息或模型原文的阶段诊断。
- 第一段即在 parse 阶段失败：模型输出不是有效 JSON。
- 这次失败不是凭据缺失或无法建立连接；已取得响应后才解析失败。
- 未保存模型原文，因此不判断具体是自然语言、格式包裹还是截断。

## 结论

常驻连接的协议机制可行，但当前模型输出契约不稳定，尚不能作为正式会议模式。复用连接并不等于稳定转写或可靠讲话人区分。正式功能继续使用已存在的分段流程和片段暂定标签，不自动将跨片段编号认作同一人。

下一步先验证当前模型/端点是否提供并真正执行结构化输出约束；如没有，再单独评估输出格式归一化。不得以忽略解析错误或自动重试后只保留成功样本来声称验收通过。格式稳定之后，再做多轮声线一致性及真人线下会议验收。

## 自动测试

本轮新增工具最终参数、逐轮回执、无额外 response 和只初始化一次音频格式测试；共 13 项自动测试通过。

执行 `node --test macos-native/scripts/tests/meeting-persistent.test.mjs macos-native/scripts/tests/meeting-pi-audio.test.mjs`。

覆盖同一连接连续请求、每轮输出独立、错误后不静默重连沿用身份，以及既有 Pi 音频协议测试。这些是协议回归测试，不能替代真实模型质量验收。

## 后续结构化输出实验

核实官方 [客户端事件](https://help.aliyun.com/en/model-studio/client-events) 与 [服务端事件](https://help.aliyun.com/en/model-studio/server-events)：文档没有列出 `response_format` / `tool_choice` 强制参数；列出了 Function Calling，工具是否调用由模型决定。这不是端点绝对不支持结构化输出的证明，但本轮不使用没有文档依据的强制参数。

### 固定指令与低随机性

只在首次连接配置 PCM 格式，后续更新指令和 temperature=0；初始化即使用转写指令，不先设置通用对话角色。报告 `meeting-speech-persistent-lowtemp-2026-10-06.json`：前两段成功，第三段仍返回无效 JSON。此组合没有通过格式稳定性验收。

### Function Calling

仅实验模式 `--context --tool` 暴露 `submit_meeting_transcript` 工具，要求模型用参数提交当前片段转写。等待 `response.done` 完成后取最终工具参数，不消费增量参数；提交接收回执，不额外触发回答。工具参数仍交给原始转写校验器，不补写内容、时间或身份。

- `meeting-speech-persistent-tool-2026-10-06.json`：前三段成功，第四段响应阶段失败，旧诊断未记录具体原因。
- `meeting-speech-persistent-tool-recheck-2026-10-06.json`：第一段成功，第二段明确未调用转写工具，实验拒绝将普通回复当作工具参数。
- 两次均未完成 81.28 秒全程验收，没有以重试掩盖失败。

结论：Function Calling 已能实际返回部分转写，但当前端点上并非可靠的强制输出通道。降低随机性和注册工具都未根治问题；实验不升级为正式功能。

下一项建议是分离“转写文字”和“结构化标签”：先观察并保留模型真实输出的文本，再在 Pi 内做结构化整理，保留原文并验证整理后没有增删发言。讲话人不确定时不补身份。该方案尚未实施，不代表已经解决长期讲话人一致性。
