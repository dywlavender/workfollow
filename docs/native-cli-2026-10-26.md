# 原生 WorkFollow CLI

已在 `experiment/macos-native` 增加 `workfollowctl`，供 Codex 和终端操作当前原生 App 的待办、笔记。命令通过运行中的 App 执行业务动作并保存到本地 SQLite；App 未运行时会后台启动。

CLI 本身不调用模型，也不依赖旧 Python 后端。AI 理解用户意图后调用 CLI，所以执行这些命令不会额外产生模型服务费用。

## 安装与使用

新构建的 `WorkFollow.app` 已包含：

- `Contents/MacOS/workfollowctl`
- `Contents/Resources/Skills/workfollow-cli/SKILL.md`
- `Contents/Resources/Automation/install-native-cli.sh`

用户接入入口位于「帮助 → 新手引导 → 👋欢迎 → 探索更多 → 让 AI 操作任务和笔记」：

- **复制给 AI**：复制包含目标 Mac 上的 App 定位方式、Skill 目录、配置步骤和连接验证的通用说明，粘贴给能在目标机器执行命令的 AI 助手完成接入。
- **手动执行**：选择 WorkBuddy 或 Codex，复制显示的命令到终端执行，再按安装输出刷新技能或新建会话。

指引页面只展示和复制文本。手动命令使用 App 内置安装脚本，可以在没有开发仓库的 Mac 上使用；CLI 与 Skill 的快捷入口指向当前 App。既有欢迎清单会在升级时补入这条指引，保留完成状态。

复制文本中的 `$HOME`、`CODEX_HOME` 在目标 Mac 上解析，不写入生成说明时的用户名或构建路径。手动命令优先查找 `/Applications/WorkFollow.app` 与 `$HOME/Applications/WorkFollow.app`；放在其他位置时，先设置 `WORKFOLLOW_APP_PATH` 为目标机器的实际 `.app` 路径。App 内置安装脚本不传参数时会从脚本自身位置定位 App，仍支持显式传入 App 路径。找不到 App 或安装失败时会停止，不继续用已有 CLI 的状态掩盖失败。

先按 [日用版构建与更新](../macos-native/README.md#日用版构建与更新) 更新 App，再在仓库根目录执行：

```sh
macos-native/scripts/install-native-cli.sh /Applications/WorkFollow.app
~/.local/bin/workfollowctl status --json
~/.local/bin/workfollowctl --help
```

安装脚本把 CLI 链接到 `~/.local/bin/workfollowctl`，把 Skill 链接到 `${CODEX_HOME:-~/.codex}/skills/workfollow-cli`。已有普通文件会保留并提示换目录；脚本不会修改 shell 配置。将 `~/.local/bin` 加入 PATH 后可直接使用 `workfollowctl`。如需自定义安装位置，设置 `WORKFOLLOW_CLI_BIN_DIR`、`WORKFOLLOW_CLI_SKILL_DIR`。

让 Codex 重新加载技能后，可直接说“把这段内容保存为 WorkFollow 笔记”“安排明天下午的待办”。Skill 指导 Codex 查询分类、定位记录、读取版本并执行命令。仓库内的技能源文件位于 [.agents/skills/workfollow-cli/SKILL.md](../.agents/skills/workfollow-cli/SKILL.md)。

也可直接调用 App 内的 CLI；`--app PATH` 可指定另一份新版 App。首次接入先查看 `status` 返回的 `storageDirectory`，确认操作的是预期工作区。

## 命令范围

| 对象 | 命令 |
| --- | --- |
| 连接 | `status` |
| 待办 | `task add`、`list`、`lists`、`get`、`update`、`complete`、`reopen` |
| 笔记 | `note create`、`list`、`folders`、`get`、`update`、`append` |
| 清单 | `list list`、`get`、`create`、`rename`、`move`、`archive`、`unarchive`、`delete` |
| 侧边栏清单分组 | `group list`、`get`、`create`、`rename`、`dissolve` |
| 清单内任务分组 | `section list`、`get`、`create`、`rename`、`move`、`delete` |

```sh
workfollowctl task lists --json
workfollowctl task add --title "准备周会材料" --date 2026-10-27 --due 2026-10-28 --priority high --json
workfollowctl task list --query "周会" --completed false --limit 10 --json
workfollowctl task get --id TASK_ID --json
workfollowctl task complete --id TASK_ID --version VERSION --json

workfollowctl note folders --json
workfollowctl note create --title "周会纪要" --content-file /tmp/minutes.txt --json
workfollowctl note list --query "周会" --json
workfollowctl note get --id NOTE_ID --json
workfollowctl note append --id NOTE_ID --version VERSION --content-file /tmp/addition.txt --json
```

`TASK_ID`、`NOTE_ID` 使用实际返回的 `id`；`VERSION` 使用刚刚 `get` 返回的 `version`。更新、追加、完成和恢复都要求版本，记录已被编辑时返回 `version_conflict`，重新读取后再处理。

- `--date` 是安排日期，`--due` 是独立截止日期；支持 `YYYY-MM-DD` 或带时区的 ISO8601 时间。更新时可用 `--clear-date`、`--clear-due` 清除。
- 优先级为 `none`、`low`、`medium`、`high`。清单及笔记文件夹使用已有名称，默认分别为“收集箱”“未归档”。
- 列表支持关键词、分类及分页，默认 20 项，最多 100 项；只返回元数据，正文用 `get` 读取。
- 正文按纯文本写入，Markdown 标记保持字面形式。`update --content` 替换正文；`note append` 保留已有富文本段落，末尾追加纯文本段落。
- 长正文使用 UTF-8 文件；`--content-file -` 从标准输入读取。CLI 不会把正文当作 shell 命令执行，调用方仍需使用正常的 shell 引号或文件传参。

## 清单与两层分组

原生 App 的组织层级为“侧边栏分组 → 清单 → 清单内任务分组 → 待办”。CLI 分别使用 `group`、`list`、`section`，避免把两层分组混为一谈。笔记的 `--folder` 是独立的笔记文件夹。

```sh
workfollowctl group create --name "工作" --json
workfollowctl list create --name "项目 A" --group "工作" --json
workfollowctl section create --list "项目 A" --title "待处理" --json
workfollowctl section list --list "项目 A" --json
workfollowctl task add --title "确认需求" --list "项目 A" --section SECTION_ID --priority high --json

workfollowctl list list --group "工作" --archived false --json
workfollowctl list rename --name "项目 A" --to "客户项目" --json
workfollowctl group rename --name "工作" --to "公司" --json
workfollowctl section rename --id SECTION_ID --title "本周处理" --json
workfollowctl task list --section SECTION_ID --json

workfollowctl list move --name "客户项目" --clear-group --json
workfollowctl list move --name "客户项目" --group "公司" --json
workfollowctl list archive --name "客户项目" --json
workfollowctl list unarchive --name "客户项目" --json
```

`SECTION_ID` 使用 `section create` 或 `section list` 实际返回的 `id`，可以保留导入记录原有的字符串 ID。新建或修改待办的分组必须属于目标清单；换清单时需要同时传入目标 `--list` 和 `--section`，只传 `--list` 会清除旧分组。`task update --clear-section` 可移到未分组，仍须传入该任务的 `--id` 和最新 `--version`。返回的待办元数据增加 `group`、`sectionID`、`sectionTitle`。

`list list` 返回清单名称、所属分组、归档状态及任务/分组数量，支持分类、关键词和分页；默认包含归档清单。`task lists` 保持原有行为，只返回可用清单名称。分类修改先通过 `list get --name`、`group get --name`、`section get --id` 查询，再使用当前名称或分组 ID 执行；分类命令不使用待办、笔记的版本参数。同名分类会返回 `already_exists`。

- `list create --group` 使用已有侧边栏分组；空分组可先用 `group create` 创建。
- 重命名清单会同步更新所属任务及任务分组；重命名侧边栏分组会更新其中全部清单，包括归档清单。
- `section move --id ID --list NAME` 把任务分组、其中的任务和任务的子任务一起移到另一清单。
- `group dissolve --name NAME` 解散侧边栏分组，清单保留并移回顶层。
- `section delete --id ID` 删除任务分组，任务保留并移到未分组。
- `list delete --name NAME` 删除清单，把任务移回收集箱并清理其任务分组。重复任务模板同步更新，后续任务不会回到已移除的分类。
- 归档保留任务和组织关系；恢复后可继续新增任务、编辑任务分组。收集箱不支持上述清单管理和自定义分组操作。

新建待办并放入分组、同时修改待办多个字段、新建清单并放入侧边栏分组，各自都只占一条撤销记录。

`--json` 输出单行 JSON，默认输出缩进 JSON。待办与笔记的成功数据包含记录 ID、最新版本及打开链接；分类命令返回对应元数据或移除结果。写操作在 App 保存成功后才返回 `ok=true`。退出码为：成功 `0`、业务或连接失败 `1`、参数错误 `2`。默认等待 20 秒，`--timeout` 可调整到最多 120 秒。

## 实现

`WorkFollowCLI` 和 App 共用 `AutomationShared` 协议。CLI 原子写入工作区下的 `automation/requests`，通过系统分布式通知唤醒 App。App 的 `NativeAutomationBridge` 串行处理请求，调用现有 `TaskWorkspaceModel`、`NotesWorkspaceModel`，等待 `PersistenceCoordinator.flush` 完成，再写入响应。CLI 读取并清理响应。

主 App 继续负责数据写入、撤销和界面刷新。后台启动携带 `--automation`，不主动打开主窗口；新建待办、笔记或清单时保留当前选中项。CLI 不使用会停止会议录音的应用退出保存流程。

旧 `workfollow` MCP 仍指向另一套后端，不会自动切换到原生数据。当前原生接入使用本 CLI 和配套 Skill。

## 验证记录

2026-10-27，接入说明跨 Mac 路径修正：

- 复制给 AI 的文本和手动命令改为通用模板，账户目录与 App 位置在目标 Mac 执行时解析。原实现是在生成文本时读取所在机器的绝对路径；App 本身换机后会重新生成，但已复制的文本无法跨机器复用。
- 6 项 `AgentAccessGuideTests` 全部通过：同一段命令分别在两套不同 App 和用户目录中执行，覆盖 WorkBuddy、Codex；内置脚本不传 App 参数也能定位所属 App；缺少 App 时不写入配置；宽窄窗口的复制、切换与引导入口正常。
- 日志：`/private/tmp/workfollow-agent-guide-portability-20261027-tests.log`。测试使用临时安装目录，不改写 `HOME` 或本机 Agent 配置。

2026-10-27，新手接入指引：

- 新增 3 项 `AgentAccessGuideTests` 通过：宽窄窗口下复制说明、切换助手及复制命令；真实任务详情中的入口；复制 App 内置安装脚本到带空格的临时路径后，分别执行 WorkBuddy 和 Codex 命令，验证 CLI 与 Skill 的链接及状态返回。测试未修改本机 Agent 配置。
- 19 项欢迎引导、升级、入口与演示回归通过，新增说明会补入旧欢迎清单并保留完成状态。
- 日用版 0.2.0（36）已安装、启动并核对主程序和内置脚本与构建包一致。只读检查本地数据库确认“让 AI 操作任务和笔记”已保存到“👋欢迎”清单。旧应用与数据备份位于 `~/Library/Application Support/WorkFollowNativeUpdates/deploy-20261027-agent-guide36/`。
- 日志：`/private/tmp/workfollow-agent-guide-20261027-interaction-tests.log`、`/private/tmp/workfollow-agent-guide-20261027-final-tests.log`；构建包：`/private/tmp/workfollow-agent-guide-20261027-release/WorkFollow.app`。

2026-10-26，清单与分组补充批次：

- 51/51 项相关 XCTest 通过：`NativeAutomationTests` 8 项、`NativeAutomationOrganizationTests` 6 项、`ListMetaTests` 33 项、`MoveListSectionCarriesTasksTests` 2 项、`TaskKanbanRecurrenceConsistencyTests` 2 项。
- 隔离真实 App 的 15/15 项验收通过。除基础待办与笔记操作外，验证两层分组与清单的新建、改名、移动、归档/恢复、解散/删除，以及两次重启后的组织关系和移除结果。
- 分组搬移会带走子任务，归属变更同步更新重复任务模板；只改任务分组也会更新记录版本。删除清单清理其任务分组，避免残留归属。
- Skill 校验通过，构建包内的 Skill 与源文件一致，`git diff --check` 通过。

构建包：`/private/tmp/wf-native-cli-organization-20261026-build/Build/Products/Debug/WorkFollow.app`。验收报告：`/private/tmp/wf-native-cli-organization-20261026-acceptance.json`。测试日志：`/private/tmp/wf-native-cli-organization-20261026-tests.log`。未替换日用 App。

基础接入批次的记录：

- `NativeAutomationTests`：8/8 通过，覆盖参数、日期、修改与撤销、版本冲突、笔记追加、保存确认及后台启动策略。
- 隔离临时 App 的实际验收：8/8 通过。覆盖冷启动、待办新建/编辑/完成/恢复、多行中文文件写入、笔记追加、旧版本拒绝、查询，以及 App 重启后的数据保留。
- 安装脚本在临时目录验证通过；通过符号链接调用 CLI，可直接定位对应 App，`status` 成功。Skill 校验通过。
- 基础接入时的相关桌面回归共 37 项，36 项通过。`NativeResourceLinkTests.testInspectorDuplicateEntryCreatesCopyAndClosesMenu` 当时的菜单宽度断言失败：实际 176，预期 208。后续当前源码的预期为 176，AI 待办批次已重跑该测试类并通过；本次 CLI 工作未修改其菜单实现或该断言。

基础接入时的构建包：`/private/tmp/wf-native-cli-20261026-build/Build/Products/Debug/WorkFollow.app`。

实际验收报告：`/private/tmp/wf-native-cli-20261026-acceptance-desktop.json`。相关测试日志：`/private/tmp/wf-native-cli-20261026-desktop-tests.log`；最终 CLI 测试日志：`/private/tmp/wf-native-cli-20261026-packaged-tests.log`。

复现命令（仓库根目录）：

```sh
WORKFOLLOW_DERIVED_DATA=/private/tmp/wf-native-cli-build WORKFOLLOW_DISABLE_SWIFT_SANDBOX=1 macos-native/scripts/run-tests.sh NativeAutomationTests NativeAutomationOrganizationTests ListMetaTests MoveListSectionCarriesTasksTests TaskKanbanRecurrenceConsistencyTests
python3 macos-native/scripts/accept-native-cli.py --app /private/tmp/wf-native-cli-build/Build/Products/Debug/WorkFollow.app --report /private/tmp/wf-native-cli-acceptance.json
```

实际 App 验收使用独立应用标识和临时数据，退出的也仅为其自身测试进程；未操作用户已有待办与笔记。
