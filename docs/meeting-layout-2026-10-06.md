# 会议纪要页布局对齐（2026-10-06）

**起因**：用户反馈「会议纪要页面布局太丑了，和项目不符合」。

**结论**：不是审美问题，是这一页**另起了一套实现**。它用了系统 `List(.sidebar)`、
写死 220 的列宽、`.title3` / `.callout` 这类语义字号、散落的 12/16/20/24 间距——
而旁边每一页都在用 `WFType` / `WFSpace` / `WFMetrics` 这套角色。改法就是**换回项目自己的零件**。

---

## 1. 改前 vs 改后

| 元素 | 改前 | 改后 | 依据 |
| --- | --- | --- | --- |
| 列表列 | 系统 `List(.sidebar)`，自带一整块系统灰底 | `ScrollView` + `LazyVStack(spacing: 0)` | `NotesWorkspaceView` |
| 列宽 | 硬编码 `220` | `WFMetrics.listPreferred`（340），可拖 | 与任务列/笔记列**共用同一个值** |
| 列标题 | `.title3.weight(.semibold)` | `WFType.pageTitle`（19 semibold），行高 44 | `NotesWorkspaceView` |
| 新建按钮 | 裸 `Image(systemName: "plus")` | 28×28、白字、`WFColors.accent` 底、圆角 6 | `NotesWorkspaceView` |
| 列表行 | 系统行（行高/选中色/分割线都不同） | 上下 padding 11、最小高 50、选中 `WFColors.listSelection` 圆角 8 | `WFMetrics` + `WFColors` |
| 行分割线 | 无（系统 List 自己画） | `ListRowDivider`，画在行内底边、不占行距、选中行不画 | 与任务/笔记列**同一条线** |
| 分栏线 | 系统 `Divider()`，拖不动、深一档 | `Rectangle().fill(WFColors.border).frame(width: WFMetrics.divider)` + 拖拽 | `NotesWorkspaceView` |
| 详情工具行 | 无（正文顶上直接排按钮） | 44pt 工具行 + `Divider()` | 笔记检查器同高 |
| 详情标题 | `.title2.weight(.semibold)` | `WFType.detailTitle`（18 semibold） | `WFType` |
| 正文 | 系统默认（约 13） | `WFType.body`（14） | `WFType` |
| 空态 | 32pt `mic` + 两行字飘在大白底上 | 符号 `.largeTitle` + `WFType.body` + `WFType.supporting` + accent 按钮，居中 | `CountdownWorkspaceView`（同为 rail-only 目的地） |
| 设置入口 | 裸 `Button("Pi 接入设置")` 贴白条上 | 齿轮图标 + 文字 + 整行可点（导航行样式） | 本页新增，见 §3 |
| 间距 | 12 / 16 / 20 / 24 混用 | `WFSpace.*` | `WFSpace` |

## 2. 顺带改掉的三处「说不通」

1. **「补转写已保存录音」原来是一个常驻按钮，绝大多数时候是灰的。** 改成
   `store.audioConfigured && 有未转写分片` 时才出现——不能做的事就别占位置。
2. **纪要里的对话行原来是 `speaker · mm:ss` 一行同色同字号。** 说话人比时刻重要，
   拆成两级：说话人 `WFType.listMeta` + `secondaryText`，时刻 `WFType.caption` + `tertiaryText`。
   *（这是取舍，不是照抄；实测渲染后说话人/时刻都是 `(128,128,128)`，正文是 `(37,37,37)`，层级成立。）*
3. **`MeetingMinutesView` 的标题梯度是 `.title2` / `.headline` / `.subheadline` 混着来的**，
   与正文的默认字号连不成梯度。换成 `detailTitle` / `sectionSemibold` / `section`。

## 3. 刻意**没有**做的

- **没加搜索框**。笔记列表有，会议列表没有。这是功能不是布局，等用户提了再加。
- **没合并重复标题**。滚动纪要里 Markdown 的 `# 标题` 会和上面的可编辑标题重字
  （见 `04-after-minutes.png`）。那是模型输出的文档标题，**隐藏内容比重复显示更危险**，
  所以留着。
- **`.sheet` 没动**。项目里 `TaskListView` / `RootShellView` / `SidebarViews` / `SettingsDataView`
  都在用 `.sheet`，这是既有约定，不是这一页的问题。

## 4. 验收

- 构建：`xcodebuild ... OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'` → **BUILD SUCCEEDED**。
- 测试：**436 通过**，与改前一致，**未新增失败**。`MeetingStoreTests` 5/5 通过
  （`MeetingPiBridgeIntegrationTests` 按设计跳过，需 `MEETING_PI_INTEGRATION=1`）。
  剩余 3 个失败与本次无关，见 §5。
- 截图：`docs/screenshots/meeting-layout-2026-10-06/`（改前 / 改后空态 / 改后详情 /
  改后纪要档 / 上下对照 / 笔记页参照）。

## 5. 已知的既有失败（不是本次引入）

| 用例 | 原因 |
| --- | --- |
| `ArrowlessTaskPopupContractTests.testBusinessSourceDoesNotUseSystemPopover` | 断言业务源码里 `.popover(` 计数为 0，`TaskListView.swift` 有 1。**`git show HEAD:` 也是 1**，既有违反——而且这正是之前那颗白圆的成因 |
| `ArrowlessTaskPopupContractTests.testQuickAddAndTaskRowPropertiesKeepArrowlessPresentation` | 同一根因 |
| `NativeResourceLinkTests.testInspectorDuplicateEntryCreatesCopyAndClosesMenu` | `bundleProxyForCurrentProcess is nil`，`xcrun xctest` 宿主环境问题；且它 `Abort trap: 6` **会带走整轮**，排在后面的 suite 不会执行 |

## 6. 一个操作坑

**`WorkFollowAcceptanceStorageRoot` 每次重建都会被清掉。** 源 `WorkFollow-Info.plist` 里写的是
构建变量 `$(WF_ACCEPTANCE_STORAGE_ROOT)`，默认为空 → 构建产物的 Info.plist 里这个键是空的 →
应用会去读**用户的真实数据目录**。

所以「构建 → 用数据副本启动」这个流程里，**`PlistBuddy Set` 必须放在构建之后**，
或者干脆在构建时就传 `WF_ACCEPTANCE_STORAGE_ROOT=<目录>`。

2026-10-06 踩到：先 Set 再 rebuild，Set 被覆盖，应用读的是真实目录，截出来还是空态
（和改前那张逐字节相同），一度以为改动没生效。**真实数据没有被写入**（该目录下始终没有
`meetings.json`）。
