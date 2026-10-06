# 会议语音验收：短对话通过项与未通过项

## 方法

本机 AVSpeechSynthesizer 在内存生成 Tingting / Eddy 两种中文声线，A→B→A→B，27.094 秒。台词全为虚构，含周五→下周一、3000→2500 元、清单/校对分工。转换复用 Native 的 MeetingPCMCapture；音频不写文件。音频及纪要请求均通过真实安装 Pi 和内置扩展，使用现有 Qwen 配置。

这不是两名真人的线下会议，也没有覆盖 3～5 分钟长会议、噪声、重叠讲话或网络中断。

## 实测结果

| 项目 | 原固定15秒 | 改进切段 | 连续音频讲话人探测 |
|---|---|---|---|
| 字错率（去标点，数字统一） | 0 | 0 | 0 |
| 词语边界 | “下周 / 一提交”断裂 | 未切断“下周一” | 无固定分段 |
| 最终期限 / 预算 | 正确 | 正确 | 正确 |
| 讲话人 | 两种声线却出现第三标签 | 本次片段内未多出标签 | 两种声线仍出现第三标签，失败 |
| 跨片段身份 | 未验收 | 未验收 | 此探测不覆盖跨片段 |

改进切段为 0～10.67、10.67～20.67、20.67～27.09 秒，单段模型请求约 1.35 / 1.20 / 1.09 秒（不含录音等待）。并非所有句子都在同一段，但不再把本例的“下周一”切断。总体字错率为零不代表断句、时间戳或身份准确。

## 已实施修正

- 采集改为约 10 秒后寻找 300ms 低能量停顿；持续讲话/背景噪声没有停顿时约 20 秒强制分段。仍不是常驻流式连接。
- 使用原生累计器跑合成 PCM，保证新策略与生产代码一致。增加停顿切段、最大时长和字节不丢失测试。
- 强化“轮次不等于讲话人、相同声音复用标签”的提示；连续音频探测证明 **仅靠该提示仍不足**。
- 标签显示为“片段…·暂定讲话人…”。纪要完整保留片段标签，不合并身份；仅凭暂定标签不能确定行动项负责人。
- 短片段通过不等于整场讲话人稳定，继续保持未通过状态。

## 证据

最终最新代码 build-for-testing 成功，16 项 Swift 测试和10项 Node 协议测试全部通过。真实模型的连续音频讲话人探测按预期记录为失败，未混入自动测试通过数量。所有模型请求经过 Pi；没有采集真人麦克风或保存音频。

- [固定分段报告](meeting-speech-acceptance-2026-10-06.json)
- [原生静音边界分段报告](meeting-speech-acceptance-improved-2026-10-06.json)
- [连续音频讲话人失败报告](meeting-speech-speaker-probe-2026-10-06.json)

报告仅文字，历史报告中的标签来自当时模型结果，未为了“通过”重写。固定分段报告的时间范围检查不代表“无幻觉”；改进脚本已将其准确命名为 timestampsWithinAudio。改进报告的短片段标签检查不证明同一人重复讲话；连续音频探测已揭示这个缺口。

## 后续

1. Pi 常驻音频会话与上下文的对照实验，先比较同样 A→B→A→B 的身份稳定性，再决定是否替换应用生命周期。模型连接仍在 Pi 内。
2. 若常驻上下文仍失败，评估 Pi 扩展内部的可靠讲话人识别能力/其他音频模型；不能用界面编号伪装声纹识别。
3. 两名真人 3～5 分钟线下测试仍需实际参会者配合；不自动开启麦克风上传。

## 复现

```sh
xcrun swiftc -parse-as-library -swift-version 5 -module-cache-path /private/tmp/wf-meeting-speech-cache macos-native/WorkFollow/Domain/Meeting/Meeting.swift macos-native/WorkFollow/Infrastructure/Meeting/MeetingRecorder.swift macos-native/scripts/tests/MeetingSpeechFixture.swift -o /private/tmp/wf-meeting-speech-fixture
node macos-native/scripts/accept-meeting-speech.mjs /private/tmp/meeting-speech-report.json
```

`--fixed` 保留旧策略；`--single` 为连续音频讲话人探测。后二者是实验，不修改生产分段。命令会将虚构语音发往 Pi 配置的模型。
