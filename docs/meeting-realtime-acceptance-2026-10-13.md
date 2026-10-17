# 会议实时转写验收记录

## 实现结果

- 新增专用 Streaming ASR 协议；Pi 常驻连接按 250ms 采集包接收音频，经二进制 PCM 送至百炼。
- 按 `sentence_id` 将中间/最终结果映射到现有草稿和定稿。停止发送 `finish-task`，等 `task-finished` 后结束；未定稿句子不会被当成成功收尾。
- 转写模型和纪要模型独立配置，旧内置 HTTP 配置迁移到同 provider 的 Streaming 模型；显式 HTTP 选择和自定义扩展仍可使用。
- 设置页实机确认转写模型为 `qwen-audio-3.1-asr-flash-streaming`，纪要模型留空使用 Pi 当前文字模型。
- 补回生成/更新纪要入口。原实现关闭了自动生成，却没有保留手动按钮，旧占位提示仍宣称自动更新；本轮一起修正。

## 自动化

- 28 项 Node 测试通过，无跳过。包含专用 ASR 二进制输入、中间结果原位修正、尾段收齐、真实 Pi 进程加载新协议，以及已有 HTTP/Omni 回归。
- 56 项会议 XCTest 通过，无跳过。包含旧配置读取、分别传给 Pi 的模型、定稿归属、内存音频、停止尾段和已安装 Pi 的本地 fixture 集成。
- Xcode 27 测试构建成功，新资源已进入 App 包。
- 测试宿主新增 App 资源链接，使测试实际读取内置扩展和纪要规则。两个旧 HTTP 测试改为显式选择 HTTP；原“空扩展不可录音”测试改为验证内置扩展及持久化，避免让自动化测试触发真实麦克风授权。

## 实际服务

使用最新 App 包内的扩展，经真实 Pi 上传虚构合成语音；按实际音频速度发送，没有使用麦克风或保存音频。

- 输入：10.335125 秒。
- 首条非空中间结果：494ms。
- 停止到收到停止 ACK：120ms。
- 讲话结束前已有草稿；收到最终文字并正常收尾。
- 延迟起点是会话就绪，**不包含连接准备、麦克风采集和 UI 绘制**。

原始报告：[meeting-realtime-service-2026-10-13.json](meeting-realtime-service-2026-10-13.json)。脚本保留了非零退出结果，不能称为所有验收通过。

准确率检查：严格文本比对未通过。模型将“同意”识别为“通义”，将“两千五百”输出为“2500”；后者是数字格式差异，前者是真实识别错误。没有用成功重跑替换或删掉这个结果。

## 界面与实际纪要

隔离验收版使用 `/private/tmp/wf-meeting-realtime-preview/data` 的虚构会议记录；不读取用户真实会议。

实际点击“生成纪要”，经 Pi 当前文字模型 `AgentRouter-Pi/deepseek-v4-flash` 生成结果；界面出现纪要，已处理两条定稿，复制按钮可用，未有新增定稿时更新按钮禁用。纪要保留“下周一”期限，未猜测校对者姓名，标为身份待确认。

该项使用手工准备的虚构定稿文字，单独验证 Native 界面到 Pi 文字模型的调用，不是麦克风到纪要的完整现场测试。证据：[meeting-realtime-ui-2026-10-13.json](meeting-realtime-ui-2026-10-13.json)。补回按钮后重新构建并再次执行 56 项会议 XCTest，全部通过。

## 复现

```sh
node --test macos-native/scripts/tests/meeting-asr-stream.test.mjs macos-native/scripts/tests/meeting-stream.test.mjs macos-native/scripts/tests/meeting-http.test.mjs macos-native/scripts/tests/meeting-pi-audio.test.mjs

MEETING_PI_INTEGRATION=1 WORKFOLLOW_DERIVED_DATA=/private/tmp/wf-meeting-realtime-build WORKFOLLOW_DISABLE_SWIFT_SANDBOX=1 macos-native/scripts/run-tests.sh MeetingModelConfigurationTests MeetingStreamingTests MeetingStoreTests MeetingMemoryAudioTests MeetingPiBridgeIntegrationTests MeetingPiOwnershipTests MeetingAudioTransportTests MeetingAudioLedgerTests MeetingCaptureSequenceTests MeetingSpeechTurnTrackerTests MeetingSpeechTurnStoreWiringTests
```

真实服务脚本需要先编译 `macos-native/scripts/tests/MeetingSpeechFixture.swift` 及其引用的会议 Domain、Recorder、Transport、Ledger 到 `/private/tmp/wf-meeting-speech-fixture`；本机语音合成需正常访问系统语音服务。

```sh
WF_MEETING_MODEL=ali-Pi/qwen-audio-3.1-asr-flash-streaming MEETING_TEST_EXTENSION=/private/tmp/wf-meeting-realtime-build/Build/Products/Debug/WorkFollow.app/Contents/Resources/wf-meeting-stream.mjs node macos-native/scripts/accept-meeting-stream.mjs /private/tmp/meeting-realtime-recheck.json
```

## 尚未验收

真人麦克风到屏幕的 20～30 分钟现场录音、实际会议准确率和长时间延迟变化。实时转写显示“未区分”；本轮未增加说话人分离。
