---
name: workfollow-cli
description: 在本机 WorkFollow 原生 App 中查询、新建和修改待办与笔记，管理清单及分组；用户要求把内容保存进打勾、安排待办、维护笔记或整理清单和分组时使用。
---

# WorkFollow 原生 CLI

使用 `workfollowctl` 操作原生 App。旧 `workfollow` MCP 连接的是另一套后端数据；原生记录走本 CLI。

先查找 PATH 中的 `workfollowctl`，其次检查 `~/.local/bin/workfollowctl`，或使用已安装 WorkFollow.app 的 `Contents/MacOS/workfollowctl`。运行 `--help` 获取命令，`status --json` 确认连接和工作区。工具会在需要时后台启动 App。

- 列表默认返回元数据。按关键词、清单或文件夹缩小范围，再按 ID `get` 读取需要的正文。
- 修改、追加、完成或恢复现有待办或笔记前，使用 `get` 返回的 `version`。遇到 `version_conflict` 重新读取，结合最新内容执行用户原意。只改分组也需要最新版本。
- 使用 `--json`，读取返回的 `ok`；只有 `ok=true` 才表示写入已保存。向用户提供实际返回的记录链接。
- 长正文写入 UTF-8 临时文件，再用 `--content-file`；`--content-file -` 接收标准输入。正文按纯文本保存，Markdown 标记会保持字面形式。追加保留已有段落格式。
- `--date` 是安排日期，`--due` 是独立的截止日期；支持 YYYY-MM-DD 和带时区 ISO8601。优先级为 none、low、medium、high。
- 先通过 `list list` / `note folders` 查询已有分类。`list list` 包含归档清单，可用 `--archived false` 缩小范围；`task lists` 只返回可用清单名称。待办、笔记新建默认进入“收集箱”或“未归档”。
- 层级为 `group`（侧边栏清单分组）→ `list`（清单）→ `section`（清单内任务分组）→ 待办。`note --folder` 是笔记文件夹，与 `group` 不同。
- `group list` / `group get --name` 查询清单分组；用 `group create`、`rename`、`dissolve` 管理。`list create`、`rename`、`move`、`archive`、`unarchive`、`delete` 管理清单。改名使用 `--name OLD --to NEW`；移动清单使用 `--group NAME` 或 `--clear-group`。
- 用 `section list --list NAME` 获取分组 ID；`section create --list NAME --title TEXT` 新建分组；`section get`、`rename`、`move`、`delete` 使用 `--id`。移动分组会带走其中的任务和子任务。
- 新建/修改待办传 `--list NAME --section ID` 可指定归属，分组必须属于该清单。只换清单会清除旧分组；`task update --clear-section` 移到未分组；`task list --section ID` 按分组查询。
- 修改分类前先读取对应 `list get`、`group get` 或 `section get`；分类管理按名称或分组 ID 操作，不使用待办的 `version`。用户要求新分类时先创建，再放入记录；归档清单需先恢复才能新增任务或修改任务分组。
- 删除清单会把任务移回收集箱；解散 `group` 保留清单并移回顶层；删除 `section` 保留任务并移到未分组。它们均沿用 App 的撤销和保存流程。

示例：

```sh
workfollowctl task add --title "整理周会纪要" --priority high --json
workfollowctl note create --title "周会纪要" --content-file /tmp/minutes.txt --json
workfollowctl note get --id RECORD_ID --json
workfollowctl note append --id RECORD_ID --version VERSION --content-file /tmp/addition.txt --json
workfollowctl group create --name "工作" --json
workfollowctl list create --name "项目 A" --group "工作" --json
workfollowctl section create --list "项目 A" --title "待处理" --json
workfollowctl task add --title "确认需求" --list "项目 A" --section SECTION_ID --priority high --json
```
