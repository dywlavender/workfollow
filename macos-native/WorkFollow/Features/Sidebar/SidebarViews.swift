import SwiftUI

struct IconRailView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    let onNavigate: (NativeDestination) -> Void
    let onOpenQuickOpen: () -> Void
    var sync: RemindersSyncCoordinator? = nil
    var onRetrySync: () -> Void = {}
    var onOpenSyncSettings: () -> Void = {}
    @Environment(\.openSettings) private var openSettings
    @Environment(\.mainWindowRailInset) private var mainWindowRailInset
    @FocusState private var focusedDestination: NativeDestination?
    @State private var focusRequest = UUID()
    @StateObject var tooltips = RailTooltipState()

    var body: some View {
        VStack(spacing: RailMetrics.itemGap) {
            // 图标一律用**实心**（`.fill`）符号，对齐滴答清单的图标风格（2026-10-03 第三轮）。
            //
            // 为什么不是描边：滴答的「选中态」就是**图标本体变成蓝色实心**，它背后
            // 没有任何底色块（实测选中蓝块 40x40px = 20pt，与旁边灰图标墨迹 42~44px 同量级）。
            // 我们原来抄了那块蓝色圆角底、却留着描边图标，于是蓝块读起来像一张贴上去的
            // 色块 —— 用户报「看起来很怪，图标不一样，为什么选中后的颜色图案和滴答一样」。
            // 现在把两头对齐到同一套语言：**图标实心，选中＝图标自己变蓝，不再有底块**。
            //
            // ⚠️ SF Symbols 的实心覆盖是**部分**的，下面 5 个是换过的（隐喻有变）：
            //   · 笔记  text.alignleft → text.document.fill（描边线条没有实心版）
            //   · 倒数  hourglass      → hourglass.bottomhalf.filled（保留沙漏，做成半实心）
            //   · 专注  timer          → timer.circle.fill（保留秒表，外面加实心圆）
            //   · 摘要  square.and.pencil → list.bullet.clipboard.fill
            //   · 日历  calendar.circle.fill → **自绘 glyph**（SF 没有实心 calendar 变体，
            //     circle.fill 是整列唯一圆底、小尺寸糊成一团，2026-10-07 用户报"丑"；
            //     见 `RailCalendarGlyph`，几何与 docs/design/calendar-rail-icon.svg 同源）
            // 另两个是原形直接加 `.fill`：任务 checkmark.square.fill、四象限 square.grid.2x2.fill。
            //
            // 底部「搜索 / 设置」保持描边：滴答自己的搜索也是描边放大镜。
            railButton(.today, symbol: "checkmark.square.fill", title: "任务",
                       selected: navigation.destination.isTaskList)
            railButton(.notes, symbol: "text.document.fill", title: "笔记",
                       selected: navigation.destination.isNotes)
            railButton(.calendar, symbol: "calendar.circle.fill", title: "日历",
                       selected: navigation.destination == .calendar)
            railButton(.matrix, symbol: "square.grid.2x2.fill", title: "四象限",
                       selected: navigation.destination == .matrix)
            railButton(.countdown, symbol: "hourglass.bottomhalf.filled", title: "倒数纪念日",
                       selected: navigation.destination == .countdown)
            railButton(.focus, symbol: "timer.circle.fill", title: "专注",
                       selected: navigation.destination == .focus)
            railButton(.meetings, symbol: "mic.fill", title: "会议纪要",
                       selected: navigation.destination == .meetings)
            Spacer()
            if let sync {
                AppleSyncStatusButton(integration: sync, onRetry: onRetrySync,
                    onOpenSettings: { onOpenSyncSettings(); openSettings() })
                    .railTooltip("Apple 同步", state: tooltips)
            }
            Button { tooltips.dismiss(); onOpenQuickOpen() } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: RailMetrics.iconSize))
                    .frame(width: RailMetrics.hitSize, height: RailMetrics.hitSize)
            }
            .railTooltip("快速打开（⌘K）", state: tooltips)
            .accessibilityLabel("快速打开")
            Button { tooltips.dismiss(); openSettings() } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: RailMetrics.iconSize))
                    .frame(width: RailMetrics.hitSize, height: RailMetrics.hitSize)
            }
            .railTooltip("设置（⌘,）", state: tooltips)
            .accessibilityLabel("设置")
        }
        .buttonStyle(.plain)
        .foregroundStyle(WFColors.secondaryText)
        .padding(.top, max(RailMetrics.topPadding, mainWindowRailInset))
        .padding(.bottom, RailMetrics.topPadding)
        .frame(width: RailMetrics.width)
        .background(WFColors.canvas)
        .coordinateSpace(name: RailTooltipOverlay.space)
        .overlay(alignment: .topLeading) { RailTooltipOverlay(state: tooltips) }
        // Draw across the rail boundary above the adjacent navigation column.
        .zIndex(1)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            tooltips.dismiss()
        }
        .onChange(of: navigation.destination) { _, _ in tooltips.dismiss() }
        .onDisappear { tooltips.dismiss() }
        .focusRenderAnchor(.rail)
    }

    private func railButton(_ destination: NativeDestination, symbol: String,
                            title: String, selected: Bool) -> some View {
        Button {
            activate(destination, eventType: NSApp.currentEvent?.type)
        } label: {
            railIcon(symbol, selected: selected)
                .foregroundStyle(selected ? WFColors.accent : WFColors.secondaryText)
                .frame(width: RailMetrics.hitSize, height: RailMetrics.hitSize)
                // Path.fill 的命中区域只是墨迹本身——日历 glyph 中间的镂空区
                // （2026-10-07 用户实测"点击没反应"）不吃点击。整个 hitSize
                // 方块声明为可点区，对 Image 图标也无害。
                .contentShape(Rectangle())
                .focusRenderAnchor(.railSelectedHitArea)
        }
        .focused($focusedDestination, equals: destination)
        .onKeyPress(.return) {
            activate(destination, eventType: .keyDown)
            return .handled
        }
        .railTooltip(title, state: tooltips)
        .accessibilityLabel(title)
        .guideTourAnchor("rail." + title)
    }

    /// 日历的实心 glyph 不存在于 SF Symbols（circle.fill 是整列唯一圆底，2026-10-07
    /// 用户报"丑"并两版否掉自创几何后，改用 Google Material Symbols `calendar_month`
    /// 的官方几何）。960 坐标系换算到 24 单位设计空间：本体 3..21、吊耳 2..4.8、
    /// 页眉白线 6..8、日期点阵 2×3（r=1，x 7/12/16，y 13/17）。镂空用 even-odd，
    /// 任意着色（含选中蓝）都成立。
    @ViewBuilder
    private func railIcon(_ symbol: String, selected: Bool) -> some View {
        if symbol == "calendar.circle.fill" {
            RailCalendarGlyph(selected: selected)
        } else {
            Image(systemName: symbol)
                .font(.system(size: RailMetrics.iconSize))
        }
    }

    private func activate(_ destination: NativeDestination, eventType: NSEvent.EventType?) {
        tooltips.dismiss()
        let keyboard = eventType == .keyDown || eventType == .keyUp
        let pointer = eventType == .leftMouseDown || eventType == .leftMouseUp
        let window = NSApp.currentEvent?.window ?? NSApp.keyWindow
        let request = UUID()
        focusRequest = request
        if keyboard { focusedDestination = nil }
        RailNavigationFocus.activate(eventType: eventType,
                                     window: window,
                                     clearRailFocus: { focusedDestination = nil },
                                     navigate: { onNavigate(destination) })
        guard keyboard || pointer else { return }
        // Navigation can rebuild the destination's key-view loop. Reapply
        // keyboard focus after that update; a later activation cancels it.
        DispatchQueue.main.async {
            guard focusRequest == request,
                  navigation.destination == destination else { return }
            if keyboard {
                focusedDestination = destination
            } else {
                focusedDestination = nil
                window?.makeFirstResponder(nil)
            }
        }
    }
}

/// 日历 rail 图标：Material Symbols「calendar_month」官方几何的 SwiftUI 原生实现
/// （用户选定 B 方案，2026-10-07）。用 Path even-odd 镂空——横线与日期点在任何
/// 着色（含选中蓝）下都成立；几何换算见 `railIcon` 注释，SVG 对照件在
/// docs/design/calendar-icon-candidates.svg。
private struct RailCalendarGlyph: View {
    let selected: Bool

    var body: some View {
        // 24 单位设计空间；墨迹高 20 单位（2..22），缩放到与 SF Symbol 21pt 同量级。
        let scale = RailMetrics.iconSize / 20
        let shell = Path { path in
            path.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 18),
                                cornerSize: CGSize(width: 2, height: 2))
            path.addRect(CGRect(x: 5, y: 10, width: 14, height: 10)) // 内腔镂空
            path.addRect(CGRect(x: 5, y: 6, width: 14, height: 2))   // 页眉白线镂空
            for y in [13.0, 17.0] {
                for x in [7.0, 12.0, 16.0] {
                    path.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                }
            }
        }
        let tabs = Path { path in
            path.addRoundedRect(in: CGRect(x: 6, y: 2, width: 2, height: 2.8),
                                cornerSize: CGSize(width: 0.7, height: 0.7))
            path.addRoundedRect(in: CGRect(x: 15, y: 2, width: 2, height: 2.8),
                                cornerSize: CGSize(width: 0.7, height: 0.7))
        }
        let color = selected ? WFColors.accent : WFColors.secondaryText
        return ZStack {
            shell.fill(color, style: FillStyle(eoFill: true))
            tabs.fill(color)
        }
        .frame(width: 24 * scale, height: 24 * scale)
        .frame(width: RailMetrics.hitSize, height: RailMetrics.hitSize)
    }
}

/// 侧栏分组头：38pt 行、行首折叠箭头、右侧悬停动作。
/// 箭头从容器 8pt 内边距处起画，标题落在 19pt（与滴答实测一致）。
struct SidebarSectionHeader<Trailing: View>: View {
    let title: String
    let collapsed: Bool
    let toggle: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 2) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WFColors.tertiaryText)
                        .frame(width: 9)
                    Text(title)
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText)
                    Spacer(minLength: 0)
                }
                .frame(height: NavigationMetrics.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title + (collapsed ? "，已收起" : "，已展开"))
            trailing
        }
        .padding(.trailing, WFSpace.sm)
        .frame(height: NavigationMetrics.rowHeight)
    }
}

/// 分组空态提示卡：滴答的整行灰底卡（文字两侧各 10pt）。
struct SidebarHintCard: View {
    let text: String
    var minHeight: CGFloat = 0

    var body: some View {
        Text(text)
            .font(WFType.supporting)
            .foregroundStyle(WFColors.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: minHeight, alignment: .leading)
            .background(WFColors.panelFill, in: RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 6)
    }
}

/// 分组间隔：分隔线上下各 10pt。整栏只在两处使用（清单前、已完成前）。
private struct SidebarGroupGap: View {
    var body: some View {
        Divider().padding(.vertical, 10)
    }
}

/// 对齐滴答清单的侧栏：整栏一个滚动列表，智能清单、三个可折叠分组和底部清单
/// 一起滚；分组头是列表里的普通行，不吸顶，也不画侧栏滚动条。
struct NavigationColumnView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    @EnvironmentObject private var environment: AppEnvironment
    /// Seam for the saved-filter group (Wave 1 F5): the shell passes the
    /// module's FilterStore here; when nil the section stays hidden.
    var filterStore: FilterStore? = nil
    var onNavigate: () -> Void = {}

    /// 智能清单顺序对齐滴答：所有 → 最近 7 天 → 今天 → 明天 → 收集箱。
    private let smartLists: [NativeDestination] = [.today, .tomorrow, .inbox, .allTasks, .nextSevenDays, .summary]
    private let bottomLists: [NativeDestination] = [.completed, .abandoned, .trash]

    private var destinations: [NativeDestination] {
        if navigation.destination.isNotes { return [.notes, .notesTrash] }
        if navigation.destination == .calendar { return [.calendar] }
        if navigation.destination == .matrix { return [.matrix] }
        if navigation.destination == .countdown { return [.countdown] }
        if navigation.destination == .focus { return [.focus] }
        if navigation.destination == .summary { return [.summary] }
        return NativeDestination.taskDestinations
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if navigation.destination.isTaskList {
                taskSidebar
            } else if navigation.destination.isNotes {
                NotesNavigationSection(notes: environment.notesWorkspace, navigation: navigation, onNavigate: onNavigate)
            } else {
                Text(navigation.destination.isNotes ? "笔记" : "工作空间")
                    .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                    .padding(.horizontal, WFSpace.sm).padding(.bottom, WFSpace.sm)
                ForEach(destinations) { destinationRow($0) }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, WFSpace.sm)
        .padding(.vertical, WFSpace.md)
        .frame(maxHeight: .infinity)
        .background(WFColors.content)
    }

    /// 滴答口径的单滚动列表：智能清单 → 32pt 间隔 → 清单/过滤器/标签 →
    /// 32pt 间隔 → 已完成/已放弃/垃圾桶。分组头随列表一起滚。
    private var taskSidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(visibleSmartLists) { destination in
                    if SmartListVisibility.isConfigurable(destination) {
                        destinationRow(destination)
                            .businessContextMenu(width: PopupMetrics.menuWidthNarrow) {
                                visibilityMenu(for: destination)
                            }
                    } else {
                        destinationRow(destination)
                    }
                }
                SidebarGroupGap()
                TaskCollectionsView(workspace: workspace, navigation: navigation, onNavigate: onNavigate,
                                    collapsed: isSectionCollapsed(.collections),
                                    onToggleSection: { toggleSection(.collections) })
                if let filterStore {
                    TaskFiltersSectionView(workspace: workspace, filterStore: filterStore,
                                           navigation: navigation, onNavigate: onNavigate,
                                           collapsed: isSectionCollapsed(.filters),
                                           onToggleSection: { toggleSection(.filters) })
                }
                TaskTagsSectionView(workspace: workspace, navigation: navigation, onNavigate: onNavigate,
                                    sectionCollapsed: isSectionCollapsed(.tags),
                                    onToggleSection: { toggleSection(.tags) },
                                    sectionVisibility: environment.viewPreferences.visibility(for: .tags),
                                    onSetSectionVisibility: {
                                        environment.viewPreferences.setVisibility($0, for: .tags)
                                    })
                SidebarGroupGap()
                ForEach(bottomLists) { destinationRow($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func isSectionCollapsed(_ section: SidebarSectionID) -> Bool {
        environment.viewPreferences.isSidebarSectionCollapsed(section)
    }

    private func toggleSection(_ section: SidebarSectionID) {
        environment.viewPreferences.setSidebarSectionCollapsed(section, !isSectionCollapsed(section))
    }

    /// 按"显示状态"过滤后的智能清单：隐藏 → 不出现；有内容时显示 → 未完成数为 0 时不出现。
    private var visibleSmartLists: [NativeDestination] {
        smartLists.filter { destination in
            environment.viewPreferences.visibility(for: destination)
                .shows(hasContent: workspace.count(for: destination) > 0)
        }
    }

    /// 智能清单行的右键：显示 / 隐藏 / 有内容时显示（收集箱除外，滴答不允许隐藏它）。
    @ViewBuilder
    private func visibilityMenu(for destination: NativeDestination) -> some View {
        BusinessMenuChoices(selection: Binding(
            get: { environment.viewPreferences.visibility(for: destination) },
            set: { environment.viewPreferences.setVisibility($0, for: destination) }),
            options: SmartListVisibility.menuOrder.map { BusinessChoice($0, $0.title) })
    }

    private func destinationRow(_ destination: NativeDestination) -> some View {
        Button {
            environment.navigate(to: destination)
            onNavigate()
        } label: {
            // 图标列与文字位置按滴答 AX 实测（2026-10-17）：图标框 22pt 起于行内 19pt，
            // 图标右缘到文字 6pt —— 得到图标 `@81`、文字 `@109`（行从 62 起）。
            HStack(spacing: 6) {
                Image(systemName: destination.symbol)
                    .font(.system(size: 16))
                    .frame(width: 22)
                Text(destination.title).lineLimit(1)
                Spacer(minLength: WFSpace.xs)
                let count = workspace.count(for: destination)
                if count > 0 {
                    Text("\(count)").font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText)
                }
            }
            .font(WFType.navigation)
            // 选中项的文字保持普通墨色（滴答实测：导航选中行只有灰底，字仍深色）。
            // 原来这里切 `accent`，是"当前所在页"的强调，用户要求跟滴答一样去掉蓝。
            .foregroundStyle(WFColors.text)
            // 左侧 11 + 容器 8 = 行内 19，与滴答图标起点一致；底色块宽度保持 196（滴答 195.5）。
            .padding(.leading, 11)
            .padding(.trailing, WFSpace.sm)
            .frame(height: NavigationMetrics.rowHeight)
            .contentShape(Rectangle())
            .rowHoverBackground(selected: navigation.destination == destination)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.title)
        .guideTourAnchor("nav." + destination.title)
    }
}

private struct NotesNavigationSection: View {
    @ObservedObject var notes: NotesWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    @EnvironmentObject private var environment: AppEnvironment
    var onNavigate: () -> Void
    /// 正在被笔记拖拽悬停的文件夹行（只影响描边高亮）。
    @State private var noteDropTarget: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("全部笔记", symbol: "text.alignleft", folder: nil)
            row("收藏", symbol: "star", folder: nil, favorites: true)
            row("未归档", symbol: "folder", folder: "未归档")
                .modifier(NoteFolderDropTarget(folder: "未归档", notes: notes, targeted: $noteDropTarget))
            HStack {
                Text("文件夹").font(WFType.supporting)
                Spacer()
                Button {
                    if let name = TaskNamePrompt.ask("新建文件夹") {
                        if notes.addFolder(name) { notes.folderFilter = name; notes.favoritesOnly = false; environment.navigate(to: .notes) }
                        else { TaskNamePrompt.invalidName() }
                    }
                } label: { Image(systemName: "plus") }.buttonStyle(.plain).hoverTip("新建文件夹")
            }.foregroundStyle(WFColors.secondaryText)
             .padding(.horizontal, WFSpace.sm).padding(.top, WFSpace.lg).padding(.bottom, WFSpace.sm)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(notes.folders, id: \.self) { folder in
                        row(folder, symbol: "folder", folder: folder)
                            .modifier(NoteFolderDropTarget(folder: folder, notes: notes, targeted: $noteDropTarget))
                            .businessContextMenu {
                                Button("重命名文件夹…") {
                                    if let name = TaskNamePrompt.ask("重命名文件夹", value: folder), name != folder,
                                       !notes.renameFolder(folder, to: name) { TaskNamePrompt.invalidName() }
                                }
                                Button("删除文件夹…") {
                                    if TaskNamePrompt.confirm("删除文件夹“\(folder)”？",
                                                              message: "其中的笔记会保留，并移到“未归档”。",
                                                              action: "删除") { notes.removeFolder(folder) }
                                }
                            }
                    }
                }
                .compactScrollbars()
            }
            Divider().padding(.vertical, WFSpace.xs)
            row("垃圾桶", symbol: "trash", folder: nil, trash: true)
        }
    }

    private func row(_ title: String, symbol: String, folder: String?, favorites: Bool = false, trash: Bool = false) -> some View {
        let selected = trash ? navigation.destination == .notesTrash :
            navigation.destination == .notes && notes.folderFilter == folder && notes.favoritesOnly == favorites
        let count = notes.rows(trash: trash, query: "", folder: folder, favorites: favorites).count
        return Button {
            notes.folderFilter = folder
            notes.favoritesOnly = favorites
            environment.navigate(to: trash ? .notesTrash : .notes)
            onNavigate()
        } label: {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: symbol).frame(width: 18)
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                if count > 0 { Text("\(count)").font(WFType.supporting).foregroundStyle(WFColors.secondaryText) }
            }
            .font(WFType.navigation).padding(.horizontal, WFSpace.sm).frame(height: NavigationMetrics.rowHeight)
            .foregroundStyle(WFColors.text)
            .contentShape(Rectangle())
            .rowHoverBackground(selected: selected)
        }.buttonStyle(.plain)
    }
}

/// Saved-filter group (Wave 1 F5) shown under the task collections. Rendered
/// only when the shell wires a FilterStore through `NavigationColumnView.filterStore`.
/// Clicking an entry navigates to 所有任务 and activates it; clicking the active
/// entry again cancels the filter. Editing/deleting lives in the row's context menu.
private struct FilterEditorRequest: Identifiable {
    let id = UUID()
    let filter: SavedFilter?
}

private struct TaskFiltersSectionView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var filterStore: FilterStore
    @ObservedObject var navigation: AppNavigation
    var onNavigate: () -> Void = {}
    var collapsed: Bool = false
    var onToggleSection: () -> Void = {}
    @EnvironmentObject private var environment: AppEnvironment
    @State private var editorRequest: FilterEditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSectionHeader(title: "过滤器", collapsed: collapsed, toggle: onToggleSection) {
                Button {
                    editorRequest = FilterEditorRequest(filter: nil)
                } label: {
                    Image(systemName: "plus").font(.system(size: 12))
                        .foregroundStyle(WFColors.secondaryText)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .hoverTip("新建过滤器")
                .accessibilityLabel("新建过滤器")
            }
            if !collapsed {
                if filterStore.filters.isEmpty {
                    SidebarHintCard(text: "根据清单、时间、优先级、标签等过滤出特定的任务", minHeight: 54)
                } else {
                    ForEach(filterStore.filters) { filter in
                        filterRow(filter)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .font(WFType.navigation)
        .sheet(item: $editorRequest) { request in
            FilterEditorView(store: filterStore, workspace: workspace,
                             initial: request.filter) { editorRequest = nil }
        }
    }

    private func filterRow(_ filter: SavedFilter) -> some View {
        let selected = navigation.destination == .allTasks && workspace.activeFilterID == filter.id
        return Button {
            if selected {
                workspace.openFilter(nil)
            } else {
                environment.navigate(to: .allTasks)
                workspace.openFilter(filter.id)
                onNavigate()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 13))
                    .frame(width: 22)
                Text(filter.name).lineLimit(1)
                Spacer(minLength: WFSpace.xs)
            }
            .foregroundStyle(WFColors.text)
            .padding(.leading, 11)
            .padding(.trailing, WFSpace.sm)
            .frame(height: NavigationMetrics.rowHeight)
            .contentShape(Rectangle())
            .rowHoverBackground(selected: selected)
        }
        .businessContextMenu {
            Button("编辑") {
                editorRequest = FilterEditorRequest(filter: filter)
            }
            Button("删除…") {
                if TaskNamePrompt.confirm("删除过滤器“\(filter.name)”？",
                                          message: "只删除过滤器本身，不会删除任务。",
                                          action: "删除") {
                    _ = workspace.deleteFilter(filter.id)
                }
            }
        }
    }
}
