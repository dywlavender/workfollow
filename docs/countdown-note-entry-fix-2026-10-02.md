# 倒数纪念日：编辑器里那个「备注」入口是猜的 —— 改回图标选择器

日期：2026-10-02
范围：`Features/Countdown/CountdownEditorView.swift`（只动这一个文件）
基线：`891b9b3`
前置：`docs/countdown-declared-vs-actual-2026-10-02.md`（#6 备注）、
`docs/countdown-a-batch-2026-10-02.md`（A 批）
参照图：`docs/screenshots/ticktick-reference/07-`…`19-`

---

## 一句话结论

用户指出「编辑页面里多了一个备注按钮，滴答上没有」。查证属实，而且比这更糟：
那个按钮**在参照图里是图标选择器**，我们把它猜成了备注开关，于是
① 面板上凭空多出一行备注；② 真正的图标选择器从来没被实现。

已修复并真机验证；顺带把两个待定项（#2 显示、#6 备注）的参照证据补齐。

---

## 用户指出的是什么

> 「现在编辑页面中多了一个备注的按钮，我看滴答上是没有的」

代码里是这一处（`CountdownEditorView.swift:376`，修复前）：

```swift
// 参考图里输入框右端有个小方块图标按钮。它对应的行为在图上不可见，
// 这里接成「备注」的展开开关——否则整页没有写备注的入口。
Button {
    noteExpanded.toggle()
} label: { Image(systemName: "note.text") ... }
.help("备注")
.accessibilityLabel("备注")
```

配套的还有：`@State noteExpanded`（初值 = 已有备注非空）、`noteField`（两行文本框）、
body 里的 `if noteExpanded { noteField }`，以及 `submit()` 里的 `original.note = note`。

**注释写得很诚实**——「它对应的行为在图上不可见」。问题不在诚实，在**猜了之后没有回头查**：
一个猜出来的行为，被当成了对齐结果留在了面板上。

---

## 参照实现实际是什么

真机点开那个按钮（`AXButton @913,325 26x26`），出来的是一个**图标选择器**：

```
旅行 / 演唱会 / 发工资 / 交房租 / 信用卡还款 / 房贷还款 / 保险缴费 /
定期体检 / 宠物体检 / 驾驶证到期 / 签证到期 / 考试 / 开学      ← 13 条，每条带图标
```

见 `16-countdown-icon-picker.png`。按钮本身的图形是**书签里嵌一颗星**。

同时确认：**滴答的添加/编辑面板里根本没有备注行**。面板行是

```
名称（右端：图标按钮）
日期 / 提醒 / 重复 / 类型 / 显示        ← 倒数日、纪念日两种类型完全一样
```

备注只有一个入口：**卡片菜单 → 备注 → 独立模态框**
（`13-countdown-note-panel.png`：标题 = 卡片图标 + 记录名，一个占满的大文本框，
占位「记录点什么…」，底部 取消/保存）。

---

## 改了什么

一个文件，四处：

1. **删掉面板里的备注入口**：`noteExpanded` / `noteField` / body 里那一行条件渲染。
2. **`submit()` 不再写 `original.note`**（原来写的是本地面板状态）。
   这一步是**必须**的：面板里已经没有备注入口，若照旧赋值，用编辑器改一次名字
   就会把卡片菜单写进去的备注抹掉。
   `store.add(...)` 的 `note:` 参数有默认值 `""`，新建路径直接省掉。
3. **那个按钮改回图标选择器**：`Button { symbolPickerOpen.toggle() }` +
   `.popover { symbolPicker }`，网格取自已有的 `CountdownEvent.symbolOptions`（12 个符号）。
4. 无障碍标签从 `"备注"` 改成 `"图标"`——标签本身也是「声明」，写错了等于继续骗下一个读代码的人。

### 两处取舍（不是对齐）

| 项 | 参照实现 | 我们 | 为什么 |
| --- | --- | --- | --- |
| 按钮图形 | 书签 + 星 | `bookmark`（无星） | SF Symbols **没有** `bookmark.star` / `bookmark.star.fill`（逐个查过 `NSImage(systemSymbolName:)`），取形状最接近的 |
| 选择器内容 | 13 条**带名字的预设场景** | 12 个 SF Symbol 网格 | 我们的域模型只存一个符号名（`symbol`），**没有「预设场景」这个概念**。要真对齐得先加一个预设类型 + 13 条映射，本轮不做 |

颜色仍在卡片菜单的「样式」里改；面板里的选择器只挑图标，与参照图「点一下换个图标」的用法一致。

---

## 验证

### 构建

主工作树**当时编译不过**，但报错不在我改的文件里：

```
WorkFollow/Features/Tasks/TaskList/TaskListView.swift:1076:21:
  error: type '()' cannot conform to 'View'
```

那是**另一个会话的在途改动**（`git status` 里 `TaskListView.swift` 是 `M`，
还有 `TaskViewBuilder.swift` / `TaskViewPreferences.swift` 等未跟踪文件）。没有动它。

改用**隔离 worktree** 验证：`git worktree add --detach /tmp/wf-verify-notefix 891b9b3`，
只把改过的 `CountdownEditorView.swift` 拷进去 → **BUILD SUCCEEDED**。

### 真机三项（应用从隔离构建启动，pid 19009）

| # | 验的是什么 | 怎么验的 | 结果 |
| --- | --- | --- | --- |
| 1 | 面板里没有备注行 | 读添加面板与编辑面板的 AX 树 | 行只有 `日期 / 提醒 / 重复 / 类型 / 显示`；`docs/screenshots/countdown-note-entry-fix-2026-10-02/01-add-panel-no-note-row.png`、`03-edit-panel-no-note-row.png` |
| 2 | 那个按钮开的是图标选择器 | 点 `AXButton desc="图标" @920,323` | 弹出 `AXPopover`，12 个符号按钮（heart / gift / hourglass / flag / star / bell / party.popper / birthday.cake / airplane / graduationcap / cross.case / house）；`02-icon-picker-popover.png` |
| 3 | **编辑不会抹掉备注** | 卡片菜单给「春节」写备注 → 落盘确认 → 打开「编辑」→ 点「确定」→ 再读盘 | 写盘后 `note='备注保留测试ZZZ'`；编辑保存后**仍是** `note='备注保留测试ZZZ'` |

第 3 项是这次最容易漏的回归：**只看「面板里没有备注行」会以为改完了**，
而真正的失败面是「编辑一次就把备注清了」——面板不显示备注，用户根本不会发现。

### 项目自带测试

在隔离 worktree 里跑（`scripts/run-tests.sh`，注意它**只认最后一个套件名**，要逐个跑）：

| 套件 | 结果 |
| --- | --- |
| `CountdownEventTests` | 51 / 51 通过 |
| `CountdownStoreTests` | 21 / 21 通过 |
| `CountdownReminderScheduleTests` | 9 / 9 通过 |

> **必须说清楚**：这三个套件**覆盖不到本次改动**。改的是 SwiftUI 视图里的
> 状态与提交路径，纯函数测试碰不到。上面第 3 项那种「编辑后备注还在不在」
> 只能真机验——这正是 `countdown-a-batch` 里那条教训的又一次应用：
> **纯函数单测盖不住状态机与视图接线。**

---

## 数据卫生

本次为了补齐两个待定项的参照证据，**在滴答清单里临时建过一条记录**（用户已授权）：

- 建：名称 `审计临时-102`，日期 2026/10/2（当天），类型 倒数日，显示 默认；
  随后经卡片菜单写入备注 `有备注的样本XYZ`。
- 用：截「今天」清单的分组形态 + 卡片是否显示备注指示器。
- 删：卡片菜单 → 删除 → 确认「确认删除纪念日？」。
- 核：主页回到原来的 3 张卡（春节 / 小美 / 使用滴答清单），`grep 审计临时` = 0 处。

我们自己的数据：`~/Library/Application Support/WorkFollowNativePreview/modules/countdowns.json`
在验证前整目录备份，验证后按备份**逐字节还原**（`cmp` 报 IDENTICAL）。
与备份的差异**只有**我为验证故意写入的 `春节.note` 一个字段，已还原。
另一个会话的实例（pid 15088，`workfollow-arrowless-derived`）**没有动**。

---

## 没做 / 没验的

- **图标选择器只是符号网格**，不是参照实现的 13 条预设场景。要做真对齐需要新增一个预设类型。
- **参照实现的添加流程是两步**：第一步是基本行（图标+名称 / 日期 / 提醒 / 重复 / 类型 /
  显示，共六项，按钮是「取消 / 下一步」），第二步才是「样式」（预览卡 + 卡片样式缩略图 +
  颜色，按钮是「返回 / 保存」）。我们是**单步**面板，样式另挂在卡片菜单里。
  这一条**没有动**，也没判定是不是该补。
- **勘误（2026-10-02 复核）：本节早先写的「第一步多一行『天数计算方式：标准』」是错的。**
  已逐张核对参照图与参照物语言包：
  `11-countdown-add-dialog.png` 与 `14-countdown-add-jinianri.png` 的「添加」面板都只有
  上面那六项，**没有**「天数计算方式」这一行。语言包里 `day_calculation` = `天数计算\n方式`
  配的是 `day_calculation_standard` = `标准`、`day_calculation_standard_desc` =
  `当天显示为今天，次日为第一天`、`day_calculation_standard_1` = `标准+1天`——
  那是**任务「日期」面板**的字符串（开始/结束时间 + 天数计算方式），
  被误读成了倒数纪念日添加面板的一行。同一节下面那句「参照的行比我们少」方向才对。
  **结论：这一项不存在，不必补。**
- 面板高度：删掉备注行之后面板从 523pt 变成 467pt（`AXSheet @526,229 460x467`）。
  这个数值变化**没有**和参照图逐项比对过——参照图的面板是 460×448，两者差 19pt。
  行数已核对（参照六项；我们删掉备注行后也是六项，生日再多一行「显示岁数」），
  所以**这 19pt 的来源仍未查明**，不要按「参照行少」去解释它。
- **本次没有任何单元测试覆盖**（原因见上）。

---

## 顺带确认的卡片渲染细节（备查）

真机观察到的、之前没记录过的：

- **倒计时为 0 天时**，卡片大数字位置显示「**今天**」，副标题只写日期、**不带**「还有/已经」
  （`19-countdown-card-with-note-no-indicator.png`）。
- **卡片悬停时副标题会换成已过形态**：`距离 2026/10/3 还有` → `距离 2026/8/8 已经 55 天`。
  非悬停态看不到。
- **删除确认框的文案是「确认删除纪念日？」**——不管这条记录是倒数日还是纪念日，
  用的是模块名。我们这边的文案是另一套，未比对。
