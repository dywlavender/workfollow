# 弹层宽度审计（2026-10-24）

> 范围：本应用所有**浮层/弹层**——anchored 属性面板、菜单、选择器、Sheet、对话框。
> 不含主窗口内的固定栏（侧栏 / 详情栏宽度另有约束）。
>
> **结论：确实有一批偏宽，而且集中在"菜单"与"Sheet"两类，不是普遍问题。**
> 属性类面板（标签/关联/属性）反而偏紧，余量只有 1~16pt。

---

## 1. 量测方法

不是靠肉眼，也不是靠估算字符串宽度（估出来和真实布局差 10~20%）。做法是**真渲染 + 像素扫描**：

1. 用真实数据构造每个弹层（最长的清单名、最长的菜单文案、最长的日期串）；
2. 按**当前给定宽度**渲染进离屏 `NSWindow`，等布局稳定；
3. `cacheDisplay` 成位图，取**出现次数最多的颜色**作背景（众数；取角落会被按钮/分隔线压住，第一版就是这么量出一片 0 的）；
4. 从右往左逐列扫描，找出最右的**非背景像素** = 内容真实右缘；
5. `余量 = 给定宽度 − 墨迹右缘`。

判读口径：

| 余量 | 判定 | 含义 |
|---|---|---|
| > 60pt | **偏宽** | 右侧一片空白，肉眼可见 |
| 4 ~ 60pt | 合适 | 留白是呼吸感 |
| < 4pt | 偏紧 | 文案一长就截断/换行 |

量测代码：`macos-native/WorkFollowTests/PopupWidthInventoryTests.swift`
（跑 `-only-testing:WorkFollowTests/PopupWidthInventoryTests`，输出 `INV|...` 行）。

---

## 2. 总盘结果

15 个弹层，**4 个偏宽、4 个偏紧、7 个合适**。

| 弹层 | 宽度来源 | 给定 | 内容右缘 | 余量 | 判定 |
|---|---|---|---|---|---|
| 标签编辑 Sheet | 字面量 420 | 420 | 260 | **160** | **偏宽** |
| 清单动态 Sheet | 字面量 360 | 360 | 256 | **104** | **偏宽** |
| 排序选项 | 字面量 264 | 264 | 188 | **76** | **偏宽** |
| 任务类型菜单 | `taskMenuWidth` | 176 | 108 | **68** | **偏宽** |
| 笔记信息 | `noteInfoWidth` | 220 | 163 | 57 | 合适 |
| 更多操作菜单 | `taskActionsWidth` | 208 | 152 | 56 | 合适 |
| 同步/提醒事项状态 | `syncStatusWidth` | 340 | 304 | 36 | 合适 |
| 清单图标 | 6×26+5×10+2×lg | 238 | 218 | 20 | 合适 |
| 模板说明 | 字面量 380 | 380 | 362 | 18 | 合适 |
| 关联任务/笔记 | `relationPickerWidth` | 320 | 304 | 16 | 合适 |
| 清单颜色 | 7×22+6×10+2×lg | 246 | 230 | 16 | 合适 |
| 快速添加属性 | `quickAddPropertiesWidth` | 270 | 258 | 12 | 合适 |
| 预计专注 | `focusEstimateWidth` | 280 | 279 | **1** | 偏紧 |
| 移动到分组 | 字面量 230 | 230 | 229 | **1** | 偏紧 |
| 标签选择 | `tagPickerWidth` | 264 | 263 | **1** | 偏紧 |
| 关联主任务 | `parentPickerWidth` | 280 | 279 | **1** | 偏紧 |

> 「其余」说明：`预计专注`/`移动到分组`/`标签选择`/`关联主任务` 的墨迹贴到边，
> 是因为它们内部有**撑满宽度的底部分隔线或滚动条**，不是文字真的顶边。
> 所以这 4 个"偏紧"应读作"**宽度刚好，没有可压缩空间**"——想再窄就得动布局。

---

## 3. 逐项分析

### 3.1 真正偏宽的四个

**① 标签编辑 Sheet：420 → 内容只用到 260，浪费 160pt**

`TaskTagEditorView.swift:74` `.frame(width: 420)`。内容是一列「名称 / 颜色 / 图标」表单，
最长一行是 `名称` + 一个文本输入。420 是照搬"macOS 设置窗口"的通用宽度，但这个表单只有
单列、没有分栏。

**建议**：降到 **320**（仍留 60pt 呼吸），或改成 `.frame(minWidth: 280, idealWidth: 320)`。

**② 清单动态 Sheet：360 → 内容 256，浪费 104pt**

`ListActivitySheet.swift:76` `.frame(width: 360, height: 420)`。内容是时间线列表，
每行是「时间 + 动作 + 任务名」，最长行约 250pt。

**建议**：**300**。高度 420 保留（列表要能滚）。

**③ 排序选项：264 → 内容 188，浪费 76pt**

来源是字面量 `264`（`AdvancedFilterRuleEditor.swift:59` 与 `:122` 各有一处）。
排序文案最长「按创建时间排序」约 120pt + 图标 + 内边距 = 188。

**建议**：提到 `PopupMetrics` 里当常量，值改 **208**。

**④ 任务类型菜单：176 → 内容 108，浪费 68pt**

`PopupMetrics.taskMenuWidth = 176`，只有三项（文本 / 清单 / 笔记），最长「文本文档」约
100pt。这个常量还被 **8 处**引用（优先级菜单、任务类型菜单、三级菜单等），
其中优先级菜单确实需要更宽（「优先级」+ 4 个选项 + 旗子）。

**建议**：**拆成两个常量**——`taskMenuWidth`（176→**144**，给类型/时间这类短菜单）
和 `priorityMenuWidth`（保持 176）。现在一个常量背两种用途，导致短菜单被长菜单拖着走。

### 3.2 相对滴答的位置

滴答同类弹层的实测宽度（NIBArchive 解析，`otool`/`parse_nibarchive.py`）：

| 滴答弹层 | nib 实测宽 | 本地对应 | 本地宽 | 差 |
|---|---|---|---|---|
| `TTTaskMenuViewController`（任务菜单） | **194** | 更多操作菜单 | 208 | +14 |
| `TTMenuViewController`（主菜单） | **352** | 业务菜单 | 224 | −128 |
| `TTDatePickerViewController`（日期选择） | **216** | 日期面板 | 260 | +44 |
| `TTSortOptionPickerViewController`（排序） | **192** | 排序选项 | 264 | **+72** |
| `TTPopupMutiSectionPickerVC`（多段选择） | **194** | — | — | — |
| `TTColorPickerViewController`（颜色） | **232** | 清单颜色 | 246 | +14 |
| `TTEmojiPickerViewController`（表情） | 398 | 清单图标 | 238 | −160 |
| `TTTaskStickyThemePickerViewController`（便签主题） | **256** | — | — | — |

两条可用的校准结论：

- **菜单普遍是 190~200pt 起步**，本地 224 的通用菜单宽了约 25pt，而 `taskMenuWidth=176`
  在滴答那套里其实**偏窄**——但本地菜单项更短，176 反而还有 68pt 富余。
- **排序选择滴答是 192，本地 264 宽了 72pt**，和上面 §3.1③ 的结论互相印证。

### 3.3 偏紧的四个（不是 bug，是"没有余量"）

| 弹层 | 结论 |
|---|---|
| 标签选择 264 | 搜索框 + 「新建标签」按钮刚好铺满；想再窄要把按钮改成图标 |
| 关联主任务 280 | 列表行是「标题 + 清单名」两行，标题截断阈值正好卡在这 |
| 移动到分组 230 | 与 `TaskContextMenuPopover` 的分组子菜单同宽，一致性好，**不建议改** |
| 预计专注 280 | 分段控件（时长/番茄数）+ 数值框 + Stepper，正好一行 |

---

## 4. 优化建议（按收益排序）

| # | 改动 | 现值 → 建议 | 收益 |
|---|---|---|---|
| 1 | 标签编辑 Sheet | 420 → **320** | 少 100pt 空白，最显眼的一处 |
| 2 | 拆 `taskMenuWidth` | 176 → **144**（新增 `priorityMenuWidth: 176`） | 影响 8 处调用里的短菜单 |
| 3 | 排序选项 | 264 → **208**（并入 `PopupMetrics`） | 对齐滴答 192 的量级 |
| 4 | 清单动态 Sheet | 360 → **300** | 少 60pt 空白 |
| 5 | `syncStatusWidth` 340 | **保持** | 那段"已写入仅表示…"中文说明需要宽度，压了会换三行 |

**不建议动的**：清单颜色/图标（由内容推导，改网格数才有意义）、日期面板 260（滴答 216，
但本地多了时间段与重复结束两块，压窄会换行）、业务菜单 224（滴答 352 更宽，本地已经算收着）。

---

## 5. 一处结构性问题（比数字更重要）

`PopupMetrics` 里 25 个常量，其中 6 个名字带 `Width` 却混装了两种语义：

- **由内容决定的**（菜单行高 × 列数、网格列宽推导）：`7*22+6*10+2*lg` 这类，写在用它的视图里；
- **全局口径的**：`menuWidth` / `taskMenuWidth` / `tagPickerWidth`…

而且**有 10 处弹层宽度是裸字面量**（420×2 / 380 / 360×2 / 264×2 / 250×3 / 230×2 / 240 / 190），
分布在 `TaskTagEditorView` / `SettingsDataView` / `ListActivitySheet` / `TaskManagementViews` /
`AdvancedFilterRuleEditor` / `QuickAddPropertiesPopover` / `MoveTargetPickerCard` /
`TaskListView` / `TemplateEducationView` / `CountdownEditorView` / `FocusOverviewPane`，
不在 `PopupMetrics` 里，改口径时容易漏。建议：

1. 所有弹层宽度常量收进 `PopupMetrics`（哪怕值不变）；
2. 命名带上用途：`*MenuWidth` / `*SheetWidth` / `*PickerWidth`，而不是都叫 `*Width`；
3. 给 `AnchoredPropertyPanel` 加一个 `maxWidth` 兜底，防止未来再出现 420 这种照抄值。

---

## 6. 复现

```bash
cd macos-native
xcodebuild -scheme WorkFollow -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:WorkFollowTests/PopupWidthInventoryTests test 2>&1 | grep '^INV|'
```

输出格式：`INV|名称|宽度来源|给定|内容右缘|余量|高度|判定`。


---

## 7. 实施结果（2026-10-24 同日）

### 7.1 已改的宽度

| 弹层 | 原值 | 现值 | 改后余量 | 判定 |
|---|---|---|---|---|
| 标签编辑 Sheet | 420 | **320** | 18 | 合适 |
| 清单动态 Sheet | 360 | **300** | 1 | 已到下限定（列表行会撑满） |
| 排序选项 | 264 | **208** | 48 | 合适 |
| 任务类型菜单 | 176 | **144** | 52 | 合适 |
| 每日目标 | 190 | **160** | 56 | 合适 |

新增常量（都进了 `PopupMetrics`，不再有裸字面量）：

```
taskMenuWidth        176 → 144    短菜单（任务类型）
priorityMenuWidth           176   新拆分，优先级菜单专用
sortOptionWidth             208   排序/筛选选项（原裸字面量 264）
settingsSheetWidth          320   标签编辑 Sheet（原裸字面量 420）
activitySheetWidth          300   清单动态 Sheet（原裸字面量 360）
templateNoteWidth           380   模板说明（原裸字面量 380）
rhythmPopoverWidth          360   Focus 节奏（原裸字面量）
goalPopoverWidth            160   Focus 每日目标（原裸字面量 190）
symbolPickerWidth           240   图标选择（原裸字面量）
```

`taskMenuWidth` 的拆分是本轮的结构性修正：它原来被 8 处引用，其中 2 处
（详情优先级菜单、快速组合器优先级菜单）实际需要 176，其余是短菜单。
**一个常量背两种用途**，导致短菜单被拖着多出 68pt 空白。

### 7.2 补漏：第一轮没覆盖到的浮层

第一轮只覆盖了属性面板与菜单。第二轮补测了 Sheet / 编辑器 / 网格类：

| 浮层 | 宽度 | 墨迹 | 余量 | 结论 |
|---|---|---|---|---|
| 筛选器编辑 Sheet | 520 | 519 | 1 | **保持**——表单行内 `maxWidth: .infinity` 撑满，是真实的宽度需求 |
| 任务新建面板 | 360 | 336 | 24 | 合适 |
| 快速添加·清单候选 | 250 | 208 | 42 | 合适 |
| 标签颜色网格 | 220 | 216 | 4 | **保持**——7×22 + 6×10 = 214 的网格加内边距刚好放下，再窄会挤 |
| 图标选择 | 240 | 220 | 20 | 合适 |

两处「看起来可以再收」但**实测不能动**的：

- **筛选器编辑 520**：表单型的宽度由控件撑，收窄会让条件行换行；
- **标签颜色网格 220**：色板网格的算术下限就在 234（214 + 20 内边距）附近，
  当前 220 已经很紧。

### 7.3 仍然存在的、未修改的项

| 项 | 现状 | 为什么不动 |
|---|---|---|
| 笔记信息 220（余 57） | 略宽 | 三行「字数/创建/修改」，日期列需要宽度；压到 180 会让 `2026/10/24 14:30` 贴边 |
| 同步状态 340（余 36） | 合适 | 那段"已写入仅表示…"中文说明需要宽度，压窄换三行 |
| 清单颜色 246 / 清单图标 238 | 合适 | 由网格列数推导，改列数才有意义 |
| 移动到分组 230 / 标签选择 264 / 关联主任务 280 / 预计专注 280 | 余量 1 | 内部有撑满的分隔线/滚动条，**宽度刚好**，不是偏宽 |
| 日期面板 260 | 滴答 216 | 本地多了时间段与重复结束两块，压到 216 会换行 |
| 业务菜单 224 | 滴答 352 | 本地已经比滴答收着三分之一，不必再收 |

### 7.4 覆盖度自查

应用内浮层构造点：`AnchoredPropertyPanel` 42 处、`BusinessMenu` 21 处、
`.sheet` 29 处、`NSPanel` 6 处，去重后是 **29 个不同弹层**，四轮全部覆盖：

| 轮次 | 测试类 | 覆盖 |
|---|---|---|
| 一 | `PopupWidthInventoryTests` | 15 个属性面板 / 菜单 / 选择器 |
| 二 | `PopupWidthCoverageTests` | 8 个 Sheet / 网格 / Focus 弹层 |
| 三 | `PopupWidthSecondPassTests` | 4 个表单 Sheet / 编辑器面板 |
| 四 | `PopupWidthThirdPassTests` | 3 个 `NSPanel` 直建窗 + Slash 菜单 |

第四轮量到三处「余量大但**不该改**」的，写清楚避免以后误改：

| 浮层 | 余量 | 为什么不动 |
|---|---|---|
| Mini 专注窗 300 | 94 | 真实视图是 `.frame(maxWidth: .infinity, maxHeight: .infinity)` **撑满窗口**——宽度由窗口决定，不是内容决定。余量是它自己居中的留白 |
| Slash 菜单 160 | 76 | `SlashMenuMetrics.width` 是**等宽口径**（14 槽 + 图标 + 11 隙 + 12 尾白）。菜单类刻意等宽，行短不代表能压 |
| 任务提醒弹窗 350 | 20 | 合适；内容是两个按钮 + 可换两行的标题 |

量测代码已进库，三条命令可复跑：

```bash
xcodebuild ... -only-testing:WorkFollowTests/PopupWidthInventoryTests test 2>&1 | grep '^INV|'
xcodebuild ... -only-testing:WorkFollowTests/PopupWidthCoverageTests test 2>&1 | grep '^COV'
xcodebuild ... -only-testing:WorkFollowTests/PopupWidthThirdPassTests test 2>&1 | grep '^COV3|'
```

判定规则统一是一条纯函数：`余量 > 60` 偏宽 / `4~60` 合适 / `< 4` 偏紧。
「撑满型」与「等宽型」按结构判读，不按数字判读——这两类的余量没有优化含义。

### 7.5 本次改动落在哪

代码随 `11182e1` 一起入库（那次提交同时含一个日期面板的对齐修复，
提交标题只写了后者）。为便于追溯，改动清单如下：

| 类型 | 文件 |
|---|---|
| 常量与规则 | `Infrastructure/Presentation/PopupMetrics.swift`（+10 常量、`taskMenuWidth` 拆分、`popupSlackWide/Tight` 阈值） |
| 宽度修正 | `TaskTagEditorView` 420→320、`ListActivitySheet` 360→300、`AdvancedFilterRuleEditor` 264→208、`TaskInspectorShell` 优先级菜单走新常量、`FocusOverviewPane` 190→160 |
| 裸字面量收编 | `CountdownEditorView`(240/350/360/380)、`FocusTimerPane`(360)、`FocusRecordEditor`(440)、`LinkHoverMenu`(226)、`TagCompletionPanel`(160)、`MoveTargetPickerCard`(230)、`QuickAddPropertiesPopover`(250×3)、`TaskNoteInfoPanel`(220)、`TemplateEducationView`(380)、`TaskListView`(230) |
| 量测代码 | `PopupWidthInventoryTests` / `PopupWidthCoverageTests`（含 SecondPass / ThirdPass 两个类） |

### 7.6 一处契约测试同步

`PopupStandardizationTests` 原先硬断言任务类型菜单宽 176，改为断言
`PopupMetrics.taskMenuWidth`（现在是 144）。这是**逻辑上的必然变更**：
宽度常量本身改了，契约测试应该跟着常量走，而不是钉死一个数字。
