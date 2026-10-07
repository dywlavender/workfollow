# Pi HTTP ASR 接入验收

## 接入范围

- 内置扩展识别 `qwen-audio-3.1-asr-flash`，通过 Pi 的当前模型注册表获取端点、认证和 headers。
- Native 只采集内存 PCM，经 Pi RPC 发 `/wf-meeting-audio`；HTTP、内存 WAV 封装和讲话人区分参数都在 Pi 扩展内。
- 原实时模型保留 WebSocket 路径。自定义扩展保持原有入口，不擅自替换。
- HTTP 录音使用现有 contextual 分段：满 10 秒后等待静音边界，连续讲话最多 20 秒；停止补发尾段，等待队列 drain。
- HTTP 启动预检查只验证 Pi 模型、认证及端点配置，不发送音频，不代表服务可达或额度有效。真实请求错误明确显示，不伪造空成功。
- speaker_id 映射为带片段前缀的匿名标签，不保证跨片段身份一致。没有编号时显示未区分。
- 不保存音频，不自动生成纪要。ASR 模型不能生成纪要，手动编辑保留；手动请求生成时返回明确能力限制。

## 本机验收结果

- Xcode `TEST BUILD SUCCEEDED`；49 个会议 XCTest 全部通过，无跳过。
- 22 个 Node 测试通过，包括正式扩展 HTTP 请求结构、内存 WAV、错误、模型分流及原 WebSocket 回归。
- Native→本机真实 Pi→正式扩展的 HTTP 测试替身：完整段、停止尾段都落入原会议；切换选择不串记录；停止后解除忙状态；不自动生成纪要。
- 真实模型测试使用内存合成双人语音，不使用麦克风。源码正式扩展与最新 App 包内正式扩展各运行一次：29.094375 秒完整输入，分别约 1.78 秒和 2.15 秒返回。归一化文字与合成内容一致，片段内交替讲话人主标签一致。
- 报告：`meeting-http-production-probe-2026-10-07.json`、`meeting-http-bundled-probe-2026-10-07.json`。生产协议不包含句子结束时间，报告中的 end_time 由下一句开始推算，只用于测试范围匹配，不是服务原始结束时间。
- 回归暴露并修复旧会话收尾关闭新会话的问题：finisher 按会话 token 检查归属，迟到的 idle/settled 状态按 transport 实例检查归属。
- `git diff --check` 通过。

## 未覆盖及限制

- 本轮未执行真实麦克风录音、现场多人远距离/重叠讲话验收；不能将合成语音结果称为真实会议最终 PASS。
- HTTP 为完整片段请求，并非持续输入实时输出；上述返回耗时不包含录音凑段时间。
- 音频失败自动修复/Repair Buffer 不在本轮范围内，不能承诺绝不遗漏。
- 应用设置须明确填写 HTTP ASR 模型标识；留空的 Native 默认路径仍按 Pi 实时模型处理。

接口依据：[百炼 HTTP ASR 文档](https://help.aliyun.com/zh/model-studio/fun-asr-flash-recorded-speech-recognition-http-api)。
