# 倒数纪念日：真机走查问题清单（2026-10-02）

承接 `4a9e8ba`（统一浮层宽度）。这一轮把**除了已经验过的日期浮层之外**的边角
在真机上逐个走了一遍：页头菜单、卡片悬停条、卡片菜单、样式/备注 sheet、
归档→已归档→恢复→删除、类型胶囊、深色模式。

方法：真机运行 + AX 读 UI 树 + 合成事件操作 + 截图。证据图见
`docs/screenshots/countdown-audit-2026-10-02/`。

**用户数据未被改动。** 走查用了一条临时记录（`审计临时`）跑归档/恢复/删除，
结束后已删除；全程结束核对 `countdowns.json` 与开工前备份
**语义完全相等**（仅 JSON key 顺序不同，值一致）。

---

## 一、确定是缺陷

### D1. 已归档列表的副标题是残句，没有天数

- 位置：`Features/Countdown/CountdownEditorView.swift:1221`
- 现象：`已归档倒数纪念日` 里那一行，副标题显示 **`距离 2026/10/2 还有`** ——
  句子断在「还有」，后面的天数没了。
- 证据：`audit-archived-sheet.png`（AX 读到的字符串逐字相同）
- 复现：新建任意一条 → 卡片 `⋯` → 归档 → 页头 `⋯` → 已归档…
- 根因：`CountdownProjection.caption` 按设计**只是前缀**（`CountdownEvent.swift:592`
  的注释写明了：`距离 正月初一（2027/2/6）还有`）。卡片上是把它和
  `magnitudeRow` 的大数字**拼起来**读的（`CountdownWorkspaceView.swift:290,296`），
  所以单看没问题。归档行只渲染了 `caption`，没有那个数字伙伴，于是成了半句话。
- 影响：一句话说不完自己。这是「读起来是 bug」而不是「看起来是 bug」。

### D2. 卡片 tooltip 是同一个残句

- 位置：`Features/Countdown/CountdownWorkspaceView.swift:333` —— `.help(projection.caption)`
- 现象：鼠标停在卡片上，浮出的提示写 **`距离 2027/9/15 还有`**，同样没有天数。
- 证据：`audit-tooltip-caption.png`（卡片本体 `348` 与 tooltip 同框，对照明显）
- 根因：与 D1 同一处，caption 被单独拿去用了。
- 备注：tooltip 是**唯一**只给这句话的地方，没有数字在旁边兜底，所以比 D1 更明显。

> D1/D2 是同一个根因的两个落点。修法两种，取舍不同：
> ①给 `CountdownProjection` 加一个「完整句」属性（`caption + 天数`），两处改用它；
> ②两处各自把天数拼上。推荐 ①，因为拼法只有一处，以后不会再漏第三个落点。

### D3. 日期浮层的「取消/确定」与 sheet 的「取消/确定」同名

- 位置：`Features/Countdown/CountdownEditorView.swift:465`（`Button("取消")`）、
  `:468`（`Button("确定")`）
- 现象：日期浮层打开时，屏幕上**同时有两组「取消」「确定」**——浮层里一组
  （撤销/提交日期），sheet 底部一组（撤销/提交整条记录）。肉眼分不出哪组管什么。
- 证据：`audit-date-popup-create.png`（浅色）、`audit-date-popup-dark.png`（深色）
- 复现：新建/编辑 → 点日期行 → 看屏幕
- 关键点：作者**已经知道要区分**——两处的 `accessibilityLabel` 就是
  `取消日期` / `确定日期`（`:467`、`:478`）。也就是说区分只做给了读屏，
  没做给眼睛。把 `accessibilityLabel` 直接当可见文案用即可（或者浮层用
  「取消」「确定」以外的措辞）。
- 严重度：中。不是坏，是会点错——而点错的代价是丢掉刚选的日期。

### D4. 删除确认的按钮叫「确定」，不叫「删除」

- 位置：`Features/Tasks/TaskManagementViews.swift:17-21`（`TaskNamePrompt.confirm`）
- 现象：对话框正文写着 `删除"审计临时"？` / `删除后无法恢复。`，
  但确认按钮是 **`确定`**。
- 证据：`audit-delete-confirm.png`
- 复现：卡片 `⋯` → 删除；或已归档列表 → 删除
- 影响面：`TaskNamePrompt.confirm` 是**全应用共用**的，共 8 处调用
  （`SidebarViews.swift:190,309`、`CountdownWorkspaceView.swift:241`、
  `CountdownEditorView.swift:1229`、`TaskManagementViews.swift:171,293`、
  `TemplateManagementView.swift:89`、`TaskInspectorShell.swift:550`）。
  改这一个函数就全改了；同理，这个毛病现在也是全局的。
- 备注：破坏性动作的按钮不写动作名，是 macOS 上比较常见的一条批评。
  改法建议给 `confirm` 加一个 `confirmTitle:` 参数，默认仍是 `确定`，
  破坏性调用点传 `删除`/`移除`。

---

## 二、存疑（判不了，需要你或参照图定）

### Q1. 编辑 sheet 里出现了三套左边界

AX 实测（同一个 sheet 内）：

| 元素 | x | 宽 |
| --- | --- | --- |
| 备注输入框 | 574 | 364 |
| 名称输入框 | 628 | 268 |
| 属性字段（日期/提醒/重复/类型/显示） | 626 | 320 |

也就是说备注框比属性字段**两边各多出约 50pt**，一直顶到标签列的左边缘；
名称框又和属性字段差 2pt。视觉上是三条不同的竖线。
证据：`audit-edit-sheet-note.png`。

判不了的原因：这一轮手上**没有编辑面板的参照图**（`docs/screenshots/ticktick-reference/`
里 7 张全是任务/日历/四象限/摘要/专注/习惯/菜单栏，没有倒数纪念日）。
上一轮量卡片用的是聊天里给的图，没落盘。
所以「备注框满宽」可能是照抄、也可能是我方自由发挥。

### Q2. 卡片大数字不带单位「天」

- 现象：卡片显示 `小美 1岁 / 348 / 距离 2027/9/15 还有`，那个 `348` 后面**没有「天」**。
  而读屏标签是 `小美，1 岁，还有 348 天`。
- 位置：`Domain/Countdown/CountdownEvent.swift:666-667` —— `.day` 分支返回
  `unit: ""`（周/月分支都有单位）。看起来是有意的：句子里的「还有」已经在
  承担量词，数字就当纯数。
- 判不了的原因：同 Q1，没有参照图。`CountdownWorkspaceView.swift:295` 的注释提到
  「数字那簇 127px vs 我们 117px」，参照物那簇比我们的三位数宽 10px——
  10px（5pt）可能是一个小号「天」，也可能只是字体更宽。**证据不足以判定。**

---

## 三、只是取舍 / 已确认不是缺陷

### T1. 胶囊行没有「生日」——已按你的决定修掉（生日归「纪念日」）

页头胶囊是 `所有 / 纪念日 / 倒数日 / 节日`，**没有生日**。走查时实测一条生日记录
（小美）在 `纪念日`、`倒数日`、`节日` 下**都不出现**，只在 `所有` 下出现。

**2026-10-02 决定并已实施**：不加第 5 个胶囊，而是把生日归到「纪念日」下。
理由：纪念日和生日本来就是同一类——都是「某一天」的年度纪念，差别只在
生日多记一个出生年、卡片上多显示一个岁数。于是四个胶囊正好把四种
`CountdownKind` 分完，**不会有记录落在任何胶囊之外**。

改法：

| 文件 | 改动 |
| --- | --- |
| `CountdownWorkspaceView.swift:39` | `CountdownFilter.kind: CountdownKind?` → `kinds: Set<CountdownKind>?`；`.anniversary → [.anniversary, .birthday]` |
| `CountdownStore.swift:183` | `events(matching: CountdownKind?)` → `events(matching: Set<CountdownKind>?)` |
| `CountdownWorkspaceView.swift:190` | 调用点改传 `filter.kinds` |

加了一个不变量测试 `testEveryKindIsReachableFromExactlyOneChip`：每个类型
必须能被**恰好一个**胶囊收到。以后加新类型时忘了更新映射表会直接挂测试，
而不是等用户点了一圈发现少东西——生日当初就是这么漏的。

真机复核：`纪念日` → 小美（生日），`节日` → 春节，`倒数日` → 空，`所有` → 两条。
证据：`audit-filter-anniversary.png`、`audit-filter-all.png`。

### T2. 分段控件的选中态是品牌蓝

日期浮层的 `公历/农历` 选中态是 accent 蓝，参照图是中性白。
这是上一轮就披露过的**有意偏离**：全应用 `.tint(WFColors.accent)`，
若这里强行改成中性色，它会成为全应用唯一一个不跟随 tint 的控件。
维持现状。

### T3. 页头「更多」只有一项

`⋯` 里只有 `已归档…`。注释说参照图的「更多」内容不可见，只放了本页真需要的入口。
可以接受。

---

## 四、走查通过的部分（无发现）

- **页头 `+` 菜单**：纪念日 / 倒数日 / 生日 / 节日，顺序与文案正确
  （`audit-add-menu2.png`）。
- **卡片悬停条**：`置顶` + `⋯`，位置在卡片右上、不遮挡内容（`audit-hover-bar.png`）。
- **卡片菜单**：编辑 / 样式 / 备注 / 归档 / 删除，5 项齐全（`audit-card-menu2.png`）。
- **置顶**：点击后 `pinned=true` 且卡片移到最前，再点恢复原序。✓
- **样式 sheet**：6 色 + 12 图标 + 完成；选色/选图标即时落盘（`apply()` → `store.setStyle`），
  所以误点即写——这是设计，不是 bug，但意味着这个面板**没有取消语义**。
- **备注 sheet**：`取消` 不写盘（store 逐字未变）；`保存` 写盘且重开能读回；
  中文输入正常。✓
- **归档 / 已归档 / 恢复 / 删除**：四步全通。归档写 `archivedAt` 时间戳
  （不是 `archived` 布尔）；恢复清空它；删除有二次确认且真删。
  空态文案 `还没有已归档的纪念日` 正确。✓
- **类型胶囊**：节日→春节、所有→两条，过滤正确。✓
- **深色模式**：卡片页、编辑 sheet、日期浮层、设置页全部可读；
  浮层面板用 `fieldFill`（#3A3E47）与 sheet 底分开，层次成立；
  `忽略年份` 的勾选态是蓝底白勾，对比度够（`audit-countdown-dark.png`、
  `audit-date-popup-dark.png`）。**没有发现硬编码颜色**。

---

## 五、环境改动（已还原）

深色模式测试改了应用的「外观」偏好，**已还原**。

还原过程值得记一笔：应用的「外观」原值不在任何备份里，我是**推**出来的——
系统当前是深色（菜单栏为证），而走查前 21:36–00:11 的所有截图里应用都是浅色，
两者矛盾，只能是应用被显式设成了「浅色」。再用
`~/Library/Preferences/.GlobalPreferences.plist` 的 mtime（10-01 18:26，即日落时刻）
确认系统自 18:26 起就一直是深色、期间没切换过，推断成立。
最终 `defaults read com.workfollow.native.preview appearance` = `light`，
与走查前渲染一致。

如果你其实是想要「跟随系统」，在 设置 → 通用 → 外观 里切一下即可。

---

## 建议的处理顺序

1. **D1 + D2**（同一根因，一处修好两个落点）—— 改 `CountdownProjection`，
   加一个完整句属性。
2. **D3** —— 把已有的 `accessibilityLabel` 提为可见文案，成本极低。
3. **D4** —— 给 `TaskNamePrompt.confirm` 加 `confirmTitle:` 参数。
4. **Q1 / Q2** —— 等你给一张编辑面板的参照图（或直接定夺），否则只能维持现状。

**T1 已完成**：生日归「纪念日」，见上面 T1 节。
