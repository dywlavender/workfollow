# 会议本地录音与复测

用户试录反馈：断句不合理、长句识别不准确。本轮先保留可回放的音频和相同识别输入，通过实际样本对照后再决定识别参数。

## 本地保存

- 每次开始/继续录音创建一组文件，原始麦克风音频保存为 CAF，保持设备实际采样率及声道；转码后的 ASR 输入保存为 16kHz、单声道、PCM16 WAV。
- 所在目录：`~/Library/Application Support/WorkFollowNativePreview/modules/meeting-audio/<会议ID>/`。隔离验收版按各自的数据目录保存。
- 录音停止后等待文件队列排空、关闭文件，再完成元数据保存。“录音文件”按钮可在 Finder 查看；可使用系统播放器回放。
- 音频写入使用独立 utility 队列，录音回调复制采样。转写断流、失败或发送积压时暂停转写，原始录音及后续转写输入继续保存。
- Pi 未连接时允许仅录音。已有会议仍可读取，新的文件路径及模型记录保存在原会议的 `audio` 字段中。
- 删除会议文字记录暂时不会删除磁盘上的音频文件。

## 复测方法

先回听原始 CAF 与对应 WAV，检查声音是否连续、长句是否完整、音量是否正常，并核对两者时长。之后对同一个 WAV 按原速重放，经 Pi 保留草稿修订、句子起止时间及最终文字。

```sh
node macos-native/scripts/probe-meeting-recording.mjs --audio /absolute/path/recording-asr.wav --report /private/tmp/meeting-vad.json
node macos-native/scripts/probe-meeting-recording.mjs --audio /absolute/path/recording-asr.wav --report /private/tmp/meeting-semantic.json --semantic
```

生产配置仍使用 800ms VAD 静音断句。复测可使用 `--silence-ms 1200` 或 `--semantic` 对照；复测参数不会改写应用设置。

对照重点：

1. 原始音频本身是否缺词或不清楚。
2. WAV 与原始录音是否有明显差异；保存的 WAV 是否与送入 Pi 的采样一致。
3. 同一音频在静音断句和语义断句下是否被切成不同句子。
4. 长句草稿何时开始出错，最终文字是否修正或进一步出错。

参考：[官方断句参数](https://help.aliyun.com/zh/model-studio/qwen-audio-asr-streaming-client-events)。语义断句和静音断句需要用用户的同一份实际录音比较，文档说明不代替实际准确率测试。

## 验证

Xcode 27 构建成功，60 项会议 XCTest、30 项 Node 测试全部通过，无跳过。自动化验证原始立体声采样、停止尾段、转写失败后的持续保存、录音引用持久化，以及 WAV 与实际输送的 PCM 一致。文件时长以已成功写入帧数计算，避免 `AVAudioFile.length` 在文件尚未关闭时读到缓冲区之前的较短长度。

WAV 复测工具经已安装 Pi 与本地协议服务验证：音频字节保持一致，语义/静音参数被传入，报告保留中间修订和最终句子时间。

现已取得“新会议123”的 4 分 13.5 秒音视频播放样本，完成同一 WAV 的静音断句、语义断句和完整文件讲话人分离对照。语义开关未显示明显断句改善，文件模型返回讲话人编号但内容也有缺失及差异；没有正确原文，不能报告识别错误率，也没有声称已修复准确率。详见 [实际样本复测](meeting-recording-diagnostics-2026-10-13.md)。

新构建：`/private/tmp/wf-meeting-local-recording-build/Build/Products/Debug/WorkFollow.app`。使用该构建重试后，保存开始生效；此前仅内存处理的录音不能恢复成文件。

自动化复现：

```sh
MEETING_PI_INTEGRATION=1 WORKFOLLOW_DERIVED_DATA=/private/tmp/wf-meeting-local-recording-build WORKFOLLOW_DISABLE_SWIFT_SANDBOX=1 macos-native/scripts/run-tests.sh MeetingRecordingFileTests MeetingModelConfigurationTests MeetingStreamingTests MeetingStoreTests MeetingMemoryAudioTests MeetingPiBridgeIntegrationTests MeetingPiOwnershipTests MeetingAudioTransportTests MeetingAudioLedgerTests MeetingCaptureSequenceTests MeetingSpeechTurnTrackerTests MeetingSpeechTurnStoreWiringTests

node --test macos-native/scripts/tests/meeting-recording-replay.test.mjs macos-native/scripts/tests/meeting-asr-stream.test.mjs macos-native/scripts/tests/meeting-stream.test.mjs macos-native/scripts/tests/meeting-http.test.mjs macos-native/scripts/tests/meeting-pi-audio.test.mjs
```
