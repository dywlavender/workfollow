# WorkFollow Native 实验

> 当前功能以 [功能迁移清单](../docs/native-feature-migration-status.md) 及各批验收记录为准。本文后半部分保留早期实验记录，其中的功能范围和测试数量不代表当前版本。

Native macOS 实验版本，不是 Flutter 的替代版本。要求 macOS 14+、支持同步文件组的 Xcode 16+；本轮使用 Xcode 26.6 编译。

## 日用版构建与更新

固定安装到 `/Applications/WorkFollow.app`，沿用标识 `com.workfollow.native.preview`，任务及模块数据继续位于 `~/Library/Application Support/WorkFollowNativePreview`。日用版使用 Release 配置，打包时移除验收配置，不包含测试插件。

先从 WorkFollow 菜单正常退出，等待保存完成，然后在仓库根目录运行：

```sh
python3 macos-native/scripts/local-app.py update
python3 macos-native/scripts/local-app.py status
```

更新前会验证新包，并保留一份上一版应用至 `~/Library/Application Support/WorkFollowNativeUpdates/previous/WorkFollow.app`。安装脚本不改任务数据；退出后可用下面的命令回退应用。跨数据格式版本的回退需要同时考虑升级前的数据备份，不能把旧程序直接当作数据恢复工具。

```sh
python3 macos-native/scripts/local-app.py rollback
```

只构建不安装：`python3 macos-native/scripts/local-app.py build`，输出到 `/private/tmp/workfollow-local-build/WorkFollow.app`。也可用 `--output` 指定位置，再用 `install <应用路径>` 安装。构建号默认取已安装版本加一，构建日志覆盖写入 `~/Library/Logs/WorkFollowNativeUpdates/build.log`，临时 DerivedData 自动清理。

当前机器没有可用签名证书，默认使用本机签名。固定应用标识和路径保留数据位置，但本机签名无法保证更新后沿用日历等隐私授权；系统可能再次询问。有可用证书后，构建或更新时传 `--signing-identity '证书名称'`，后续持续沿用同一身份。[Apple 对签名身份与隐私授权的说明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

安装流程验证：`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s macos-native/scripts/tests -p 'test_local_app.py'`。应用功能验证使用 `scripts/run-tests.sh` 指定相关测试类，避免为局部改动重复全量回归。

## 开发运行

用 Xcode 打开 `WorkFollow.xcodeproj`，选择 WorkFollow scheme / My Mac，Run。无需第三方依赖。

在仓库根目录也可运行：

```sh
xcodebuild -project macos-native/WorkFollow.xcodeproj -scheme WorkFollow -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/workfollow-native-build CODE_SIGNING_ALLOWED=NO build
codesign --force --deep --sign - --identifier com.workfollow.native.preview /private/tmp/workfollow-native-build/Build/Products/Debug/WorkFollow.app
codesign --verify --deep --strict /private/tmp/workfollow-native-build/Build/Products/Debug/WorkFollow.app
open /private/tmp/workfollow-native-build/Build/Products/Debug/WorkFollow.app
```

命令行关闭自动签名后，应先对完整应用包签名并校验，再独立启动。否则日历权限请求可能被系统归给启动它的开发工具，导致授权弹窗被阻止。日历授权成功后，设置页会显示“已允许完整访问”。

## 任务日常操作

- 提醒选项显示实际触发时刻，跨天时标明日期；任务详情显示提醒摘要，没有提醒时显示“未设提醒”。点击摘要可直接修改。
- 搜索优先显示已有任务和笔记，正文命中显示匹配片段。回车打开选中结果，`⌘Enter` 新建任务。
- 左侧云朵入口显示 Apple 任务同步状态，有异常时显示待处理数量，可重试、处理冲突或直达同步设置。“已写入”只确认 Mac 本地写入成功。
- 全局快速添加在本次应用运行期间保留未提交草稿，收起再打开可继续输入；成功提交或点击“清空草稿”后清除。
- 未选择任务时收起空详情区，列表使用更宽的阅读区域；选择任务后恢复分栏，返回列表时保留滚动位置。

## Apple 同步与 iPhone

在「设置 → Apple 同步」开启「同步任务到 Apple 提醒事项」，首次按系统提示允许访问；这项权限独立于日历。固定使用 iCloud 的 WorkFollow 清单，没有时自动创建。开启后自动同步所有未完成任务，包含未安排日期的任务以及以后新增的清单；已同步任务完成后保留完成记录，已归档或删除的任务不再同步。

任务同步只保留一个总开关和状态，不再选择账户、填写清单名称、选择来源清单或调整双向同步及通知方式。任务编辑栏和更多菜单不提供独立的 Apple 同步设置。旧版选择性同步在升级后先暂停，用户开启新总开关后才扩展至全部任务；关闭开关只暂停同步，已写入系统的任务仍保留。

任务不再额外写成日历日程。在 Apple 日历的日历列表勾选「计划的提醒事项」即可看到有日期的任务。无日期的任务只显示在提醒事项列表中。

独立提醒时间与安排日期不同时，Apple 的排期显示可能不同：本机实测安排在 10 月 29 日、独立提醒为 28 日的任务，Apple 提醒事项和日历显示在 28 日；项目仍保留原安排日期及提醒时间。

同一设置页的「在 WorkFollow 显示系统日程」仅用于读取系统日历中的会议、预约等日程。旧版任务日历关联保留供一次性清理：仅清理仍关联且未单独修改的副本，清理前保存可恢复内容，设置页支持「撤销副本清理」；独立修改或已取消关联的日程会保留。正常读取及任务编辑均不写入系统日历。本机声音、稍后提醒等设置单列在「本机通知」。

Mac 与 iPhone 使用同一 Apple 账户，并在两端的 iCloud 中开启「提醒事项」；手机需允许提醒事项通知。标题、安排日期、优先级和完成状态双向同步；WorkFollow 的时间提醒写入系统。Apple 提醒事项自身的“提前提醒”在本机实测无法从 EventKit 回读，不承诺回写。手机修改到达 Mac 后由运行中的 WorkFollow 回写，下次启动或返回前台也会核对。同一字段的双方修改在设置页处理冲突。

默认由 Apple 提醒事项负责已成功关联任务的到点提醒，WorkFollow 不重复响铃。手机已收到的提醒由系统执行，不依赖 WorkFollow 持续运行。「已写入提醒事项」只确认 Mac 本地写入，不能确认手机接收。

子任务平铺显示，富文本、附件、标签保留在 WorkFollow。按日期重复的任务预先同步未来 30 天的独立期次；按完成日期重复的下一期需 WorkFollow 收到完成状态后生成。独立截止日期放入说明，安排日期对应提醒事项的日期。提醒事项的全天通知时间和声音遵循系统设置。方案与验收范围见 [提醒事项同步](../docs/apple-reminders-integration-2026-10-20.md)。

## 弹框规范

根属性入口点击打开，子菜单使用悬停意图；面板锚定实际控件，按用途共用尺寸、操作栏、焦点和关闭规则。接入要求及本批验证范围见 [弹框规范实施计划](../docs/popup-standardization-plan-2026-10-22.md)。

业务下拉和业务右键菜单统一使用 `BusinessMenu` / `BusinessPicker`，包括选中标记、悬停、搜索、滚动和键盘操作；系统菜单栏、系统对话框、文本编辑系统菜单及分段控件保留原生。最新范围和验收结果见[业务菜单视觉统一](../docs/business-popup-visual-unification-2026-10-22.md)。

## 早期实验范围记录

- SwiftUI 图标栏、导航栏、Today / 收集箱 / 已完成任务列表和原生 Task Inspector。
- Task 列表由纯 Swift Domain、`TaskActions` 和 Projection 驱动；完成框独立于行选择，Quick Add 经动作层创建真实 Domain Task。
- Inspector 支持标题实时编辑、完成/恢复、安排日期与截止日期、优先级、固定清单选择和软删除；正文已接入 NSTextView 纯文本编辑。
- 正文支持原生撤销/重做及 ⌘F 查找；撤销历史按正文视图隔离，切换任务时重置。尚未实现格式、Slash、附件和持久化。
- 日期选择使用系统 Popover 和图形日期控件；优先级、清单和更多操作使用系统 Menu。
- ⌘N 聚焦新建、⌘K 快速打开、⌘, 设置、⌘1 今天、⌘2 收集箱。
- 跟随系统/浅色/深色；AppKit 保存窗口位置和尺寸。
- 列表宽度 340–470pt，受剩余 Inspector 最小 300pt 约束；紧凑窗口使用导航弹层和列表/详情切换。
- 日历与四象限已接业务：月/周网格（含跨天色带、今天圈、节假日角标）与固定 2×2 棋盘都由 Domain 投影驱动；点任务条/任务行弹出 **400×356** 的锚定编辑器，点「+」或双击某天弹出 **320×212** 的锚定新建卡。这两个浮层没有箭头、贴着被点元素，位置与尺寸按原版 `calculatePopoverGeometry` 逐点对齐（见 `Features/Planning/PlanningOverlay.swift` 与 `PlanningOverlayLayer.swift`）。浮层画在页面自己的叠层里，与原版同架构，因此键盘输入、焦点与嵌套日期面板的行为都与任务页一致。
- 笔记与两个垃圾桶仍是导航占位。

`TaskWorkspaceModel` 通过 `TaskActions` 操作 `WorkspaceStore`，列表来自 Domain 投影。首次启动无快照时载入示例任务；后续编辑同步原子保存至独立 `Application Support/WorkFollowNativePreview/workspace.json`，重启重载，读取失败会停止自动保存并提示。附件副本也存于该独立目录。不读取 Flutter 正式任务、笔记或附件。

## 会议实时转写

内置会议扩展使用 `qwen-audio-3.1-asr-flash-streaming` 持续转写；Pi 管理音频连接与认证。会议设置分别选择转写模型和纪要文字模型，纪要模型留空沿用 Pi 当前文字模型。点击“生成/更新纪要”只处理新增定稿，讲话人暂未区分。

录音保存在模块数据目录的 `meeting-audio/<会议ID>/`：原始麦克风音频为 CAF，转写输入为 16kHz 单声道 PCM16 WAV。停止后点击“录音文件”在 Finder 查看。转写连接失败或积压时仅暂停转写，本地录音继续；暂停/继续分别保存新文件。复测工具与验收见 [本地录音方案](../docs/meeting-local-recording-2026-10-13.md)。

在已有百炼 provider 注册实时模型：`node macos-native/scripts/register-meeting-asr.mjs --provider <名称> --apply`。旧内置 `qwen-audio-3.1-asr-flash` 配置读取时迁移到同 provider 的 Streaming 模型；如需继续使用 HTTP 分段转写，在新转写模型字段中明确选择旧模型。

实现及验证范围见 [实施计划](../docs/meeting-realtime-plan-2026-10-13.md) 和 [验收记录](../docs/meeting-realtime-acceptance-2026-10-13.md)。

后续范围与验收记录见 [迁移计划](../docs/native-migration-plan.md) 和 [行为基线](../docs/ticktick-parity-matrix.md)。

## Domain / Task List 与测试

`WorkFollow/Domain` 和 `WorkFollow/Application` 是独立纯 Swift 层。WorkFollowTests 覆盖核心动作、一级父子关系、列表/树投影、TaskWorkspaceModel 行为和键盘选择边界。

```sh
xcodebuild -project macos-native/WorkFollow.xcodeproj -scheme WorkFollow -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/workfollow-native-build CODE_SIGNING_ALLOWED=NO test
```

列表获得焦点时 ↑/↓ 切换任务，Return 打开首项或保持所选详情；Quick Add 输入焦点下不接管这些按键。Today Quick Add 设置当天真实 schedule，Inbox Quick Add 不预设日期。Phase 1 全尺寸拖动、窄屏返回和跨屏窗口恢复仍是 IMPLEMENTED / PARTIALLY VERIFIED。

提醒、重复、标签、附件、关联、Persistence、Notes 尚未接入完整业务；此实验数据不会写入 Flutter 正式数据。当前 401 项 XCTest 通过。正文中文多行粘贴、撤销/重做、查找、跨任务隔离已实机验证；中文输入法候选窗仍待专门实测。Phase 4 的日期 Popover、优先级/清单菜单、父子清单联动及完成/恢复已有验收记录；低于 641pt 紧凑布局阈值后的第二次 Escape、Popover 外部关闭和菜单键盘导航仍待实机验收。
